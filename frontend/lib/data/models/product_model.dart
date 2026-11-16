class ProductModel {
  final String id;
  final String name;
  final DateTime? submittedAt;
  final double price;
  final double? merchantClaimedOriginalPrice;
  final String category;
  final String? mainCategoryId;
  final String? mainCategory;
  final int? mainCategorySortOrder;
  final String? subcategoryId;
  final String? subcategory;
  final String description;
  final List<String> colors;
  final Map<String, String> colorImageUrls;
  final List<String> sizes;
  final bool hasSizes;
  final String imageUrl;
  final List<String> imageUrls;
  final String videoUrl;
  final bool available;
  final String merchantId;
  final String merchantName;
  final String currencyCode;
  final String currencySymbol;
  final String currencyName;
  final double vatRate;
  final double? vatRateOverride;
  final bool vatExempt;
  final String? commissionModeOverride;
  final double? commissionValueOverride;
  final String? effectiveCommissionMode;
  final double? effectiveCommissionValue;

  const ProductModel({
    required this.id,
    required this.name,
    this.submittedAt,
    required this.price,
    this.merchantClaimedOriginalPrice,
    required this.category,
    this.mainCategoryId,
    this.mainCategory,
    this.mainCategorySortOrder,
    this.subcategoryId,
    this.subcategory,
    required this.description,
    this.colors = const [],
    this.colorImageUrls = const {},
    this.sizes = const [],
    this.hasSizes = true,
    required this.imageUrl,
    this.imageUrls = const [],
    this.videoUrl = '',
    required this.available,
    required this.merchantId,
    this.merchantName = '',
    this.currencyCode = 'SAR',
    this.currencySymbol = 'ر.س',
    this.currencyName = 'ريال سعودي',
    this.vatRate = 0,
    this.vatRateOverride,
    this.vatExempt = false,
    this.commissionModeOverride,
    this.commissionValueOverride,
    this.effectiveCommissionMode,
    this.effectiveCommissionValue,
  });

  double get vatAmount => 0;
  double get commissionAmount {
    final mode = effectiveCommissionMode ?? commissionModeOverride;
    final value = effectiveCommissionValue ?? commissionValueOverride;
    if (mode == null || value == null) return 0;
    return commissionAmountForPrice(price: price, mode: mode, value: value);
  }

  double get priceIncludingCommission => price + commissionAmount;
  double get priceIncludingVat => priceIncludingCommission;

  static double commissionAmountForPrice({
    required double price,
    required String mode,
    required double value,
  }) {
    if (!price.isFinite || !value.isFinite || value < 0) return 0;
    if (mode == 'fixed') return value;
    if (mode == 'percent') return price * value / 100;
    return 0;
  }

  static int compareNewestFirst(ProductModel first, ProductModel second) {
    final firstDate = first.submittedAt;
    final secondDate = second.submittedAt;
    if (firstDate == null) return secondDate == null ? 0 : 1;
    if (secondDate == null) return -1;
    return secondDate.compareTo(firstDate);
  }

  String formatPrice(num value) =>
      '${value.toStringAsFixed(0)} ${currencySymbol.trim().isEmpty ? 'ر.س' : currencySymbol.trim()}';

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    final primaryImage = _normalizeImageSource(
      json['image_url'] ??
          json['imageUrl'] ??
          json['image'] ??
          json['cover_image_url'] ??
          json['coverImageUrl'] ??
          '',
    );

    final imageList = _toStringList(
      json['image_urls'] ??
          json['imageUrls'] ??
          json['images'] ??
          json['cover_images'] ??
          const [],
    );

    final normalizedImageUrl = primaryImage.isNotEmpty
        ? primaryImage
        : (imageList.isNotEmpty ? imageList.first : '');

    final availability = _parseAvailability(
      json['available'],
      json['is_available'],
      json['status'],
    );

    return ProductModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      submittedAt: _toDateTime(
        json['submitted_at'] ??
            json['submittedAt'] ??
            json['created_at'] ??
            json['createdAt'],
      ),
      price: _toDouble(json['price']),
      merchantClaimedOriginalPrice: _toNullableDouble(
        json['merchant_claimed_original_price'] ??
            json['merchantClaimedOriginalPrice'],
      ),
      category: json['category']?.toString() ?? 'عام',
      mainCategoryId:
          (json['main_category_id'] ?? json['mainCategoryId'])?.toString(),
      mainCategory: (json['main_category'] ?? json['mainCategory'])?.toString(),
      mainCategorySortOrder: _toNullableInt(
        json['main_category_sort_order'] ?? json['mainCategorySortOrder'],
      ),
      subcategoryId:
          (json['subcategory_id'] ?? json['subcategoryId'])?.toString(),
      subcategory: json['subcategory']?.toString(),
      description: json['description']?.toString() ?? '',
      colors: _toStringList(json['colors'] ?? json['available_colors']),
      colorImageUrls: _toStringMap(
        json['color_image_urls'] ?? json['colorImageUrls'],
      ),
      sizes: _toStringList(json['sizes'] ?? json['available_sizes']),
      hasSizes: _toBool(json['has_sizes'] ?? json['hasSizes'], fallback: true),
      imageUrl: normalizedImageUrl,
      imageUrls: imageList.isNotEmpty
          ? imageList
          : (normalizedImageUrl.isNotEmpty ? [normalizedImageUrl] : const []),
      videoUrl:
          json['video_url']?.toString() ?? json['videoUrl']?.toString() ?? '',
      available: availability,
      merchantId: json['merchant_id']?.toString() ??
          json['merchantId']?.toString() ??
          '',
      merchantName: json['merchant_name']?.toString() ??
          json['merchantName']?.toString() ??
          '',
      currencyCode: json['currency_code']?.toString() ??
          json['currencyCode']?.toString() ??
          'SAR',
      currencySymbol: json['currency_symbol']?.toString() ??
          json['currencySymbol']?.toString() ??
          'ر.س',
      currencyName: json['currency_name']?.toString() ??
          json['currencyName']?.toString() ??
          'ريال سعودي',
      vatRate: _toDouble(json['vat_rate'] ?? json['vatRate']),
      vatRateOverride: _toNullableDouble(json['vat_rate_override']),
      vatExempt: json['vat_exempt'] == true ||
          json['vat_exempt']?.toString().toLowerCase() == 'true',
      commissionModeOverride: json['commission_mode_override']?.toString(),
      commissionValueOverride:
          _toNullableDouble(json['commission_value_override']),
      effectiveCommissionMode: json['effective_commission_mode']?.toString(),
      effectiveCommissionValue:
          _toNullableDouble(json['effective_commission_value']),
    );
  }

  ProductModel copyWith({
    String? id,
    String? name,
    DateTime? submittedAt,
    double? price,
    double? merchantClaimedOriginalPrice,
    String? category,
    String? mainCategoryId,
    String? mainCategory,
    int? mainCategorySortOrder,
    String? subcategoryId,
    String? subcategory,
    String? description,
    List<String>? colors,
    Map<String, String>? colorImageUrls,
    List<String>? sizes,
    bool? hasSizes,
    String? imageUrl,
    List<String>? imageUrls,
    String? videoUrl,
    bool? available,
    String? merchantId,
    String? merchantName,
    String? currencyCode,
    String? currencySymbol,
    String? currencyName,
    double? vatRate,
    double? vatRateOverride,
    bool? vatExempt,
    String? commissionModeOverride,
    double? commissionValueOverride,
    String? effectiveCommissionMode,
    double? effectiveCommissionValue,
  }) {
    return ProductModel(
      id: id ?? this.id,
      name: name ?? this.name,
      submittedAt: submittedAt ?? this.submittedAt,
      price: price ?? this.price,
      merchantClaimedOriginalPrice:
          merchantClaimedOriginalPrice ?? this.merchantClaimedOriginalPrice,
      category: category ?? this.category,
      mainCategoryId: mainCategoryId ?? this.mainCategoryId,
      mainCategory: mainCategory ?? this.mainCategory,
      mainCategorySortOrder:
          mainCategorySortOrder ?? this.mainCategorySortOrder,
      subcategoryId: subcategoryId ?? this.subcategoryId,
      subcategory: subcategory ?? this.subcategory,
      description: description ?? this.description,
      colors: colors ?? this.colors,
      colorImageUrls: colorImageUrls ?? this.colorImageUrls,
      sizes: sizes ?? this.sizes,
      hasSizes: hasSizes ?? this.hasSizes,
      imageUrl: imageUrl ?? this.imageUrl,
      imageUrls: imageUrls ?? this.imageUrls,
      videoUrl: videoUrl ?? this.videoUrl,
      available: available ?? this.available,
      merchantId: merchantId ?? this.merchantId,
      merchantName: merchantName ?? this.merchantName,
      currencyCode: currencyCode ?? this.currencyCode,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      currencyName: currencyName ?? this.currencyName,
      vatRate: vatRate ?? this.vatRate,
      vatRateOverride: vatRateOverride ?? this.vatRateOverride,
      vatExempt: vatExempt ?? this.vatExempt,
      commissionModeOverride:
          commissionModeOverride ?? this.commissionModeOverride,
      commissionValueOverride:
          commissionValueOverride ?? this.commissionValueOverride,
      effectiveCommissionMode:
          effectiveCommissionMode ?? this.effectiveCommissionMode,
      effectiveCommissionValue:
          effectiveCommissionValue ?? this.effectiveCommissionValue,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (submittedAt != null) 'submitted_at': submittedAt!.toIso8601String(),
      'price': price,
      'merchant_claimed_original_price': merchantClaimedOriginalPrice,
      'category': category,
      if (mainCategoryId != null) 'main_category_id': mainCategoryId,
      if (mainCategory != null) 'main_category': mainCategory,
      if (mainCategorySortOrder != null)
        'main_category_sort_order': mainCategorySortOrder,
      if (subcategoryId != null) 'subcategory_id': subcategoryId,
      if (subcategory != null) 'subcategory': subcategory,
      'description': description,
      'colors': colors,
      'color_image_urls': colorImageUrls,
      'sizes': sizes,
      'has_sizes': hasSizes,
      'image_url': imageUrl,
      'image_urls': imageUrls,
      'video_url': videoUrl,
      'available': available,
      'merchant_id': merchantId,
      'merchant_name': merchantName,
      'currency_code': currencyCode,
      'currency_symbol': currencySymbol,
      'currency_name': currencyName,
      'vat_rate': vatRate,
      'vat_rate_override': vatRateOverride,
      'vat_exempt': vatExempt,
      'commission_mode_override': commissionModeOverride,
      'commission_value_override': commissionValueOverride,
      if (effectiveCommissionMode != null)
        'effective_commission_mode': effectiveCommissionMode,
      if (effectiveCommissionValue != null)
        'effective_commission_value': effectiveCommissionValue,
    };
  }

  static bool _parseAvailability(
    dynamic available,
    dynamic isAvailable,
    dynamic status,
  ) {
    final candidates = [available, isAvailable, status];

    for (final candidate in candidates) {
      if (candidate == null) continue;

      if (candidate is bool) return candidate;
      if (candidate is num) return candidate != 0;
      if (candidate is String) {
        final normalized = candidate.trim().toLowerCase();
        if (normalized.isEmpty) continue;

        if (normalized == 'true' ||
            normalized == '1' ||
            normalized == 'yes' ||
            normalized == 'active' ||
            normalized == 'available') {
          return true;
        }

        if (normalized == 'false' ||
            normalized == '0' ||
            normalized == 'no' ||
            normalized == 'inactive' ||
            normalized == 'unavailable' ||
            normalized == 'hidden' ||
            normalized == 'archived' ||
            normalized == 'draft') {
          return false;
        }
      }
    }

    return true;
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static double? _toNullableDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int? _toNullableInt(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static bool _toBool(dynamic value, {required bool fallback}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      switch (value.trim().toLowerCase()) {
        case 'true':
        case '1':
        case 'yes':
          return true;
        case 'false':
        case '0':
        case 'no':
          return false;
      }
    }
    return fallback;
  }

  static Map<String, String> _toStringMap(dynamic value) {
    if (value is! Map) return const {};
    return {
      for (final entry in value.entries)
        if (entry.key.toString().trim().isNotEmpty &&
            entry.value?.toString().trim().isNotEmpty == true)
          entry.key.toString().trim(): entry.value.toString().trim(),
    };
  }

  static List<String> _toStringList(dynamic value) {
    if (value == null) return const [];

    if (value is String) {
      final raw = value.trim();
      if (raw.isEmpty) return const [];

      if (raw.startsWith('data:image')) {
        return [raw];
      }

      final chunks = raw
          .split(RegExp(r'[\r\n,]+'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
      return chunks
          .map((item) => _normalizeImageSource(item))
          .where((item) => item.isNotEmpty)
          .toList();
    }

    if (value is! List) return const [];
    return value
        .map((item) => _normalizeImageSource(item))
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static String _normalizeImageSource(dynamic value) {
    if (value == null) return '';
    final text = value.toString().trim();
    if (text.isEmpty) return '';

    if (text.startsWith('http://') || text.startsWith('https://')) {
      final match = RegExp(
        r'^https?://github\.com/([^/]+/[^/]+)/blob/([^/]+)/(.*)$',
      ).firstMatch(text);
      if (match == null) return text;

      final repository = match.group(1)!;
      final branch = Uri.encodeComponent(match.group(2)!);
      final path =
          match.group(3)!.split('/').map(Uri.encodeComponent).join('/');
      return 'https://raw.githubusercontent.com/$repository/$branch/$path';
    }

    if (text.startsWith('data:image')) {
      return text;
    }

    if (text.contains(',')) {
      final parts = text.split(',');
      if (parts.length > 1 && parts.first.contains('data:image')) {
        return text;
      }
    }

    return text;
  }
}
