import 'package:she_m_app/data/services/firebase_database_service.dart';

class SupportService {
  SupportService({DatabaseService? databaseService})
      : _databaseService = databaseService ?? FirebaseDatabaseService.instance;

  static const String _supportContactPath = 'app_settings/support_contact';
  static const String _refundRequestsPath = 'refund_requests';

  final DatabaseService _databaseService;

  Future<Map<String, dynamic>> getSupportContact() async {
    try {
      final saved = await _databaseService.read(_supportContactPath);
      return {
        'phone': saved['phone']?.toString() ?? '',
        'whatsapp_phone': saved['whatsapp_phone']?.toString() ?? '',
        'email': saved['email']?.toString() ?? '',
        'working_hours': saved['working_hours']?.toString() ?? '',
        'response_time': saved['response_time']?.toString() ?? '',
        'updated_at': saved['updated_at']?.toString() ?? '',
      };
    } catch (_) {
      return const {
        'phone': '',
        'whatsapp_phone': '',
        'email': '',
        'working_hours': '',
        'response_time': '',
        'updated_at': '',
      };
    }
  }

  Future<void> saveSupportContact({
    required String phone,
    required String whatsappPhone,
    required String email,
    required String workingHours,
    required String responseTime,
  }) async {
    final normalizedPhone = phone.trim();
    final normalizedWhatsApp = whatsappPhone.trim();
    final normalizedEmail = email.trim();
    if (normalizedPhone.isEmpty &&
        normalizedWhatsApp.isEmpty &&
        normalizedEmail.isEmpty) {
      throw ArgumentError('أدخل رقم هاتف أو واتساب أو بريدًا للتواصل');
    }

    await _databaseService.write(_supportContactPath, {
      'phone': normalizedPhone,
      'whatsapp_phone': normalizedWhatsApp,
      'email': normalizedEmail,
      'working_hours': workingHours.trim(),
      'response_time': responseTime.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<Map<String, dynamic>> createRefundRequest({
    required String customerId,
    required String orderId,
    required int itemIndex,
    required String reason,
    required String customerMessage,
  }) async {
    final normalizedCustomerId = customerId.trim();
    final normalizedOrderId = orderId.trim();
    final normalizedReason = reason.trim();
    if (normalizedCustomerId.isEmpty || normalizedOrderId.isEmpty) {
      throw ArgumentError('تعذر تحديد العميل أو الطلب');
    }
    if (normalizedReason.isEmpty) {
      throw ArgumentError('يرجى تحديد سبب الاسترداد');
    }

    final order = await _databaseService.read('orders/$normalizedOrderId');
    if (order.isEmpty ||
        (order['customer_id'] ?? order['customerId']).toString() !=
            normalizedCustomerId) {
      throw StateError('الطلب غير موجود أو لا يتبع حسابك');
    }

    final rawItems = order['items'];
    if (rawItems is! List || itemIndex < 0 || itemIndex >= rawItems.length) {
      throw ArgumentError('المنتج المحدد غير موجود في الطلب');
    }
    final orderItem = Map<String, dynamic>.from(rawItems[itemIndex] as Map);
    final productId =
        (orderItem['product_id'] ?? orderItem['productId'] ?? '').toString();
    final merchantId =
        (orderItem['merchant_id'] ?? orderItem['merchantId'] ?? '').toString();
    final customer =
        await _databaseService.read('profiles/$normalizedCustomerId');
    final product = productId.isEmpty
        ? <String, dynamic>{}
        : await _databaseService.read('products/$productId');
    final merchant = merchantId.isEmpty
        ? <String, dynamic>{}
        : await _databaseService.read('profiles/$merchantId');

    final productSnapshot = <String, dynamic>{
      ...product,
      'id': product['id']?.toString() ?? productId,
      'name': orderItem['product_name']?.toString() ??
          product['name']?.toString() ??
          orderItem['productName']?.toString() ??
          '',
      'category': orderItem['product_category']?.toString() ??
          product['category']?.toString() ??
          '',
      'description': orderItem['product_description']?.toString() ??
          product['description']?.toString() ??
          '',
      'image_url': orderItem['image_url']?.toString() ??
          product['image_url']?.toString() ??
          '',
      'merchant_id': merchantId,
    };
    final merchantSnapshot = <String, dynamic>{
      ...merchant,
      'id': merchant['id']?.toString() ?? merchantId,
      'shop_name': orderItem['merchant_name']?.toString() ??
          merchant['shop_name']?.toString() ??
          '',
      'full_name': merchant['full_name']?.toString() ?? '',
      'phone': merchant['phone']?.toString() ?? '',
      'email': merchant['email']?.toString() ?? '',
    };
    final customerSnapshot = <String, dynamic>{
      'id': customer['id']?.toString() ?? normalizedCustomerId,
      'full_name': customer['full_name']?.toString() ?? '',
      'phone': customer['phone']?.toString() ?? '',
      'email': customer['email']?.toString() ?? '',
      'city': customer['city']?.toString() ?? '',
      'address': customer['address']?.toString() ?? '',
    };

    final itemTotal = _asDouble(orderItem['total']);
    final unitPrice = _asDouble(
      orderItem['unit_price'] ?? orderItem['unitPrice'],
    );
    final quantity = _asInt(orderItem['quantity']);
    final amountDue = itemTotal > 0 ? itemTotal : unitPrice * quantity;
    final rawMerchantClaim = orderItem['merchant_claimed_original_price'] ??
        product['merchant_claimed_original_price'];
    final merchantClaimedOriginalPrice =
        rawMerchantClaim == null ? null : _asDouble(rawMerchantClaim);

    final previousRequests = await _databaseService.read(_refundRequestsPath);
    final duplicate = previousRequests.values.whereType<Map>().any((entry) {
      final request = Map<String, dynamic>.from(entry);
      final status = request['status']?.toString();
      return request['customer_id']?.toString() == normalizedCustomerId &&
          request['order_id']?.toString() == normalizedOrderId &&
          _asInt(request['item_index']) == itemIndex &&
          (status == 'pending' ||
              status == 'under_review' ||
              status == 'approved');
    });
    if (duplicate) {
      throw StateError('يوجد طلب استرداد قيد المراجعة لهذا المنتج');
    }

    final now = DateTime.now().toUtc();
    final requestId = 'refund-${now.microsecondsSinceEpoch}';
    final request = <String, dynamic>{
      'id': requestId,
      'status': 'pending',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'customer_id': normalizedCustomerId,
      'customer_snapshot': customerSnapshot,
      'order_id': normalizedOrderId,
      'order_status': order['status']?.toString() ?? '',
      'order_created_at': order['created_at']?.toString() ?? '',
      'order_snapshot': {
        'id': normalizedOrderId,
        'status': order['status']?.toString() ?? '',
        'created_at': order['created_at']?.toString() ?? '',
        'payment_method': order['payment_method']?.toString() ?? '',
        'subtotal': order['subtotal'],
        'shipping_fee': order['shipping_fee'],
        'commission': order['commission'],
        'total': order['total'],
        'delivery_address': order['delivery_address']?.toString() ??
            customerSnapshot['address'],
      },
      'item_index': itemIndex,
      'order_item_snapshot': orderItem,
      'product_id': productId,
      'product_snapshot': productSnapshot,
      'merchant_id': merchantId,
      'merchant_snapshot': merchantSnapshot,
      'reason': normalizedReason,
      'customer_message': customerMessage.trim(),
      'currency_code': orderItem['currency_code']?.toString() ?? 'SAR',
      'currency_symbol': orderItem['currency_symbol']?.toString() ?? 'ر.س',
      'unit_price': unitPrice,
      'quantity': quantity,
      'customer_claimed_amount': amountDue,
      'amount_due_to_customer': amountDue,
      'merchant_claimed_original_price': merchantClaimedOriginalPrice,
      'merchant_claimed_total': merchantClaimedOriginalPrice == null
          ? null
          : merchantClaimedOriginalPrice * quantity,
      'approved_amount': null,
      'admin_note': '',
      'reviewed_by': '',
      'reviewed_at': null,
    };

    await _databaseService.write('$_refundRequestsPath/$requestId', request);
    await _databaseService.write(
      'customers/$normalizedCustomerId/refund_requests/$requestId',
      request,
    );
    return request;
  }

  Future<List<Map<String, dynamic>>> getRefundRequests() async {
    try {
      final stored = await _databaseService.read(_refundRequestsPath);
      final requests = stored.entries
          .where((entry) => entry.value is Map)
          .map((entry) => {
                ...Map<String, dynamic>.from(entry.value as Map),
                'id': (entry.value as Map)['id']?.toString() ?? entry.key,
              })
          .toList();
      requests.sort(
          (first, second) => (second['created_at'] ?? '').toString().compareTo(
                (first['created_at'] ?? '').toString(),
              ));
      return requests;
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> getRefundRequestsForCustomer(
    String customerId,
  ) async {
    try {
      final stored = await _databaseService.read(
        'customers/${customerId.trim()}/refund_requests',
      );
      return stored.entries
          .where((entry) => entry.value is Map)
          .map((entry) => {
                ...Map<String, dynamic>.from(entry.value as Map),
                'id': (entry.value as Map)['id']?.toString() ?? entry.key,
              })
          .toList()
        ..sort((first, second) =>
            (second['created_at'] ?? '').toString().compareTo(
                  (first['created_at'] ?? '').toString(),
                ));
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, dynamic>?> reviewRefundRequest({
    required String requestId,
    required String status,
    required double approvedAmount,
    required String adminNote,
    required String reviewedBy,
  }) async {
    if (!{'under_review', 'approved', 'rejected'}.contains(status)) return null;

    final request =
        await _databaseService.read('$_refundRequestsPath/$requestId');
    if (request.isEmpty) return null;
    final requestedAmount = _asDouble(request['customer_claimed_amount']);
    if (status == 'approved' &&
        (approvedAmount <= 0 || approvedAmount > requestedAmount)) {
      return null;
    }

    final updated = <String, dynamic>{
      ...request,
      'status': status,
      'approved_amount': status == 'approved'
          ? approvedAmount
          : status == 'rejected'
              ? 0
              : null,
      'admin_note': adminNote.trim(),
      'reviewed_by': reviewedBy.trim(),
      'reviewed_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final saved = await _databaseService.write(
      '$_refundRequestsPath/$requestId',
      updated,
    );
    final customerId = request['customer_id']?.toString() ?? '';
    if (customerId.isNotEmpty) {
      await _databaseService.write(
        'customers/$customerId/refund_requests/$requestId',
        saved,
      );
    }
    return saved;
  }

  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _asInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
