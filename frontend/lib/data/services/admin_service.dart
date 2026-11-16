import 'package:she_m_app/core/constants/app_constants.dart';
import 'package:she_m_app/data/models/order_model.dart';
import 'package:she_m_app/data/services/currency_service.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/data/services/notification_service.dart';
import 'package:she_m_app/data/services/order_service.dart';

class AdminDashboardStats {
  final String revenueLabel;
  final int unconvertedOrderCount;
  final int totalOrders;
  final int totalMerchants;
  final int totalCustomers;

  const AdminDashboardStats({
    required this.revenueLabel,
    this.unconvertedOrderCount = 0,
    required this.totalOrders,
    required this.totalMerchants,
    required this.totalCustomers,
  });

  factory AdminDashboardStats.fromJson(Map<String, dynamic> json) {
    final revenue = json['revenue'] is num ? json['revenue'] as num : 0;
    final totalOrders = json['orders'] is num ? json['orders'] as num : 0;
    final totalMerchants =
        json['merchants'] is num ? json['merchants'] as num : 0;
    final totalCustomers =
        json['customers'] is num ? json['customers'] as num : 0;

    return AdminDashboardStats(
      revenueLabel: _formatCurrency(
        revenue.toDouble(),
        CurrencyService.yerCurrency.symbol,
      ),
      totalOrders: totalOrders.toInt(),
      totalMerchants: totalMerchants.toInt(),
      totalCustomers: totalCustomers.toInt(),
    );
  }

  static String _formatCurrency(double value, String symbol) {
    final whole = value.round();
    final formatted = whole.toString().replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (match) => ',',
        );
    return '$formatted $symbol';
  }
}

class AdminManagementSummary {
  final int totalOrders;
  final int totalMerchants;
  final int totalCustomers;
  final int totalProducts;
  final int availableProducts;
  final int pendingApprovals;
  final int activeDeliveries;
  final int unreadNotifications;

  const AdminManagementSummary({
    required this.totalOrders,
    required this.totalMerchants,
    required this.totalCustomers,
    required this.totalProducts,
    required this.availableProducts,
    required this.pendingApprovals,
    required this.activeDeliveries,
    required this.unreadNotifications,
  });

  factory AdminManagementSummary.fromJson(Map<String, dynamic> json) {
    final orders = _asInt(json['orders']);
    final merchants = _asInt(json['merchants']);
    final customers = _asInt(json['customers']);

    final products = json['products'];
    final productRows = products is List ? products : const <dynamic>[];
    final totalProducts = productRows.length;
    final availableProducts = productRows.where((row) {
      if (row is! Map) return false;
      final item = Map<String, dynamic>.from(row);
      final available = item['available'];
      return available == true || available == 'true';
    }).length;

    final pendingProofs = _asInt(json['pending_proofs']);
    final notificationCount = _asInt(json['notifications']);

    final statusRows = json['orders_status'];
    final activeDeliveries = statusRows is List
        ? statusRows.where((row) {
            if (row is! Map) return false;
            final item = Map<String, dynamic>.from(row);
            final status = item['status']?.toString();
            return status == 'confirmed' ||
                status == 'preparing' ||
                status == 'shipped';
          }).length
        : 0;

    return AdminManagementSummary(
      totalOrders: orders,
      totalMerchants: merchants,
      totalCustomers: customers,
      totalProducts: totalProducts,
      availableProducts: availableProducts,
      pendingApprovals: pendingProofs,
      activeDeliveries: activeDeliveries,
      unreadNotifications: notificationCount,
    );
  }

  const AdminManagementSummary.fallback()
      : totalOrders = 4820,
        totalMerchants = 96,
        totalCustomers = 14220,
        totalProducts = 1458,
        availableProducts = 1360,
        pendingApprovals = 18,
        activeDeliveries = 27,
        unreadNotifications = 327;

  static int _asInt(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

class AdminDriverDispatchSummary {
  final int activeDrivers;
  final int inTransitOrders;
  final int availableDrivers;
  final List<Map<String, dynamic>> assignments;

  const AdminDriverDispatchSummary({
    required this.activeDrivers,
    required this.inTransitOrders,
    required this.availableDrivers,
    required this.assignments,
  });

  factory AdminDriverDispatchSummary.fromJson(Map<String, dynamic> json) {
    final activeDrivers = _asInt(json['active_drivers']);
    final inTransitOrders = _asInt(json['in_transit']);
    final availableDrivers = _asInt(json['available_drivers']);

    final rows = json['assignments'];
    final assignments = rows is List
        ? rows
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
        : const <Map<String, dynamic>>[];

    return AdminDriverDispatchSummary(
      activeDrivers: activeDrivers,
      inTransitOrders: inTransitOrders,
      availableDrivers: availableDrivers,
      assignments: assignments,
    );
  }

  const AdminDriverDispatchSummary.fallback()
      : activeDrivers = 24,
        inTransitOrders = 12,
        availableDrivers = 7,
        assignments = const [
          {
            'order_id': '#1042',
            'courier_name': 'سائق كريم',
            'status': 'preparing',
          },
          {
            'order_id': '#1078',
            'courier_name': 'سائق محمد',
            'status': 'shipped',
          },
        ];

  static int _asInt(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

enum DispatcherReportPeriod { daily, monthly, yearly }

class DispatcherPerformanceReport {
  final int totalAssigned;
  final int delivered;
  final int cancelled;
  final int inProgress;
  final double totalOrderValue;
  final int unconvertedOrderCount;
  final List<Map<String, dynamic>> orders;

  const DispatcherPerformanceReport({
    required this.totalAssigned,
    required this.delivered,
    required this.cancelled,
    required this.inProgress,
    required this.totalOrderValue,
    this.unconvertedOrderCount = 0,
    required this.orders,
  });
}

class AdminService {
  AdminService({DatabaseService? databaseService})
      : _databaseService = databaseService ?? FirebaseDatabaseService.instance;

  final DatabaseService _databaseService;

  bool _hasAssignedDriver(Map<String, dynamic> order) {
    final driverId =
        (order['driver_id'] ?? order['driverId'] ?? '').toString().trim();
    final driverPhone =
        (order['driver_phone'] ?? order['driverPhone'] ?? '').toString().trim();
    final courierName = (order['courier_name'] ?? order['driver_name'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    const unassignedNames = {
      '',
      'غير مخصص',
      'غير مخصص بعد',
      'غير معين',
      'unassigned',
    };
    return driverId.isNotEmpty ||
        driverPhone.isNotEmpty ||
        !unassignedNames.contains(courierName);
  }

  Future<AdminDashboardStats> getDashboardStats() async {
    final database = _databaseService;
    final snapshots = await Future.wait([
      database.read('orders'),
      database.read('profiles'),
    ]);
    final orders = snapshots[0].values.whereType<Map>();
    final profiles = snapshots[1].values.whereType<Map>();
    final currencies =
        await CurrencyService(databaseService: database).getCurrencies();
    final revenue = orders.fold<double>(0, (sum, order) {
      return sum +
          (CurrencyOption.orderTotalInYER(
                Map<String, dynamic>.from(order),
                currencies,
              ) ??
              0);
    });
    final unconvertedOrderCount = orders
        .where((order) =>
            CurrencyOption.orderTotalInYER(
              Map<String, dynamic>.from(order),
              currencies,
            ) ==
            null)
        .length;
    final merchants = profiles.where((profile) =>
        (profile['role'] ?? '').toString().toLowerCase() == 'merchant');
    final customers = profiles.where((profile) =>
        (profile['role'] ?? '').toString().toLowerCase() == 'customer');
    return AdminDashboardStats(
      revenueLabel: AdminDashboardStats._formatCurrency(
        revenue,
        CurrencyService.yerCurrency.symbol,
      ),
      unconvertedOrderCount: unconvertedOrderCount,
      totalOrders: orders.length,
      totalMerchants: merchants.length,
      totalCustomers: customers.length,
    );
  }

  Future<List<Map<String, dynamic>>> getRecentOrders({int limit = 5}) async {
    return const <Map<String, dynamic>>[];
  }

  Future<List<Map<String, dynamic>>> getRecentProducts({int limit = 5}) async {
    return const <Map<String, dynamic>>[];
  }

  Future<List<Map<String, dynamic>>> getRecentProfiles({
    String? role,
    int limit = 5,
  }) async {
    return const <Map<String, dynamic>>[];
  }

  Future<List<Map<String, dynamic>>> getOrdersForAdmin({
    String? status,
    int? limit = 10,
    bool propagateErrors = false,
    bool includeArchived = false,
  }) async {
    if (limit != null && limit <= 0) return const <Map<String, dynamic>>[];
    try {
      final orders = await _databaseService.read('orders');
      final requestedStatus = status?.trim();
      final rows = orders.entries
          .where((entry) => entry.value is Map)
          .map((entry) {
            final order = Map<String, dynamic>.from(entry.value as Map);
            order.putIfAbsent('id', () => entry.key);
            return order;
          })
          .where((order) =>
              (includeArchived || order['is_archived'] != true) &&
              (requestedStatus == null ||
                  requestedStatus.isEmpty ||
                  order['status']?.toString() == requestedStatus))
          .toList()
        ..sort((left, right) {
          final leftDate =
              DateTime.tryParse(left['created_at']?.toString() ?? '') ??
                  DateTime.fromMillisecondsSinceEpoch(0);
          final rightDate =
              DateTime.tryParse(right['created_at']?.toString() ?? '') ??
                  DateTime.fromMillisecondsSinceEpoch(0);
          return rightDate.compareTo(leftDate);
        });
      return limit == null ? rows : rows.take(limit).toList();
    } catch (_) {
      if (propagateErrors) rethrow;
      return const <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> getProductsForAdmin(
      {int limit = 10}) async {
    return const <Map<String, dynamic>>[];
  }

  Future<List<Map<String, dynamic>>> getProfilesForAdmin({
    String? role,
    int? limit = 10,
    bool propagateErrors = false,
    bool includeArchived = false,
  }) async {
    if (limit != null && limit <= 0) {
      return const <Map<String, dynamic>>[];
    }
    try {
      final profiles = await _databaseService.read('profiles');
      final requestedRole = role?.trim().toLowerCase();
      final rows = profiles.entries
          .where((entry) => entry.value is Map)
          .map((entry) {
            final profile = Map<String, dynamic>.from(entry.value as Map);
            profile.putIfAbsent('id', () => entry.key);
            return profile;
          })
          .where((profile) =>
              (includeArchived || profile['is_archived'] != true) &&
              (requestedRole == null ||
                  requestedRole.isEmpty ||
                  profile['role']?.toString().toLowerCase() == requestedRole))
          .toList();
      return limit == null ? rows : rows.take(limit).toList();
    } catch (_) {
      if (propagateErrors) rethrow;
      return const <Map<String, dynamic>>[];
    }
  }

  Future<bool> setProfileArchivedForAdmin({
    required String profileId,
    required bool archived,
  }) async {
    final normalizedId = profileId.trim();
    if (normalizedId.isEmpty) return false;
    await _databaseService.update('profiles/$normalizedId', {
      'is_archived': archived,
      'archived_at': archived ? DateTime.now().toIso8601String() : null,
    });
    return true;
  }

  Future<bool> setOrderArchivedForAdmin({
    required String orderId,
    required bool archived,
  }) async {
    final normalizedId = orderId.trim();
    if (normalizedId.isEmpty) return false;
    await _databaseService.update('orders/$normalizedId', {
      'is_archived': archived,
      'archived_at': archived ? DateTime.now().toIso8601String() : null,
    });
    return true;
  }

  Future<bool> setProductArchivedForAdmin({
    required String productId,
    required bool archived,
  }) async {
    final normalizedId = productId.trim();
    if (normalizedId.isEmpty) return false;
    await _databaseService.update('products/$normalizedId', {
      'is_archived': archived,
      'archived_at': archived ? DateTime.now().toIso8601String() : null,
    });
    return true;
  }

  Future<bool> updateOrderStatusForAdmin({
    required String orderId,
    required String status,
  }) async {
    final normalizedId = orderId.trim();
    final normalizedStatus = status.trim();
    if (normalizedId.isEmpty) return false;

    final now = DateTime.now().toUtc().toIso8601String();
    late final Set<String> allowedCurrentStatuses;
    late final Map<String, dynamic> updates;
    switch (normalizedStatus) {
      case 'confirmed':
        allowedCurrentStatuses = {
          'new',
          'pending_payment',
          'awaiting_confirmation',
        };
        updates = {'status': 'confirmed', 'confirmed_at': now};
        break;
      case 'preparing':
        allowedCurrentStatuses = {'confirmed', 'accepted'};
        updates = {'status': 'preparing', 'preparing_at': now};
        break;
      case 'rejected':
        allowedCurrentStatuses = {
          'new',
          'pending_payment',
          'awaiting_confirmation',
          'confirmed',
          'accepted',
          'preparing',
        };
        updates = {
          'status': 'rejected',
          'rejected_by': 'admin',
          'rejection_reason': 'تم رفض الطلب من المسؤول',
          'rejected_at': now,
        };
        break;
      default:
        return false;
    }

    final saved = await _databaseService.updateIf(
      'orders/$normalizedId',
      condition: (current) =>
          allowedCurrentStatuses.contains(current['status']?.toString()),
      updates: updates,
    );
    if (saved == null) return false;

    final customerId =
        (saved['customer_id'] ?? saved['customerId'] ?? '').toString().trim();
    if (customerId.isNotEmpty) {
      await _databaseService.write(
        'customers/$customerId/orders/$normalizedId',
        sanitizeOrderForCustomer(saved),
      );
      await NotificationService(databaseService: _databaseService)
          .notifyOrderStatus(
        customerId: customerId,
        orderId: normalizedId,
        status: normalizedStatus,
        cancellationReason: saved['rejection_reason']?.toString(),
      );
    }
    return true;
  }

  Future<String?> prepareOrderHandoffForAdmin({
    required String orderId,
  }) async {
    final normalizedId = orderId.trim();
    if (normalizedId.isEmpty) return null;

    final order = await _databaseService.read('orders/$normalizedId');
    if (order.isEmpty ||
        !_hasAssignedDriver(order) ||
        !{'preparing', 'shipped'}.contains(order['status']?.toString())) {
      return null;
    }

    final prepared = await OrderService(databaseService: _databaseService)
        .prepareDeliveryOtp(normalizedId);
    return prepared?.pickupOtp;
  }

  Future<OrderModel?> handoffOrderToDriverWithoutPickupOtpForAdmin({
    required String orderId,
  }) async {
    final normalizedId = orderId.trim();
    if (normalizedId.isEmpty) return null;

    final order = await _databaseService.read('orders/$normalizedId');
    if (order.isEmpty ||
        !_hasAssignedDriver(order) ||
        !{'preparing', 'shipped'}.contains(order['status']?.toString())) {
      return null;
    }

    return OrderService(databaseService: _databaseService)
        .handoffToDriverWithoutPickupOtpForAdmin(orderId: normalizedId);
  }

  Future<bool> deleteOrderForAdmin({
    required String orderId,
    String? customerId,
  }) async {
    final normalizedId = orderId.trim();
    if (normalizedId.isEmpty) return false;

    final order = await _databaseService.read('orders/$normalizedId');
    final storedCustomerId =
        (order['customer_id'] ?? order['customerId'] ?? '').toString().trim();
    final normalizedCustomerId = storedCustomerId.isNotEmpty
        ? storedCustomerId
        : customerId?.trim() ?? '';
    if (order.isEmpty && normalizedCustomerId.isEmpty) return false;

    if (normalizedCustomerId.isNotEmpty) {
      await _databaseService
          .delete('customers/$normalizedCustomerId/orders/$normalizedId');
    }
    if (order.isNotEmpty) {
      await _databaseService.delete('orders/$normalizedId');
    }
    return true;
  }

  Future<bool> createProductForAdmin({
    required String name,
    required String category,
    required String description,
    required double price,
    required String merchantId,
    String imageUrl = '',
    bool available = true,
  }) async {
    return true;
  }

  Future<bool> createMerchantAccountForAdmin({
    required String fullName,
    required String shopName,
    required String phone,
    required String password,
    required String adminId,
    String? shopCategory,
    String? shopLocation,
    String? city,
    List<String> shopContactPhones = const [],
    List<Map<String, String>> shopWallets = const [],
  }) async {
    final normalizedPhone = AuthService().normalizePhone(phone);
    final normalizedName = fullName.trim();
    final normalizedShopName = shopName.trim();
    final normalizedAdminId = adminId.trim();
    final safePassword = password.trim();

    if (normalizedName.isEmpty || normalizedShopName.isEmpty) {
      throw ArgumentError('اسم التاجر واسم المتجر مطلوبان');
    }
    if (!AppConstants.isYemenPhoneValid(normalizedPhone)) {
      throw ArgumentError('رقم الهاتف غير صالح');
    }
    if (!AppConstants.isStrongPassword(safePassword)) {
      throw ArgumentError('كلمة المرور يجب ألا تقل عن 6 أحرف');
    }
    if (normalizedAdminId.isEmpty) {
      throw ArgumentError('تعذر التحقق من حساب المدير الحالي');
    }

    final normalizedContactPhones = shopContactPhones
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .map(AuthService().normalizePhone)
        .toList();
    if (normalizedContactPhones.any(
      (value) => !AppConstants.isYemenPhoneValid(value),
    )) {
      throw ArgumentError('أحد أرقام التواصل الإضافية غير صالح');
    }
    if (normalizedContactPhones.toSet().length !=
            normalizedContactPhones.length ||
        normalizedContactPhones.contains(normalizedPhone)) {
      throw ArgumentError('لا يمكن تكرار أرقام التواصل');
    }

    final normalizedWallets = <Map<String, String>>[];
    for (final wallet in shopWallets) {
      final provider = wallet['provider']?.trim() ?? '';
      final accountNumber = wallet['account_number']?.trim() ?? '';
      if (provider.isEmpty && accountNumber.isEmpty) continue;
      if (provider.isEmpty || accountNumber.isEmpty) {
        throw ArgumentError('أدخل اسم المحفظة ورقمها معًا');
      }
      normalizedWallets.add({
        'provider': provider,
        'account_number': accountNumber,
      });
    }

    final normalizedCity = city?.trim() ?? '';
    final profileId = normalizedPhone.replaceAll(RegExp(r'[^0-9]'), '');
    final profilePath = 'profiles/$profileId';
    final createdAt = DateTime.now().toUtc().toIso8601String();
    final payload = <String, dynamic>{
      'id': profileId,
      'full_name': normalizedName,
      'phone': normalizedPhone,
      'email': null,
      'role': 'merchant',
      'password_hash': AuthService().hashPassword(safePassword),
      'profile_image': null,
      'city': normalizedCity.isEmpty ? null : normalizedCity,
      'shop_name': normalizedShopName,
      'shop_category': shopCategory?.trim(),
      'shop_location': shopLocation?.trim(),
      'shop_region': normalizedCity.isEmpty ? null : normalizedCity,
      'shop_contact_phones': normalizedContactPhones,
      'shop_wallets': normalizedWallets,
      'is_verified': true,
      'phone_verified_by_admin': true,
      'phone_verified_at': createdAt,
      'phone_verified_by_admin_id': normalizedAdminId,
      'created_by_admin_id': normalizedAdminId,
      'created_at': createdAt,
    };

    if (_databaseService is FirebaseDatabaseService) {
      return _databaseService.createIfAbsent(profilePath, payload);
    }

    if ((await _databaseService.read(profilePath)).isNotEmpty) return false;
    await _databaseService.write(profilePath, payload);
    return true;
  }

  Future<bool> updateProductForAdmin({
    required String productId,
    String? name,
    String? category,
    String? description,
    double? price,
    String? imageUrl,
    bool? available,
  }) async {
    return true;
  }

  Future<bool> updateProductAvailabilityForAdmin({
    required String productId,
    required bool available,
  }) async {
    return true;
  }

  Future<bool> deleteProductForAdmin({required String productId}) async {
    return true;
  }

  Future<bool> updateProfileRoleForAdmin({
    required String profileId,
    required String role,
  }) async {
    final normalizedRole = role.trim().toLowerCase();
    const editableRoles = {'customer', 'merchant', 'driver'};
    if (profileId.trim().isEmpty || !editableRoles.contains(normalizedRole)) {
      return false;
    }
    await _databaseService.update('profiles/${profileId.trim()}', {
      'role': normalizedRole,
    });
    return true;
  }

  Future<bool> updateProfileVerificationForAdmin({
    required String profileId,
    required bool isVerified,
  }) async {
    if (profileId.trim().isEmpty) return false;
    await _databaseService.update('profiles/${profileId.trim()}', {
      'is_verified': isVerified,
    });
    return true;
  }

  Future<bool> updateMerchantDisplayDeliveryFeeForAdmin({
    required String merchantId,
    required double? deliveryFee,
  }) async {
    final normalizedId = merchantId.trim();
    if (normalizedId.isEmpty ||
        (deliveryFee != null && (!deliveryFee.isFinite || deliveryFee < 0))) {
      return false;
    }
    await _databaseService.update('profiles/$normalizedId', {
      'merchant_display_delivery_fee': deliveryFee,
    });
    return true;
  }

  Future<double?> getGlobalMerchantDisplayDeliveryFeeForAdmin() async {
    final pricing = await _databaseService.read('settings/pricing');
    final value = pricing['merchant_display_delivery_fee'];
    final fee = value is num ? value.toDouble() : double.tryParse('$value');
    return fee != null && fee.isFinite && fee >= 0 ? fee : null;
  }

  Future<bool> updateGlobalMerchantDisplayDeliveryFeeForAdmin({
    required double? deliveryFee,
  }) async {
    if (deliveryFee != null && (!deliveryFee.isFinite || deliveryFee < 0)) {
      return false;
    }
    await _databaseService.update('settings/pricing', {
      'merchant_display_delivery_fee': deliveryFee,
    });
    return true;
  }

  Future<bool> updateDriverAvailabilityForAdmin({
    required String driverId,
    required bool isAvailable,
  }) async {
    final normalizedId = driverId.trim();
    if (normalizedId.isEmpty) return false;
    await _databaseService.update('profiles/$normalizedId', {
      'is_available': isAvailable,
    });
    return true;
  }

  Future<AdminManagementSummary> getManagementSummary() async {
    final database = _databaseService;
    final snapshots = await Future.wait([
      database.read('orders'),
      database.read('profiles'),
      database.read('products'),
    ]);
    final orders = snapshots[0].values.whereType<Map>().toList();
    final profiles = snapshots[1].values.whereType<Map>().toList();
    final products = snapshots[2].values.whereType<Map>().toList();
    final activeDeliveries = orders.where((order) {
      const activeStatuses = {'confirmed', 'preparing', 'shipped'};
      return activeStatuses.contains(order['status']?.toString());
    }).length;
    return AdminManagementSummary(
      totalOrders: orders.length,
      totalMerchants: profiles
          .where((profile) => profile['role']?.toString() == 'merchant')
          .length,
      totalCustomers: profiles
          .where((profile) => profile['role']?.toString() == 'customer')
          .length,
      totalProducts: products.length,
      availableProducts: products.where((product) {
        final available = product['available'];
        return available == true || available?.toString() == 'true';
      }).length,
      pendingApprovals: orders
          .where((order) => order['status']?.toString() == 'pending_payment')
          .length,
      activeDeliveries: activeDeliveries,
      unreadNotifications: 0,
    );
  }

  Future<AdminDriverDispatchSummary> getDriverDispatchSummary({
    String? driverId,
    String? driverName,
    String? driverPhone,
    bool includeCompleted = false,
  }) async {
    final database = _databaseService;
    final snapshots = await Future.wait([
      database.read('orders'),
      database.read('profiles'),
    ]);
    final profiles = <String, Map<String, dynamic>>{};
    for (final entry in snapshots[1].entries) {
      if (entry.value is Map) {
        profiles[entry.key] = Map<String, dynamic>.from(entry.value as Map);
      }
    }

    final assignments = <Map<String, dynamic>>[];
    for (final entry in snapshots[0].entries) {
      if (entry.value is! Map) continue;
      final order = Map<String, dynamic>.from(entry.value as Map);
      final status = order['status']?.toString() ?? '';
      final isCompleted = {'delivered', 'cancelled'}.contains(status);
      if (!{
            'accepted',
            'confirmed',
            'preparing',
            'shipped',
            'picked_up',
            if (includeCompleted) ...{'delivered', 'cancelled'},
          }.contains(status) ||
          (isCompleted && !includeCompleted)) {
        continue;
      }
      final targetDriverId = driverId?.trim() ?? '';
      final targetDriverName = driverName?.trim() ?? '';
      final targetDriverPhone = driverPhone?.trim() ?? '';
      if (targetDriverId.isNotEmpty ||
          targetDriverName.isNotEmpty ||
          targetDriverPhone.isNotEmpty) {
        final assignedId =
            (order['driver_id'] ?? order['driverId'] ?? '').toString().trim();
        final assignedName =
            (order['courier_name'] ?? order['driver_name'] ?? '')
                .toString()
                .trim();
        final assignedPhone =
            (order['driver_phone'] ?? order['driverPhone'] ?? '')
                .toString()
                .trim();
        final matchesDriver = (targetDriverId.isNotEmpty &&
                assignedId == targetDriverId) ||
            (targetDriverName.isNotEmpty && assignedName == targetDriverName) ||
            (targetDriverPhone.isNotEmpty &&
                assignedPhone == targetDriverPhone);
        if (!matchesDriver) {
          continue;
        }
      }
      final orderId = order['id']?.toString() ?? entry.key;
      final customerId =
          (order['customer_id'] ?? order['customerId'] ?? '').toString();
      final customer = profiles[customerId] ?? const <String, dynamic>{};
      assignments.add({
        'order_id': orderId,
        'status': status,
        'driver_status': order['driver_status']?.toString() ?? 'assigned',
        'created_at': order['created_at'],
        'updated_at': order['updated_at'],
        'driver_id': order['driver_id'] ?? order['driverId'],
        'courier_name': order['courier_name']?.toString() ?? 'غير مخصص',
        'eta': order['eta']?.toString() ?? 'غير محدد',
        'customer_name': customer['full_name']?.toString() ?? 'عميل',
        'customer_phone': customer['phone']?.toString() ?? '',
        'total': order['total'],
        'currency_symbol': order['currency_symbol'] ??
            order['currencySymbol'] ??
            CurrencyService.yerCurrency.symbol,
        'delivery_address': order['delivery_address'] ??
            order['address'] ??
            customer['address'] ??
            'العنوان غير محدد',
        'latitude': order['latitude'] ?? order['customer_latitude'],
        'longitude': order['longitude'] ?? order['customer_longitude'],
      });
    }

    return AdminDriverDispatchSummary(
      activeDrivers: assignments
          .map(
              (item) => (item['driver_id'] ?? item['courier_name'])?.toString())
          .where((id) => id != null && id.isNotEmpty && id != 'غير مخصص')
          .toSet()
          .length,
      inTransitOrders:
          assignments.where((item) => item['status'] == 'picked_up').length,
      availableDrivers: profiles.values.where((profile) {
        final isDriver = profile['role']?.toString() == 'driver';
        final isAvailable = profile['is_available'] == true ||
            profile['is_available']?.toString().toLowerCase() == 'true' ||
            profile['isAvailable'] == true ||
            profile['isAvailable']?.toString().toLowerCase() == 'true';
        return isDriver && isAvailable;
      }).length,
      assignments: assignments,
    );
  }

  Future<List<Map<String, dynamic>>> getOrdersAwaitingDispatch({
    int limit = 100,
    String? dispatcherId,
  }) async {
    if (limit <= 0) return const <Map<String, dynamic>>[];
    final normalizedDispatcherId = dispatcherId?.trim() ?? '';
    final snapshots = await Future.wait([
      _databaseService.read('orders'),
      _databaseService.read('profiles'),
      if (normalizedDispatcherId.isNotEmpty)
        _databaseService.read(
          'dispatcher_starred_orders/$normalizedDispatcherId',
        ),
    ]);
    final starredOrderIds = normalizedDispatcherId.isEmpty
        ? const <String>{}
        : snapshots[2]
            .entries
            .where((entry) =>
                entry.value == true ||
                entry.value?.toString().toLowerCase() == 'true')
            .map((entry) => entry.key)
            .toSet();
    final profiles = <String, Map<String, dynamic>>{};
    for (final entry in snapshots[1].entries) {
      if (entry.value is Map) {
        profiles[entry.key] = Map<String, dynamic>.from(entry.value as Map);
      }
    }

    final orders =
        snapshots[0].entries.where((entry) => entry.value is Map).map((entry) {
      final order = Map<String, dynamic>.from(entry.value as Map);
      order.putIfAbsent('id', () => entry.key);
      return order;
    }).where((order) {
      const dispatchableStatuses = {
        'accepted',
        'confirmed',
        'preparing',
      };
      return dispatchableStatuses.contains(order['status']?.toString()) &&
          !_hasAssignedDriver(order);
    }).toList()
          ..sort((left, right) {
            final leftDate = DateTime.tryParse(
                  (left['created_at'] ?? left['createdAt'] ?? '').toString(),
                ) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final rightDate = DateTime.tryParse(
                  (right['created_at'] ?? right['createdAt'] ?? '').toString(),
                ) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return rightDate.compareTo(leftDate);
          });

    return orders.take(limit).map((order) {
      final customerId =
          (order['customer_id'] ?? order['customerId'] ?? '').toString();
      final customer = profiles[customerId] ?? const <String, dynamic>{};
      return {
        ...order,
        'is_starred': starredOrderIds.contains(order['id']?.toString()),
        'customer_name': customer['full_name']?.toString() ?? 'عميل',
        'customer_phone': customer['phone']?.toString() ?? '',
        'delivery_address': order['delivery_address'] ??
            order['address'] ??
            customer['address'] ??
            'العنوان غير محدد',
      };
    }).toList();
  }

  Future<bool> setDispatcherOrderStarred({
    required String dispatcherId,
    required String orderId,
    required bool starred,
  }) async {
    final normalizedDispatcherId = dispatcherId.trim();
    final normalizedOrderId = orderId.trim();
    if (normalizedDispatcherId.isEmpty || normalizedOrderId.isEmpty) {
      return false;
    }
    await _databaseService.update(
      'dispatcher_starred_orders/$normalizedDispatcherId',
      {normalizedOrderId: starred ? true : null},
    );
    return true;
  }

  Future<List<Map<String, dynamic>>> getActiveDispatcherOrders({
    required String dispatcherId,
  }) async {
    final ordersSnapshot = await _databaseService.read('orders');
    final profilesSnapshot = await _databaseService.read('profiles');
    final profiles = <String, Map<String, dynamic>>{};
    for (final entry in profilesSnapshot.entries) {
      if (entry.value is Map) {
        profiles[entry.key] = Map<String, dynamic>.from(entry.value as Map);
      }
    }
    const closedStatuses = {'delivered', 'cancelled', 'rejected'};
    final orders = ordersSnapshot.entries
        .where((entry) => entry.value is Map)
        .map((entry) {
      final order = Map<String, dynamic>.from(entry.value as Map);
      order.putIfAbsent('id', () => entry.key);
      return order;
    }).where((order) {
      final assignedDispatcher =
          (order['dispatcher_id'] ?? order['assigned_by_dispatcher_id'] ?? '')
              .toString()
              .trim();
      return assignedDispatcher == dispatcherId &&
          _hasAssignedDriver(order) &&
          !closedStatuses.contains(order['status']?.toString());
    }).toList()
      ..sort((left, right) {
        final leftDate = DateTime.tryParse(
              (left['dispatcher_assigned_at'] ?? left['assigned_at'] ?? '')
                  .toString(),
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final rightDate = DateTime.tryParse(
              (right['dispatcher_assigned_at'] ?? right['assigned_at'] ?? '')
                  .toString(),
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return rightDate.compareTo(leftDate);
      });

    return orders.map((order) {
      final customerId =
          (order['customer_id'] ?? order['customerId'] ?? '').toString();
      final driverId =
          (order['driver_id'] ?? order['driverId'] ?? '').toString();
      final merchantId =
          (order['merchant_id'] ?? order['merchantId'] ?? '').toString();
      final customer = profiles[customerId] ??
          (order['customer_snapshot'] is Map
              ? Map<String, dynamic>.from(order['customer_snapshot'] as Map)
              : const <String, dynamic>{});
      final driver = profiles[driverId] ??
          (order['driver_snapshot'] is Map
              ? Map<String, dynamic>.from(order['driver_snapshot'] as Map)
              : const <String, dynamic>{});
      final merchant = profiles[merchantId] ??
          (order['merchant_snapshot'] is Map
              ? Map<String, dynamic>.from(order['merchant_snapshot'] as Map)
              : const <String, dynamic>{});
      return {
        ...order,
        'customer_snapshot': customer,
        'driver_snapshot': driver,
        'merchant_snapshot': merchant,
        'customer_name': customer['full_name']?.toString() ??
            order['customer_name']?.toString() ??
            'عميل',
        'customer_phone': customer['phone']?.toString() ??
            order['customer_phone']?.toString() ??
            '',
        'driver_name': driver['full_name']?.toString() ??
            order['driver_name']?.toString() ??
            order['courier_name']?.toString() ??
            'غير محدد',
        'delivery_address': order['delivery_address'] ??
            order['shipping_address'] ??
            order['address'] ??
            customer['address'] ??
            'العنوان غير محدد',
      };
    }).toList();
  }

  Future<Map<String, dynamic>?> getOrderTrackingSnapshot(
    String orderId,
  ) async {
    final normalizedOrderId = orderId.trim();
    if (normalizedOrderId.isEmpty) return null;

    final order = await _databaseService.read('orders/$normalizedOrderId');
    if (order.isEmpty) return null;
    order.putIfAbsent('id', () => normalizedOrderId);
    final updatesSnapshot = await _databaseService.read('delivery_updates');
    final orderUpdates = updatesSnapshot.entries
        .where((entry) => entry.value is Map)
        .map((entry) => Map<String, dynamic>.from(entry.value as Map))
        .where((update) =>
            (update['order_id'] ?? update['orderId'])?.toString() ==
            normalizedOrderId)
        .toList()
      ..sort((left, right) {
        final leftDate = DateTime.tryParse(
              (left['created_at'] ?? left['createdAt'] ?? '').toString(),
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final rightDate = DateTime.tryParse(
              (right['created_at'] ?? right['createdAt'] ?? '').toString(),
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return rightDate.compareTo(leftDate);
      });
    final latestUpdate =
        orderUpdates.isEmpty ? const <String, dynamic>{} : orderUpdates.first;
    final rawItems = order['items'] ?? order['order_items'];
    final Iterable<Map> items =
        rawItems is List ? rawItems.whereType<Map>() : const <Map>[];
    final profileIds = <String>{
      (order['customer_id'] ?? order['customerId'] ?? '').toString(),
      (order['driver_id'] ?? order['driverId'] ?? '').toString(),
      (order['merchant_id'] ?? order['merchantId'] ?? '').toString(),
      ...items.map((item) =>
          (item['merchant_id'] ?? item['merchantId'] ?? '').toString()),
    }..removeWhere((id) => id.trim().isEmpty);
    final profileResults = await Future.wait(
      profileIds.map((id) => _databaseService.read('profiles/$id')),
    );
    final profiles = <String, Map<String, dynamic>>{};
    var profileIndex = 0;
    for (final id in profileIds) {
      final profile = profileResults[profileIndex++];
      if (profile.isNotEmpty) {
        profile.putIfAbsent('id', () => id);
        profiles[id] = profile;
      }
    }
    final customerId =
        (order['customer_id'] ?? order['customerId'] ?? '').toString();
    final driverId = (order['driver_id'] ?? order['driverId'] ?? '').toString();
    final merchantId =
        (order['merchant_id'] ?? order['merchantId'] ?? '').toString();
    return {
      ...order,
      'customer_snapshot':
          profiles[customerId] ?? order['customer_snapshot'] ?? const {},
      'driver_snapshot':
          profiles[driverId] ?? order['driver_snapshot'] ?? const {},
      'merchant_snapshot':
          profiles[merchantId] ?? order['merchant_snapshot'] ?? const {},
      'merchant_snapshots': profiles,
      'latest_delivery_update': latestUpdate,
    };
  }

  Future<DispatcherPerformanceReport> getDispatcherPerformanceReport({
    required String dispatcherId,
    required DispatcherReportPeriod period,
    DateTime? referenceDate,
  }) async {
    final ordersSnapshot = await _databaseService.read('orders');
    final currencies = await CurrencyService(databaseService: _databaseService)
        .getCurrencies();
    final now = referenceDate ?? DateTime.now();
    final start = switch (period) {
      DispatcherReportPeriod.daily => DateTime(now.year, now.month, now.day),
      DispatcherReportPeriod.monthly => DateTime(now.year, now.month),
      DispatcherReportPeriod.yearly => DateTime(now.year),
    };
    final end = switch (period) {
      DispatcherReportPeriod.daily => start.add(const Duration(days: 1)),
      DispatcherReportPeriod.monthly => DateTime(start.year, start.month + 1),
      DispatcherReportPeriod.yearly => DateTime(start.year + 1),
    };
    final rows = <Map<String, dynamic>>[];
    for (final entry in ordersSnapshot.entries) {
      if (entry.value is! Map) continue;
      final order = Map<String, dynamic>.from(entry.value as Map);
      final assignedDispatcher =
          (order['dispatcher_id'] ?? order['assigned_by_dispatcher_id'] ?? '')
              .toString()
              .trim();
      if (assignedDispatcher != dispatcherId) continue;
      final assignedAt = DateTime.tryParse(
        (order['dispatcher_assigned_at'] ??
                order['assigned_at'] ??
                order['created_at'] ??
                '')
            .toString(),
      )?.toLocal();
      if (assignedAt == null ||
          assignedAt.isBefore(start) ||
          !assignedAt.isBefore(end)) {
        continue;
      }
      order.putIfAbsent('id', () => entry.key);
      order['dispatcher_assigned_at'] = assignedAt.toIso8601String();
      final totalInYER = CurrencyOption.orderTotalInYER(order, currencies);
      if (totalInYER != null) {
        order['report_total_yer'] = totalInYER;
      }
      rows.add(order);
    }
    rows.sort((left, right) {
      final leftDate =
          DateTime.tryParse(left['dispatcher_assigned_at']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
      final rightDate = DateTime.tryParse(
              right['dispatcher_assigned_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return rightDate.compareTo(leftDate);
    });
    final delivered = rows
        .where((order) => order['status']?.toString() == 'delivered')
        .length;
    final cancelled = rows
        .where((order) => order['status']?.toString() == 'cancelled')
        .length;
    final inProgress = rows.where((order) {
      const completedStatuses = {'delivered', 'cancelled', 'rejected'};
      return !completedStatuses.contains(order['status']?.toString());
    }).length;
    final unconvertedOrderCount =
        rows.where((order) => order['report_total_yer'] == null).length;
    final totalOrderValue = rows.fold<double>(
      0,
      (sum, order) =>
          sum + ((order['report_total_yer'] as num?)?.toDouble() ?? 0),
    );
    return DispatcherPerformanceReport(
      totalAssigned: rows.length,
      delivered: delivered,
      cancelled: cancelled,
      inProgress: inProgress,
      totalOrderValue: totalOrderValue,
      unconvertedOrderCount: unconvertedOrderCount,
      orders: rows,
    );
  }

  Future<bool> assignOrderToDriver({
    required String orderId,
    required String driverName,
    String? driverId,
    String? driverPhone,
    String? eta,
    String? dispatcherId,
    String? dispatcherName,
  }) async {
    try {
      final assignedAt = DateTime.now().toUtc().toIso8601String();
      final updated = {
        'driver_name': driverName,
        'courier_name': driverName,
        'driver_status': 'assigned',
        'driver_assigned_at': assignedAt,
        if (dispatcherId?.trim().isNotEmpty == true) ...{
          'dispatcher_id': dispatcherId!.trim(),
          'dispatcher_name': dispatcherName?.trim() ?? '',
          'dispatcher_assigned_at': assignedAt,
        },
        if (driverId != null && driverId.trim().isNotEmpty)
          'driver_id': driverId.trim(),
        if (driverPhone != null && driverPhone.trim().isNotEmpty)
          'driver_phone': driverPhone.trim(),
        'eta': eta ?? 'قريبًا',
      };
      final assigned = await _databaseService.updateIf(
        'orders/$orderId',
        condition: (current) {
          const closedStatuses = {'delivered', 'cancelled', 'rejected'};
          return !closedStatuses.contains(current['status']?.toString()) &&
              !_hasAssignedDriver(current);
        },
        updates: updated,
      );
      final normalizedDriverId = driverId?.trim() ?? '';
      if (assigned != null && normalizedDriverId.isNotEmpty) {
        await NotificationService(databaseService: _databaseService)
            .notifyProfile(
          profileId: normalizedDriverId,
          role: 'driver',
          title: 'تم إسناد طلب جديد إليك',
          body: 'تم إسناد الطلب رقم $orderId إليك. افتح قائمة طلباتك للمتابعة.',
          type: 'delivery_assignment',
          orderId: orderId,
          status: 'assigned',
          eventId: 'driver-assigned-$orderId-$assignedAt',
        );
      }
      return assigned != null;
    } catch (_) {
      return false;
    }
  }

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
    final normalizedOrderId = orderId.trim();
    final normalizedCurrentDriverId = currentDriverId.trim();
    final normalizedCurrentDriverName = currentDriverName.trim();
    final normalizedCurrentDriverPhone = currentDriverPhone.trim();
    final normalizedDriverId = driverId.trim();
    final normalizedDriverName = driverName.trim();
    final normalizedDriverPhone = driverPhone.trim();
    if (normalizedOrderId.isEmpty ||
        normalizedDriverId.isEmpty ||
        normalizedDriverName.isEmpty) {
      return false;
    }

    final now = DateTime.now().toUtc();
    final assignedAt = now.toIso8601String();
    final updated = <String, dynamic>{
      'driver_id': normalizedDriverId,
      'driverId': normalizedDriverId,
      'driver_name': normalizedDriverName,
      'driver_phone': normalizedDriverPhone,
      'driverPhone': normalizedDriverPhone,
      'courier_name': normalizedDriverName,
      'driver_status': 'assigned',
      'driver_assigned_at': assignedAt,
      'driver_reassigned_at': assignedAt,
      'driver_accepted_at': null,
      'driverAcceptedAt': null,
      'pickup_otp': null,
      'pickup_otp_hash': null,
      'pickup_otp_salt': null,
      'pickup_otp_expires_at': null,
      'pickup_otp_attempts': 0,
      'pickup_otp_locked': false,
      'pickup_otp_verified': false,
      'pickupOtp': null,
      'pickupOtpHash': null,
      'pickupOtpSalt': null,
      'pickupOtpExpiresAt': null,
      'eta': eta ?? 'قريبًا',
    };

    final reassigned = await _databaseService.updateIf(
      'orders/$normalizedOrderId',
      condition: (current) {
        const replaceableOrderStatuses = {'preparing', 'shipped'};
        const completedDriverStatuses = {'picked_up', 'delivered'};
        final status = current['status']?.toString();
        final driverStatus = current['driver_status']?.toString();
        final pickupOtpVerified = current['pickup_otp_verified'] == true ||
            current['pickup_otp_verified']?.toString().toLowerCase() == 'true';
        final existingDriverId =
            (current['driver_id'] ?? current['driverId'] ?? '')
                .toString()
                .trim();
        final existingDriverPhone =
            (current['driver_phone'] ?? current['driverPhone'] ?? '')
                .toString()
                .trim();
        final existingDriverName =
            (current['driver_name'] ?? current['courier_name'] ?? '')
                .toString()
                .trim();
        final expectedDriverMatches = normalizedCurrentDriverId.isNotEmpty
            ? existingDriverId == normalizedCurrentDriverId
            : normalizedCurrentDriverPhone.isNotEmpty
                ? existingDriverPhone == normalizedCurrentDriverPhone
                : normalizedCurrentDriverName.isNotEmpty &&
                    existingDriverName == normalizedCurrentDriverName;
        final sameDriver = existingDriverId.isNotEmpty
            ? existingDriverId == normalizedDriverId
            : existingDriverPhone.isNotEmpty &&
                    normalizedDriverPhone.isNotEmpty
                ? existingDriverPhone == normalizedDriverPhone
                : existingDriverName == normalizedDriverName;

        return replaceableOrderStatuses.contains(status) &&
            !completedDriverStatuses.contains(driverStatus) &&
            !pickupOtpVerified &&
            _hasAssignedDriver(current) &&
            expectedDriverMatches &&
            !sameDriver;
      },
      updates: updated,
    );
    if (reassigned == null) return false;

    final notificationService =
        NotificationService(databaseService: _databaseService);
    final eventSuffix = now.microsecondsSinceEpoch.toString();
    if (normalizedCurrentDriverId.isNotEmpty) {
      await notificationService.notifyProfile(
        profileId: normalizedCurrentDriverId,
        role: 'driver',
        title: 'تم تغيير إسناد الطلب',
        body: 'لم يعد الطلب رقم $normalizedOrderId مسندًا إليك.',
        type: 'delivery_assignment_cancelled',
        orderId: normalizedOrderId,
        status: 'reassigned',
        eventId: 'driver-unassigned-$normalizedOrderId-$eventSuffix',
      );
    }
    await notificationService.notifyProfile(
      profileId: normalizedDriverId,
      role: 'driver',
      title: 'تم إسناد طلب جديد إليك',
      body: 'تم إسناد الطلب رقم $normalizedOrderId إليك.',
      type: 'delivery_assignment',
      orderId: normalizedOrderId,
      status: 'assigned',
      eventId: 'driver-reassigned-$normalizedOrderId-$eventSuffix',
    );
    return true;
  }

  Future<bool> acceptDriverAssignment({
    required String orderId,
    required String driverId,
    required String driverName,
    String? driverPhone,
  }) async {
    try {
      final database = _databaseService;
      final order = await database.read('orders/$orderId');
      if (order.isEmpty ||
          !_isAssignedToDriver(
            order,
            driverId: driverId,
            driverName: driverName,
            driverPhone: driverPhone,
          )) {
        return false;
      }
      final accepted = await database.updateIf(
        'orders/$orderId',
        condition: (current) =>
            _isAssignedToDriver(
              current,
              driverId: driverId,
              driverName: driverName,
              driverPhone: driverPhone,
            ) &&
            (current['driver_status']?.toString() ?? 'assigned') == 'assigned',
        updates: {
          'driver_status': 'accepted',
          'driver_accepted_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
      return accepted != null;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateDriverEta({
    required String orderId,
    required String driverId,
    required String driverName,
    required String eta,
    String? driverPhone,
  }) async {
    if (eta.trim().isEmpty) return false;
    try {
      final database = _databaseService;
      final order = await database.read('orders/$orderId');
      if (order.isEmpty ||
          !_isAssignedToDriver(
            order,
            driverId: driverId,
            driverName: driverName,
            driverPhone: driverPhone,
          )) {
        return false;
      }

      final now = DateTime.now().toUtc().toIso8601String();
      final updated = <String, dynamic>{
        'eta': eta.trim(),
        'courier_name': driverName,
        'updated_at': now,
      };
      await database.update('orders/$orderId', updated);

      final customerId =
          (order['customer_id'] ?? order['customerId'] ?? '').toString();
      if (customerId.isNotEmpty) {
        await database.update(
          'customers/$customerId/orders/$orderId',
          updated,
        );
      }
      await database.write(
        'delivery_updates/${orderId}_${DateTime.now().millisecondsSinceEpoch}',
        {
          'order_id': orderId,
          'status': order['status']?.toString() ?? '',
          ...updated,
          'created_at': now,
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _isAssignedToDriver(
    Map<String, dynamic> order, {
    required String driverId,
    required String driverName,
    String? driverPhone,
  }) {
    final assignedId =
        (order['driver_id'] ?? order['driverId'] ?? '').toString().trim();
    final assignedPhone =
        (order['driver_phone'] ?? order['driverPhone'] ?? '').toString().trim();
    final assignedName =
        (order['courier_name'] ?? order['driver_name'] ?? '').toString().trim();
    return (driverId.trim().isNotEmpty && assignedId == driverId.trim()) ||
        (driverPhone?.trim().isNotEmpty == true &&
            assignedPhone == driverPhone!.trim()) ||
        (driverName.trim().isNotEmpty && assignedName == driverName.trim());
  }
}
