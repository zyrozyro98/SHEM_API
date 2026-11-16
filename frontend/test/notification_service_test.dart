import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/services/admin_service.dart';
import 'package:she_m_app/data/models/order_model.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/data/services/notification_service.dart';
import 'package:she_m_app/data/services/order_service.dart';

class _FakeDatabase implements DatabaseService {
  _FakeDatabase(this.data);

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
    final current = await read(path);
    return write(path, {...current, ...value});
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
  Future<void> delete(String path) async {
    final segments = path.split('/');
    var parent = data;
    for (final segment in segments.take(segments.length - 1)) {
      final child = parent[segment];
      if (child is! Map) return;
      final nested = Map<String, dynamic>.from(child);
      parent[segment] = nested;
      parent = nested;
    }
    parent.remove(segments.last);
  }
}

void main() {
  test('new orders use the status for the selected payment method', () async {
    final database = _FakeDatabase({});
    final order = await OrderService(databaseService: database).createOrder(
      customerId: 'customer-1',
      items: const [
        OrderItem(
          productId: 'product-1',
          productName: 'منتج',
          quantity: 1,
          unitPrice: 100,
          total: 100,
        ),
      ],
      paymentMethod: 'cash_on_delivery',
      subtotal: 100,
      shippingFee: 0,
      commission: 10,
      status: 'new',
    );

    expect(order?.paymentMethod, 'cash_on_delivery');
    expect(order?.status, 'new');
    final storedOrder = await database.read('orders/${order!.id}');
    expect(storedOrder['status'], 'new');
    expect(storedOrder['payment_method'], 'cash_on_delivery');
    expect(storedOrder['commission'], 10);
    expect(storedOrder['total'], 100);
    expect(storedOrder['commission_included_in_subtotal'], isTrue);
    expect(OrderService.isVisibleToMerchant(storedOrder), isTrue);
  });

  test('merchant confirmation is applied only once per order', () async {
    final database = _FakeDatabase({
      'orders': {
        'order-1': {
          'id': 'order-1',
          'customer_id': 'customer-1',
          'status': 'pending_payment',
          'items': <dynamic>[],
        },
      },
    });

    final service = OrderService(databaseService: database);

    final firstApproval = await service.updateOrderStatus(
      orderId: 'order-1',
      status: 'confirmed',
    );
    final repeatedApproval = await service.updateOrderStatus(
      orderId: 'order-1',
      status: 'confirmed',
    );
    final notifications = await database.read('notifications');

    expect(firstApproval?.status, 'confirmed');
    expect(repeatedApproval, isNull);
    expect(notifications, hasLength(1));
  });

  test('merchant can confirm a newly created order', () async {
    final database = _FakeDatabase({
      'orders': {
        'order-new': {
          'id': 'order-new',
          'customer_id': 'customer-1',
          'status': 'new',
          'items': <dynamic>[],
        },
      },
    });

    final confirmed = await OrderService(databaseService: database)
        .updateOrderStatus(orderId: 'order-new', status: 'confirmed');

    expect(confirmed?.status, 'confirmed');
    expect((await database.read('orders/order-new'))['status'], 'confirmed');
  });

  test('order status transition creates a customer notification', () async {
    final database = _FakeDatabase({
      'orders': {
        'order-1': {
          'id': 'order-1',
          'customer_id': 'customer-1',
          'status': 'confirmed',
          'items': <dynamic>[],
        },
      },
    });

    final updatedOrder = await OrderService(databaseService: database)
        .updateOrderStatus(orderId: 'order-1', status: 'preparing');
    final notifications = await NotificationService(databaseService: database)
        .getForCustomer('customer-1');

    expect(updatedOrder?.status, 'preparing');
    expect(notifications, hasLength(1));
    expect(notifications.single.title, 'طلبك قيد التجهيز');
    expect(notifications.single.orderId, 'order-1');

    await OrderService(databaseService: database)
        .updateOrderStatus(orderId: 'order-1', status: 'shipped');
    final deliveryUpdates = await database.read('delivery_updates');
    expect(
      deliveryUpdates.values
          .any((value) => value is Map && value['status'] == 'shipped'),
      isTrue,
    );
  });

  test('delivery fee adjustment updates totals and notifies the customer',
      () async {
    final database = _FakeDatabase({
      'orders': {
        'order-fee': {
          'id': 'order-fee',
          'customer_id': 'customer-1',
          'status': 'confirmed',
          'subtotal': 100.0,
          'commission': 10.0,
          'shipping_fee': 20.0,
          'total': 130.0,
          'items': [
            {'currency_symbol': 'ر.س'},
          ],
        },
      },
    });

    final result =
        await OrderService(databaseService: database).updateDeliveryFee(
      orderId: 'order-fee',
      shippingFee: 35,
      actorId: 'dispatcher-1',
      actorRole: 'central_dispatcher',
    );
    final saved = await database.read('orders/order-fee');
    final customerCopy =
        await database.read('customers/customer-1/orders/order-fee');
    final notifications = await NotificationService(databaseService: database)
        .getForCustomer('customer-1');

    expect(result?.order.shippingFee, 35);
    expect(result?.order.total, 145);
    expect(result?.notificationSent, isTrue);
    expect(saved['delivery_fee_updated_by'], 'dispatcher-1');
    expect(customerCopy['shipping_fee'], 35);
    expect(notifications.single.type, 'delivery_fee_changed');
    expect(notifications.single.body, contains('20 إلى 35 ر.س'));
  });

  test('delivery fee can only be adjusted by admins before completion',
      () async {
    final database = _FakeDatabase({
      'orders': {
        'order-fee': {
          'id': 'order-fee',
          'customer_id': 'customer-1',
          'status': 'delivered',
          'subtotal': 100.0,
          'commission': 10.0,
          'shipping_fee': 20.0,
          'total': 130.0,
        },
      },
    });

    final result =
        await OrderService(databaseService: database).updateDeliveryFee(
      orderId: 'order-fee',
      shippingFee: 35,
      actorId: 'dispatcher-1',
      actorRole: 'central_dispatcher',
    );

    expect(result, isNull);
    expect((await database.read('orders/order-fee'))['shipping_fee'], 20);
  });

  test('merchant can reject one out-of-stock item and keep the order active',
      () async {
    final database = _FakeDatabase({
      'orders': {
        'order-2': {
          'id': 'order-2',
          'customer_id': 'customer-1',
          'status': 'confirmed',
          'subtotal': 300.0,
          'commission': 30.0,
          'shipping_fee': 10.0,
          'total': 340.0,
          'items': [
            {
              'product_id': 'product-1',
              'product_name': 'فستان',
              'quantity': 1,
              'unit_price': 100.0,
              'total': 100.0,
              'merchant_id': 'merchant-1',
            },
            {
              'product_id': 'product-2',
              'product_name': 'حقيبة',
              'quantity': 2,
              'unit_price': 100.0,
              'total': 200.0,
              'merchant_id': 'merchant-2',
            },
          ],
        },
      },
    });
    final service = OrderService(databaseService: database);

    final updated = await service.rejectOrderItemForOutOfStock(
      orderId: 'order-2',
      itemIndex: 0,
      merchantId: 'merchant-1',
    );
    final saved = await database.read('orders/order-2');
    final customerCopy =
        await database.read('customers/customer-1/orders/order-2');
    final notifications = await NotificationService(databaseService: database)
        .getForCustomer('customer-1');

    expect(updated?.status, 'confirmed');
    expect(updated?.items[0].status, 'rejected');
    expect(updated?.items[0].rejectionReason, 'نفدت الكمية');
    expect(updated?.items[1].status, 'available');
    expect(updated?.subtotal, 200);
    expect(updated?.commission, 20);
    expect(updated?.total, 230);
    expect(saved['total'], 230);
    expect(customerCopy['items'][0]['status'], 'rejected');
    expect(notifications, hasLength(1));
    expect(notifications.single.type, 'order_item_rejected');
    expect(notifications.single.body, contains('سيتم إتمام بقية المنتجات'));
  });

  test(
      'rejecting an item preserves included commission without adding it twice',
      () async {
    final database = _FakeDatabase({
      'orders': {
        'order-included-commission': {
          'id': 'order-included-commission',
          'customer_id': 'customer-1',
          'status': 'confirmed',
          'subtotal': 330.0,
          'commission': 30.0,
          'commission_included_in_subtotal': true,
          'shipping_fee': 10.0,
          'total': 340.0,
          'items': [
            {
              'product_id': 'product-1',
              'product_name': 'فستان',
              'quantity': 1,
              'unit_price': 110.0,
              'total': 110.0,
              'total_yer': 110.0,
              'base_unit_price_yer': 100.0,
              'merchant_id': 'merchant-1',
            },
            {
              'product_id': 'product-2',
              'product_name': 'حقيبة',
              'quantity': 1,
              'unit_price': 220.0,
              'total': 220.0,
              'total_yer': 220.0,
              'base_unit_price_yer': 200.0,
              'merchant_id': 'merchant-2',
            },
          ],
        },
      },
    });

    final updated = await OrderService(databaseService: database)
        .rejectOrderItemForOutOfStock(
      orderId: 'order-included-commission',
      itemIndex: 0,
      merchantId: 'merchant-1',
    );

    expect(updated?.subtotal, 220);
    expect(updated?.commission, 20);
    expect(updated?.total, 230);
    expect(
      (await database.read('orders/order-included-commission'))['total'],
      230,
    );
  });

  test('merchant cannot reject another merchant item', () async {
    final database = _FakeDatabase({
      'orders': {
        'order-3': {
          'id': 'order-3',
          'customer_id': 'customer-1',
          'status': 'confirmed',
          'subtotal': 100.0,
          'commission': 10.0,
          'shipping_fee': 10.0,
          'total': 120.0,
          'items': [
            {
              'product_id': 'product-1',
              'product_name': 'فستان',
              'quantity': 1,
              'unit_price': 100.0,
              'total': 100.0,
              'merchant_id': 'merchant-1',
            },
          ],
        },
      },
    });

    final updated = await OrderService(databaseService: database)
        .rejectOrderItemForOutOfStock(
      orderId: 'order-3',
      itemIndex: 0,
      merchantId: 'merchant-2',
    );

    expect(updated, isNull);
    expect((await database.read('orders/order-3'))['status'], 'confirmed');
    expect(await database.read('notifications'), isEmpty);
  });

  test('rejecting the last available item cancels the unfulfillable order',
      () async {
    final database = _FakeDatabase({
      'orders': {
        'order-4': {
          'id': 'order-4',
          'customer_id': 'customer-1',
          'status': 'confirmed',
          'subtotal': 100.0,
          'commission': 10.0,
          'shipping_fee': 10.0,
          'total': 120.0,
          'items': [
            {
              'product_id': 'product-1',
              'product_name': 'فستان',
              'quantity': 1,
              'unit_price': 100.0,
              'total': 100.0,
              'merchant_id': 'merchant-1',
            },
          ],
        },
      },
    });

    final updated = await OrderService(databaseService: database)
        .rejectOrderItemForOutOfStock(
      orderId: 'order-4',
      itemIndex: 0,
      merchantId: 'merchant-1',
    );

    expect(updated?.status, 'cancelled');
    expect(updated?.cancellationReason, contains('نفدت كمية جميع المنتجات'));
    expect(updated?.total, 0);
  });

  test('admin order list retains item rejection details', () async {
    final database = _FakeDatabase({
      'orders': {
        'order-5': {
          'customer_id': 'customer-1',
          'status': 'confirmed',
          'created_at': '2026-10-05T00:00:00.000Z',
          'items': [
            {
              'product_name': 'فستان',
              'status': 'rejected',
              'rejection_reason': 'نفدت الكمية',
            },
          ],
        },
      },
    });

    final orders = await AdminService(databaseService: database)
        .getOrdersForAdmin(limit: 5);

    expect(orders, hasLength(1));
    expect(orders.single['id'], 'order-5');
    expect(orders.single['items'][0]['status'], 'rejected');
    expect(orders.single['items'][0]['rejection_reason'], 'نفدت الكمية');
  });

  test('marking all notifications as read persists the change', () async {
    final database = _FakeDatabase({
      'notifications': {
        'n1': {
          'profile_id': 'customer-1',
          'title': 'تحديث الطلب',
          'body': 'طلبك قيد التجهيز',
          'is_read': false,
        },
      },
    });

    final marked = await NotificationService(databaseService: database)
        .markAllAsRead(['n1']);

    expect(marked, isTrue);
    expect((await database.read('notifications/n1'))['is_read'], isTrue);
  });

  test('notifications are scoped to the signed-in profile and role', () async {
    final database = _FakeDatabase({
      'notifications': {
        'customer-notification': {
          'profile_id': 'shared-id',
          'recipient_role': 'customer',
          'title': 'تحديث العميل',
          'body': 'للعميل',
          'created_at': '2026-10-22T10:00:00.000Z',
        },
        'driver-notification': {
          'profile_id': 'shared-id',
          'recipient_role': 'driver',
          'title': 'إسناد طلب',
          'body': 'للسائق',
          'created_at': '2026-10-22T11:00:00.000Z',
        },
        'another-profile': {
          'profile_id': 'other-id',
          'recipient_role': 'driver',
          'title': 'إشعار آخر',
          'body': 'حساب آخر',
        },
      },
    });

    final notifications = await NotificationService(databaseService: database)
        .getForProfile('shared-id', role: 'driver');

    expect(notifications, hasLength(1));
    expect(notifications.single.id, 'driver-notification');
    expect(notifications.single.recipientRole, 'driver');
  });

  test('product rejection notification retains its product id', () async {
    final database = _FakeDatabase({});

    final sent =
        await NotificationService(databaseService: database).notifyProfile(
      profileId: 'merchant-1',
      role: 'merchant',
      title: 'تم رفض منتجك',
      body: 'السبب: صورة المنتج غير واضحة',
      type: 'product_rejected',
      productId: 'product-1',
      status: 'rejected',
      eventId: 'product-rejected-product-1',
    );

    expect(sent, isTrue);
    final notifications = await NotificationService(databaseService: database)
        .getForProfile('merchant-1', role: 'merchant');
    expect(notifications.single.productId, 'product-1');
  });

  test('new orders notify merchants, admins, and managers', () async {
    final database = _FakeDatabase({
      'profiles': {
        'merchant-1': {'id': 'merchant-1', 'role': 'merchant'},
        'admin-1': {'id': 'admin-1', 'role': 'admin'},
        'manager-1': {'id': 'manager-1', 'role': 'manager'},
        'dispatcher-1': {'id': 'dispatcher-1', 'role': 'central_dispatcher'},
        'customer-1': {'id': 'customer-1', 'role': 'customer'},
      },
    });
    final service = NotificationService(databaseService: database);

    final sent = await service.notifyOrderCreated(
      orderId: 'order-1',
      merchantIds: ['merchant-1'],
    );

    expect(sent, isTrue);
    for (final recipientId in [
      'merchant-1',
      'admin-1',
      'manager-1',
      'dispatcher-1',
    ]) {
      final notifications = await service.getForProfile(recipientId);
      expect(notifications, hasLength(1), reason: recipientId);
      expect(notifications.single.type, 'new_order');
      expect(notifications.single.orderId, 'order-1');
    }
    expect(await service.getForProfile('customer-1'), isEmpty);
  });

  test('order creation sends notifications to its merchant and managers',
      () async {
    final database = _FakeDatabase({
      'profiles': {
        'merchant-1': {'id': 'merchant-1', 'role': 'merchant'},
        'admin-1': {'id': 'admin-1', 'role': 'admin'},
        'manager-1': {'id': 'manager-1', 'role': 'central_dispatcher'},
      },
    });

    final order = await OrderService(databaseService: database).createOrder(
      customerId: 'customer-1',
      items: const [
        OrderItem(
          productId: 'product-1',
          productName: 'منتج',
          quantity: 1,
          unitPrice: 100,
          total: 100,
          merchantId: 'merchant-1',
        ),
      ],
      paymentMethod: 'cash_on_delivery',
      subtotal: 100,
      shippingFee: 0,
      status: 'confirmed',
      notifyCustomer: false,
    );
    final notifications = NotificationService(databaseService: database);

    expect(order, isNotNull);
    expect(
      (await notifications.getForProfile('merchant-1')).single.type,
      'new_order',
    );
    expect(
      (await notifications.getForProfile('admin-1')).single.type,
      'new_order',
    );
    expect(
      (await notifications.getForProfile('manager-1')).single.type,
      'new_order',
    );
    expect(await notifications.getForProfile('customer-1'), isEmpty);
  });

  test('driver assignment sends a notification to the assigned driver',
      () async {
    final database = _FakeDatabase({
      'orders': {
        'order-1': {'status': 'confirmed'},
      },
    });

    final assigned =
        await AdminService(databaseService: database).assignOrderToDriver(
      orderId: 'order-1',
      driverName: 'سائق',
      driverId: 'driver-1',
    );
    final notifications = await NotificationService(databaseService: database)
        .getForProfile('driver-1', role: 'driver');

    expect(assigned, isTrue);
    expect(notifications, hasLength(1));
    expect(notifications.single.type, 'delivery_assignment');
    expect(notifications.single.orderId, 'order-1');
  });
}
