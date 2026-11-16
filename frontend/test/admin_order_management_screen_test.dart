import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/services/admin_service.dart';
import 'package:she_m_app/presentation/admin/admin_management_detail_screens.dart';

class _ScreenAdminService extends AdminService {
  _ScreenAdminService({
    this.failOrders = false,
    this.failSummary = false,
    List<Map<String, dynamic>>? orders,
    this.drivers = const [],
  }) : orders = orders ??
            [
              {
                'id': 'order-42',
                'status': 'preparing',
                'customer_name': 'عميل الاختبار',
                'total': 125,
                'items': const <Map<String, dynamic>>[],
              },
            ];

  final bool failOrders;
  final bool failSummary;
  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> drivers;
  int reassignments = 0;

  @override
  Future<AdminManagementSummary> getManagementSummary() async {
    if (failSummary) throw StateError('summary unavailable');
    return const AdminManagementSummary(
      totalOrders: 1,
      totalMerchants: 1,
      totalCustomers: 1,
      totalProducts: 1,
      availableProducts: 1,
      pendingApprovals: 0,
      activeDeliveries: 1,
      unreadNotifications: 0,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getOrdersForAdmin({
    String? status,
    int? limit = 10,
    bool propagateErrors = false,
    bool includeArchived = false,
  }) async {
    if (failOrders) throw StateError('orders unavailable');
    return orders;
  }

  @override
  Future<List<Map<String, dynamic>>> getProfilesForAdmin({
    String? role,
    int? limit = 10,
    bool propagateErrors = false,
    bool includeArchived = false,
  }) async =>
      drivers
          .where((driver) => role == null || driver['role'] == role)
          .toList();

  @override
  Future<bool> reassignOrderToDriver({
    required String orderId,
    required String currentDriverId,
    required String currentDriverName,
    required String currentDriverPhone,
    required String driverName,
    required String driverId,
    required String driverPhone,
    String? eta,
  }) async {
    reassignments++;
    final order = orders.firstWhere((order) => order['id'] == orderId);
    order.addAll({
      'driver_id': driverId,
      'driver_name': driverName,
      'driver_phone': driverPhone,
      'driver_status': 'assigned',
    });
    return true;
  }
}

void main() {
  testWidgets('order management shows a retry action when loading fails',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OrderManagementScreen(
          service: _ScreenAdminService(failOrders: true),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('تعذر تحميل الطلبات'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
  });

  testWidgets(
      'order list remains available when the nonessential summary query fails',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OrderManagementScreen(
          service: _ScreenAdminService(failSummary: true),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('عميل الاختبار'), findsOneWidget);
    expect(
      find.text('تعذر تحميل مؤشرات الملخص؛ ما زال بإمكانك إدارة الطلبات.'),
      findsOneWidget,
    );
    expect(find.text('تعذر تحميل الطلبات'), findsNothing);
  });

  testWidgets('order cards show the primary product image', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OrderManagementScreen(
          service: _ScreenAdminService(
            orders: [
              {
                'id': 'order-image-1',
                'status': 'preparing',
                'customer_name': 'عميل الصورة',
                'total': 125,
                'items': [
                  {
                    'product_name': 'حقيبة',
                    'image_url':
                        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jk0YAAAAASUVORK5CYII=',
                  },
                  {
                    'product_name': 'حذاء',
                    'image_url':
                        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jk0YAAAAASUVORK5CYII=',
                  },
                ],
              },
            ],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('admin-order-product-image-order-image-1-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('admin-order-product-image-order-image-1-1')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Image>(
            find.byKey(
              const ValueKey('admin-order-product-image-order-image-1-0'),
            ),
          )
          .fit,
      BoxFit.contain,
    );
  });

  testWidgets('admin can change an order to another available driver',
      (tester) async {
    final service = _ScreenAdminService(
      orders: [
        {
          'id': 'order-42',
          'status': 'preparing',
          'customer_name': 'عميل الاختبار',
          'driver_id': 'old-driver',
          'driver_name': 'السائق السابق',
          'driver_status': 'assigned',
          'total': 125,
          'items': const <Map<String, dynamic>>[],
        },
      ],
      drivers: [
        {
          'id': 'new-driver',
          'role': 'driver',
          'full_name': 'السائق البديل',
          'phone': '700000002',
          'is_available': true,
        },
      ],
    );
    await tester.pumpWidget(
      MaterialApp(home: OrderManagementScreen(service: service)),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('إجراءات الطلب'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('إجراءات الطلب'));
    await tester.pumpAndSettle();
    expect(find.text('تغيير السائق'), findsOneWidget);

    await tester.tap(find.text('تغيير السائق'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('السائق البديل'));
    await tester.pumpAndSettle();

    expect(service.reassignments, 1);
    expect(service.orders.single['driver_id'], 'new-driver');
    expect(service.orders.single['driver_name'], 'السائق البديل');
    expect(
      find.text('تم تغيير سائق الطلب order-42 إلى السائق البديل'),
      findsOneWidget,
    );
    expect(find.text('تعذر تحديث الطلب، حاول مرة أخرى'), findsNothing);
  });

  testWidgets('all orders includes archived orders by default', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OrderManagementScreen(
          service: _ScreenAdminService(
            orders: [
              {
                'id': 'active-42',
                'status': 'preparing',
                'customer_name': 'عميل نشط',
                'total': 125,
                'items': const <Map<String, dynamic>>[],
              },
              {
                'id': 'archived-42',
                'status': 'delivered',
                'customer_name': 'عميل مؤرشف',
                'is_archived': true,
                'total': 125,
                'items': const <Map<String, dynamic>>[],
              },
            ],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('عميل نشط'), findsOneWidget);
    expect(find.text('2 طلب'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('عميل مؤرشف'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('عميل مؤرشف'), findsOneWidget);
    expect(find.text('جميع الطلبات'), findsOneWidget);
  });
}
