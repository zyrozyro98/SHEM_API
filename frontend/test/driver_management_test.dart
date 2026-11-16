import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/services/admin_service.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';

class _MemoryDatabase implements DatabaseService {
  _MemoryDatabase(this.data);

  final Map<String, dynamic> data;

  dynamic _readPath(String path) {
    dynamic value = data;
    for (final segment in path.split('/')) {
      if (value is! Map) return null;
      value = value[segment];
    }
    return value;
  }

  @override
  Future<Map<String, dynamic>> read(String path) async {
    final value = _readPath(path);
    return value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> write(
    String path,
    Map<String, dynamic> value,
  ) async {
    final segments = path.split('/');
    var parent = data;
    for (final segment in segments.take(segments.length - 1)) {
      final child = parent[segment];
      if (child is Map) {
        final nested = Map<String, dynamic>.from(child);
        parent[segment] = nested;
        parent = nested;
      } else {
        final nested = <String, dynamic>{};
        parent[segment] = nested;
        parent = nested;
      }
    }
    parent[segments.last] = value;
    return value;
  }

  @override
  Future<Map<String, dynamic>> update(
    String path,
    Map<String, dynamic> value,
  ) async {
    return write(path, {...await read(path), ...value});
  }

  @override
  Future<Map<String, dynamic>?> updateIf(
    String path, {
    required bool Function(Map<String, dynamic> current) condition,
    required Map<String, dynamic> updates,
  }) async {
    final current = await read(path);
    if (current.isEmpty || !condition(current)) return null;
    return update(path, updates);
  }

  @override
  Future<void> delete(String path) async {}
}

void main() {
  test('driver dispatch summary calculates active drivers and transit workload',
      () {
    final summary = AdminDriverDispatchSummary.fromJson({
      'active_drivers': 3,
      'in_transit': 4,
      'available_drivers': 1,
      'assignments': [
        {'order_id': 'o-1', 'courier_name': 'سائق احمد', 'status': 'shipped'},
        {'order_id': 'o-2', 'courier_name': 'سائق محمد', 'status': 'preparing'},
        {'order_id': 'o-3', 'courier_name': 'سائق احمد', 'status': 'shipped'},
      ],
    });

    expect(summary.activeDrivers, 3);
    expect(summary.inTransitOrders, 4);
    expect(summary.availableDrivers, 1);
    expect(summary.assignments.length, 3);
    expect(summary.assignments.first['courier_name'], 'سائق احمد');
  });

  test(
      'driver can accept a task and update ETA without sharing location',
      () async {
    final database = _MemoryDatabase({
      'orders': {
        'order-1': {
          'id': 'order-1',
          'customer_id': 'customer-1',
          'driver_id': 'driver-1',
          'driver_phone': '0500000000',
          'courier_name': 'سائق التوصيل',
          'status': 'preparing',
        },
      },
      'customers': {
        'customer-1': {
          'orders': {
            'order-1': {'status': 'preparing'},
          },
        },
      },
    });
    final service = AdminService(databaseService: database);

    expect(
      await service.acceptDriverAssignment(
        orderId: 'order-1',
        driverId: 'driver-1',
        driverName: 'سائق التوصيل',
        driverPhone: '0500000000',
      ),
      isTrue,
    );
    expect(
      await service.acceptDriverAssignment(
        orderId: 'order-1',
        driverId: 'driver-1',
        driverName: 'سائق التوصيل',
        driverPhone: '0500000000',
      ),
      isFalse,
    );
    expect(
      await service.updateDriverEta(
        orderId: 'order-1',
        driverId: 'driver-1',
        driverName: 'سائق التوصيل',
        driverPhone: '0500000000',
        eta: '15 دقيقة',
      ),
      isTrue,
    );

    final order = await database.read('orders/order-1');
    final customerOrder =
        await database.read('customers/customer-1/orders/order-1');
    final updates = await database.read('delivery_updates');
    expect(order['driver_status'], 'accepted');
    expect(order['status'], 'preparing');
    expect(order['eta'], '15 دقيقة');
    expect(customerOrder.containsKey('current_location'), isFalse);
    expect(order.containsKey('driver_latitude'), isFalse);
    expect(order.containsKey('driver_longitude'), isFalse);
    expect(updates.values.single['eta'], '15 دقيقة');
    expect(updates.values.single.containsKey('current_location'), isFalse);
  });

  test('driver dashboard query includes only this driver assignments',
      () async {
    final database = _MemoryDatabase({
      'orders': {
        'active': {
          'id': 'active',
          'customer_id': 'customer-1',
          'driver_id': 'driver-1',
          'status': 'confirmed',
        },
        'done': {
          'id': 'done',
          'driver_id': 'driver-1',
          'status': 'delivered',
        },
        'other': {
          'id': 'other',
          'driver_id': 'driver-2',
          'status': 'preparing',
        },
      },
      'profiles': {
        'driver-1': {'role': 'driver', 'is_available': true},
        'customer-1': {'full_name': 'عميل الاختبار'},
      },
    });

    final summary =
        await AdminService(databaseService: database).getDriverDispatchSummary(
      driverId: 'driver-1',
      includeCompleted: true,
    );

    expect(summary.assignments.map((item) => item['order_id']).toSet(),
        {'active', 'done'});
    expect(summary.availableDrivers, 1);
  });

  test('driver dashboard includes cancelled tasks in completed history',
      () async {
    final database = _MemoryDatabase({
      'orders': {
        'cancelled': {
          'id': 'cancelled',
          'driver_id': 'driver-1',
          'status': 'cancelled',
        },
      },
    });
    final service = AdminService(databaseService: database);

    final activeSummary = await service.getDriverDispatchSummary(
      driverId: 'driver-1',
    );
    final completedSummary = await service.getDriverDispatchSummary(
      driverId: 'driver-1',
      includeCompleted: true,
    );

    expect(activeSummary.assignments, isEmpty);
    expect(completedSummary.assignments, hasLength(1));
    expect(completedSummary.assignments.single['status'], 'cancelled');
  });

  test('dispatcher queue only includes unassigned fulfillment orders',
      () async {
    final database = _MemoryDatabase({
      'orders': {
        'needs-driver': {
          'status': 'confirmed',
          'customer_id': 'customer-1',
          'total': 120,
          'delivery_address': 'حي النخيل',
          'created_at': '2026-10-20T09:00:00.000Z',
        },
        'already-assigned': {
          'status': 'preparing',
          'driver_id': 'driver-1',
        },
        'not-ready': {'status': 'pending_payment'},
      },
      'profiles': {
        'customer-1': {
          'full_name': 'عميل الاختبار',
          'phone': '0500000000',
        },
      },
    });

    final queue = await AdminService(databaseService: database)
        .getOrdersAwaitingDispatch();

    expect(queue, hasLength(1));
    expect(queue.single['id'], 'needs-driver');
    expect(queue.single['customer_name'], 'عميل الاختبار');
    expect(queue.single['delivery_address'], 'حي النخيل');
  });

  test('dispatcher assignment is attributed and appears in period report',
      () async {
    final now = DateTime.now();
    final database = _MemoryDatabase({
      'orders': {
        'order-1': {
          'id': 'order-1',
          'status': 'confirmed',
          'total': 450,
        },
      },
    });
    final service = AdminService(databaseService: database);

    expect(
      await service.assignOrderToDriver(
        orderId: 'order-1',
        driverName: 'سائق التوصيل',
        driverId: 'driver-1',
        dispatcherId: 'dispatcher-1',
        dispatcherName: 'مسؤول التوصيل',
      ),
      isTrue,
    );

    final savedOrder = await database.read('orders/order-1');
    expect(savedOrder['dispatcher_id'], 'dispatcher-1');
    expect(savedOrder['dispatcher_name'], 'مسؤول التوصيل');
    expect(savedOrder['dispatcher_assigned_at'], isNotEmpty);

    final report = await service.getDispatcherPerformanceReport(
      dispatcherId: 'dispatcher-1',
      period: DispatcherReportPeriod.monthly,
      referenceDate: now,
    );
    expect(report.totalAssigned, 1);
    expect(report.inProgress, 1);
    expect(report.totalOrderValue, 450);
    expect(report.orders.single['id'], 'order-1');
  });

  test('dispatcher reports filter by assignment day, month, and year',
      () async {
    final referenceDate = DateTime(2026, 10, 20, 12);
    Map<String, dynamic> attributedOrder(
      String id,
      DateTime assignedAt,
    ) =>
        {
          'id': id,
          'status': id == 'delivered' ? 'delivered' : 'confirmed',
          'total': 100,
          'dispatcher_id': 'dispatcher-1',
          'dispatcher_assigned_at': assignedAt.toUtc().toIso8601String(),
        };
    final database = _MemoryDatabase({
      'orders': {
        'today': attributedOrder('today', DateTime(2026, 10, 20, 8)),
        'this-month': attributedOrder('this-month', DateTime(2026, 10, 2)),
        'this-year': attributedOrder('this-year', DateTime(2026, 3, 1)),
        'last-year': attributedOrder('last-year', DateTime(2025, 12, 31)),
      },
    });
    final service = AdminService(databaseService: database);

    final daily = await service.getDispatcherPerformanceReport(
      dispatcherId: 'dispatcher-1',
      period: DispatcherReportPeriod.daily,
      referenceDate: referenceDate,
    );
    final monthly = await service.getDispatcherPerformanceReport(
      dispatcherId: 'dispatcher-1',
      period: DispatcherReportPeriod.monthly,
      referenceDate: referenceDate,
    );
    final yearly = await service.getDispatcherPerformanceReport(
      dispatcherId: 'dispatcher-1',
      period: DispatcherReportPeriod.yearly,
      referenceDate: referenceDate,
    );

    expect(daily.orders.map((order) => order['id']), ['today']);
    expect(monthly.totalAssigned, 2);
    expect(yearly.totalAssigned, 3);
    expect(yearly.delivered, 1);
  });
}
