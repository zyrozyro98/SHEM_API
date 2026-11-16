import 'package:she_m_app/data/models/order_number.dart';

Map<String, dynamic> sanitizeOrderForCustomer(
  Map<String, dynamic> order,
) {
  const secretFields = {
    'pickup_otp',
    'pickupOtp',
    'pickup_otp_hash',
    'pickupOtpHash',
    'pickup_otp_salt',
    'pickupOtpSalt',
    'pickup_otp_expires_at',
    'pickupOtpExpiresAt',
    'pickup_otp_attempts',
    'pickupOtpAttempts',
    'pickup_otp_locked',
    'pickupOtpLocked',
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
    'delivery_otp',
    'deliveryOtp',
    'delivery_otp_hash',
    'deliveryOtpHash',
    'delivery_otp_salt',
    'deliveryOtpSalt',
    'delivery_otp_expires_at',
    'deliveryOtpExpiresAt',
    'delivery_otp_attempts',
    'deliveryOtpAttempts',
    'delivery_otp_locked',
    'deliveryOtpLocked',
  };
  return Map<String, dynamic>.from(order)
    ..removeWhere((key, _) => secretFields.contains(key));
}

class OrderItem {
  final String productId;
  final String productName;
  final String productCategory;
  final String productDescription;
  final int quantity;
  final double unitPrice;
  final double total;
  final double? baseUnitPrice;
  final double vatAmount;
  final double? baseUnitPriceYER;
  final double? vatAmountYER;
  final double? totalYER;
  final double? rateToYER;
  final double? merchantClaimedOriginalPrice;
  final String? selectedColor;
  final String? selectedSize;
  final String imageUrl;
  final String currencyCode;
  final String currencySymbol;
  final String merchantId;
  final String merchantName;
  final String status;
  final String? rejectionReason;
  final String? rejectedBy;
  final DateTime? rejectedAt;

  const OrderItem({
    required this.productId,
    required this.productName,
    this.productCategory = '',
    this.productDescription = '',
    required this.quantity,
    required this.unitPrice,
    required this.total,
    this.baseUnitPrice,
    this.vatAmount = 0,
    this.baseUnitPriceYER,
    this.vatAmountYER,
    this.totalYER,
    this.rateToYER,
    this.merchantClaimedOriginalPrice,
    this.selectedColor,
    this.selectedSize,
    this.imageUrl = '',
    this.currencyCode = 'SAR',
    this.currencySymbol = 'ر.س',
    this.merchantId = '',
    this.merchantName = '',
    this.status = 'available',
    this.rejectionReason,
    this.rejectedBy,
    this.rejectedAt,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      productId:
          json['product_id']?.toString() ?? json['productId']?.toString() ?? '',
      productName: json['product_name']?.toString() ??
          json['productName']?.toString() ??
          '',
      productCategory: json['product_category']?.toString() ??
          json['productCategory']?.toString() ??
          '',
      productDescription: json['product_description']?.toString() ??
          json['productDescription']?.toString() ??
          '',
      quantity: json['quantity'] is int
          ? json['quantity'] as int
          : int.tryParse(json['quantity']?.toString() ?? '0') ?? 0,
      unitPrice: _toDouble(json['unit_price'] ?? json['unitPrice']),
      total: _toDouble(json['total']),
      baseUnitPrice: json['base_unit_price'] is num
          ? (json['base_unit_price'] as num).toDouble()
          : double.tryParse(json['base_unit_price']?.toString() ?? ''),
      vatAmount: _toDouble(json['vat_amount']),
      baseUnitPriceYER: _toNullableDouble(json['base_unit_price_yer']),
      vatAmountYER: _toNullableDouble(json['vat_amount_yer']),
      totalYER: _toNullableDouble(json['total_yer']),
      rateToYER: _toNullableDouble(json['rate_to_yer']),
      merchantClaimedOriginalPrice:
          json['merchant_claimed_original_price'] is num
              ? (json['merchant_claimed_original_price'] as num).toDouble()
              : double.tryParse(
                  json['merchant_claimed_original_price']?.toString() ?? '',
                ),
      selectedColor: json['selected_color']?.toString() ??
          json['selectedColor']?.toString(),
      selectedSize:
          json['selected_size']?.toString() ?? json['selectedSize']?.toString(),
      imageUrl: json['image_url']?.toString() ??
          json['imageUrl']?.toString() ??
          json['cover_image_url']?.toString() ??
          json['coverImageUrl']?.toString() ??
          '',
      currencyCode: json['currency_code']?.toString() ??
          json['currencyCode']?.toString() ??
          'SAR',
      currencySymbol: json['currency_symbol']?.toString() ??
          json['currencySymbol']?.toString() ??
          'ر.س',
      merchantId: json['merchant_id']?.toString() ??
          json['merchantId']?.toString() ??
          '',
      merchantName: json['merchant_name']?.toString() ??
          json['merchantName']?.toString() ??
          '',
      status: json['status']?.toString() ?? 'available',
      rejectionReason: json['rejection_reason']?.toString() ??
          json['rejectionReason']?.toString(),
      rejectedBy:
          json['rejected_by']?.toString() ?? json['rejectedBy']?.toString(),
      rejectedAt: DateTime.tryParse(
        (json['rejected_at'] ?? json['rejectedAt'] ?? '').toString(),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'product_name': productName,
      'product_category': productCategory,
      'product_description': productDescription,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total': total,
      'base_unit_price': baseUnitPrice,
      'vat_amount': vatAmount,
      'base_unit_price_yer': baseUnitPriceYER,
      'vat_amount_yer': vatAmountYER,
      'total_yer': totalYER,
      'rate_to_yer': rateToYER,
      'merchant_claimed_original_price': merchantClaimedOriginalPrice,
      'selected_color': selectedColor,
      'selected_size': selectedSize,
      'image_url': imageUrl,
      'currency_code': currencyCode,
      'currency_symbol': currencySymbol,
      'merchant_id': merchantId,
      'merchant_name': merchantName,
      'status': status,
      'rejection_reason': rejectionReason,
      'rejected_by': rejectedBy,
      'rejected_at': rejectedAt?.toIso8601String(),
    };
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
}

class OrderModel {
  final String id;
  final String? orderNumber;
  final String customerId;
  final List<OrderItem> items;
  final String status;
  final String paymentMethod;
  final String? paymentWalletId;
  final String? paymentWalletName;
  final double subtotal;
  final double shippingFee;
  final double commission;
  final double total;
  final String currencyCode;
  final String currencySymbol;
  final bool hasExplicitCurrencyCode;
  final String? paymentProofId;
  final String? deliveryOtp;
  final String? pickupOtp;
  final bool deliveryOtpVerified;
  final DateTime? deliveryOtpExpiresAt;
  final int deliveryOtpAttempts;
  final bool deliveryOtpLocked;
  final DateTime createdAt;
  final String? cancelledBy;
  final String? cancellationReason;
  final DateTime? cancelledAt;

  const OrderModel({
    required this.id,
    this.orderNumber,
    required this.customerId,
    required this.items,
    required this.status,
    required this.paymentMethod,
    this.paymentWalletId,
    this.paymentWalletName,
    required this.subtotal,
    required this.shippingFee,
    this.commission = 0,
    required this.total,
    this.currencyCode = 'YER',
    this.currencySymbol = 'ر.ي',
    this.hasExplicitCurrencyCode = true,
    this.paymentProofId,
    this.deliveryOtp,
    this.pickupOtp,
    this.deliveryOtpVerified = false,
    this.deliveryOtpExpiresAt,
    this.deliveryOtpAttempts = 0,
    this.deliveryOtpLocked = false,
    required this.createdAt,
    this.cancelledBy,
    this.cancellationReason,
    this.cancelledAt,
  });

  String get displayOrderNumber => OrderNumber.fromId(orderNumber ?? id);

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] ?? json['order_items'] ?? <dynamic>[];
    final list = (rawItems as List<dynamic>? ?? <dynamic>[])
        .map((e) => OrderItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    return OrderModel(
      id: json['id']?.toString() ?? '',
      orderNumber: (json['order_number'] ?? json['orderNumber'])
                  ?.toString()
                  .trim()
                  .isNotEmpty ==
              true
          ? OrderNumber.fromOrder(json)
          : null,
      customerId: json['customer_id']?.toString() ??
          json['customerId']?.toString() ??
          '',
      items: list,
      status: json['status']?.toString() ?? 'pending_payment',
      paymentMethod: json['payment_method']?.toString() ??
          json['paymentMethod']?.toString() ??
          'cash_on_delivery',
      paymentWalletId: json['payment_wallet_id']?.toString() ??
          json['paymentWalletId']?.toString(),
      paymentWalletName: json['payment_wallet_name']?.toString() ??
          json['paymentWalletName']?.toString(),
      subtotal: _toDouble(json['subtotal']),
      shippingFee: _toDouble(json['shipping_fee'] ?? json['shippingFee']),
      commission: _toDouble(json['commission']),
      total: _toDouble(json['total']),
      currencyCode: json['currency_code']?.toString() ??
          (list.isNotEmpty ? list.first.currencyCode : 'YER'),
      currencySymbol: json['currency_symbol']?.toString() ??
          (list.isNotEmpty ? list.first.currencySymbol : 'ر.ي'),
      hasExplicitCurrencyCode:
          json.containsKey('currency_code') || json.containsKey('currencyCode'),
      paymentProofId: json['payment_proof_id']?.toString() ??
          json['paymentProofId']?.toString(),
      deliveryOtp:
          json['delivery_otp']?.toString() ?? json['deliveryOtp']?.toString(),
      pickupOtp:
          json['pickup_otp']?.toString() ?? json['pickupOtp']?.toString(),
      deliveryOtpVerified: json['delivery_otp_verified'] == true ||
          json['deliveryOtpVerified'] == true,
      deliveryOtpExpiresAt: DateTime.tryParse(
        (json['delivery_otp_expires_at'] ?? json['deliveryOtpExpiresAt'] ?? '')
            .toString(),
      ),
      deliveryOtpAttempts: int.tryParse(
            (json['delivery_otp_attempts'] ?? json['deliveryOtpAttempts'] ?? 0)
                .toString(),
          ) ??
          0,
      deliveryOtpLocked: json['delivery_otp_locked'] == true ||
          json['deliveryOtpLocked'] == true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      cancelledBy: json['cancelled_by']?.toString(),
      cancellationReason: json['cancellation_reason']?.toString(),
      cancelledAt: DateTime.tryParse(json['cancelled_at']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_number': displayOrderNumber,
      'customer_id': customerId,
      'items': items.map((e) => e.toJson()).toList(),
      'status': status,
      'payment_method': paymentMethod,
      'payment_wallet_id': paymentWalletId,
      'payment_wallet_name': paymentWalletName,
      'subtotal': subtotal,
      'shipping_fee': shippingFee,
      'commission': commission,
      'total': total,
      'currency_code': currencyCode,
      'currency_symbol': currencySymbol,
      'payment_proof_id': paymentProofId,
      'pickup_otp': pickupOtp,
      'created_at': createdAt.toIso8601String(),
      'cancelled_by': cancelledBy,
      'cancellation_reason': cancellationReason,
      'cancelled_at': cancelledAt?.toIso8601String(),
    };
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }
}
