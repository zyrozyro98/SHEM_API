import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/models/product_model.dart';
import 'package:she_m_app/data/models/promotion_model.dart';
import 'package:she_m_app/data/services/order_service.dart';
import 'package:she_m_app/data/services/delivery_service.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/data/services/notification_service.dart';
import 'package:she_m_app/data/services/rating_service.dart';
import 'package:she_m_app/data/services/promotion_service.dart';
import 'package:she_m_app/data/services/wishlist_service.dart';

class _FakeDatabase implements DatabaseService {
  _FakeDatabase(this.data);

  final Map<String, dynamic> data;
  final List<String> writes = [];

  @override
  Future<Map<String, dynamic>> read(String path) async =>
      Map<String, dynamic>.from(data[path] as Map? ?? const {});

  @override
  Future<Map<String, dynamic>> write(
      String path, Map<String, dynamic> value) async {
    writes.add(path);
    data[path] = value;
    return value;
  }

  @override
  Future<Map<String, dynamic>> update(
      String path, Map<String, dynamic> value) async {
    writes.add(path);
    return value;
  }

  @override
  Future<Map<String, dynamic>?> updateIf(
    String path, {
    required bool Function(Map<String, dynamic> current) condition,
    required Map<String, dynamic> updates,
  }) async {
    final current = await read(path);
    if (current.isEmpty || !condition(current)) return null;
    return write(path, {...current, ...updates});
  }

  @override
  Future<void> delete(String path) async => writes.add('delete:$path');
}

const product = ProductModel(
  id: 'p1',
  name: 'حقيبة',
  price: 100,
  category: 'حقائب',
  description: '',
  imageUrl: '',
  available: true,
  merchantId: 'm1',
);

void main() {
  test('wishlist loads IDs and persists toggles', () async {
    final database = _FakeDatabase({
      'customers/c1/wishlist': {
        'p1': {'product_id': 'p1'}
      },
    });
    final service = WishlistService(databaseService: database);

    await service.loadForCustomer('c1');
    service.syncProducts([product]);
    expect(service.contains('p1'), isTrue);
    service.toggle(product);
    expect(database.writes, contains('delete:customers/c1/wishlist/p1'));
  });

  test('rating service calculates a real average', () async {
    final database = _FakeDatabase({
      'product_ratings/p1': {
        'c1': {'rating': 5},
        'c2': {'rating': 4},
      },
    });
    final summary =
        await RatingService(databaseService: database).getSummary('p1');

    expect(summary.average, 4.5);
    expect(summary.count, 2);

    expect(
      await RatingService(databaseService: database).submitRating(
        productId: 'p1',
        customerId: 'c3',
        rating: 5,
      ),
      isTrue,
    );
    expect(database.writes, contains('product_ratings/p1/c3'));
  });

  test('merchant order lookup uses product ownership for mixed orders',
      () async {
    final database = _FakeDatabase({
      'products': {
        'p1': {'merchant_id': 'm1'},
        'p2': {'merchant_id': 'm2'},
      },
      'orders': {
        'mixed-order': {
          'id': 'mixed-order',
          'status': 'confirmed',
          'created_at': '2026-01-01T00:00:00Z',
          'items': [
            {'product_id': 'p1', 'merchant_id': 'm2'},
            {'product_id': 'p2', 'merchant_id': 'm1'},
          ],
        },
        'other-order': {
          'id': 'other-order',
          'status': 'confirmed',
          'created_at': '2026-01-02T00:00:00Z',
          'items': [
            {'product_id': 'p2', 'merchant_id': 'm1'},
          ],
        },
      },
    });
    final service = OrderService(databaseService: database);

    final firstMerchantOrders = await service.getOrdersByMerchant('m1');
    final secondMerchantOrders = await service.getOrdersByMerchant('m2');

    expect(firstMerchantOrders.map((order) => order.id), ['mixed-order']);
    expect(
      secondMerchantOrders.map((order) => order.id),
      ['mixed-order', 'other-order'],
    );
  });

  test(
      'assigned driver completes delivery without a customer verification code',
      () async {
    final database = _FakeDatabase({
      'orders/order-otp': {
        'id': 'order-otp',
        'customer_id': 'c1',
        'driver_id': 'driver-1',
        'status': 'preparing',
        'customer_delivery_otp_hash': 'legacy-hash',
        'customer_delivery_otp_salt': 'legacy-salt',
        'items': [
          {'product_id': 'p1', 'quantity': 1, 'unit_price': 10, 'total': 10}
        ],
      },
    });
    final service = OrderService(databaseService: database);

    final prepared = await service.prepareDeliveryOtp('order-otp');
    expect(prepared?.status, 'shipped');
    expect(prepared?.pickupOtp, hasLength(6));

    final pickedUp = await service.confirmPickupOtp(
      orderId: 'order-otp',
      otp: prepared!.pickupOtp!,
    );
    expect(pickedUp?.status, 'picked_up');
    final storedOrder = database.data['orders/order-otp'] as Map;
    expect(storedOrder.containsKey('customer_delivery_otp_hash'), isFalse);
    expect(storedOrder.containsKey('customer_delivery_otp_salt'), isFalse);

    expect(
      await service.updateOrderStatus(
          orderId: 'order-otp', status: 'delivered'),
      isNull,
    );
    expect(
      await service.confirmDeliveryByDriver(
        orderId: 'order-otp',
        driverId: 'other-driver',
      ),
      isNull,
    );
    expect(storedOrder['status'], 'picked_up');

    final confirmedDelivery = await service.confirmDeliveryByDriver(
      orderId: 'order-otp',
      driverId: 'driver-1',
    );
    expect(confirmedDelivery?.status, 'delivered');
    final deliveredOrder = database.data['orders/order-otp'] as Map;
    expect(deliveredOrder['status'], 'delivered');
    expect(deliveredOrder['driver_status'], 'delivered');
    expect(
      (database.data['customers/c1/orders/order-otp'] as Map)['status'],
      'delivered',
    );
  });

  test('driver can complete an active legacy order with an expired old code',
      () async {
    final database = _FakeDatabase({
      'orders/legacy-picked-up': {
        'id': 'legacy-picked-up',
        'customer_id': 'customer-1',
        'driver_id': 'driver-1',
        'status': 'picked_up',
        'customer_delivery_otp_hash': 'expired-legacy-hash',
        'customer_delivery_otp_salt': 'expired-legacy-salt',
        'customer_delivery_otp_expires_at': '2000-01-01T00:00:00Z',
        'items': [],
      },
    });

    final delivered =
        await OrderService(databaseService: database).confirmDeliveryByDriver(
      orderId: 'legacy-picked-up',
      driverId: 'driver-1',
    );

    expect(delivered?.status, 'delivered');
    final storedOrder = database.data['orders/legacy-picked-up'] as Map;
    expect(storedOrder['customer_delivery_otp_hash'], isNull);
    expect(storedOrder['customer_delivery_otp_salt'], isNull);
    expect(storedOrder['customer_delivery_otp_expires_at'], isNull);
    expect(
      (database.data['customers/customer-1/orders/legacy-picked-up'] as Map)
          .containsKey('customer_delivery_otp_hash'),
      isFalse,
    );
  });

  test(
      'pickup code survives reopening and driver pickup verification advances '
      'the order', () async {
    final database = _FakeDatabase({
      'orders/order-pickup': {
        'id': 'order-pickup',
        'customer_id': 'c1',
        'driver_id': 'driver-1',
        'status': 'preparing',
        'items': [],
      },
    });

    final merchantService = OrderService(databaseService: database);
    final prepared = await merchantService.prepareDeliveryOtp('order-pickup');
    final storedOrder = database.data['orders/order-pickup'] as Map;
    final customerOrder =
        database.data['customers/c1/orders/order-pickup'] as Map;

    expect(prepared?.status, 'shipped');
    expect(prepared?.pickupOtp, hasLength(6));
    expect(storedOrder['pickup_otp'], prepared?.pickupOtp);
    expect(customerOrder.containsKey('pickup_otp'), isFalse);
    expect(customerOrder.containsKey('pickup_otp_hash'), isFalse);
    expect(customerOrder.containsKey('pickup_otp_salt'), isFalse);

    final reopenedMerchantService = OrderService(databaseService: database);
    final restored =
        await reopenedMerchantService.prepareDeliveryOtp('order-pickup');
    expect(restored?.pickupOtp, prepared?.pickupOtp);

    expect(
      await reopenedMerchantService.confirmPickupOtp(
        orderId: 'order-pickup',
        otp: '000000',
      ),
      isNull,
    );
    expect(
      await reopenedMerchantService.updateOrderStatus(
        orderId: 'order-pickup',
        status: 'picked_up',
      ),
      isNull,
    );
    expect((database.data['orders/order-pickup'] as Map)['status'], 'shipped');

    final pickedUp = await reopenedMerchantService.confirmPickupOtp(
      orderId: 'order-pickup',
      otp: restored!.pickupOtp!,
    );
    expect(pickedUp?.status, 'picked_up');
    expect(
      (database.data['orders/order-pickup'] as Map).containsKey('pickup_otp'),
      isFalse,
    );
    final syncedOrder =
        database.data['customers/c1/orders/order-pickup'] as Map;
    expect(syncedOrder.containsKey('pickup_otp'), isFalse);
    expect(syncedOrder.containsKey('customer_delivery_otp_hash'), isFalse);

    final delivered = await reopenedMerchantService.confirmDeliveryByDriver(
      orderId: 'order-pickup',
      driverId: 'driver-1',
    );
    expect(delivered?.status, 'delivered');
  });

  test('admin can hand off an assigned order without pickup OTP', () async {
    final database = _FakeDatabase({
      'orders/order-admin-handoff': {
        'id': 'order-admin-handoff',
        'customer_id': 'customer-1',
        'driver_id': 'driver-1',
        'status': 'shipped',
        'pickup_otp': '123456',
        'pickup_otp_hash': 'old-hash',
        'pickup_otp_salt': 'old-salt',
        'pickup_otp_verified': false,
        'items': [],
      },
    });

    final handedOff = await OrderService(databaseService: database)
        .handoffToDriverWithoutPickupOtpForAdmin(
      orderId: 'order-admin-handoff',
    );
    final storedOrder = database.data['orders/order-admin-handoff'] as Map;
    final customerOrder =
        database.data['customers/customer-1/orders/order-admin-handoff'] as Map;

    expect(handedOff?.status, 'picked_up');
    expect(storedOrder['pickup_otp_verified'], isTrue);
    expect(storedOrder['pickup_otp_bypassed_by_admin'], isTrue);
    expect(storedOrder['pickup_otp'], isNull);
    expect(storedOrder['customer_delivery_otp'], isNull);
    expect(storedOrder['customer_delivery_otp_hash'], isNull);
    expect(customerOrder['status'], 'picked_up');
    expect(customerOrder.containsKey('pickup_otp_hash'), isFalse);
    expect(customerOrder.containsKey('customer_delivery_otp_hash'), isFalse);
    expect(customerOrder.containsKey('customer_delivery_otp'), isFalse);

    final orderService = OrderService(databaseService: database);
    expect(
      await orderService.updateOrderStatus(
        orderId: 'order-admin-handoff',
        status: 'delivered',
      ),
      isNull,
    );
    final delivered = await orderService.confirmDeliveryByDriver(
      orderId: 'order-admin-handoff',
      driverId: 'driver-1',
    );
    expect(delivered?.status, 'delivered');

    expect(
      await orderService.handoffToDriverWithoutPickupOtpForAdmin(
        orderId: 'order-admin-handoff',
      ),
      isNull,
    );
  });

  test('legacy handed-off orders without a saved pickup code get a new code',
      () async {
    final database = _FakeDatabase({
      'orders/order-legacy-pickup': {
        'id': 'order-legacy-pickup',
        'status': 'shipped',
        'pickup_otp_hash': 'legacy-hash',
        'pickup_otp_salt': 'legacy-salt',
        'pickup_otp_expires_at':
            DateTime.now().add(const Duration(minutes: 10)).toIso8601String(),
        'pickup_otp_attempts': 2,
        'pickup_otp_locked': true,
        'items': [],
      },
    });

    final prepared = await OrderService(databaseService: database)
        .prepareDeliveryOtp('order-legacy-pickup');
    final storedOrder = database.data['orders/order-legacy-pickup'] as Map;

    expect(prepared?.pickupOtp, matches(RegExp(r'^\d{6}$')));
    expect(storedOrder['pickup_otp'], prepared?.pickupOtp);
    expect(storedOrder['pickup_otp_hash'], isNot('legacy-hash'));
    expect(storedOrder['pickup_otp_attempts'], 0);
    expect(storedOrder['pickup_otp_locked'], isFalse);
  });

  test('promotion service exposes only active promotions and persists changes',
      () async {
    final database = _FakeDatabase({
      'promotions': {
        'active': {
          'title': 'عرض حقيقي',
          'image_url': 'https://example.com/active.jpg',
          'is_active': true,
          'sort_order': 1,
        },
        'inactive': {
          'title': 'عرض متوقف',
          'image_url': 'https://example.com/inactive.jpg',
          'is_active': false,
        },
        'pending': {
          'title': 'عرض بانتظار المراجعة',
          'image_url': 'https://example.com/pending.jpg',
          'is_active': true,
          'approval_status': 'pending',
        },
      },
    });
    final service = PromotionService(databaseService: database);

    final visible = await service.getVisiblePromotions();

    expect(visible.map((item) => item.id), ['active']);
    expect(visible.every((item) => item.approvalStatus == 'approved'), isTrue);
    await service.createPromotion(const PromotionModel(
      id: 'new',
      title: 'جديد',
      subtitle: '',
      imageUrl: 'https://example.com/new.jpg',
      actionText: 'تسوق الآن',
      actionUrl: '',
      productId: 'p1',
      merchantId: 'm1',
      isActive: true,
      sortOrder: 2,
      startsAt: null,
      endsAt: null,
      approvalStatus: 'pending',
      reviewReason: '',
    ));
    expect(database.writes, contains('promotions/new'));
  });

  test('delivery service merges order and delivery update data', () async {
    final database = _FakeDatabase({
      'customers/c1/orders': {
        'o1': {'id': 'o1', 'status': 'preparing'},
      },
      'delivery_updates': {
        'u1': {
          'order_id': 'o1',
          'status': 'shipped',
          'courier_name': 'مندوب فعلي',
          'current_location': 'بوابة المتجر',
          'eta': '20 دقيقة',
        },
      },
    });
    final deliveries = await DeliveryService(databaseService: database)
        .getCustomerDeliveries('c1');

    expect(deliveries.single['status'], 'shipped');
    expect(deliveries.single['courier'], 'مندوب فعلي');
    expect(deliveries.single['eta'], '20 دقيقة');
  });

  test('delivery service shows ETA without exposing driver location', () async {
    final database = _FakeDatabase({
      'customers/c1/orders': {
        'o1': {'id': 'o1', 'status': 'preparing'},
        'o2': {'id': 'o2', 'status': 'accepted'},
      },
      'delivery_updates': {
        'old': {
          'order_id': 'o1',
          'status': 'preparing',
          'courier_name': 'مندوب قديم',
          'current_location': 'المتجر',
          'eta': '45 دقيقة',
          'created_at': '2024-01-01T08:00:00.000Z',
        },
        'new': {
          'order_id': 'o1',
          'status': 'shipped',
          'courier_name': 'مندوب جديد',
          'current_location': 'في الطريق',
          'driver_latitude': 15.3694,
          'driver_longitude': 44.191,
          'eta': '20 دقيقة',
          'created_at': '2024-01-01T09:00:00.000Z',
        },
      },
    });

    final deliveries = await DeliveryService(databaseService: database)
        .getCustomerDeliveries('c1');

    final orderOne =
        deliveries.firstWhere((delivery) => delivery['order_id'] == 'o1');
    expect(orderOne['status'], 'shipped');
    expect(orderOne['courier'], 'مندوب جديد');
    expect(orderOne['current_location'], isNull);
    expect(orderOne['driver_latitude'], isNull);
    expect(orderOne['driver_longitude'], isNull);
    expect(orderOne['eta'], '20 دقيقة');
  });

  test('notification service returns only the customer notifications',
      () async {
    final database = _FakeDatabase({
      'notifications': {
        'n1': {
          'profile_id': 'c1',
          'title': 'تم تحديث طلبك',
          'body': 'طلبك في الطريق',
          'is_read': false,
        },
        'n2': {'profile_id': 'c2', 'title': 'خاص بعميل آخر'},
      },
    });
    final notifications = await NotificationService(databaseService: database)
        .getForCustomer('c1');

    expect(notifications, hasLength(1));
    expect(notifications.single.title, 'تم تحديث طلبك');
    expect(notifications.single.isRead, isFalse);
    await NotificationService(databaseService: database).markAllAsRead(['n1']);
    expect(database.writes, contains('notifications/n1'));
  });
}
