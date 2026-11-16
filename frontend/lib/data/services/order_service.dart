import 'dart:math';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:she_m_app/data/models/order_model.dart';
import 'package:she_m_app/data/models/order_number.dart';
import 'package:she_m_app/data/services/driver_service.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/data/services/notification_service.dart';

class DeliveryFeeUpdateResult {
  final OrderModel order;
  final bool notificationSent;

  const DeliveryFeeUpdateResult({
    required this.order,
    required this.notificationSent,
  });
}

class OrderService {
  static const Duration _pickupOtpLifetime = Duration(minutes: 30);
  static const int _maxPickupOtpAttempts = 5;
  static const List<String> _customerDeliveryOtpFields = [
    'customer_delivery_otp',
    'customerDeliveryOtp',
    'customer_delivery_otp_hash',
    'customerDeliveryOtpHash',
    'customer_delivery_otp_salt',
    'customerDeliveryOtpSalt',
    'customer_delivery_otp_expires_at',
    'customerDeliveryOtpExpiresAt',
    'customer_delivery_otp_attempts',
    'customerDeliveryOtpAttempts',
    'customer_delivery_otp_locked',
    'customerDeliveryOtpLocked',
    'customer_delivery_otp_verified',
    'customerDeliveryOtpVerified',
    'customer_delivery_otp_verified_at',
    'customerDeliveryOtpVerifiedAt',
  ];

  static Map<String, String> productOwnersById(
    Map<String, dynamic> productsSnapshot,
  ) {
    final owners = <String, String>{};
    for (final entry in productsSnapshot.entries) {
      if (entry.value is! Map) continue;
      final product = Map<String, dynamic>.from(entry.value as Map);
      final productId = (product['id'] ?? entry.key).toString().trim();
      final ownerId = (product['merchant_id'] ??
              product['merchantId'] ??
              product['owner_id'] ??
              product['ownerId'] ??
              '')
          .toString()
          .trim();
      if (productId.isNotEmpty && ownerId.isNotEmpty) {
        owners[productId] = ownerId;
      }
      if (entry.key.trim().isNotEmpty && ownerId.isNotEmpty) {
        owners[entry.key.trim()] = ownerId;
      }
    }
    return owners;
  }

  static bool orderItemBelongsToMerchant({
    required Map<String, dynamic> item,
    required String merchantId,
    Map<String, String> productOwners = const {},
    Set<String> merchantProductIds = const {},
  }) {
    final productId =
        (item['product_id'] ?? item['productId'] ?? '').toString().trim();
    final productOwner = productOwners[productId]?.trim();
    if (productOwner != null && productOwner.isNotEmpty) {
      return productOwner == merchantId.trim();
    }

    final itemMerchantId =
        (item['merchant_id'] ?? item['merchantId'] ?? '').toString().trim();
    if (itemMerchantId.isNotEmpty) {
      return itemMerchantId == merchantId.trim();
    }
    return productId.isNotEmpty && merchantProductIds.contains(productId);
  }

  OrderService({
    DatabaseService? databaseService,
    NotificationService? notificationService,
  })  : _databaseService = databaseService ?? FirebaseDatabaseService.instance,
        _notificationService = notificationService ??
            NotificationService(
              databaseService:
                  databaseService ?? FirebaseDatabaseService.instance,
            );

  final DatabaseService _databaseService;
  final NotificationService _notificationService;
  String? lastPickupOtpError;

  Future<OrderModel?> createOrder({
    required String customerId,
    required List<OrderItem> items,
    required String paymentMethod,
    required double subtotal,
    required double shippingFee,
    double commission = 0,
    String status = 'new',
    bool notifyCustomer = true,
    String? paymentWalletId,
    String? paymentWalletName,
  }) async {
    if (items.isEmpty) return null;

    final total = subtotal + shippingFee;
    final orderId = 'order-${DateTime.now().millisecondsSinceEpoch}';
    final order = OrderModel(
      id: orderId,
      orderNumber: OrderNumber.fromId(orderId),
      customerId: customerId,
      items: items,
      status: status,
      subtotal: subtotal,
      shippingFee: shippingFee,
      commission: commission,
      total: total,
      paymentMethod: paymentMethod,
      paymentWalletId: paymentWalletId,
      paymentWalletName: paymentWalletName,
      createdAt: DateTime.now(),
    );

    try {
      final payload = order.toJson();
      payload['commission_included_in_subtotal'] = true;
      await _databaseService.write('orders/$orderId', payload);
      await _databaseService.write(
          'customers/$customerId/orders/$orderId', payload);
      if (notifyCustomer) {
        await _notificationService.notifyOrderStatus(
          customerId: customerId,
          orderId: orderId,
          status: order.status,
        );
      }
      await _notificationService.notifyOrderCreated(
        orderId: orderId,
        merchantIds: items.map((item) => item.merchantId),
      );
      return order;
    } catch (_) {
      return null;
    }
  }

  Future<List<OrderModel>> getOrdersByCustomer(String customerId) async {
    try {
      final snapshot =
          await _databaseService.read('customers/$customerId/orders');
      if (snapshot.isEmpty) {
        return const [];
      }

      return snapshot.values
          .whereType<Map>()
          .map((value) => OrderModel.fromJson(Map<String, dynamic>.from(value)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<OrderModel>> getOrdersByMerchant(String merchantId) async {
    final normalizedMerchantId = merchantId.trim();
    if (normalizedMerchantId.isEmpty) {
      return const [];
    }

    try {
      final productsSnapshot = await _databaseService.read('products');
      final productOwners = productOwnersById(productsSnapshot);
      final merchantProductIds = productOwners.entries
          .where((entry) => entry.value == normalizedMerchantId)
          .map((entry) => entry.key)
          .toSet();

      final ordersSnapshot = await _databaseService.read('orders');
      if (ordersSnapshot.isEmpty) {
        return const [];
      }

      final orders = ordersSnapshot.values
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .where(isVisibleToMerchant)
          .map(OrderModel.fromJson)
          .where((order) {
        final items = order.items;
        if (items.isEmpty) {
          return false;
        }

        return items.any((item) {
          return orderItemBelongsToMerchant(
            item: item.toJson(),
            merchantId: normalizedMerchantId,
            productOwners: productOwners,
            merchantProductIds: merchantProductIds,
          );
        });
      }).toList();

      return orders;
    } catch (_) {
      return const [];
    }
  }

  static bool isVisibleToMerchant(Map<String, dynamic> order) {
    final status =
        (order['status'] ?? 'pending_payment').toString().trim().toLowerCase();
    if (status == 'pending_payment' || status == 'awaiting_confirmation') {
      return false;
    }

    final proofId = (order['payment_proof_id'] ?? order['paymentProofId'] ?? '')
        .toString()
        .trim();
    final cancellationReason =
        (order['cancellation_reason'] ?? order['cancellationReason'] ?? '')
            .toString()
            .trim();
    return !(status == 'cancelled' &&
        proofId.isNotEmpty &&
        (order['cancelled_by'] ?? order['cancelledBy'])?.toString() ==
            'admin' &&
        cancellationReason.contains('إثبات الدفع'));
  }

  Future<OrderModel?> getOrderById(String orderId) async {
    try {
      final snapshot = await _databaseService.read('orders/$orderId');
      if (snapshot.isEmpty) {
        return null;
      }
      return OrderModel.fromJson(Map<String, dynamic>.from(snapshot));
    } catch (_) {
      return null;
    }
  }

  Future<DeliveryFeeUpdateResult?> updateDeliveryFee({
    required String orderId,
    required double shippingFee,
    required String actorId,
    required String actorRole,
  }) async {
    final normalizedOrderId = orderId.trim();
    final normalizedActorId = actorId.trim();
    if (normalizedOrderId.isEmpty ||
        normalizedActorId.isEmpty ||
        !shippingFee.isFinite ||
        shippingFee < 0 ||
        !{'admin', 'central_dispatcher'}.contains(actorRole)) {
      return null;
    }

    try {
      final snapshot = await _databaseService.read('orders/$normalizedOrderId');
      if (snapshot.isEmpty ||
          {'delivered', 'cancelled'}.contains(snapshot['status']?.toString())) {
        return null;
      }
      final previousFee = _toDouble(
        snapshot['shipping_fee'] ?? snapshot['shippingFee'],
      );
      if (previousFee == shippingFee) {
        return DeliveryFeeUpdateResult(
          order: OrderModel.fromJson(snapshot),
          notificationSent: true,
        );
      }
      final subtotal = _toDouble(snapshot['subtotal']);
      final commission = _toDouble(snapshot['commission']);
      final commissionIncludedInSubtotal =
          snapshot['commission_included_in_subtotal'] == true;
      final status = snapshot['status']?.toString() ?? 'pending_payment';
      final updates = <String, dynamic>{
        'shipping_fee': shippingFee,
        'total': subtotal +
            (commissionIncludedInSubtotal ? 0 : commission) +
            shippingFee,
        'commission_included_in_subtotal': commissionIncludedInSubtotal,
        'delivery_fee_updated_at': DateTime.now().toUtc().toIso8601String(),
        'delivery_fee_updated_by': normalizedActorId,
        'delivery_fee_updated_by_role': actorRole,
      };
      final saved = await _databaseService.updateIf(
        'orders/$normalizedOrderId',
        condition: (current) =>
            _toDouble(current['shipping_fee'] ?? current['shippingFee']) ==
                previousFee &&
            _toDouble(current['subtotal']) == subtotal &&
            _toDouble(current['commission']) == commission &&
            (current['commission_included_in_subtotal'] == true) ==
                commissionIncludedInSubtotal &&
            jsonEncode(current['items']) == jsonEncode(snapshot['items']) &&
            (current['status']?.toString() ?? 'pending_payment') == status &&
            !{'delivered', 'cancelled'}.contains(current['status']?.toString()),
        updates: updates,
      );
      if (saved == null) return null;

      final customerId =
          (saved['customer_id'] ?? saved['customerId'] ?? '').toString();
      var notificationSent = false;
      if (customerId.isNotEmpty) {
        await _databaseService.write(
          'customers/$customerId/orders/$normalizedOrderId',
          sanitizeOrderForCustomer(saved),
        );
        final rawItems = saved['items'];
        final firstItem =
            rawItems is List && rawItems.isNotEmpty && rawItems.first is Map
                ? Map<String, dynamic>.from(rawItems.first as Map)
                : const <String, dynamic>{};
        notificationSent = await _notificationService.notifyDeliveryFeeChanged(
          customerId: customerId,
          orderId: normalizedOrderId,
          previousFee: previousFee,
          updatedFee: shippingFee,
          currencySymbol: (saved['currency_symbol'] ??
                  saved['currencySymbol'] ??
                  firstItem['currency_symbol'] ??
                  'ر.س')
              .toString(),
        );
      }
      return DeliveryFeeUpdateResult(
        order: OrderModel.fromJson(saved),
        notificationSent: notificationSent,
      );
    } catch (_) {
      return null;
    }
  }

  Future<OrderModel?> updateOrderStatus({
    required String orderId,
    required String status,
    String? cancelledBy,
    String? cancellationReason,
  }) async {
    try {
      final snapshot = await _databaseService.read('orders/$orderId');
      if (snapshot.isEmpty) return null;

      if (status == 'picked_up' && snapshot['pickup_otp_verified'] != true) {
        return null;
      }
      if (status == 'delivered') return null;

      if (status == 'confirmed') {
        final saved = await _databaseService.updateIf(
          'orders/$orderId',
          condition: (current) => {'new', 'pending_payment'}.contains(
            current['status']?.toString(),
          ),
          updates: {'status': 'confirmed'},
        );
        if (saved == null) return null;
        await _syncCustomerOrder(snapshot, saved, orderId);
        return OrderModel.fromJson(saved);
      }

      final updated = Map<String, dynamic>.from(snapshot)..['status'] = status;
      if (status == 'cancelled') {
        updated['cancelled_by'] = cancelledBy ?? 'system';
        updated['cancellation_reason'] =
            cancellationReason ?? 'تم إلغاء الطلب من الجهة المسؤولة';
        updated['cancelled_at'] = DateTime.now().toUtc().toIso8601String();
      }
      final saved = await _databaseService.write('orders/$orderId', updated);
      await _syncCustomerOrder(snapshot, updated, orderId);
      return OrderModel.fromJson(saved);
    } catch (_) {
      return null;
    }
  }

  Future<OrderModel?> rejectOrderItemForOutOfStock({
    required String orderId,
    required int itemIndex,
    required String merchantId,
  }) async {
    final normalizedMerchantId = merchantId.trim();
    if (orderId.trim().isEmpty ||
        itemIndex < 0 ||
        normalizedMerchantId.isEmpty) {
      return null;
    }

    try {
      final snapshot = await _databaseService.read('orders/$orderId');
      if (snapshot.isEmpty) return null;
      final rawItems = snapshot['items'];
      if (rawItems is! List || itemIndex >= rawItems.length) return null;

      final item = rawItems[itemIndex];
      if (item is! Map) return null;
      final orderItem = Map<String, dynamic>.from(item);
      if ((orderItem['status'] ?? 'available').toString() == 'rejected') {
        return null;
      }

      var itemMerchantId =
          (orderItem['merchant_id'] ?? orderItem['merchantId'] ?? '')
              .toString()
              .trim();
      final productId =
          (orderItem['product_id'] ?? orderItem['productId'] ?? '')
              .toString()
              .trim();
      if (itemMerchantId.isEmpty && productId.isNotEmpty) {
        final products = await _databaseService.read('products');
        for (final value in products.values.whereType<Map>()) {
          final product = Map<String, dynamic>.from(value);
          if ((product['id'] ?? '').toString() == productId) {
            itemMerchantId = (product['merchant_id'] ??
                    product['merchantId'] ??
                    product['owner_id'] ??
                    product['ownerId'] ??
                    '')
                .toString()
                .trim();
            break;
          }
        }
      }
      if (itemMerchantId != normalizedMerchantId) return null;

      final currentStatus =
          (snapshot['status'] ?? 'pending_payment').toString();
      if ({'shipped', 'picked_up', 'delivered', 'cancelled'}
          .contains(currentStatus)) {
        return null;
      }

      const rejectionReason = 'نفدت الكمية';
      final updatedItems = rawItems.map((value) {
        if (value is! Map) return value;
        return Map<String, dynamic>.from(value);
      }).toList();
      final now = DateTime.now().toUtc();
      updatedItems[itemIndex] = {
        ...Map<String, dynamic>.from(updatedItems[itemIndex] as Map),
        'status': 'rejected',
        'rejection_reason': rejectionReason,
        'rejected_by': normalizedMerchantId,
        'rejected_at': now.toIso8601String(),
      };

      var updatedSubtotal = 0.0;
      for (final value in updatedItems) {
        if (value is! Map || value['status']?.toString() == 'rejected') {
          continue;
        }
        final line = Map<String, dynamic>.from(value);
        updatedSubtotal += _toDouble(
          line['total_yer'] ??
              line['total'] ??
              line['line_total'] ??
              (_toDouble(line['unit_price'] ?? line['unitPrice']) *
                  _toDouble(line['quantity'])),
        );
      }
      final previousSubtotal = _toDouble(snapshot['subtotal']);
      final previousCommission = _toDouble(snapshot['commission']);
      final commissionIncludedInSubtotal =
          snapshot['commission_included_in_subtotal'] == true;
      var hasCompleteBaseAmounts = commissionIncludedInSubtotal;
      var commissionFromRemainingItems = 0.0;
      if (hasCompleteBaseAmounts) {
        for (final value in updatedItems) {
          if (value is! Map || value['status']?.toString() == 'rejected') {
            continue;
          }
          final item = Map<String, dynamic>.from(value);
          final totalYER = _toNullableDouble(item['total_yer']);
          final baseUnitPriceYER =
              _toNullableDouble(item['base_unit_price_yer']);
          final quantity = _toDouble(item['quantity']);
          if (totalYER == null || baseUnitPriceYER == null || quantity <= 0) {
            hasCompleteBaseAmounts = false;
            break;
          }
          final vatYER = _toDouble(item['vat_amount_yer']);
          commissionFromRemainingItems +=
              (totalYER - baseUnitPriceYER * quantity - vatYER)
                  .clamp(0, double.infinity);
        }
      }
      final updatedCommission = hasCompleteBaseAmounts
          ? commissionFromRemainingItems
          : previousSubtotal > 0
              ? previousCommission * updatedSubtotal / previousSubtotal
              : 0.0;
      final shippingFee =
          _toDouble(snapshot['shipping_fee'] ?? snapshot['shippingFee']);
      final remainingItems = updatedItems.where((value) {
        return value is Map && value['status']?.toString() != 'rejected';
      }).length;
      final orderCancelled = remainingItems == 0;
      final updated = Map<String, dynamic>.from(snapshot)
        ..['items'] = updatedItems
        ..['subtotal'] = updatedSubtotal
        ..['commission'] = updatedCommission
        ..['shipping_fee'] = orderCancelled ? 0.0 : shippingFee
        ..['total'] = updatedSubtotal +
            (commissionIncludedInSubtotal ? 0 : updatedCommission) +
            (orderCancelled ? 0 : shippingFee);
      if (orderCancelled) {
        updated
          ..['status'] = 'cancelled'
          ..['cancelled_by'] = 'merchant'
          ..['cancellation_reason'] =
              'تعذر إتمام الطلب: نفدت كمية جميع المنتجات'
          ..['cancelled_at'] = now.toIso8601String();
      }

      final saved = await _databaseService.updateIf(
        'orders/$orderId',
        condition: (current) {
          final currentItems = current['items'];
          return currentItems is List &&
              jsonEncode(currentItems) == jsonEncode(rawItems) &&
              (current['status'] ?? 'pending_payment').toString() ==
                  currentStatus &&
              !{'shipped', 'picked_up', 'delivered', 'cancelled'}
                  .contains(currentStatus);
        },
        updates: updated,
      );
      if (saved == null) return null;

      final customerId =
          (saved['customer_id'] ?? saved['customerId'] ?? '').toString();
      if (customerId.isNotEmpty) {
        await _databaseService.write(
          'customers/$customerId/orders/$orderId',
          saved,
        );
        await _notificationService.notifyOrderItemRejected(
          customerId: customerId,
          orderId: orderId,
          productId: productId.isEmpty ? 'item-$itemIndex' : productId,
          productName:
              (orderItem['product_name'] ?? orderItem['productName'] ?? 'منتج')
                  .toString(),
          reason: rejectionReason,
          updatedTotal: _toDouble(saved['total']),
          currencySymbol:
              (saved['currency_symbol'] ?? saved['currencySymbol'] ?? 'ر.س')
                  .toString(),
          orderCancelled: orderCancelled,
        );
        if (orderCancelled) {
          await _notificationService.notifyOrderStatus(
            customerId: customerId,
            orderId: orderId,
            status: 'cancelled',
            cancellationReason: updated['cancellation_reason']?.toString(),
          );
        }
      }
      return OrderModel.fromJson(saved);
    } catch (_) {
      return null;
    }
  }

  Future<OrderModel?> cancelOrderByCustomer({
    required String orderId,
    required String customerId,
  }) async {
    try {
      final snapshot = await _databaseService.read('orders/$orderId');
      if (snapshot.isEmpty) return null;

      final storedCustomerId =
          (snapshot['customer_id'] ?? snapshot['customerId'] ?? '')
              .toString()
              .trim();
      if (storedCustomerId.isEmpty || storedCustomerId != customerId.trim()) {
        return null;
      }

      final status = snapshot['status']?.toString() ?? 'pending_payment';
      const deliveryStartedStatuses = {
        'shipped',
        'picked_up',
        'delivered',
        'cancelled',
      };
      if (deliveryStartedStatuses.contains(status)) return null;

      final createdAt =
          DateTime.tryParse(snapshot['created_at']?.toString() ?? '')?.toUtc();
      if (createdAt == null ||
          DateTime.now().toUtc().difference(createdAt) >
              const Duration(minutes: 15)) {
        return null;
      }

      final now = DateTime.now().toUtc();
      final updated = Map<String, dynamic>.from(snapshot)
        ..['status'] = 'cancelled'
        ..['cancelled_by'] = 'customer'
        ..['cancellation_reason'] = 'ألغاه العميل خلال المهلة المسموحة'
        ..['cancelled_at'] = now.toIso8601String();
      final saved = await _databaseService.write('orders/$orderId', updated);
      await _syncCustomerOrder(snapshot, updated, orderId);
      return OrderModel.fromJson(saved);
    } catch (_) {
      return null;
    }
  }

  Future<OrderModel?> prepareDeliveryOtp(String orderId) async {
    try {
      final snapshot = await _databaseService.read('orders/$orderId');
      if (snapshot.isEmpty) return null;

      final status = snapshot['status']?.toString();
      if (!{'preparing', 'shipped'}.contains(status) ||
          snapshot['pickup_otp_verified'] == true) {
        return null;
      }

      if (status == 'shipped') {
        final existingOtp =
            (snapshot['pickup_otp'] ?? snapshot['pickupOtp'] ?? '')
                .toString()
                .trim();
        final expiresAt = DateTime.tryParse(
          (snapshot['pickup_otp_expires_at'] ??
                  snapshot['pickupOtpExpiresAt'] ??
                  '')
              .toString(),
        )?.toUtc();
        if (snapshot['pickup_otp_hash']?.toString().trim().isNotEmpty == true &&
            RegExp(r'^\d{6}$').hasMatch(existingOtp) &&
            expiresAt != null &&
            DateTime.now().toUtc().isBefore(expiresAt)) {
          return OrderModel.fromJson(snapshot);
        }
      }

      final now = DateTime.now().toUtc();
      final otp = _generateOtp();
      final salt = _generateSalt();
      final updated = Map<String, dynamic>.from(snapshot)
        ..['status'] = 'shipped'
        ..['pickup_otp'] = otp
        ..['pickup_otp_hash'] = _hashOtp(otp, salt)
        ..['pickup_otp_salt'] = salt
        ..['pickup_otp_expires_at'] =
            now.add(_pickupOtpLifetime).toIso8601String()
        ..['pickup_otp_attempts'] = 0
        ..['pickup_otp_locked'] = false
        ..['pickup_otp_verified'] = false
        ..remove('delivery_otp')
        ..remove('delivery_otp_expires_at')
        ..remove('delivery_otp_attempts')
        ..remove('delivery_otp_locked')
        ..remove('delivery_otp_verified');
      final saved = await _databaseService.write('orders/$orderId', updated);
      await _syncCustomerOrder(snapshot, updated, orderId);
      return OrderModel.fromJson({...saved, 'pickup_otp': otp});
    } catch (_) {
      return null;
    }
  }

  Future<OrderModel?> confirmPickupOtp({
    required String orderId,
    required String otp,
  }) async {
    final result = await _verifyPickupOtp(
      orderId: orderId,
      otp: otp,
    );
    if (result == null) return null;

    final now = DateTime.now().toUtc();
    final updated = Map<String, dynamic>.from(result)
      ..['status'] = 'picked_up'
      ..['current_location'] = 'استلمه السائق من المتجر'
      ..['eta'] = 'في الطريق'
      ..remove('pickup_otp')
      ..remove('pickupOtp')
      ..['pickup_otp_verified'] = true
      ..['pickup_otp_verified_at'] = now.toIso8601String();
    _removeCustomerDeliveryOtpFields(updated);
    final saved = await _databaseService.write('orders/$orderId', updated);
    await _syncCustomerOrder(result, updated, orderId);
    return OrderModel.fromJson(saved);
  }

  Future<OrderModel?> handoffToDriverWithoutPickupOtpForAdmin({
    required String orderId,
  }) async {
    final normalizedId = orderId.trim();
    if (normalizedId.isEmpty) return null;

    final snapshot = await _databaseService.read('orders/$normalizedId');
    if (!_hasAssignedDriver(snapshot) ||
        !{'preparing', 'shipped'}.contains(snapshot['status']?.toString()) ||
        snapshot['pickup_otp_verified'] == true) {
      return null;
    }

    final now = DateTime.now().toUtc();
    final updates = <String, dynamic>{
      'status': 'picked_up',
      'current_location': 'استلمه السائق من المتجر',
      'eta': 'في الطريق',
      'pickup_otp': null,
      'pickupOtp': null,
      'pickup_otp_hash': null,
      'pickupOtpHash': null,
      'pickup_otp_salt': null,
      'pickupOtpSalt': null,
      'pickup_otp_expires_at': null,
      'pickupOtpExpiresAt': null,
      'pickup_otp_attempts': null,
      'pickupOtpAttempts': null,
      'pickup_otp_locked': null,
      'pickupOtpLocked': null,
      'pickup_otp_verified': true,
      'pickup_otp_verified_at': now.toIso8601String(),
      'pickup_otp_bypassed_by_admin': true,
      'pickup_otp_bypassed_at': now.toIso8601String(),
      ..._customerDeliveryOtpNullUpdates(),
    };
    final saved = await _databaseService.updateIf(
      'orders/$normalizedId',
      condition: (current) =>
          _hasAssignedDriver(current) &&
          {'preparing', 'shipped'}.contains(current['status']?.toString()) &&
          current['pickup_otp_verified'] != true,
      updates: updates,
    );
    if (saved == null) return null;

    await _syncCustomerOrder(snapshot, saved, normalizedId);
    return OrderModel.fromJson(saved);
  }

  Future<OrderModel?> confirmDeliveryByDriver({
    required String orderId,
    required String driverId,
    String? driverPhone,
  }) async {
    final normalizedId = orderId.trim();
    final normalizedDriverId = driverId.trim();
    final normalizedDriverPhone = driverPhone?.trim() ?? '';
    if (normalizedId.isEmpty ||
        (normalizedDriverId.isEmpty && normalizedDriverPhone.isEmpty)) {
      return null;
    }

    try {
      final snapshot = await _databaseService.read('orders/$normalizedId');
      if (snapshot.isEmpty) return null;
      final deliveredAt = DateTime.now().toUtc().toIso8601String();
      final saved = await _databaseService.updateIf(
        'orders/$normalizedId',
        condition: (current) =>
            current['status']?.toString() == 'picked_up' &&
            _isAssignedDriver(
              current,
              driverId: normalizedDriverId,
              driverPhone: normalizedDriverPhone,
            ),
        updates: {
          'status': 'delivered',
          'driver_status': 'delivered',
          'current_location': 'تم التسليم',
          'eta': 'مكتمل',
          'delivered_at': deliveredAt,
          ..._customerDeliveryOtpNullUpdates(),
        },
      );
      if (saved == null) return null;
      await _syncCustomerOrder(snapshot, saved, normalizedId);
      return OrderModel.fromJson(saved);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _verifyPickupOtp({
    required String orderId,
    required String otp,
  }) async {
    lastPickupOtpError = null;
    try {
      final snapshot = await _databaseService.read('orders/$orderId');
      if (snapshot.isEmpty) {
        lastPickupOtpError = 'تعذر العثور على الطلب';
        return null;
      }
      const prefix = 'pickup_otp';
      final hash = snapshot['${prefix}_hash']?.toString() ?? '';
      final salt = snapshot['${prefix}_salt']?.toString() ?? '';
      final expiresAt = DateTime.tryParse(
        snapshot['${prefix}_expires_at']?.toString() ?? '',
      )?.toUtc();
      final attempts = int.tryParse(
            snapshot['${prefix}_attempts']?.toString() ?? '0',
          ) ??
          0;
      if (hash.isEmpty || salt.isEmpty) {
        lastPickupOtpError = 'لم ينشئ التاجر رمز استلام الطلب بعد';
        return null;
      }
      if (snapshot['status']?.toString() != 'shipped') {
        lastPickupOtpError = 'الطلب ليس جاهزًا للاستلام من التاجر';
        return null;
      }
      if (snapshot['${prefix}_locked'] == true) {
        lastPickupOtpError = 'تم قفل رمز التاجر بعد محاولات خاطئة متعددة';
        return null;
      }
      if (expiresAt == null || !DateTime.now().toUtc().isBefore(expiresAt)) {
        lastPickupOtpError = 'انتهت صلاحية رمز استلام الطلب من التاجر';
        return null;
      }
      if (!_secureEquals(_hashOtp(otp.trim(), salt), hash)) {
        final nextAttempts = attempts + 1;
        final failed = Map<String, dynamic>.from(snapshot)
          ..['${prefix}_attempts'] = nextAttempts
          ..['${prefix}_locked'] = nextAttempts >= _maxPickupOtpAttempts;
        await _databaseService.write('orders/$orderId', failed);
        lastPickupOtpError = nextAttempts >= _maxPickupOtpAttempts
            ? 'تم قفل رمز التاجر بعد 5 محاولات خاطئة'
            : 'رمز التاجر غير صحيح، المحاولات المتبقية: ${_maxPickupOtpAttempts - nextAttempts}';
        return null;
      }
      return snapshot;
    } catch (_) {
      lastPickupOtpError = 'تعذر التحقق من رمز التاجر للسائق';
      return null;
    }
  }

  bool _isAssignedDriver(
    Map<String, dynamic> order, {
    required String driverId,
    required String driverPhone,
  }) {
    final assignedId =
        (order['driver_id'] ?? order['driverId'] ?? '').toString().trim();
    final assignedPhone =
        (order['driver_phone'] ?? order['driverPhone'] ?? '').toString().trim();
    if (driverId.isNotEmpty && assignedId.isNotEmpty) {
      return assignedId == driverId;
    }
    return driverPhone.isNotEmpty && assignedPhone == driverPhone;
  }

  void _removeCustomerDeliveryOtpFields(Map<String, dynamic> order) {
    for (final field in _customerDeliveryOtpFields) {
      order.remove(field);
    }
  }

  Map<String, dynamic> _customerDeliveryOtpNullUpdates() => {
        for (final field in _customerDeliveryOtpFields) field: null,
      };

  Future<void> _syncCustomerOrder(
    Map<String, dynamic> previous,
    Map<String, dynamic> updated,
    String orderId,
  ) async {
    final customerId = (previous['customer_id'] ??
            previous['customerId'] ??
            updated['customer_id'] ??
            updated['customerId'] ??
            '')
        .toString();
    final previousStatus = (previous['status'] ?? '').toString().trim();
    final updatedStatus = (updated['status'] ?? '').toString().trim();
    if (updatedStatus.isNotEmpty && updatedStatus != previousStatus) {
      const deliveryStatuses = {
        'shipped',
        'picked_up',
        'delivered',
        'cancelled'
      };
      if (deliveryStatuses.contains(updatedStatus)) {
        final now = DateTime.now().toUtc().toIso8601String();
        final fallbackLocation = switch (updatedStatus) {
          'shipped' => 'جاهز للاستلام من المتجر',
          'picked_up' => 'استلمه السائق',
          'delivered' => 'تم التسليم',
          _ => 'ملغي',
        };
        final fallbackEta = updatedStatus == 'delivered'
            ? 'مكتمل'
            : updatedStatus == 'cancelled'
                ? 'ملغي'
                : 'قريبًا';
        await _databaseService.write(
          'delivery_updates/${orderId}_${DateTime.now().millisecondsSinceEpoch}',
          {
            'order_id': orderId,
            'status': updatedStatus,
            'current_location': updated['current_location'] ?? fallbackLocation,
            'eta': updated['eta'] ?? fallbackEta,
            'courier_name':
                updated['courier_name'] ?? updated['driver_name'] ?? 'غير مخصص',
            'created_at': now,
          },
        );
      }
      if (customerId.isNotEmpty) {
        await _databaseService.write(
          'customers/$customerId/orders/$orderId',
          sanitizeOrderForCustomer(updated),
        );
        await _notificationService.notifyOrderStatus(
          customerId: customerId,
          orderId: orderId,
          status: updatedStatus,
          cancellationReason: updated['cancellation_reason']?.toString(),
        );
      }
    }
  }

  static String _generateOtp() {
    return (Random.secure().nextInt(900000) + 100000).toString();
  }

  static String _generateSalt() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256))
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static bool _hasAssignedDriver(Map<String, dynamic> order) {
    final driverId =
        (order['driver_id'] ?? order['driverId'] ?? '').toString().trim();
    final driverPhone =
        (order['driver_phone'] ?? order['driverPhone'] ?? '').toString().trim();
    final driverName =
        (order['courier_name'] ?? order['driver_name'] ?? '').toString().trim();
    const unassignedNames = {
      '',
      'غير مخصص',
      'غير مخصص بعد',
      'غير معين',
      'unassigned',
    };
    return driverId.isNotEmpty ||
        driverPhone.isNotEmpty ||
        !unassignedNames.contains(driverName.toLowerCase());
  }

  static String _hashOtp(String otp, String salt) =>
      sha256.convert(utf8.encode('$salt:$otp')).toString();

  static bool _secureEquals(String left, String right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }

    return difference == 0;
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  static double? _toNullableDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  Future<OrderModel?> updatePaymentMethod({
    required String orderId,
    required String paymentMethod,
    String? status,
    String? paymentWalletId,
    String? paymentWalletName,
  }) async {
    try {
      final snapshot = await _databaseService.read('orders/$orderId');
      if (snapshot.isEmpty) return null;

      final updated = Map<String, dynamic>.from(snapshot)
        ..['payment_method'] = paymentMethod;
      if (status != null) updated['status'] = status;
      if (paymentWalletId != null) {
        if (paymentWalletId.isEmpty) {
          updated.remove('payment_wallet_id');
        } else {
          updated['payment_wallet_id'] = paymentWalletId;
        }
      }
      if (paymentWalletName != null) {
        if (paymentWalletName.isEmpty) {
          updated.remove('payment_wallet_name');
        } else {
          updated['payment_wallet_name'] = paymentWalletName;
        }
      }

      final saved = await _databaseService.write('orders/$orderId', updated);
      await _syncCustomerOrder(snapshot, updated, orderId);
      return OrderModel.fromJson(saved);
    } catch (_) {
      return null;
    }
  }

  static Future<DriverProfile?> autoAssignDriverForOrder({
    required String orderId,
    required String region,
    required String vehicleType,
  }) async {
    return DriverService.dispatchBestDriverForOrder(
      orderId: orderId,
      region: region,
      vehicleType: vehicleType,
    );
  }
}
