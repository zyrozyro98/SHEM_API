import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/services/admin_service.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';

void main() {
  test('admin dashboard stats parse from Supabase style payload', () {
    const stats = AdminDashboardStats(
      revenueLabel: '128,450 ر.ي',
      totalOrders: 4820,
      totalMerchants: 96,
      totalCustomers: 14220,
    );

    final parsed = AdminDashboardStats.fromJson({
      'revenue': 128450,
      'orders': 4820,
      'merchants': 96,
      'customers': 14220,
    });

    expect(parsed.revenueLabel, stats.revenueLabel);
    expect(parsed.totalOrders, stats.totalOrders);
    expect(parsed.totalMerchants, stats.totalMerchants);
    expect(parsed.totalCustomers, stats.totalCustomers);
  });

  test(
      'admin management summary counts available products from raw product rows',
      () {
    final summary = AdminManagementSummary.fromJson({
      'orders': 84,
      'merchants': 12,
      'customers': 320,
      'products': [
        {'id': 'p1', 'available': true},
        {'id': 'p2', 'available': true},
        {'id': 'p3', 'available': false},
      ],
      'pending_proofs': 3,
      'notifications': 5,
      'orders_status': [
        {'status': 'confirmed'},
        {'status': 'confirmed'},
        {'status': 'delivered'},
        {'status': 'pending_payment'},
      ],
    });

    expect(summary.totalOrders, 84);
    expect(summary.totalProducts, 3);
    expect(summary.availableProducts, 2);
    expect(summary.pendingApprovals, 3);
    expect(summary.activeDeliveries, 2);
    expect(summary.unreadNotifications, 5);
  });

  test('admin merchant profiles include saved contact phone numbers', () async {
    final service = AdminService(
      databaseService: _ProfilesDatabase({
        'merchant-1': {
          'full_name': 'Merchant',
          'role': 'merchant',
          'shop_contact_phones': ['711111111', '733333333'],
        },
        'customer-1': {'full_name': 'Customer', 'role': 'customer'},
      }),
    );

    final merchants = await service.getProfilesForAdmin(role: 'merchant');

    expect(merchants, hasLength(1));
    expect(merchants.single['id'], 'merchant-1');
    expect(merchants.single['shop_contact_phones'], ['711111111', '733333333']);
  });

  test('admin can load every profile and propagate profile read failures',
      () async {
    final service = AdminService(
      databaseService: _ProfilesDatabase({
        'user-1': {'full_name': 'First', 'role': 'customer'},
        'user-2': {'full_name': 'Second', 'role': 'merchant'},
      }),
    );

    final profiles = await service.getProfilesForAdmin(
      limit: null,
      propagateErrors: true,
    );

    expect(profiles, hasLength(2));
    expect(profiles.map((profile) => profile['id']),
        containsAll(['user-1', 'user-2']));

    final failingService = AdminService(
      databaseService: _ProfilesDatabase({}, failReads: true),
    );
    await expectLater(
      failingService.getProfilesForAdmin(propagateErrors: true),
      throwsStateError,
    );
  });

  test('admin profile role and verification changes update stored profiles',
      () async {
    final database = _ProfilesDatabase({
      'user-1': {'role': 'customer', 'is_verified': false},
    });
    final service = AdminService(databaseService: database);

    expect(
      await service.updateProfileRoleForAdmin(
        profileId: 'user-1',
        role: ' merchant ',
      ),
      isTrue,
    );
    expect(
      await service.updateProfileVerificationForAdmin(
        profileId: 'user-1',
        isVerified: true,
      ),
      isTrue,
    );
    expect(database.updates, [
      {
        'path': 'profiles/user-1',
        'data': {'role': 'merchant'},
      },
      {
        'path': 'profiles/user-1',
        'data': {'is_verified': true},
      },
    ]);
  });

  test('admin cannot assign unsupported profile roles', () async {
    final database = _ProfilesDatabase({});
    final service = AdminService(databaseService: database);

    expect(
      await service.updateProfileRoleForAdmin(
        profileId: 'user-1',
        role: 'admin',
      ),
      isFalse,
    );
    expect(database.updates, isEmpty);
  });

  test('admin creates a verified merchant profile without OTP fields',
      () async {
    final database = _MerchantAccountDatabase();
    final service = AdminService(databaseService: database);

    final created = await service.createMerchantAccountForAdmin(
      fullName: '  تاجر جديد  ',
      shopName: '  متجر جديد  ',
      phone: '0771234567',
      password: 'secure-pass',
      adminId: 'admin-1',
      shopCategory: 'أجهزة',
      shopLocation: 'شارع الزبيري، صنعاء',
      city: 'صنعاء',
      shopContactPhones: ['0772345678'],
      shopWallets: [
        {'provider': 'محفظة الاختبار', 'account_number': '777123456'},
      ],
    );

    expect(created, isTrue);
    final profile = database.records['profiles/967771234567']!;
    expect(profile['id'], '967771234567');
    expect(profile['full_name'], 'تاجر جديد');
    expect(profile['shop_name'], 'متجر جديد');
    expect(profile['city'], 'صنعاء');
    expect(profile['shop_region'], 'صنعاء');
    expect(profile['shop_location'], 'شارع الزبيري، صنعاء');
    expect(profile['shop_contact_phones'], ['+967772345678']);
    expect(profile['shop_wallets'], [
      {'provider': 'محفظة الاختبار', 'account_number': '777123456'},
    ]);
    expect(profile['phone'], '+967771234567');
    expect(profile['role'], 'merchant');
    expect(profile['is_verified'], isTrue);
    expect(profile['phone_verified_by_admin'], isTrue);
    expect(profile['phone_verified_by_admin_id'], 'admin-1');
    expect(profile['password_hash'], AuthService().hashPassword('secure-pass'));
    expect(profile.containsKey('otp'), isFalse);
    expect(profile.containsKey('verification_code'), isFalse);
  });

  test('admin merchant creation rejects duplicate phone numbers', () async {
    final database = _MerchantAccountDatabase()
      ..records['profiles/967771234567'] = {'role': 'customer'};
    final service = AdminService(databaseService: database);

    final created = await service.createMerchantAccountForAdmin(
      fullName: 'تاجر',
      shopName: 'متجر',
      phone: '+967771234567',
      password: 'secure-pass',
      adminId: 'admin-1',
    );

    expect(created, isFalse);
    expect(database.writes, isEmpty);
  });

  test('admin merchant creation validates extra phones and wallet pairs',
      () async {
    final database = _MerchantAccountDatabase();
    final service = AdminService(databaseService: database);

    Future<bool> createMerchant({
      List<String> shopContactPhones = const [],
      List<Map<String, String>> shopWallets = const [],
    }) {
      return service.createMerchantAccountForAdmin(
        fullName: 'تاجر',
        shopName: 'متجر',
        phone: '0771234567',
        password: 'secure-pass',
        adminId: 'admin-1',
        shopContactPhones: shopContactPhones,
        shopWallets: shopWallets,
      );
    }

    await expectLater(
      createMerchant(shopContactPhones: ['رقم غير صالح']),
      throwsArgumentError,
    );
    await expectLater(
      createMerchant(
        shopWallets: [
          {'provider': 'محفظة', 'account_number': ''},
        ],
      ),
      throwsArgumentError,
    );
    expect(database.writes, isEmpty);
  });

  test('admin dashboard data requests propagate database errors', () async {
    final service = AdminService(
      databaseService: _ProfilesDatabase({}, failReads: true),
    );

    await expectLater(service.getDashboardStats(), throwsStateError);
    await expectLater(service.getManagementSummary(), throwsStateError);
  });

  test('admin orders can be loaded without a limit and filtered by status',
      () async {
    final service = AdminService(
      databaseService: _ProfilesDatabase({
        'older': {
          'status': 'confirmed',
          'created_at': '2026-10-18T10:00:00.000Z',
        },
        'newer': {
          'status': 'pending_payment',
          'created_at': '2026-10-20T10:00:00.000Z',
        },
        'newest': {
          'status': 'confirmed',
          'created_at': '2026-10-21T10:00:00.000Z',
        },
      }),
    );

    final allOrders = await service.getOrdersForAdmin(limit: null);
    final confirmedOrders =
        await service.getOrdersForAdmin(status: 'confirmed', limit: null);

    expect(allOrders.map((order) => order['id']), ['newest', 'newer', 'older']);
    expect(
      confirmedOrders.map((order) => order['id']),
      ['newest', 'older'],
    );
  });

  test('admin order read failures can be surfaced to the screen', () async {
    final service = AdminService(
      databaseService: _ProfilesDatabase({}, failReads: true),
    );

    expect(await service.getOrdersForAdmin(limit: null), isEmpty);
    await expectLater(
      service.getOrdersForAdmin(limit: null, propagateErrors: true),
      throwsStateError,
    );
  });

  test('dispatcher active orders include assigned live deliveries only',
      () async {
    final service = AdminService(
      databaseService: _TrackingDatabase({
        'orders': {
          'active': {
            'dispatcher_id': 'dispatcher-1',
            'driver_id': 'driver-1',
            'status': 'shipped',
            'customer_id': 'customer-1',
          },
          'delivered': {
            'dispatcher_id': 'dispatcher-1',
            'driver_id': 'driver-1',
            'status': 'delivered',
          },
          'other-dispatcher': {
            'dispatcher_id': 'dispatcher-2',
            'driver_id': 'driver-1',
            'status': 'shipped',
          },
        },
        'profiles': {
          'customer-1': {'full_name': 'Customer', 'address': 'District 1'},
          'driver-1': {'full_name': 'Driver'},
        },
      }),
    );

    final orders =
        await service.getActiveDispatcherOrders(dispatcherId: 'dispatcher-1');

    expect(orders, hasLength(1));
    expect(orders.single['id'], 'active');
    expect(orders.single['customer_name'], 'Customer');
    expect(orders.single['driver_name'], 'Driver');
    expect(orders.single['delivery_address'], 'District 1');
  });

  test('dispatcher orders are newest first and expose personal starred state',
      () async {
    final database = _TrackingDatabase({
      'orders': {
        'older': {
          'status': 'confirmed',
          'created_at': '2026-10-18T10:00:00.000Z',
        },
        'newer': {
          'status': 'preparing',
          'created_at': '2026-10-21T10:00:00.000Z',
        },
        'undated': {'status': 'accepted'},
      },
      'profiles': {},
      'dispatcher_starred_orders/dispatcher-1': {'newer': true},
    });
    final service = AdminService(databaseService: database);

    final orders = await service.getOrdersAwaitingDispatch(
      dispatcherId: 'dispatcher-1',
    );

    expect(orders.map((order) => order['id']), ['newer', 'older', 'undated']);
    expect(orders.map((order) => order['is_starred']), [true, false, false]);

    expect(
      await service.setDispatcherOrderStarred(
        dispatcherId: 'dispatcher-1',
        orderId: 'older',
        starred: true,
      ),
      isTrue,
    );
    expect(database.updates.single['path'],
        'dispatcher_starred_orders/dispatcher-1');
    expect(database.updates.single['data'], {'older': true});
  });

  test('dispatcher tracking snapshot uses latest coordinates and party data',
      () async {
    final service = AdminService(
      databaseService: _TrackingDatabase({
        'orders/order-1': {
          'customer_id': 'customer-1',
          'driver_id': 'driver-1',
          'items': [
            {'merchant_id': 'merchant-1'},
          ],
          'status': 'shipped',
        },
        'delivery_updates': {
          'older': {
            'order_id': 'order-1',
            'driver_latitude': 10.1,
            'driver_longitude': 20.1,
            'created_at': '2026-10-22T10:00:00.000Z',
          },
          'newer': {
            'order_id': 'order-1',
            'driver_latitude': 10.2,
            'driver_longitude': 20.2,
            'created_at': '2026-10-22T11:00:00.000Z',
          },
        },
        'profiles/customer-1': {'full_name': 'Customer'},
        'profiles/driver-1': {'full_name': 'Driver'},
        'profiles/merchant-1': {'shop_name': 'Store'},
      }),
    );

    final order = await service.getOrderTrackingSnapshot('order-1');

    expect(order?['latest_delivery_update']['driver_latitude'], 10.2);
    expect(order?['customer_snapshot']['full_name'], 'Customer');
    expect(order?['driver_snapshot']['full_name'], 'Driver');
    expect(order?['merchant_snapshots']['merchant-1']['shop_name'], 'Store');
  });

  test('driver ETA updates do not store GPS coordinates', () async {
    final database = _TrackingDatabase({
      'orders/order-1': {
        'driver_id': 'driver-1',
        'customer_id': 'customer-1',
        'status': 'shipped',
      },
    });
    final service = AdminService(databaseService: database);

    final updated = await service.updateDriverEta(
      orderId: 'order-1',
      driverId: 'driver-1',
      driverName: 'Driver',
      eta: '10 minutes',
    );

    expect(updated, isTrue);
    expect(database.updates.first['path'], 'orders/order-1');
    expect(
      (database.updates.first['data'] as Map<String, dynamic>)['eta'],
      '10 minutes',
    );
    expect(
      (database.updates.first['data'] as Map<String, dynamic>)
          .containsKey('driver_latitude'),
      isFalse,
    );
    expect(
      (database.writes.single['data'] as Map<String, dynamic>)
          .containsKey('driver_longitude'),
      isFalse,
    );
  });

  test('admin archive filters and actions preserve linked records', () async {
    final database = _ProfilesDatabase({
      'active-user': {'role': 'customer'},
      'archived-user': {'role': 'merchant', 'is_archived': true},
    });
    final service = AdminService(databaseService: database);
    final ordersService = AdminService(
      databaseService: _ProfilesDatabase({
        'active-order': {'status': 'delivered'},
        'archived-order': {'status': 'delivered', 'is_archived': true},
      }),
    );

    final activeProfiles = await service.getProfilesForAdmin(limit: null);
    final allProfiles = await service.getProfilesForAdmin(
      limit: null,
      includeArchived: true,
    );
    expect(activeProfiles.map((profile) => profile['id']), ['active-user']);
    expect(allProfiles.map((profile) => profile['id']),
        containsAll(['active-user', 'archived-user']));

    final activeOrders = await ordersService.getOrdersForAdmin(limit: null);
    final allOrders = await ordersService.getOrdersForAdmin(
      limit: null,
      includeArchived: true,
    );
    expect(activeOrders.map((order) => order['id']), ['active-order']);
    expect(allOrders.map((order) => order['id']),
        containsAll(['active-order', 'archived-order']));

    expect(
      await service.setProfileArchivedForAdmin(
        profileId: ' user-1 ',
        archived: true,
      ),
      isTrue,
    );
    expect(
      await service.setOrderArchivedForAdmin(
        orderId: ' order-1 ',
        archived: true,
      ),
      isTrue,
    );
    expect(
      await service.setProductArchivedForAdmin(
        productId: ' product-1 ',
        archived: true,
      ),
      isTrue,
    );
    expect(
      database.updates.map((update) => update['path']),
      ['profiles/user-1', 'orders/order-1', 'products/product-1'],
    );
    for (final update in database.updates) {
      final data = update['data'] as Map<String, dynamic>;
      expect(data['is_archived'], isTrue);
      expect(data['archived_at'], isA<String>());
    }
  });

  test('admin can confirm, prepare, and reject orders with customer sync',
      () async {
    final database = _OrderAdminDatabase({
      'orders/order-1': {
        'status': 'new',
        'customer_id': 'customer-1',
      },
    });
    final service = AdminService(databaseService: database);

    expect(
      await service.updateOrderStatusForAdmin(
        orderId: 'order-1',
        status: 'confirmed',
      ),
      isTrue,
    );
    expect(database.records['orders/order-1']!['status'], 'confirmed');
    expect(
      database.records['customers/customer-1/orders/order-1']!['status'],
      'confirmed',
    );

    expect(
      await service.updateOrderStatusForAdmin(
        orderId: 'order-1',
        status: 'preparing',
      ),
      isTrue,
    );
    expect(database.records['orders/order-1']!['status'], 'preparing');

    expect(
      await service.updateOrderStatusForAdmin(
        orderId: 'order-1',
        status: 'rejected',
      ),
      isTrue,
    );
    expect(database.records['orders/order-1']!['status'], 'rejected');
    expect(database.records['orders/order-1']!['rejected_by'], 'admin');
    expect(
      database.records['customers/customer-1/orders/order-1']!['status'],
      'rejected',
    );
    expect(
      database.records['notifications/order-order-1-rejected']!['title'],
      'تم رفض طلبك',
    );
  });

  test('admin can reassign an order and revoke the previous pickup code',
      () async {
    final database = _OrderAdminDatabase({
      'orders/order-1': {
        'status': 'shipped',
        'driver_id': 'old-driver',
        'driver_name': 'Old Driver',
        'driver_phone': '700000001',
        'driver_status': 'assigned',
        'pickup_otp': '123456',
        'pickup_otp_hash': 'old-hash',
        'pickup_otp_salt': 'old-salt',
        'pickup_otp_expires_at':
            DateTime.now().add(const Duration(minutes: 10)).toIso8601String(),
        'pickup_otp_verified': false,
      },
    });
    final service = AdminService(databaseService: database);

    expect(
      await service.reassignOrderToDriver(
        orderId: 'order-1',
        currentDriverId: 'old-driver',
        currentDriverName: 'Old Driver',
        currentDriverPhone: '700000001',
        driverName: 'New Driver',
        driverId: 'new-driver',
        driverPhone: '700000002',
      ),
      isTrue,
    );

    final order = database.records['orders/order-1']!;
    expect(order['driver_id'], 'new-driver');
    expect(order['driver_name'], 'New Driver');
    expect(order['driver_status'], 'assigned');
    expect(order['pickup_otp_hash'], isNull);

    final newPickupOtp =
        await service.prepareOrderHandoffForAdmin(orderId: 'order-1');
    expect(newPickupOtp, matches(RegExp(r'^\d{6}$')));
    expect(newPickupOtp, isNot('123456'));

    final notifications = database.records.values
        .where((record) =>
            record['type'] == 'delivery_assignment_cancelled' ||
            record['type'] == 'delivery_assignment')
        .toList();
    expect(
      notifications.map((notification) => notification['profile_id']),
      containsAll(['old-driver', 'new-driver']),
    );
  });

  test('admin cannot reassign stale or picked-up driver assignments', () async {
    final database = _OrderAdminDatabase({
      'orders/stale': {
        'status': 'preparing',
        'driver_id': 'current-driver',
        'driver_name': 'Current Driver',
        'driver_status': 'assigned',
      },
      'orders/picked-up': {
        'status': 'picked_up',
        'driver_id': 'current-driver',
        'driver_name': 'Current Driver',
        'driver_status': 'picked_up',
      },
    });
    final service = AdminService(databaseService: database);

    for (final orderId in ['stale', 'picked-up']) {
      expect(
        await service.reassignOrderToDriver(
          orderId: orderId,
          currentDriverId: 'old-driver',
          currentDriverName: 'Old Driver',
          currentDriverPhone: '',
          driverName: 'New Driver',
          driverId: 'new-driver',
          driverPhone: '',
        ),
        isFalse,
      );
    }

    expect(database.records['orders/stale']!['driver_id'], 'current-driver');
    expect(
      database.records['orders/picked-up']!['driver_id'],
      'current-driver',
    );
  });

  test('admin handoff requires an assigned driver and hides OTP from customer',
      () async {
    final database = _OrderAdminDatabase({
      'orders/order-1': {
        'status': 'preparing',
        'customer_id': 'customer-1',
      },
    });
    final service = AdminService(databaseService: database);

    expect(
      await service.prepareOrderHandoffForAdmin(orderId: 'order-1'),
      isNull,
    );

    database.records['orders/order-1']!['driver_id'] = 'driver-1';
    final otp = await service.prepareOrderHandoffForAdmin(orderId: 'order-1');

    expect(otp, matches(RegExp(r'^\d{6}$')));
    expect(database.records['orders/order-1']!['status'], 'shipped');
    expect(
      database.records['customers/customer-1/orders/order-1']!
          .containsKey('pickup_otp'),
      isFalse,
    );
    expect(
      database.records['customers/customer-1/orders/order-1']!
          .containsKey('pickup_otp_hash'),
      isFalse,
    );
  });

  test('admin can hand off to an assigned driver without pickup OTP', () async {
    final database = _OrderAdminDatabase({
      'orders/order-1': {
        'status': 'preparing',
        'customer_id': 'customer-1',
      },
    });
    final service = AdminService(databaseService: database);

    expect(
      await service.handoffOrderToDriverWithoutPickupOtpForAdmin(
        orderId: 'order-1',
      ),
      isNull,
    );
    expect(database.records['orders/order-1']!['status'], 'preparing');

    database.records['orders/order-1']!['driver_id'] = 'driver-1';
    final handedOff =
        await service.handoffOrderToDriverWithoutPickupOtpForAdmin(
      orderId: 'order-1',
    );

    expect(handedOff?.status, 'picked_up');
    expect(
      database.records['orders/order-1']!['customer_delivery_otp_hash'],
      isNull,
    );
    expect(database.records['orders/order-1']!['pickup_otp_bypassed_by_admin'],
        isTrue);
    expect(
      database.records['customers/customer-1/orders/order-1']!
          .containsKey('customer_delivery_otp_hash'),
      isFalse,
    );
  });

  test('admin permanently deletes order and customer copy', () async {
    final database = _OrderAdminDatabase({
      'orders/order-1': {
        'status': 'delivered',
        'customer_id': 'customer-1',
      },
      'customers/customer-1/orders/order-1': {'status': 'delivered'},
    });
    final service = AdminService(databaseService: database);

    expect(
      await service.deleteOrderForAdmin(orderId: 'order-1'),
      isTrue,
    );
    expect(database.records.containsKey('orders/order-1'), isFalse);
    expect(
      database.records.containsKey('customers/customer-1/orders/order-1'),
      isFalse,
    );
    expect(
      database.deletedPaths,
      [
        'customers/customer-1/orders/order-1',
        'orders/order-1',
      ],
    );
  });
}

class _OrderAdminDatabase implements DatabaseService {
  _OrderAdminDatabase(this.records);

  final Map<String, Map<String, dynamic>> records;
  final List<String> deletedPaths = [];

  @override
  Future<Map<String, dynamic>> read(String path) async =>
      Map<String, dynamic>.from(records[path] ?? const {});

  @override
  Future<Map<String, dynamic>> write(
    String path,
    Map<String, dynamic> data,
  ) async {
    final saved = Map<String, dynamic>.from(data);
    records[path] = saved;
    return Map<String, dynamic>.from(saved);
  }

  @override
  Future<Map<String, dynamic>> update(
    String path,
    Map<String, dynamic> data,
  ) async {
    final current = records[path] ?? const <String, dynamic>{};
    final saved = {...current, ...data};
    records[path] = saved;
    return Map<String, dynamic>.from(saved);
  }

  @override
  Future<Map<String, dynamic>?> updateIf(
    String path, {
    required bool Function(Map<String, dynamic> current) condition,
    required Map<String, dynamic> updates,
  }) async {
    final current = records[path];
    if (current == null || !condition(Map<String, dynamic>.from(current))) {
      return null;
    }
    final saved = {...current, ...updates};
    records[path] = saved;
    return Map<String, dynamic>.from(saved);
  }

  @override
  Future<void> delete(String path) async {
    deletedPaths.add(path);
    records.remove(path);
  }
}

class _MerchantAccountDatabase implements DatabaseService {
  final Map<String, Map<String, dynamic>> records = {};
  final List<String> writes = [];

  @override
  Future<Map<String, dynamic>> read(String path) async =>
      Map<String, dynamic>.from(records[path] ?? const {});

  @override
  Future<Map<String, dynamic>> write(
    String path,
    Map<String, dynamic> data,
  ) async {
    writes.add(path);
    records[path] = Map<String, dynamic>.from(data);
    return data;
  }

  @override
  Future<Map<String, dynamic>> update(
    String path,
    Map<String, dynamic> data,
  ) async =>
      data;

  @override
  Future<Map<String, dynamic>?> updateIf(
    String path, {
    required bool Function(Map<String, dynamic> current) condition,
    required Map<String, dynamic> updates,
  }) async =>
      updates;

  @override
  Future<void> delete(String path) async {}
}

class _ProfilesDatabase implements DatabaseService {
  _ProfilesDatabase(this.profiles, {this.failReads = false});

  final Map<String, dynamic> profiles;
  final bool failReads;
  final List<Map<String, dynamic>> updates = [];

  @override
  Future<Map<String, dynamic>> read(String path) async {
    if (failReads) throw StateError('database unavailable');
    return profiles;
  }

  @override
  Future<Map<String, dynamic>> write(
    String path,
    Map<String, dynamic> data,
  ) async =>
      data;

  @override
  Future<Map<String, dynamic>> update(
    String path,
    Map<String, dynamic> data,
  ) async {
    updates.add({'path': path, 'data': data});
    return data;
  }

  @override
  Future<Map<String, dynamic>?> updateIf(
    String path, {
    required bool Function(Map<String, dynamic> current) condition,
    required Map<String, dynamic> updates,
  }) async =>
      updates;

  @override
  Future<void> delete(String path) async {}
}

class _TrackingDatabase implements DatabaseService {
  _TrackingDatabase(this.data);

  final Map<String, Map<String, dynamic>> data;
  final List<Map<String, dynamic>> updates = [];
  final List<Map<String, dynamic>> writes = [];

  @override
  Future<Map<String, dynamic>> read(String path) async =>
      Map<String, dynamic>.from(data[path] ?? const {});

  @override
  Future<Map<String, dynamic>> write(
    String path,
    Map<String, dynamic> data,
  ) async {
    writes.add({'path': path, 'data': data});
    return data;
  }

  @override
  Future<Map<String, dynamic>> update(
    String path,
    Map<String, dynamic> data,
  ) async {
    updates.add({'path': path, 'data': data});
    return data;
  }

  @override
  Future<Map<String, dynamic>?> updateIf(
    String path, {
    required bool Function(Map<String, dynamic> current) condition,
    required Map<String, dynamic> updates,
  }) async =>
      updates;

  @override
  Future<void> delete(String path) async {}
}
