import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:she_m_app/core/errors/app_error.dart';
import 'package:she_m_app/core/constants/yemeni_cities.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:she_m_app/core/animations/route_transitions.dart';
import 'package:she_m_app/data/models/user_model.dart';
import 'package:she_m_app/data/models/product_model.dart';
import 'package:she_m_app/data/services/admin_service.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/data/services/account_deletion_service.dart';
import 'package:she_m_app/data/services/delivery_service.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/data/services/currency_service.dart';
import 'package:she_m_app/data/services/media_upload_service.dart';
import 'package:she_m_app/data/services/merchant_category_service.dart';
import 'package:she_m_app/data/services/merchant_order_accounting.dart';
import 'package:she_m_app/data/services/order_service.dart';
import 'package:she_m_app/data/services/pricing_service.dart';
import 'package:she_m_app/data/models/order_number.dart';
import 'package:she_m_app/data/services/merchant_wallet_service.dart';
import 'package:flutter_compress/flutter_compress.dart';
import 'package:she_m_app/presentation/auth/phone_login_screen.dart';
import 'package:she_m_app/presentation/admin/promotion_management_screen.dart';
import 'package:she_m_app/presentation/common/app_version_list_tile.dart';
import 'package:she_m_app/presentation/common/account_switcher_button.dart';
import 'package:she_m_app/presentation/common/account_deletion_dialog.dart';
import 'package:she_m_app/presentation/common/logout_confirmation_dialog.dart';
import 'package:she_m_app/presentation/common/notification_bell.dart';
import 'package:she_m_app/presentation/common/order_number_copy_button.dart';
import 'package:she_m_app/presentation/common/product_color_selector.dart';
import 'package:she_m_app/presentation/support/support_center_screen.dart';
import 'package:she_m_app/presentation/common/product_video_cache.dart';
import 'package:she_m_app/presentation/common/password_change_dialog.dart';
import 'package:video_player/video_player.dart';

int normalizeCoverIndex(int candidateIndex, int imageCount) {
  if (imageCount <= 0) {
    return 0;
  }

  if (candidateIndex < 0) {
    return 0;
  }

  return candidateIndex.clamp(0, imageCount - 1);
}

DateTime? _merchantOrderCreatedAt(Map<String, dynamic> order) {
  final value = order['created_at'] ?? order['createdAt'];
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  return DateTime.tryParse(value?.toString() ?? '');
}

List<Map<String, dynamic>> sortMerchantOrdersNewestFirst(
  List<Map<String, dynamic>> orders,
) {
  final sorted = [...orders];
  sorted.sort((first, second) {
    final firstCreatedAt = _merchantOrderCreatedAt(first);
    final secondCreatedAt = _merchantOrderCreatedAt(second);
    if (firstCreatedAt == null) return secondCreatedAt == null ? 0 : 1;
    if (secondCreatedAt == null) return -1;
    return secondCreatedAt.compareTo(firstCreatedAt);
  });
  return sorted;
}

String formatMerchantOrderDateTime(Map<String, dynamic> order) {
  final createdAt = _merchantOrderCreatedAt(order)?.toLocal();
  if (createdAt == null) return 'غير محدد';

  String twoDigits(int value) => value.toString().padLeft(2, '0');

  return '${twoDigits(createdAt.day)}/${twoDigits(createdAt.month)}/'
      '${createdAt.year} • ${twoDigits(createdAt.hour)}:'
      '${twoDigits(createdAt.minute)}';
}

String? nextMerchantOrderStatus(String status) => switch (status) {
      'new' => 'preparing',
      'pending_payment' => 'confirmed',
      'confirmed' => 'preparing',
      'preparing' => 'shipped',
      _ => null,
    };

bool isMerchantOrderItem({
  required Map<String, dynamic> item,
  required String merchantId,
  Map<String, String> productOwners = const {},
  Set<String> merchantProductIds = const {},
}) {
  return OrderService.orderItemBelongsToMerchant(
    item: item,
    merchantId: merchantId,
    productOwners: productOwners,
    merchantProductIds: merchantProductIds,
  );
}

List<String> merchantOrderProductImages({
  required Map<String, dynamic> order,
  required String merchantId,
  required Map<String, dynamic> productsSnapshot,
}) {
  final normalizedMerchantId = merchantId.trim();
  if (normalizedMerchantId.isEmpty) return const [];

  final productsById = <String, Map<String, dynamic>>{};
  for (final entry in productsSnapshot.entries) {
    if (entry.value is! Map) continue;
    final product = Map<String, dynamic>.from(entry.value as Map);
    final productId = (product['id'] ?? entry.key).toString().trim();
    productsById[entry.key.trim()] = product;
    if (productId.isNotEmpty) productsById[productId] = product;
  }

  final rawItems =
      order['merchant_items'] ?? order['items'] ?? order['order_items'];
  final items = rawItems is List
      ? rawItems
      : rawItems is Map
          ? rawItems.values.toList()
          : const <dynamic>[];
  final imageUrls = <String>[];
  final seen = <String>{};

  for (final rawItem in items) {
    if (rawItem is! Map) continue;
    final item = Map<String, dynamic>.from(rawItem);
    final productId =
        (item['product_id'] ?? item['productId'] ?? '').toString().trim();
    if (productId.isEmpty) continue;

    final product = productsById[productId];
    if (product == null) continue;
    final ownerId = (product['merchant_id'] ??
            product['merchantId'] ??
            product['owner_id'] ??
            product['ownerId'] ??
            '')
        .toString()
        .trim();
    if (ownerId != normalizedMerchantId) continue;

    final itemImageUrl = resolveProductPrimaryImage(item);
    final imageUrl = itemImageUrl.isNotEmpty
        ? itemImageUrl
        : resolveProductPrimaryImage(product);
    if (imageUrl.isNotEmpty && seen.add(imageUrl)) imageUrls.add(imageUrl);
  }
  return imageUrls;
}

List<String> _merchantOrderImageUrls(Map<String, dynamic> order) {
  final rawImages = order['merchant_product_images'];
  if (rawImages is! List) return const [];
  return rawImages
      .map((image) => image.toString().trim())
      .where((image) => image.isNotEmpty)
      .toList();
}

class MerchantOrderProductThumbnails extends StatelessWidget {
  const MerchantOrderProductThumbnails({
    required this.orderId,
    required this.imageUrls,
    this.size = 46,
    this.placeholderColor = const Color(0xFFB45309),
    this.placeholderIcon = Icons.receipt_long_rounded,
    super.key,
  });

  final String orderId;
  final List<String> imageUrls;
  final double size;
  final Color placeholderColor;
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context) {
    final images = imageUrls
        .map((image) => image.trim())
        .where((image) => MediaUploadService.imageProvider(image) != null)
        .toSet()
        .toList();
    final visibleImages = images.take(3).toList();
    if (visibleImages.isEmpty) {
      return _placeholder();
    }

    final overlap = size * 0.38;
    return Semantics(
      label: 'صور منتجات الطلب $orderId',
      child: SizedBox(
        width: size + overlap * (visibleImages.length - 1),
        height: size,
        child: Stack(
          children: [
            for (var index = visibleImages.length - 1; index >= 0; index--)
              PositionedDirectional(
                start: overlap * index,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(size * 0.24),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(size * 0.2),
                    child: Image(
                      key: ValueKey(
                        'merchant-order-product-image-$orderId-$index',
                      ),
                      image: MediaUploadService.imageProvider(
                        visibleImages[index],
                      )!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(),
                    ),
                  ),
                ),
              ),
            if (images.length > visibleImages.length)
              PositionedDirectional(
                end: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827).withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                  child: Text(
                    '+${images.length - visibleImages.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: placeholderColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      child: Icon(
        placeholderIcon,
        color: placeholderColor,
        size: size * 0.5,
      ),
    );
  }
}

double? merchantProductUnitPrice(Map<String, dynamic> item) {
  double? parseAmount(Object? value) {
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  return parseAmount(item['base_unit_price'] ?? item['baseUnitPrice']) ??
      parseAmount(
        item['unit_price'] ?? item['unitPrice'] ?? item['price'],
      );
}

double? merchantProductsTotalInYER(
  Map<String, dynamic> order, {
  required String merchantId,
  Map<String, String> productOwners = const {},
  Set<String> merchantProductIds = const {},
  List<CurrencyOption> currencies = const [],
}) =>
    MerchantOrderAccounting.productsTotalInYER(
      order: order,
      merchantId: merchantId,
      productOwners: productOwners,
      merchantProductIds: merchantProductIds,
      currencies: currencies,
    );

String _merchantOrderTotalLabel(Map<String, dynamic> order) {
  final total = order['report_total_yer'];
  if (total is num) {
    return '${total.toStringAsFixed(0)} ر.ي';
  }
  return 'غير متاح بالريال اليمني';
}

String merchantOrderItemsSummary(Map<String, dynamic> order) {
  final rawItems = order['merchant_items'];
  if (rawItems is! List || rawItems.isEmpty) return 'تفاصيل الطلب';

  final items = rawItems.whereType<Map>().toList();
  final itemCount = items.fold<int>(
    0,
    (count, item) =>
        count + (int.tryParse(item['quantity']?.toString() ?? '1') ?? 1),
  );
  final firstItem = items.isEmpty ? null : items.first;
  final firstProduct = firstItem?['product_name'] ?? firstItem?['productName'];
  if (firstProduct == null || firstProduct.toString().trim().isEmpty) {
    return '$itemCount منتجات في الطلب';
  }
  return itemCount > 1
      ? '${firstProduct.toString().trim()} + ${itemCount - 1} منتجات'
      : firstProduct.toString().trim();
}

List<String> normalizeSelectedCategories(
  List<String> selectedCategories, {
  int maxCount = 3,
}) {
  final cleaned = selectedCategories
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList();

  if (cleaned.length <= maxCount) {
    return cleaned;
  }

  return cleaned.take(maxCount).toList();
}

List<String> parseSelectedCategories(String rawValue) {
  if (rawValue.trim().isEmpty) {
    return const [];
  }

  return rawValue
      .split(RegExp(r'[,/|]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

String? validateProductDraftInputs({
  required String name,
  required List<String> categories,
  required String priceText,
}) {
  if (name.trim().isEmpty) {
    return 'يرجى إدخال اسم المنتج';
  }

  if (categories.length != 1) {
    return categories.isEmpty
        ? 'اختر القسم الرئيسي والقسم الفرعي للمنتج'
        : 'اختر فئة واحدة فقط للمنتج';
  }

  final parsedPrice = double.tryParse(priceText.trim());
  if (priceText.trim().isEmpty || parsedPrice == null || parsedPrice <= 0) {
    return 'يرجى إدخال سعر المنتج';
  }

  return null;
}

Map<String, dynamic> buildMerchantProductPayload({
  required Map<String, dynamic>? existingProduct,
  required String merchantId,
  required String name,
  required String categoryText,
  required List<String> imageUris,
  required String videoDataUri,
  required bool available,
  required String description,
  required num price,
  required int stock,
  String? mainCategoryId,
  String? mainCategoryName,
  String? subcategoryId,
  String? subcategoryName,
  String currencyCode = 'SAR',
  String currencySymbol = 'ر.س',
  String currencyName = 'ريال سعودي',
  String? coverImageUri,
  List<String> colors = const [],
  Map<String, String> colorImageUrls = const {},
  List<String> sizes = const [],
  bool hasSizes = true,
}) {
  final cleanedName = name.trim();
  final submittedCategories = parseSelectedCategories(categoryText);
  final normalizedCategories = normalizeSelectedCategories(
    submittedCategories,
    maxCount: submittedCategories.length,
  );

  if (cleanedName.isEmpty) {
    throw ArgumentError('يرجى إدخال اسم المنتج');
  }

  if (normalizedCategories.length != 1) {
    throw ArgumentError('يجب اختيار فئة أساسية واحدة فقط للمنتج');
  }
  final selectedCategory = normalizedCategories.join(' / ');
  final effectiveCoverImageUri = (coverImageUri ?? '').trim();
  final selectedImageUrl = effectiveCoverImageUri.isNotEmpty
      ? effectiveCoverImageUri
      : (imageUris.isNotEmpty ? imageUris.first : '');

  final normalizedImageUris = mergeProductImageSourceUris(
    existing: imageUris,
    newlyPicked:
        (selectedImageUrl.isNotEmpty ? [selectedImageUrl] : const <String>[]),
  );
  final normalizedColorImageUrls = {
    for (final entry in colorImageUrls.entries)
      if (colors.contains(entry.key) &&
          normalizedImageUris.contains(entry.value.trim()) &&
          entry.value.trim().isNotEmpty)
        entry.key: entry.value.trim(),
  };
  final existingStatus = existingProduct == null
      ? 'pending'
      : resolveProductApprovalStatus(existingProduct);
  final isApprovedProduct =
      existingProduct != null && existingStatus == 'approved';
  final currentPrice = _productPrice(existingProduct?['price']);
  final hasPendingPriceChange =
      existingProduct?['price_change_status'] == 'pending';
  final submittedPrice = price.toDouble();
  final hasNewPriceChange = isApprovedProduct && submittedPrice != currentPrice;
  final hasPriceChangeRequest = hasNewPriceChange || hasPendingPriceChange;
  final requestedAvailability = existingProduct == null
      ? available
      : existingProduct['requested_available'] == null
          ? resolveMerchantProductAvailability(existingProduct)
          : existingProduct['requested_available'] == true ||
              existingProduct['requested_available'] == 'true';

  return {
    'id': existingProduct?['id']?.toString() ??
        'product-${DateTime.now().millisecondsSinceEpoch}',
    'name': cleanedName,
    'category': selectedCategory,
    'categories': normalizedCategories,
    if (mainCategoryId?.trim().isNotEmpty == true)
      'main_category_id': mainCategoryId!.trim(),
    if (mainCategoryName?.trim().isNotEmpty == true)
      'main_category': mainCategoryName!.trim(),
    if (subcategoryId?.trim().isNotEmpty == true)
      'subcategory_id': subcategoryId!.trim(),
    if (subcategoryName?.trim().isNotEmpty == true)
      'subcategory': subcategoryName!.trim(),
    'description': description.trim(),
    'colors': colors,
    'color_image_urls': normalizedColorImageUrls,
    'colorImageUrls': normalizedColorImageUrls,
    'sizes': hasSizes ? sizes : const <String>[],
    'has_sizes': hasSizes,
    'price': hasPriceChangeRequest ? currentPrice : price,
    'price_change_status':
        hasNewPriceChange ? 'pending' : existingProduct?['price_change_status'],
    'requested_price': hasNewPriceChange
        ? submittedPrice
        : existingProduct?['requested_price'],
    'price_change_previous_price': hasNewPriceChange
        ? currentPrice
        : existingProduct?['price_change_previous_price'],
    'price_change_requested_at': hasNewPriceChange
        ? DateTime.now().toIso8601String()
        : existingProduct?['price_change_requested_at'],
    'price_change_review_reason':
        hasNewPriceChange ? '' : existingProduct?['price_change_review_reason'],
    'price_change_reviewed_at':
        hasNewPriceChange ? null : existingProduct?['price_change_reviewed_at'],
    if (existingProduct?['merchant_claimed_original_price'] != null)
      'merchant_claimed_original_price':
          existingProduct!['merchant_claimed_original_price'],
    'commission_mode_override': existingProduct?['commission_mode_override'],
    'commission_value_override': existingProduct?['commission_value_override'],
    'currency_code': currencyCode,
    'currency_symbol': currencySymbol,
    'currency_name': currencyName,
    'stock': stock,
    'available': isApprovedProduct
        ? existingProduct['available'] == true ||
            existingProduct['available'] == 'true'
        : false,
    'requested_available': requestedAvailability,
    'approval_status': isApprovedProduct ? 'approved' : 'pending',
    'review_reason':
        isApprovedProduct ? existingProduct['review_reason'] ?? '' : '',
    'reviewed_at': isApprovedProduct ? existingProduct['reviewed_at'] : null,
    'submitted_at': DateTime.now().toIso8601String(),
    'merchant_id': merchantId,
    'image_url': selectedImageUrl,
    'imageUrl': selectedImageUrl,
    'image_urls': normalizedImageUris,
    'imageUrls': normalizedImageUris,
    'images': normalizedImageUris,
    'cover_image_url': selectedImageUrl,
    'coverImageUrl': selectedImageUrl,
    'cover_images': normalizedImageUris,
    'video_url': videoDataUri,
    'videoUrl': videoDataUri,
  };
}

double _productPrice(Object? value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? 0;

String resolveProductApprovalStatus(Map<String, dynamic> product) {
  final status = (product['approval_status'] ?? '').toString().trim();
  if (status == 'pending' || status == 'approved' || status == 'rejected') {
    return status;
  }
  return 'approved';
}

bool resolveMerchantProductAvailability(Map<String, dynamic> product) {
  final availability = product['requested_available'] ?? product['available'];
  return availability == true || availability == 'true';
}

Map<String, dynamic> buildMerchantProductAvailabilityUpdates({
  required Map<String, dynamic> product,
  required bool available,
}) {
  final isApproved = resolveProductApprovalStatus(product) == 'approved';
  return {
    'available': isApproved && available,
    'requested_available': available,
  };
}

List<String> parseProductColors(String value) {
  return value
      .split(RegExp(r'[,\n]+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList();
}

List<String> parseProductSizes(String value) {
  return value
      .split(RegExp(r'[,\n]+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList();
}

List<String> mergeProductImageSourceUris({
  required List<String> existing,
  required List<String> newlyPicked,
}) {
  final merged = <String>[];
  final seen = <String>{};

  for (final value in [...existing, ...newlyPicked]) {
    final normalized = value.trim();
    if (normalized.isEmpty || !seen.add(normalized)) {
      continue;
    }
    merged.add(normalized);
  }

  return merged;
}

String resolveProductPrimaryImage(Map<String, dynamic> product) {
  final candidateKeys = [
    'image_url',
    'imageUrl',
    'image',
    'cover_image_url',
    'coverImageUrl',
  ];

  for (final key in candidateKeys) {
    final value = product[key];
    if (value == null) continue;
    final normalized = value.toString().trim();
    if (normalized.isNotEmpty) return normalized;
  }

  final list = resolveProductImageList(product);
  return list.isNotEmpty ? list.first : '';
}

String resolveProductCurrencyLabel(Map<String, dynamic> product) {
  final symbol = (product['currency_symbol'] ?? product['currencySymbol'])
      ?.toString()
      .trim();
  if (symbol != null && symbol.isNotEmpty) return symbol;

  final code =
      (product['currency_code'] ?? product['currencyCode'])?.toString().trim();
  return code == null || code.isEmpty ? 'ر.س' : code;
}

int resolveProductStock(Map<String, dynamic> product) {
  final value = product['stock'] ?? product['inventory'] ?? 0;
  if (value is num) return value.toInt().clamp(0, 999999);
  return int.tryParse(value.toString())?.clamp(0, 999999) ?? 0;
}

String resolveInventoryStatus(int stock) {
  if (stock <= 0) return 'out_of_stock';
  if (stock <= 5) return 'low_stock';
  return 'in_stock';
}

List<String> resolveProductImageList(Map<String, dynamic> product) {
  final dynamicCandidates = [
    product['image_urls'],
    product['imageUrls'],
    product['images'],
    product['cover_images'],
    product['coverImageUrls'],
    product['image_url'],
    product['imageUrl'],
    product['cover_image_url'],
    product['coverImageUrl'],
  ];

  final merged = <String>[];
  final seen = <String>{};

  for (final candidate in dynamicCandidates) {
    if (candidate == null) continue;

    final items = <String>[];
    if (candidate is List) {
      items.addAll(candidate.map((item) => item?.toString().trim() ?? ''));
    } else {
      final text = candidate.toString().trim();
      if (text.isNotEmpty) {
        items.addAll(text
            .split(RegExp(r'[\r\n,]+'))
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty));
      }
    }

    for (final item in items) {
      if (item.isEmpty || !seen.add(item)) continue;
      merged.add(item);
    }
  }

  return merged;
}

MerchantDashboardData? _lastMerchantDashboardData;
List<Map<String, dynamic>> _lastMerchantProductsCache = const [];

class MerchantManagementScreen extends StatefulWidget {
  const MerchantManagementScreen({super.key});

  static String? resolveMerchantId(
    UserModel? sessionProfile, {
    Map<String, dynamic>? record,
    String? fallbackId,
  }) {
    final directFromSession = sessionProfile?.id.trim();
    if (directFromSession != null && directFromSession.isNotEmpty) {
      return directFromSession;
    }

    final directFromRecord = record == null
        ? null
        : (record['id'] ?? record['merchant_id'] ?? record['merchantId'])
            ?.toString()
            .trim();
    if (directFromRecord != null && directFromRecord.isNotEmpty) {
      return directFromRecord;
    }

    final fallback = (fallbackId ?? '').trim();
    return fallback.isEmpty ? null : fallback;
  }

  static List<Map<String, dynamic>> filterMerchantRecords({
    required String merchantId,
    required List<Map<String, dynamic>> records,
  }) {
    if (merchantId.trim().isEmpty) {
      return records;
    }

    return records.where((record) {
      final merchantField = record['merchant_id'] ?? record['merchantId'];
      final ownerField = record['owner_id'] ?? record['ownerId'];

      final value = (merchantField ?? ownerField)?.toString().trim();
      return value != null && value.isNotEmpty && value == merchantId;
    }).toList();
  }

  static List<Map<String, dynamic>> filterVisibleMerchantOrders(
    List<Map<String, dynamic>> orders,
  ) {
    return orders.where(OrderService.isVisibleToMerchant).toList();
  }

  static List<Map<String, dynamic>> filterOrdersForMerchant({
    required String merchantId,
    required List<Map<String, dynamic>> orders,
    Map<String, String> productOwners = const {},
    Set<String> merchantProductIds = const {},
  }) {
    final normalizedMerchantId = merchantId.trim();
    final visibleOrders = filterVisibleMerchantOrders(orders);
    if (normalizedMerchantId.isEmpty) return visibleOrders;

    final merchantOrders = <Map<String, dynamic>>[];
    for (final order in visibleOrders) {
      final rawItems = order['items'] ?? order['order_items'];
      if (rawItems is! List) {
        final orderMerchantId =
            (order['merchant_id'] ?? order['merchantId'] ?? '')
                .toString()
                .trim();
        final ownerId =
            (order['owner_id'] ?? order['ownerId'] ?? '').toString().trim();
        if (orderMerchantId == normalizedMerchantId ||
            ownerId == normalizedMerchantId) {
          merchantOrders.add(order);
        }
        continue;
      }

      final merchantItems = <Map<String, dynamic>>[];
      for (final rawItem in rawItems) {
        if (rawItem is! Map) continue;
        final item = Map<String, dynamic>.from(rawItem);
        if (isMerchantOrderItem(
          item: item,
          merchantId: normalizedMerchantId,
          productOwners: productOwners,
          merchantProductIds: merchantProductIds,
        )) {
          merchantItems.add(item);
        }
      }
      if (merchantItems.isNotEmpty) {
        merchantOrders.add({...order, 'merchant_items': merchantItems});
      }
    }
    return merchantOrders;
  }

  static List<Map<String, dynamic>> filterNewMerchantOrders(
    List<Map<String, dynamic>> orders,
  ) {
    return sortMerchantOrdersNewestFirst(
      orders.where((order) {
        return (order['status'] ?? '').toString().trim().toLowerCase() == 'new';
      }).toList(),
    );
  }

  static List<Map<String, dynamic>> filterProductsForMerchantPanel({
    required List<Map<String, dynamic>> records,
    required String query,
    required String availability,
  }) {
    final normalizedQuery = query.trim().toLowerCase();

    return records.where((record) {
      final productName = (record['name'] ?? '').toString().toLowerCase();
      final productCategory =
          (record['category'] ?? '').toString().toLowerCase();
      final matchesSearch = normalizedQuery.isEmpty ||
          productName.contains(normalizedQuery) ||
          productCategory.contains(normalizedQuery);

      final isAvailable = resolveMerchantProductAvailability(record);
      final matchesAvailability = switch (availability) {
        'available' => isAvailable,
        'unavailable' => !isAvailable,
        _ => true,
      };

      return matchesSearch && matchesAvailability;
    }).toList();
  }

  static List<Map<String, dynamic>> sortProductsForMerchantPanel({
    required List<Map<String, dynamic>> records,
    String sortBy = 'newest',
  }) {
    DateTime? productDate(Map<String, dynamic> product) {
      for (final key in [
        'submitted_at',
        'submittedAt',
        'created_at',
        'createdAt',
      ]) {
        final value = product[key];
        if (value is num) {
          return DateTime.fromMillisecondsSinceEpoch(value.toInt());
        }
        final text = value?.toString().trim() ?? '';
        if (text.isEmpty) continue;
        final parsed = DateTime.tryParse(text);
        if (parsed != null) return parsed;
        final timestamp = int.tryParse(text);
        if (timestamp != null) {
          return DateTime.fromMillisecondsSinceEpoch(timestamp);
        }
      }
      return null;
    }

    final sorted = [...records];
    sorted.sort((a, b) {
      final nameA = (a['name'] ?? '').toString();
      final nameB = (b['name'] ?? '').toString();
      final categoryA = (a['category'] ?? '').toString();
      final categoryB = (b['category'] ?? '').toString();
      final priceA = (a['price'] is num
          ? (a['price'] as num).toDouble()
          : double.tryParse(a['price']?.toString() ?? '0') ?? 0);
      final priceB = (b['price'] is num
          ? (b['price'] as num).toDouble()
          : double.tryParse(b['price']?.toString() ?? '0') ?? 0);
      final stockA =
          int.tryParse((a['stock'] ?? a['inventory'] ?? '0').toString()) ?? 0;
      final stockB =
          int.tryParse((b['stock'] ?? b['inventory'] ?? '0').toString()) ?? 0;
      final createdAtA = productDate(a);
      final createdAtB = productDate(b);

      switch (sortBy) {
        case 'newest':
        case 'oldest':
          var dateCompare = 0;
          if (createdAtA == null || createdAtB == null) {
            if (createdAtA == null && createdAtB != null) {
              dateCompare = 1;
            } else if (createdAtA != null && createdAtB == null) {
              dateCompare = -1;
            }
          } else {
            dateCompare = sortBy == 'newest'
                ? createdAtB.compareTo(createdAtA)
                : createdAtA.compareTo(createdAtB);
          }
          if (dateCompare != 0) return dateCompare;
          final nameCompare =
              nameA.toLowerCase().compareTo(nameB.toLowerCase());
          return nameCompare != 0
              ? nameCompare
              : (a['id'] ?? '').toString().compareTo(
                    (b['id'] ?? '').toString(),
                  );
        case 'category':
          final compare =
              categoryA.toLowerCase().compareTo(categoryB.toLowerCase());
          return compare != 0
              ? compare
              : nameA.toLowerCase().compareTo(nameB.toLowerCase());
        case 'price_asc':
          return priceA.compareTo(priceB);
        case 'price_desc':
          return priceB.compareTo(priceA);
        case 'stock_asc':
          return stockA.compareTo(stockB);
        case 'stock_desc':
          return stockB.compareTo(stockA);
        case 'name_desc':
          return nameB.toLowerCase().compareTo(nameA.toLowerCase());
        case 'name':
        default:
          return nameA.toLowerCase().compareTo(nameB.toLowerCase());
      }
    });

    return sorted;
  }

  static MerchantDashboardData buildDashboardData({
    UserModel? sessionProfile,
    required List<Map<String, dynamic>> orders,
    Map<String, dynamic>? merchantProfile,
    List<CurrencyOption> currencies = const [],
    Map<String, String> productOwners = const {},
    Set<String> merchantProductIds = const {},
  }) {
    final resolvedMerchantId = resolveMerchantId(
      sessionProfile,
      record: merchantProfile,
    );
    final scopedOrders = resolvedMerchantId == null
        ? filterVisibleMerchantOrders(orders)
        : filterOrdersForMerchant(
            merchantId: resolvedMerchantId,
            orders: orders,
            productOwners: productOwners,
            merchantProductIds: merchantProductIds,
          );

    final effectiveMerchantProfile = sessionProfile == null
        ? merchantProfile
        : {
            'id': sessionProfile.id,
            'full_name': sessionProfile.fullName,
            'phone': sessionProfile.phone,
            'shop_name': sessionProfile.shopName,
            'shop_category': sessionProfile.shopCategory,
            'shop_location': sessionProfile.shopLocation,
            'address': sessionProfile.address,
            'shop_banner': sessionProfile.shopBannerUrl,
          };

    return MerchantDashboardData.buildFromProfile(
      sessionProfile: sessionProfile,
      orders: scopedOrders,
      merchantProfile: effectiveMerchantProfile,
      currencies: currencies,
      productOwners: productOwners,
      merchantProductIds: merchantProductIds,
    );
  }

  @override
  State<MerchantManagementScreen> createState() =>
      _MerchantManagementScreenState();
}

class _MerchantManagementScreenState extends State<MerchantManagementScreen>
    with WidgetsBindingObserver {
  late Future<MerchantDashboardData> _dashboardFuture;
  MerchantDashboardData? _dashboardData;
  final PageController _pageController = PageController();
  Timer? _dashboardRefreshTimer;
  int _currentIndex = 0;
  bool _isRefreshingDashboard = false;
  bool _isOpeningDrawerPage = false;
  bool _isSigningOut = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshDashboard();
    _dashboardRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (_currentIndex == 0 &&
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed) {
          unawaited(_refreshDashboardInBackground());
        }
      },
    );
  }

  void _refreshDashboard() {
    final cachedData = _lastMerchantDashboardData;
    final refreshFuture = _loadDashboard().timeout(
      const Duration(seconds: 8),
    );

    _dashboardFuture = cachedData == null
        ? refreshFuture.then((data) {
            _lastMerchantDashboardData = data;
            _dashboardData = data;
            return data;
          })
        : Future.value(cachedData).then((data) async {
            final refreshed = await refreshFuture;
            _lastMerchantDashboardData = refreshed;
            _dashboardData = refreshed;
            return refreshed;
          });
  }

  Future<void> _refreshDashboardInBackground({bool showError = false}) async {
    if (_isRefreshingDashboard) return;
    _isRefreshingDashboard = true;

    try {
      final refreshed =
          await _loadDashboard().timeout(const Duration(seconds: 8));
      if (!mounted) return;
      _lastMerchantDashboardData = refreshed;
      setState(() {
        _dashboardData = refreshed;
        _dashboardFuture = Future.value(refreshed);
      });
    } catch (error, stackTrace) {
      debugPrint('Failed to refresh merchant dashboard: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (showError && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر تحديث الطلبات الجديدة. حاول مرة أخرى لاحقاً'),
          ),
        );
      }
    } finally {
      _isRefreshingDashboard = false;
    }
  }

  void _selectTab(int index) {
    if (index == _currentIndex) {
      if (index == 0) unawaited(_refreshDashboardInBackground());
      return;
    }
    setState(() => _currentIndex = index);
    if (index == 0) unawaited(_refreshDashboardInBackground());
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOutCubic,
    );
  }

  Future<MerchantDashboardData> _loadDashboard() async {
    final authService = AuthService();
    final sessionUser = await authService.loadSession();
    final currentProfile = sessionUser ?? await authService.getCurrentProfile();

    final ordersFuture = AdminService().getOrdersForAdmin(
      limit: null,
      propagateErrors: true,
    );
    final merchantProfileFuture = currentProfile != null
        ? Future.value(<Map<String, dynamic>>[
            {
              'id': currentProfile.id,
              'full_name': currentProfile.fullName,
              'phone': currentProfile.phone,
              'shop_name': currentProfile.shopName,
              'shop_category': currentProfile.shopCategory,
              'shop_location': currentProfile.shopLocation,
              'address': currentProfile.address,
              'shop_banner': currentProfile.shopBannerUrl,
              'latitude': null,
              'longitude': null,
            }
          ])
        : AdminService().getProfilesForAdmin(
            role: 'merchant',
            limit: 1,
          );

    final productSnapshot =
        await FirebaseDatabaseService.instance.read('products');
    final productOwners = OrderService.productOwnersById(productSnapshot);
    final productList = productSnapshot.values
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final scopedProducts = currentProfile == null
        ? productList
        : MerchantManagementScreen.filterMerchantRecords(
            merchantId: currentProfile.id,
            records: productList,
          );

    final results = await Future.wait([ordersFuture, merchantProfileFuture]);
    final currencies = await CurrencyService().getCurrencies();
    final orders = (results[0] as List)
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    final profileList = (results[1] as List)
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    final merchant = profileList.isNotEmpty ? profileList.first : null;

    final dashboard = MerchantManagementScreen.buildDashboardData(
      sessionProfile: currentProfile,
      orders: orders,
      merchantProfile: merchant,
      currencies: currencies,
      productOwners: productOwners,
      merchantProductIds: scopedProducts
          .expand((product) {
            final id = (product['id'] ?? '').toString().trim();
            return id.isEmpty ? const <String>[] : <String>[id];
          })
          .toSet()
          .union(
            productOwners.entries
                .where((entry) => entry.value == currentProfile?.id)
                .map((entry) => entry.key)
                .toSet(),
          )
          .toSet(),
    );
    final dashboardData = dashboard.copyWith(
      productCount: scopedProducts.length,
      currencySymbol: CurrencyService.yerCurrency.symbol,
    );
    if (currentProfile == null) return dashboardData;

    return dashboardData.copyWith(
      recentOrders: dashboardData.recentOrders.map((order) {
        return {
          ...order,
          'merchant_product_images': merchantOrderProductImages(
            order: order,
            merchantId: currentProfile.id,
            productsSnapshot: productSnapshot,
          ),
        };
      }).toList(),
    );
  }

  Future<void> _openDrawerPage(Widget page) async {
    if (_isOpeningDrawerPage) return;
    setState(() => _isOpeningDrawerPage = true);
    Navigator.pop(context);

    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (_) => page),
      );
    } finally {
      if (mounted) {
        setState(() => _isOpeningDrawerPage = false);
      }
    }
  }

  Future<void> _signOut() async {
    if (_isSigningOut) return;
    setState(() => _isSigningOut = true);

    try {
      final shouldSignOut = await showLogoutConfirmationDialog(context);
      if (!shouldSignOut || !mounted) return;

      final navigator = Navigator.of(context);
      await AuthService().clearSession();
      if (!mounted) return;
      navigator.pushAndRemoveUntil(
        slideFadeRoute(page: const PhoneLoginScreen()),
        (route) => false,
      );
    } finally {
      if (mounted) {
        setState(() => _isSigningOut = false);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _currentIndex == 0) {
      unawaited(_refreshDashboardInBackground());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dashboardRefreshTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MerchantDashboardData>(
      future: _dashboardFuture,
      builder: (context, snapshot) {
        final data = snapshot.data ?? _dashboardData;
        if (data == null &&
            snapshot.connectionState == ConnectionState.waiting) {
          return const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              backgroundColor: Color(0xFFF5F7FB),
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snapshot.hasError || data == null) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              backgroundColor: const Color(0xFFF5F7FB),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_rounded, size: 48),
                      const SizedBox(height: 12),
                      const Text('تعذر تحميل بيانات المتجر الحالية'),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => setState(_refreshDashboard),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        final tabs = [
          _MerchantOverviewTab(
            data: data,
            onOpenProducts: () => _selectTab(2),
            onOpenOrders: () => _selectTab(1),
            onRefresh: () => _refreshDashboardInBackground(showError: true),
          ),
          MerchantOrderManagementScreen(currencySymbol: data.currencySymbol),
          MerchantProductManagementScreen(
            currencySymbol: data.currencySymbol,
          ),
          _MerchantMoreTab(
            data: data,
            onOpenProducts: () => _selectTab(2),
          ),
        ];

        void navigateToTab(int index) {
          Navigator.pop(context);
          _selectTab(index);
        }

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;

            final navigator = Navigator.of(context);
            if (navigator.canPop()) {
              navigator.pop();
              return;
            }

            if (_currentIndex != 0) {
              setState(() => _currentIndex = 0);
              return;
            }

            showDialog(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('الخروج من التطبيق'),
                content:
                    const Text('هل أنت متأكد من رغبتك في الخروج من التطبيق؟'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('إلغاء'),
                  ),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      SystemNavigator.pop();
                    },
                    child: const Text('خروج'),
                  ),
                ],
              ),
            );
          },
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              backgroundColor: const Color(0xFFF5F7FB),
              appBar: _currentIndex == 0
                  ? AppBar(
                      toolbarHeight: 72,
                      backgroundColor: const Color(0xFF111827),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      scrolledUnderElevation: 0,
                      titleSpacing: 4,
                      centerTitle: false,
                      title: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD4AF37),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(9),
                              child: Image.asset(
                                'assets/icon/app_icon.png',
                                width: 38,
                                height: 38,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'لوحة التاجر',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  data.merchantName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFFD1D5DB),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      actions: const [
                        AccountSwitcherButton(),
                        NotificationBell(compactBadge: true),
                        SizedBox(width: 4),
                      ],
                      bottom: PreferredSize(
                        preferredSize: const Size.fromHeight(2),
                        child: Container(
                          height: 2,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Color(0xFFD4AF37),
                                Color(0xFF6B5A24),
                                Color(0xFF111827),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                  : null,
              drawer: Drawer(
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.white,
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    DrawerHeader(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          bottom: BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.asset(
                                  'assets/icon/app_icon.png',
                                  width: 42,
                                  height: 42,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'She M',
                                style: TextStyle(
                                  color: Color(0xFF111827),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            data.merchantName,
                            style: const TextStyle(
                              color: Color(0xFF111827),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            data.merchantCategory,
                            style: const TextStyle(
                              color: Color(0xFF9A7B1F),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(
                        'إدارة المتجر',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.home_rounded),
                      title: const Text('الرئيسية'),
                      onTap: () => navigateToTab(0),
                    ),
                    ListTile(
                      leading: const Icon(Icons.receipt_long_rounded),
                      title: const Text('الطلبات'),
                      onTap: () => navigateToTab(1),
                    ),
                    ListTile(
                      leading: const Icon(Icons.inventory_2_rounded),
                      title: const Text('المنتجات'),
                      onTap: () => navigateToTab(2),
                    ),
                    ListTile(
                      leading: const Icon(Icons.campaign_rounded),
                      title: const Text('العروض والإعلانات'),
                      onTap: () => _openDrawerPage(
                        const PromotionManagementScreen(),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.widgets_rounded),
                      title: const Text('المخزون'),
                      onTap: () => _openDrawerPage(
                        const MerchantInventoryScreen(),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.bar_chart_rounded),
                      title: const Text('التقارير'),
                      onTap: () => _openDrawerPage(
                        MerchantReportsScreen(
                          currencySymbol: data.currencySymbol,
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.account_balance_wallet_rounded),
                      title: const Text('محفظة التاجر'),
                      subtitle: const Text('المبيعات المستحقة والسحب'),
                      onTap: () => _openDrawerPage(
                        const MerchantWalletScreen(),
                      ),
                    ),
                    const Divider(),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(
                        'الحساب',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.person_rounded),
                      title: const Text('الملف الشخصي'),
                      onTap: () => _openDrawerPage(
                        const MerchantProfileScreen(),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.support_agent_rounded),
                      title: const Text('مركز مساعدة التاجر'),
                      onTap: () => _openDrawerPage(
                        const SupportCenterScreen(),
                      ),
                    ),
                    const Divider(),
                    ListTile(
                      leading:
                          const Icon(Icons.logout_rounded, color: Colors.red),
                      title: const Text(
                        'تسجيل الخروج',
                        style: TextStyle(color: Colors.red),
                      ),
                      onTap: _signOut,
                    ),
                    const Divider(height: 28),
                    const AppVersionListTile(),
                  ],
                ),
              ),
              body: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  if (_currentIndex != index) {
                    setState(() => _currentIndex = index);
                  }
                },
                children: [
                  for (final tab in tabs) _KeepAliveMerchantTab(child: tab),
                ],
              ),
              bottomNavigationBar: BottomNavigationBar(
                currentIndex: _currentIndex,
                type: BottomNavigationBarType.fixed,
                selectedItemColor: const Color(0xFF111827),
                unselectedItemColor: const Color(0xFF6B7280),
                backgroundColor: Colors.white,
                onTap: _selectTab,
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.home_rounded),
                    label: 'الرئيسية',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.assignment_rounded),
                    label: 'الطلبات',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.inventory_2_rounded),
                    label: 'المنتجات',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.more_horiz_rounded),
                    label: 'المزيد',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _KeepAliveMerchantTab extends StatefulWidget {
  const _KeepAliveMerchantTab({required this.child});

  final Widget child;

  @override
  State<_KeepAliveMerchantTab> createState() => _KeepAliveMerchantTabState();
}

class _KeepAliveMerchantTabState extends State<_KeepAliveMerchantTab>
    with AutomaticKeepAliveClientMixin<_KeepAliveMerchantTab> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _MerchantOverviewTab extends StatelessWidget {
  final MerchantDashboardData data;
  final Future<void> Function() onRefresh;
  final VoidCallback? onOpenProducts;
  final VoidCallback onOpenOrders;

  const _MerchantOverviewTab({
    required this.data,
    required this.onRefresh,
    required this.onOpenOrders,
    this.onOpenProducts,
  });

  @override
  Widget build(BuildContext context) {
    ImageProvider<Object>? bannerImageProvider;
    if (data.bannerUrl != null && data.bannerUrl!.isNotEmpty) {
      if (MediaUploadService.isDataUri(data.bannerUrl!)) {
        bannerImageProvider = MemoryImage(
          MediaUploadService.decodeDataUriToBytes(data.bannerUrl!) ??
              Uint8List(0),
        );
      } else {
        bannerImageProvider = CachedNetworkImageProvider(data.bannerUrl!);
      }
    }

    final newOrders =
        MerchantManagementScreen.filterNewMerchantOrders(data.recentOrders);
    final recentOrders = data.recentOrders.isEmpty
        ? const <_OrderRow>[]
        : data.recentOrders.take(5).map((order) {
            final orderId = OrderNumber.fromOrder(order);
            final customerName = merchantOrderItemsSummary(order);
            final totalText = _merchantOrderTotalLabel(order);
            final status = (order['status'] ?? 'pending_payment').toString();
            final statusLabel = DeliveryService.statusLabel(status);
            final color = switch (status) {
              'preparing' => const Color(0xFF3B82F6),
              'shipped' => const Color(0xFF10B981),
              'delivered' => const Color(0xFF8B5CF6),
              _ => const Color(0xFFF59E0B),
            };

            return _OrderRow(
              orderId: orderId,
              customer: customerName,
              total: totalText,
              status: statusLabel,
              statusColor: color,
              productImages: _merchantOrderImageUrls(order),
              onTap: () => _openOrder(context, order),
            );
          }).toList();

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: SafeArea(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF111827), Color(0xFF1F2937)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(22),
                image: bannerImageProvider != null
                    ? DecorationImage(
                        image: bannerImageProvider,
                        fit: BoxFit.cover,
                        opacity: 0.28,
                      )
                    : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'مرحبا بعودتك',
                          style: TextStyle(
                            color: Color(0xFFE5E7EB),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          data.merchantName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          data.merchantCategory,
                          style: const TextStyle(
                            color: Color(0xFFD4AF37),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          data.merchantPhone,
                          style: const TextStyle(
                            color: Color(0xFFE5E7EB),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4AF37).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      color: Color(0xFFD4AF37),
                      size: 28,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFFBEB), Color(0xFFFFFDF7)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFDE68A)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFB45309).withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFF111827),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.notifications_active_rounded,
                          color: Color(0xFFFBBF24),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 11),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'طلبات جديدة',
                              style: TextStyle(
                                color: Color(0xFF111827),
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'تابع طلبات متجرك فور وصولها',
                              style: TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFB45309),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${newOrders.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (newOrders.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            color: Color(0xFF15803D),
                            size: 19,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'لا توجد طلبات جديدة حالياً',
                              style: TextStyle(
                                color: Color(0xFF374151),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    for (final order in newOrders.take(3))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: _IncomingMerchantOrderCard(
                          order: order,
                          onTap: () => _openOrder(context, order),
                        ),
                      ),
                    if (newOrders.length > 3)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: onOpenOrders,
                          icon: const Icon(Icons.arrow_back_rounded, size: 17),
                          label: Text(
                            'عرض المزيد (${newOrders.length - 3})',
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'الطلبات الأخيرة',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: onOpenOrders,
                  child: const Text(
                    'عرض الكل',
                    style: TextStyle(
                      color: Color(0xFF3B82F6),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (recentOrders.isEmpty)
              const _EmptyState(message: 'لا توجد طلبات حديثة لعرضها')
            else
              ...recentOrders,
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _openOrder(
    BuildContext context,
    Map<String, dynamic> order,
  ) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MerchantOrderDetailScreen(
          order: Map<String, dynamic>.from(order),
          currencySymbol: data.currencySymbol,
        ),
      ),
    );
    if (!context.mounted) return;
    await onRefresh();
  }
}

class _MerchantOrdersTab extends StatelessWidget {
  final MerchantDashboardData data;

  const _MerchantOrdersTab({required this.data});

  @override
  Widget build(BuildContext context) {
    final rows = data.recentOrders.isEmpty
        ? const <_OrderRow>[]
        : data.recentOrders.take(8).map((order) {
            final orderId = OrderNumber.fromOrder(order);
            final customerName = order['customer_id']?.toString() ?? 'عميل';
            final totalText = _merchantOrderTotalLabel(order);
            final status = (order['status'] ?? 'pending_payment').toString();
            final color = switch (status) {
              'preparing' => const Color(0xFF3B82F6),
              'shipped' => const Color(0xFF10B981),
              'delivered' => const Color(0xFF8B5CF6),
              _ => const Color(0xFFF59E0B),
            };

            return _OrderRow(
              orderId: orderId,
              customer: customerName,
              total: totalText,
              status: DeliveryService.statusLabel(status),
              statusColor: color,
              productImages: _merchantOrderImageUrls(order),
            );
          }).toList();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            'إدارة الطلبات',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.4,
            children: [
              _MetricCard(
                label: 'الطلبات الجديدة',
                value: data.pendingOrders.toString(),
                color: const Color(0xFFF59E0B),
                icon: Icons.new_releases_rounded,
              ),
              _MetricCard(
                label: 'قيد التنفيذ',
                value: data.activeOrders.toString(),
                color: const Color(0xFF3B82F6),
                icon: Icons.local_shipping_rounded,
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (rows.isEmpty)
            const _EmptyState(message: 'لا توجد طلبات حتى الآن')
          else
            ...rows,
        ],
      ),
    );
  }
}

class _MerchantProductsTab extends StatelessWidget {
  final MerchantDashboardData data;

  const _MerchantProductsTab({required this.data});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadMerchantProducts(),
      builder: (context, snapshot) {
        final products = snapshot.data ?? const <Map<String, dynamic>>[];
        final list = products.isEmpty
            ? const <_ProductCard>[]
            : products.map((product) {
                final name = (product['name'] ?? 'منتج').toString();
                final price = product['price'];
                final productCurrency = resolveProductCurrencyLabel(product);
                final formattedPrice = price is num
                    ? '${price.toStringAsFixed(0)} $productCurrency'
                    : '0 $productCurrency';
                final available = resolveMerchantProductAvailability(product);
                return _ProductCard(
                  label: name,
                  price: formattedPrice,
                  stock: ((product['stock'] ?? product['inventory'] ?? '0')
                      .toString()),
                  active: available,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MerchantProductManagementScreen(
                          preselectedProduct: product,
                          currencySymbol: data.currencySymbol,
                        ),
                      ),
                    );
                  },
                );
              }).toList();

        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Text(
                'المنتجات',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.3,
                children: [
                  _MetricCard(
                    label: 'إجمالي المنتجات',
                    value: products.length.toString(),
                    color: const Color(0xFF10B981),
                    icon: Icons.inventory_2_rounded,
                  ),
                  _MetricCard(
                    label: 'الطلبات اليوم',
                    value: data.totalOrders.toString(),
                    color: const Color(0xFF3B82F6),
                    icon: Icons.trending_up_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.add_circle_rounded,
                        color: Color(0xFF15803D)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'إدارة المنتجات داخل هذه الشاشة',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF166534),
                            ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MerchantProductManagementScreen(
                              currencySymbol: data.currencySymbol,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('إضافة منتج'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (list.isEmpty)
                const _EmptyState(message: 'لا توجد منتجات مسجلة في المتجر')
              else
                ...list,
            ],
          ),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _loadMerchantProducts() async {
    try {
      final auth = AuthService();
      final profile =
          await auth.loadSession() ?? await auth.getCurrentProfile();
      if (profile == null) return const <Map<String, dynamic>>[];

      final snapshot = await FirebaseDatabaseService.instance.read('products');
      final products = snapshot.values
          .whereType<Map>()
          .where((item) => item['is_archived'] != true)
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      return MerchantManagementScreen.filterMerchantRecords(
        merchantId: profile.id,
        records: products,
      );
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }
}

class _MerchantMoreTab extends StatelessWidget {
  final MerchantDashboardData data;
  final VoidCallback? onOpenProducts;

  const _MerchantMoreTab({required this.data, this.onOpenProducts});

  @override
  Widget build(BuildContext context) {
    final actions = [
      _MoreActionCard(
        icon: Icons.person_rounded,
        title: 'ملف المتجر',
        subtitle: 'بيانات المتجر والهوية',
        color: const Color(0xFF0EA5E9),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MerchantProfileScreen()),
          );
        },
      ),
      _MoreActionCard(
        icon: Icons.assignment_rounded,
        title: 'الطلبات',
        subtitle: 'متابعة الطلبات الحالية',
        color: const Color(0xFF3B82F6),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MerchantOrderManagementScreen(
                currencySymbol: data.currencySymbol,
              ),
            ),
          );
        },
      ),
      _MoreActionCard(
        icon: Icons.inventory_2_rounded,
        title: 'المنتجات',
        subtitle: 'إدارة المنتجات والكميات',
        color: const Color(0xFF10B981),
        onTap: onOpenProducts ??
            () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('إدارة المنتجات غير متاحة هنا')),
                ),
      ),
      _MoreActionCard(
        icon: Icons.widgets_rounded,
        title: 'المخزون',
        subtitle: 'مراجعة مستويات المخزون',
        color: const Color(0xFF8B5CF6),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MerchantInventoryScreen()),
          );
        },
      ),
      _MoreActionCard(
        icon: Icons.bar_chart_rounded,
        title: 'التقارير',
        subtitle: 'إحصائيات الإيرادات والأداء',
        color: const Color(0xFFF59E0B),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MerchantReportsScreen(
                currencySymbol: data.currencySymbol,
              ),
            ),
          );
        },
      ),
      _MoreActionCard(
        icon: Icons.account_balance_wallet_rounded,
        title: 'المحفظة',
        subtitle: 'المبيعات المستحقة والسحب',
        color: const Color(0xFFEC4899),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MerchantWalletScreen()),
          );
        },
      ),
    ];

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'المزيد',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      data.merchantName,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${data.totalOrders} طلب',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF111827), Color(0xFF1F2937)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.storefront_rounded,
                    color: Color(0xFFD4AF37),
                    size: 30,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              data.merchantName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF22C55E)
                                  .withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'نشط',
                              style: TextStyle(
                                color: Color(0xFF86EFAC),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        data.merchantCategory,
                        style: const TextStyle(
                          color: Color(0xFFE5E7EB),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: actions.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.18,
            ),
            itemBuilder: (context, index) => actions[index],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ملخص المتجر',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _SummaryRow(
                  label: 'إيراد اليوم',
                  value: '${data.totalRevenue.round()} ${data.currencySymbol}',
                ),
                if (data.unconvertedOrderCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'تعذّر تحويل ${data.unconvertedOrderCount} طلب بسبب أسعار صرف ناقصة أو تعدد العملات في طلب قديم.',
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                _SummaryRow(
                  label: 'طلبات قيد التنفيذ',
                  value: '${data.activeOrders}',
                ),
                _SummaryRow(
                  label: 'طلبات معلقة',
                  value: '${data.pendingOrders}',
                ),
                _SummaryRow(
                  label: 'المنتجات',
                  value: '${data.productCount}',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _MoreActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }
}

class MerchantProfileScreen extends StatefulWidget {
  const MerchantProfileScreen({super.key});

  @override
  State<MerchantProfileScreen> createState() => _MerchantProfileScreenState();
}

class _MerchantProfileScreenState extends State<MerchantProfileScreen> {
  UserModel? _profile;
  bool _loading = true;
  bool _savingBanner = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _pickAndSaveBanner() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final compressed = await MediaUploadService.compactImageBytes(bytes);
    if (compressed == null) {
      if (!mounted) return;
      messenger?.showSnackBar(
        const SnackBar(content: Text('تعذر ضغط الصورة. حاول صورة أخرى')),
      );
      return;
    }

    final bannerUrl = await MediaUploadService.uploadImage(
      compressed,
      fileName: picked.name,
      mediaType: 'profiles',
    );

    final auth = AuthService();
    final profile =
        _profile ?? await auth.loadSession() ?? await auth.getCurrentProfile();
    if (profile == null) return;

    if (!mounted) return;
    setState(() => _savingBanner = true);

    if (bannerUrl == null) {
      if (!mounted) return;
      setState(() => _savingBanner = false);
      messenger?.showSnackBar(
        const SnackBar(content: Text('تعذر رفع صورة الغلاف إلى خادم الصور')),
      );
      return;
    }

    final updated = profile.copyWith(shopBannerUrl: bannerUrl);
    await auth.saveSession(updated);
    await FirebaseDatabaseService.instance.update(
      'profiles/${updated.id}',
      {'shop_banner': updated.shopBannerUrl},
    );

    if (!mounted) return;
    setState(() {
      _profile = updated;
      _savingBanner = false;
    });
    messenger?.showSnackBar(
      const SnackBar(content: Text('تم تحديث صورة غلاف المتجر')),
    );
  }

  Future<void> _loadProfile() async {
    final auth = AuthService();
    final profile = await auth.loadSession() ?? await auth.getCurrentProfile();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final profile = _profile;
    if (profile == null) {
      return const Scaffold(
        body: Center(child: Text('لم يتم العثور على بيانات المتجر')),
      );
    }

    final bannerUrl = profile.shopBannerUrl?.trim();
    final shopName = profile.shopName?.trim().isNotEmpty == true
        ? profile.shopName!
        : profile.fullName;
    final city = profile.shopLocation?.trim().isNotEmpty == true
        ? profile.shopLocation!
        : profile.address ?? 'مدينة غير محددة';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Stack(
              children: [
                Container(
                  height: 260,
                  clipBehavior: Clip.hardEdge,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF111827), Color(0xFF3B82F6)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: bannerUrl != null && bannerUrl.isNotEmpty
                      ? (MediaUploadService.isDataUri(bannerUrl)
                          ? Image.memory(
                              MediaUploadService.decodeDataUriToBytes(
                                      bannerUrl) ??
                                  Uint8List(0),
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              errorBuilder: (_, __, ___) => const SizedBox(),
                            )
                          : Image(
                              image: CachedNetworkImageProvider(bannerUrl),
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              errorBuilder: (_, __, ___) => const SizedBox(),
                            ))
                      : null,
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.20),
                          Colors.black.withValues(alpha: 0.55),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _savingBanner ? null : _pickAndSaveBanner,
                        icon: _savingBanner
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.edit_rounded,
                                color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 20,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.storefront_rounded,
                            size: 32,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                shopName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 22,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                profile.shopCategory ?? 'متجر إلكتروني',
                                style: const TextStyle(
                                  color: Color(0xFFE5E7EB),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.location_on_rounded,
                                      color: Color(0xFFDBEAFE), size: 14),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      city,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFFE5E7EB),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'معلومات المتجر',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                  const SizedBox(height: 12),
                  _ProfileInfoCard(
                    title: 'اسم المتجر',
                    value: shopName,
                    icon: Icons.storefront_rounded,
                  ),
                  _ProfileInfoCard(
                    title: 'المالك',
                    value: profile.fullName,
                    icon: Icons.person_rounded,
                  ),
                  _ProfileInfoCard(
                    title: 'رقم الهاتف',
                    value: profile.phone,
                    icon: Icons.phone_rounded,
                  ),
                  _ProfileInfoCard(
                    title: 'أرقام التواصل',
                    value: profile.shopContactPhones.isEmpty
                        ? 'لم يتم إدخال أرقام تواصل'
                        : profile.shopContactPhones.join('، '),
                    icon: Icons.contact_phone_rounded,
                  ),
                  _ProfileInfoCard(
                    title: 'الفئة',
                    value: profile.shopCategory ?? 'غير محدد',
                    icon: Icons.category_rounded,
                  ),
                  _ProfileInfoCard(
                    title: 'العنوان',
                    value: profile.address ??
                        profile.shopLocation ??
                        'لم يتم إدخال عنوان',
                    icon: Icons.location_on_rounded,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MerchantStoreSettingsScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.settings_rounded),
                      label: const Text('تعديل بيانات المتجر'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileInfoCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _ProfileInfoCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF3B82F6)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MerchantProductManagementScreen extends StatefulWidget {
  final Map<String, dynamic>? preselectedProduct;
  final String currencySymbol;
  final bool openPreselectedProductForEdit;
  final String? ownerMerchantId;
  final String? ownerMerchantName;
  final bool adminManaged;
  final bool startWithAddProduct;

  const MerchantProductManagementScreen({
    super.key,
    this.preselectedProduct,
    this.currencySymbol = 'ر.س',
    this.openPreselectedProductForEdit = false,
    this.ownerMerchantId,
    this.ownerMerchantName,
    this.adminManaged = false,
    this.startWithAddProduct = false,
  });

  @override
  State<MerchantProductManagementScreen> createState() =>
      _MerchantProductManagementScreenState();
}

class _MerchantProductManagementScreenState
    extends State<MerchantProductManagementScreen>
    with SingleTickerProviderStateMixin {
  static const int _pageSize = 8;

  final ScrollController _scrollController = ScrollController();
  final Set<String> _processingProductIds = <String>{};
  late final AnimationController _refreshAnimationController;
  late Future<List<Map<String, dynamic>>> _productsFuture;
  int _visibleCount = _pageSize;
  String _searchQuery = '';
  String _availabilityFilter = 'all';
  String _sortBy = 'newest';
  bool _isProductDialogOpen = false;
  bool _isRefreshingProducts = false;

  @override
  void initState() {
    super.initState();
    _refreshAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scrollController.addListener(_handleScroll);
    _refreshProducts();
    if (widget.openPreselectedProductForEdit &&
        widget.preselectedProduct != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showAddOrEditDialog(
            widget.preselectedProduct,
            false,
          );
        }
      });
    } else if (widget.startWithAddProduct) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showAddOrEditDialog();
      });
    }
  }

  void _refreshProducts() {
    if (_isRefreshingProducts) return;
    _isRefreshingProducts = true;
    _refreshAnimationController.repeat();
    final cachedProducts = _lastMerchantProductsCache;
    final refreshFuture = _loadProducts();

    if (cachedProducts.isEmpty) {
      _productsFuture = refreshFuture.then((data) {
        _lastMerchantProductsCache = data;
        return data;
      });
    } else {
      _productsFuture = Future.value(cachedProducts).then((data) async {
        final refreshed = await refreshFuture;
        _lastMerchantProductsCache = refreshed;
        return refreshed;
      });
    }
    _productsFuture = _productsFuture.whenComplete(() {
      if (mounted) {
        setState(() {
          _isRefreshingProducts = false;
          _refreshAnimationController
            ..stop()
            ..value = 0;
        });
      }
    });
    if (mounted) setState(() {});
  }

  void _upsertProductInCache(Map<String, dynamic> payload) {
    final productId = (payload['id'] ?? '').toString();
    if (productId.isEmpty) {
      return;
    }

    final updated = List<Map<String, dynamic>>.from(_lastMerchantProductsCache);
    final index = updated.indexWhere(
      (item) => (item['id'] ?? '').toString() == productId,
    );

    final normalized = Map<String, dynamic>.from(payload);
    if (index >= 0) {
      updated[index] = normalized;
    } else {
      updated.insert(0, normalized);
    }

    _lastMerchantProductsCache = updated;
  }

  void _removeProductFromCache(String productId) {
    if (productId.isEmpty) {
      return;
    }

    _lastMerchantProductsCache = _lastMerchantProductsCache
        .where((item) => (item['id'] ?? '').toString() != productId)
        .toList();
  }

  List<Map<String, dynamic>> _applyProductFiltersAndSort(
    List<Map<String, dynamic>> records,
  ) {
    final normalizedQuery = _searchQuery.trim().toLowerCase();
    final filtered = MerchantManagementScreen.filterProductsForMerchantPanel(
      records: records,
      query: normalizedQuery,
      availability: _availabilityFilter,
    );

    return MerchantManagementScreen.sortProductsForMerchantPanel(
      records: filtered,
      sortBy: _sortBy,
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _refreshAnimationController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    if (position.extentAfter < 300) {
      setState(() {
        _visibleCount = _visibleCount + _pageSize;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _loadProducts() async {
    try {
      final auth = AuthService();
      final profile =
          await auth.loadSession() ?? await auth.getCurrentProfile();
      if (profile == null) return const <Map<String, dynamic>>[];

      final snapshot = await FirebaseDatabaseService.instance.read('products');
      final items = snapshot.values
          .whereType<Map>()
          .where((item) => item['is_archived'] != true)
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      return MerchantManagementScreen.filterMerchantRecords(
        merchantId: widget.ownerMerchantId ?? profile.id,
        records: items,
      );
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<void> _toggleAvailability(Map<String, dynamic> product) async {
    final id = (product['id'] ?? '').toString();
    if (id.isEmpty || !_processingProductIds.add(id)) return;
    setState(() {});
    final available = !resolveMerchantProductAvailability(product);
    final productName = (product['name'] ?? 'هذا المنتج').toString();

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(available ? 'نشر المنتج' : 'إخفاء المنتج'),
          content: Text(
            available
                ? 'هل تريد نشر «$productName» ليظهر للعملاء؟'
                : 'هل تريد إخفاء «$productName» عن العملاء؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(available ? 'نشر' : 'إخفاء'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;

      try {
        await FirebaseDatabaseService.instance.update(
          'products/$id',
          buildMerchantProductAvailabilityUpdates(
            product: product,
            available: available,
          ),
        );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تعذر تحديث حالة المنتج، حاول مرة أخرى'),
            ),
          );
        }
        return;
      }

      if (mounted) {
        _refreshProducts();
        try {
          await _productsFuture;
        } catch (_) {
          // The FutureBuilder displays refresh errors in the product list.
        }
      }
    } finally {
      _processingProductIds.remove(id);
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _deleteProduct(Map<String, dynamic> product) async {
    final id = (product['id'] ?? '').toString();
    if (id.isEmpty || !_processingProductIds.add(id)) return;
    setState(() {});

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('حذف المنتج'),
          content: Text(
            'هل أنت متأكد من حذف المنتج "${product['name'] ?? 'هذا المنتج'}"؟',
            style: const TextStyle(fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حذف'),
            ),
          ],
        ),
      );

      if (!mounted || confirmed != true) return;

      await FirebaseDatabaseService.instance.delete('products/$id');

      if (!mounted) return;

      setState(() {
        _removeProductFromCache(id);
        _visibleCount = _pageSize;
        _productsFuture = Future.value(_lastMerchantProductsCache);
      });

      _refreshProducts();
    } finally {
      _processingProductIds.remove(id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _showAddOrEditDialog([
    Map<String, dynamic>? product,
    bool requireConfirmation = true,
  ]) async {
    final productId = (product?['id'] ?? '').toString();
    if (_isProductDialogOpen ||
        (productId.isNotEmpty && !_processingProductIds.add(productId))) {
      return;
    }
    setState(() {
      _isProductDialogOpen = true;
    });
    try {
      if (product != null && requireConfirmation) {
        final productName = (product['name'] ?? 'هذا المنتج').toString();
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('تعديل المنتج'),
            content: Text(
              'هل تريد فتح نموذج تعديل «$productName»؟ '
              'لن تُحفظ التغييرات إلا بعد الضغط على زر الحفظ.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('متابعة التعديل'),
              ),
            ],
          ),
        );
        if (!mounted || confirmed != true) return;
      }
      await _showAddOrEditDialogForm(product);
    } finally {
      if (productId.isNotEmpty) {
        _processingProductIds.remove(productId);
      }
      if (mounted) {
        setState(() {
          _isProductDialogOpen = false;
        });
      }
    }
  }

  Future<void> _showAddOrEditDialogForm(
    Map<String, dynamic>? product,
  ) async {
    void moveCursorToEnd(TextEditingController controller) {
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
    }

    final workingProduct =
        Map<String, dynamic>.from(product ?? <String, dynamic>{});
    final formKey = GlobalKey<FormState>();
    final nameFieldKey = GlobalKey<FormFieldState<String>>();
    final categoryFieldKey = GlobalKey<FormFieldState<String>>();
    final priceFieldKey = GlobalKey<FormFieldState<String>>();
    final nameController =
        TextEditingController(text: workingProduct['name']?.toString() ?? '');
    final categoryController = TextEditingController(
      text: workingProduct['category']?.toString() ?? '',
    );
    final descriptionController = TextEditingController(
        text: workingProduct['description']?.toString() ?? '');
    final colorsValue =
        workingProduct['colors'] ?? workingProduct['available_colors'] ?? '';
    final selectedColors = <String>{
      ...parseProductColors(colorsValue is List
          ? colorsValue.map((item) => item.toString()).join(', ')
          : colorsValue.toString()),
    };
    final sizesValue =
        workingProduct['sizes'] ?? workingProduct['available_sizes'] ?? '';
    final selectedSizes = <String>{
      ...parseProductSizes(sizesValue is List
          ? sizesValue.map((item) => item.toString()).join(', ')
          : sizesValue.toString()),
    };
    final storedHasSizes =
        workingProduct['has_sizes'] ?? workingProduct['hasSizes'];
    var hasSizes = storedHasSizes == null ||
        storedHasSizes == true ||
        storedHasSizes.toString().trim().toLowerCase() == 'true' ||
        storedHasSizes.toString().trim() == '1';
    final priceController = TextEditingController(
      text: (workingProduct['price_change_status'] == 'pending'
                  ? workingProduct['requested_price']
                  : workingProduct['price'])
              ?.toString() ??
          '',
    );
    final stockController = TextEditingController(
      text: (workingProduct['stock'] ?? workingProduct['inventory'] ?? '')
          .toString(),
    );
    final savedCommissionValue = double.tryParse(
      workingProduct['commission_value_override']?.toString() ?? '',
    );
    final commissionController = TextEditingController(
      text: savedCommissionValue?.toString() ?? '',
    );
    var commissionEnabled = savedCommissionValue != null;
    var commissionMode = {'percent', 'fixed'}
            .contains(workingProduct['commission_mode_override'])
        ? workingProduct['commission_mode_override'].toString()
        : 'percent';
    late PricingConfig pricingConfig;
    final auth = AuthService();
    final loadingNavigator = Navigator.of(context, rootNavigator: true);
    var isLoadingDialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: Dialog.fullscreen(
          backgroundColor: const Color(0xFFF5F7FB),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    Text(
                      product == null
                          ? 'جاري تحميل نموذج إضافة المنتج...'
                          : 'جاري تحميل نموذج تعديل المنتج...',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'يرجى الانتظار',
                      style: TextStyle(color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    late UserModel? currentProfile;
    late List<CurrencyOption> currencies;
    late List<ProductCategory> categories;
    try {
      currentProfile =
          await auth.loadSession() ?? await auth.getCurrentProfile();
      currencies = await CurrencyService().getCurrencies();
      categories =
          await MerchantCategoryService().getActiveProductCategoryTree();
      pricingConfig = widget.adminManaged
          ? await PricingService().load()
          : const PricingConfig();
    } catch (error) {
      debugPrint('Failed to load merchant product form: $error');
      nameController.dispose();
      categoryController.dispose();
      descriptionController.dispose();
      priceController.dispose();
      stockController.dispose();
      commissionController.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر تحميل نموذج المنتج. حاول مرة أخرى.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    } finally {
      if (loadingNavigator.mounted &&
          isLoadingDialogOpen &&
          loadingNavigator.canPop()) {
        loadingNavigator.pop();
        isLoadingDialogOpen = false;
      }
    }
    final existingCurrencyCode = workingProduct['currency_code']?.toString() ??
        workingProduct['currencyCode']?.toString() ??
        '';
    var selectedCurrency = currencies.firstWhere(
      (currency) => currency.code == existingCurrencyCode,
      orElse: () => currencies.firstWhere(
        (currency) => currency.isDefault,
        orElse: () => currencies.first,
      ),
    );
    if (!mounted) {
      nameController.dispose();
      categoryController.dispose();
      descriptionController.dispose();
      priceController.dispose();
      stockController.dispose();
      commissionController.dispose();
      return;
    }

    final initialImageUris = mergeProductImageSourceUris(
      existing: resolveProductImageList(workingProduct),
      newlyPicked: resolveProductPrimaryImage(workingProduct).isEmpty
          ? const []
          : [resolveProductPrimaryImage(workingProduct)],
    );
    final selectedImages = <String>[...initialImageUris];
    final storedColorImages =
        workingProduct['color_image_urls'] ?? workingProduct['colorImageUrls'];
    final selectedColorImages = <String, String>{
      if (storedColorImages is Map)
        for (final entry in storedColorImages.entries)
          if (entry.key.toString().trim().isNotEmpty &&
              entry.value?.toString().trim().isNotEmpty == true)
            entry.key.toString().trim(): entry.value.toString().trim(),
    };
    final pendingImagePreviews = <String, Uint8List>{};
    final storedMainCategoryId =
        (workingProduct['main_category_id'] ?? '').toString();
    final storedSubcategoryId =
        (workingProduct['subcategory_id'] ?? '').toString();
    final storedCategoryName =
        (workingProduct['subcategory'] ?? workingProduct['category'] ?? '')
            .toString()
            .trim();
    var selectedMainCategoryId = categories.any(
      (category) => category.id == storedMainCategoryId,
    )
        ? storedMainCategoryId
        : '';
    var selectedSubcategoryId = '';
    if (selectedMainCategoryId.isNotEmpty) {
      final parent = categories.firstWhere(
        (category) => category.id == selectedMainCategoryId,
      );
      selectedSubcategoryId = parent.activeSubcategories.any(
        (subcategory) => subcategory.id == storedSubcategoryId,
      )
          ? storedSubcategoryId
          : '';
    }
    if (selectedSubcategoryId.isEmpty && storedCategoryName.isNotEmpty) {
      for (final parent in categories) {
        final matchingSubcategory = parent.activeSubcategories.where(
          (subcategory) => subcategory.name == storedCategoryName,
        );
        if (matchingSubcategory.isNotEmpty) {
          selectedMainCategoryId = parent.id;
          selectedSubcategoryId = matchingSubcategory.first.id;
          break;
        }
      }
      if (commissionController.text.isEmpty) {
        commissionController.text = (pricingConfig.commissionByMerchant[
                    widget.ownerMerchantId ?? currentProfile?.id ?? ''] ??
                pricingConfig.commissionByCategory[storedCategoryName] ??
                pricingConfig.commissionValue)
            .toString();
      }
      if (!{'percent', 'fixed'}.contains(commissionMode)) {
        commissionMode = pricingConfig.commissionMode;
      }
    }
    String selectedMainCategoryName() {
      for (final category in categories) {
        if (category.id == selectedMainCategoryId) return category.name;
      }
      return '';
    }

    String selectedSubcategoryName() {
      for (final category in categories) {
        if (category.id != selectedMainCategoryId) continue;
        for (final subcategory in category.activeSubcategories) {
          if (subcategory.id == selectedSubcategoryId) {
            return subcategory.name;
          }
        }
      }
      return '';
    }

    final selectedCategories = <String>{
      if (selectedSubcategoryName().isNotEmpty) selectedSubcategoryName(),
    };
    categoryController.text = selectedSubcategoryName();
    var coverIndex = selectedImages.isEmpty
        ? 0
        : normalizeCoverIndex(
            selectedImages.indexWhere(
                (image) => image == resolveProductPrimaryImage(workingProduct)),
            selectedImages.length,
          );
    final requestedAvailability =
        workingProduct['requested_available'] ?? workingProduct['available'];
    var isAvailable = product == null
        ? true
        : requestedAvailability == true || requestedAvailability == 'true';
    var videoDataUri =
        (workingProduct['video_url'] ?? workingProduct['videoUrl'] ?? '')
            .toString();
    var videoFileName = '';
    var videoUploadDetails = '';
    String? videoPreviewPath;
    Uint8List? videoPreviewBytes;
    var isUploadingImages = false;
    var isUploadingVideo = false;
    String? imageUploadError;
    String? videoUploadError;

    Future<void> showVideoPreview() async {
      await showDialog<void>(
        context: context,
        builder: (_) => _MerchantProductVideoPreviewDialog(
          filePath: videoPreviewPath,
          videoUrl: videoDataUri,
        ),
      );
    }

    Widget buildImagePreview(String image, {double size = 92}) {
      final pendingBytes = pendingImagePreviews[image];
      if (pendingBytes != null) {
        return Image.memory(
          pendingBytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
        );
      }

      if (MediaUploadService.isDataUri(image)) {
        final bytes = MediaUploadService.decodeDataUriToBytes(image);
        if (bytes == null || bytes.isEmpty) {
          return SizedBox(
            width: size,
            height: size,
            child: const Center(
              child: Icon(Icons.broken_image_rounded, color: Colors.grey),
            ),
          );
        }

        return Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => SizedBox(
            width: size,
            height: size,
            child: const Center(
              child: Icon(Icons.broken_image_rounded, color: Colors.grey),
            ),
          ),
        );
      }

      if (image.startsWith('http://') || image.startsWith('https://')) {
        return Image(
          image: CachedNetworkImageProvider(image),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => SizedBox(
            width: size,
            height: size,
            child: const Center(
              child: Icon(Icons.broken_image_rounded, color: Colors.grey),
            ),
          ),
        );
      }

      return SizedBox(
        width: size,
        height: size,
        child: const Center(
          child: Icon(Icons.image_not_supported_rounded, color: Colors.grey),
        ),
      );
    }

    Widget buildSectionTitle(IconData icon, String label) {
      return Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: const Color(0xFF0F172A)),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF111827),
            ),
          ),
        ],
      );
    }

    Widget buildUploadErrorNotice(String message) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 18,
              color: Color(0xFFB91C1C),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Color(0xFF991B1B),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    Future<void> addImagesToDraft({
      required ImageSource source,
      VoidCallback? onChanged,
    }) async {
      if (isUploadingImages || selectedImages.length >= 6) {
        return;
      }

      imageUploadError = null;
      isUploadingImages = true;
      onChanged?.call();
      final uploadMessenger = ScaffoldMessenger.maybeOf(context);
      ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? uploadNotice;
      var failedUploads = 0;
      var pickerFailed = false;

      try {
        final List<XFile> picked;
        if (source == ImageSource.gallery) {
          picked = await ImagePicker().pickMultiImage(
            imageQuality: 85,
            maxWidth: 1280,
            maxHeight: 1280,
          );
        } else {
          final image = await ImagePicker().pickImage(
            source: source,
            imageQuality: 85,
            maxWidth: 1280,
            maxHeight: 1280,
          );
          picked = image == null ? <XFile>[] : [image];
        }
        if (picked.isEmpty) return;

        final files = picked.take(6 - selectedImages.length).toList();
        if (files.isEmpty) return;

        uploadNotice = uploadMessenger?.showSnackBar(
          SnackBar(
            duration: const Duration(hours: 1),
            content: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                const Text('جاري رفع الصور'),
              ],
            ),
          ),
        );

        for (var index = 0; index < files.length; index++) {
          final file = files[index];
          String? pendingKey;
          try {
            final bytes = await file.readAsBytes();
            final compact = await MediaUploadService.compactImageBytes(
              bytes,
              targetSizeBytes: 650000,
              quality: 78,
            );
            if (compact == null || compact.isEmpty) {
              failedUploads++;
              continue;
            }

            pendingKey =
                'pending:${DateTime.now().microsecondsSinceEpoch}:$index';
            pendingImagePreviews[pendingKey] = compact;
            selectedImages.add(pendingKey);
            onChanged?.call();

            final uploaded = await MediaUploadService.uploadImage(
              compact,
              fileName:
                  'product-${DateTime.now().millisecondsSinceEpoch}-$index.jpg',
              mediaType: 'products',
            );
            final pendingIndex = selectedImages.indexOf(pendingKey);
            if (uploaded != null) {
              pendingImagePreviews.remove(pendingKey);
              if (pendingIndex >= 0) {
                selectedImages[pendingIndex] = uploaded;
                for (final entry in selectedColorImages.entries.toList()) {
                  if (entry.value == pendingKey) {
                    selectedColorImages[entry.key] = uploaded;
                  }
                }
              }
              pendingKey = null;
            } else {
              failedUploads++;
            }
          } catch (error, stackTrace) {
            debugPrint('Failed to prepare merchant product image: $error');
            debugPrintStack(stackTrace: stackTrace);
            failedUploads++;
          } finally {
            if (pendingKey != null) {
              pendingImagePreviews.remove(pendingKey);
              final pendingIndex = selectedImages.indexOf(pendingKey);
              if (pendingIndex >= 0) {
                selectedImages.removeAt(pendingIndex);
              }
              selectedColorImages.removeWhere(
                (_, image) => image == pendingKey,
              );
            }
            onChanged?.call();
          }
        }
      } catch (error, stackTrace) {
        debugPrint('Failed to pick merchant product images: $error');
        debugPrintStack(stackTrace: stackTrace);
        pickerFailed = true;
      } finally {
        uploadMessenger?.hideCurrentSnackBar();
        uploadNotice?.close();
        isUploadingImages = false;
        coverIndex = normalizeCoverIndex(coverIndex, selectedImages.length);
        onChanged?.call();
      }

      if (pickerFailed) {
        imageUploadError = 'تعذر اختيار الصور، حاول مرة أخرى';
      } else if (failedUploads > 0) {
        imageUploadError =
            'تعذر تجهيز أو رفع $failedUploads صورة، حاول إضافتها مجدداً';
      }
      if (pickerFailed || failedUploads > 0) {
        onChanged?.call();
      }
    }

    Future<void> addVideoToDraft(
      BuildContext snackbarContext,
      VoidCallback onChanged, {
      required ImageSource source,
    }) async {
      if (isUploadingVideo) return;

      videoUploadError = null;
      isUploadingVideo = true;
      if (snackbarContext.mounted) onChanged();
      final messenger = ScaffoldMessenger.maybeOf(snackbarContext);
      ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? progressNotice;
      final compressor = FlutterCompress.instance;
      final compressedOutputPaths = <String>[];

      Future<VideoCompressResult> compressVideo(
        String path, {
        required int maxDimension,
        required int targetSizeMB,
      }) =>
          compressor.compress(
            path,
            VideoCompressConfig(
              quality: CompressQuality.high,
              targetSizeMB: targetSizeMB,
              codec: VideoCodec.h264,
              container: VideoContainer.mp4,
              maxWidth: maxDimension,
              maxHeight: maxDimension,
              audioBitrateKbps: 128,
              keepOriginalIfLarger: false,
            ),
          );

      Future<({Uint8List bytes, String codec})?> compressAndReadVideo(
        String path, {
        required int maxDimension,
        required int targetSizeMB,
      }) async {
        final result = await compressVideo(
          path,
          maxDimension: maxDimension,
          targetSizeMB: targetSizeMB,
        );
        if (result.skipped) return null;

        compressedOutputPaths.add(result.outputPath);
        final outputFile = XFile(result.outputPath);
        final bytes = await outputFile.readAsBytes();
        if (!MediaUploadService.isVideoSizeAllowed(bytes.length) ||
            !MediaUploadService.hasMp4FileSignature(bytes)) {
          return null;
        }

        return (bytes: bytes, codec: result.codec.toUpperCase());
      }

      Future<({Uint8List bytes, String codec})?> tryCompressAndReadVideo(
        String path, {
        required int maxDimension,
        required int targetSizeMB,
      }) async {
        try {
          return await compressAndReadVideo(
            path,
            maxDimension: maxDimension,
            targetSizeMB: targetSizeMB,
          );
        } catch (error, stackTrace) {
          debugPrint('Failed to compress merchant product video: $error');
          debugPrintStack(stackTrace: stackTrace);
          return null;
        }
      }

      try {
        final picked = await ImagePicker().pickVideo(
          source: source,
        );
        if (picked == null || !snackbarContext.mounted) return;
        final originalSize = await picked.length();
        if (originalSize == 0) {
          throw StateError('The selected video is empty.');
        }

        videoFileName = picked.name;
        videoPreviewPath = picked.path;
        videoUploadDetails = 'جارٍ تجهيز المعاينة';
        videoPreviewBytes = null;
        onChanged();
        try {
          final thumbnailPath = await compressor.getThumbnail(
            picked.path,
            positionMs: 0,
            maxWidth: 480,
          );
          videoPreviewBytes = await XFile(thumbnailPath).readAsBytes();
          if (snackbarContext.mounted) onChanged();
        } catch (error, stackTrace) {
          debugPrint('Failed to create merchant product video preview: $error');
          debugPrintStack(stackTrace: stackTrace);
        }

        progressNotice = messenger?.showSnackBar(
          const SnackBar(
            duration: Duration(hours: 1),
            content: Text('جارٍ ضغط الفيديو ورفعه...'),
          ),
        );

        Uint8List? uploadBytes;
        var uploadFileName =
            'product-${DateTime.now().millisecondsSinceEpoch}.mp4';
        const uploadContentType = 'video/mp4';
        var codecLabel = '';
        if (MediaUploadService.isVideoSizeAllowed(originalSize) &&
            picked.name.toLowerCase().endsWith('.mp4')) {
          final candidate = await picked.readAsBytes();
          if (MediaUploadService.isVideoSizeAllowed(candidate.length) &&
              MediaUploadService.hasMp4FileSignature(candidate)) {
            uploadBytes = candidate;
            codecLabel = 'الأصلي';
          }
        }

        if (uploadBytes == null) {
          var compressed = await tryCompressAndReadVideo(
            picked.path,
            maxDimension: 960,
            targetSizeMB: 10,
          );
          compressed ??= await tryCompressAndReadVideo(
            picked.path,
            maxDimension: 720,
            targetSizeMB: 8,
          );
          if (compressed != null) {
            uploadBytes = compressed.bytes;
            codecLabel = compressed.codec;
          }
        }

        if (uploadBytes != null &&
            !MediaUploadService.hasMp4FileSignature(uploadBytes)) {
          uploadBytes = null;
        }

        if (uploadBytes == null) {
          videoUploadDetails = 'تعذر تحويله إلى MP4';
          if (snackbarContext.mounted) onChanged();
        }

        if (uploadBytes == null) {
          progressNotice?.close();
          videoUploadError =
              'تعذر تجهيز الفيديو ضمن حد 12 ميجابايت. اختر فيديو أقصر أو أصغر.';
          if (snackbarContext.mounted) onChanged();
          return;
        }

        final uploaded = await MediaUploadService.uploadVideo(
          uploadBytes,
          fileName: uploadFileName,
          contentType: uploadContentType,
        );
        if (uploaded == null) {
          videoUploadDetails = 'تعذر رفع الفيديو؛ تحقق من الاتصال';
          videoUploadError = 'تعذر رفع الفيديو، تحقق من الاتصال وحاول مجدداً';
          if (snackbarContext.mounted) onChanged();
          progressNotice?.close();
          return;
        }

        videoDataUri = uploaded;
        videoUploadDetails = '$codecLabel • '
            '${(uploadBytes.length / (1024 * 1024)).toStringAsFixed(1)} MiB';
        progressNotice?.close();
        messenger?.showSnackBar(
          const SnackBar(
            content: Text('تمت إضافة الفيديو ورفعه بنجاح'),
            duration: Duration(seconds: 3),
          ),
        );
      } catch (error, stackTrace) {
        debugPrint('Failed to prepare merchant product video: $error');
        debugPrintStack(stackTrace: stackTrace);
        progressNotice?.close();
        videoUploadError = 'تعذر تجهيز الفيديو، تحقق من الملف وحاول مجدداً';
        if (snackbarContext.mounted) onChanged();
      } finally {
        try {
          for (final outputPath in compressedOutputPaths) {
            await compressor.releaseOutput(outputPath);
          }
          await compressor.clearCache();
        } catch (error, stackTrace) {
          debugPrint('Failed to clean up compressed video files: $error');
          debugPrintStack(stackTrace: stackTrace);
        }
        isUploadingVideo = false;
        if (snackbarContext.mounted) onChanged();
      }
    }

    var allowProductFormExit = false;
    var isExitConfirmationOpen = false;
    var isProductSaveInProgress = false;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (_) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (context, dialogSetState) {
              final sheetMessenger = ScaffoldMessenger.maybeOf(context);
              bool isSavingDialog = false;
              bool saveLocked = false;

              Future<void> confirmProductFormExit() async {
                if (allowProductFormExit ||
                    isExitConfirmationOpen ||
                    isProductSaveInProgress ||
                    isSavingDialog ||
                    isUploadingImages ||
                    isUploadingVideo) {
                  return;
                }
                isExitConfirmationOpen = true;
                final shouldExit = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('الخروج من نموذج المنتج'),
                    content: const Text(
                      'هل تريد الخروج؟ لن تُحفظ البيانات التي أدخلتها.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: const Text('متابعة التعديل'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: const Text('الخروج'),
                      ),
                    ],
                  ),
                );
                isExitConfirmationOpen = false;
                if (shouldExit != true || !context.mounted) return;
                dialogSetState(() {
                  allowProductFormExit = true;
                });
                await WidgetsBinding.instance.endOfFrame;
                if (!context.mounted) return;
                Navigator.of(context).pop(false);
              }

              void reconcileDraft() {
                coverIndex =
                    normalizeCoverIndex(coverIndex, selectedImages.length);
              }

              Future<void> saveProductDraft() async {
                if (saveLocked ||
                    isSavingDialog ||
                    isUploadingImages ||
                    isUploadingVideo ||
                    currentProfile == null) {
                  return;
                }

                final validationError = validateProductDraftInputs(
                  name: nameController.text,
                  categories: selectedCategories.toList(),
                  priceText: priceController.text,
                );

                if (validationError != null) {
                  formKey.currentState?.validate();
                  final invalidFieldContexts = <BuildContext?>[
                    if (nameFieldKey.currentState?.hasError ?? false)
                      nameFieldKey.currentContext,
                    if (categoryFieldKey.currentState?.hasError ?? false)
                      categoryFieldKey.currentContext,
                    if (priceFieldKey.currentState?.hasError ?? false)
                      priceFieldKey.currentContext,
                  ];
                  for (final fieldContext in invalidFieldContexts) {
                    if (fieldContext == null) continue;
                    await Scrollable.ensureVisible(
                      fieldContext,
                      duration: const Duration(milliseconds: 300),
                      alignment: 0.2,
                    );
                    break;
                  }
                  sheetMessenger?.showSnackBar(
                    SnackBar(
                      content: Text(validationError),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                  return;
                }

                final customCommission =
                    double.tryParse(commissionController.text.trim());
                if (widget.adminManaged &&
                    commissionEnabled &&
                    (customCommission == null ||
                        !customCommission.isFinite ||
                        customCommission < 0)) {
                  sheetMessenger?.showSnackBar(
                    const SnackBar(
                      content: Text('أدخل قيمة عمولة رقمية صحيحة وغير سالبة'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                  return;
                }

                if (selectedImages.any((image) =>
                    MediaUploadService.isDataUri(image) ||
                    image.startsWith('pending:'))) {
                  sheetMessenger?.showSnackBar(
                    const SnackBar(
                      content: Text('انتظر اكتمال رفع الصور قبل حفظ المنتج'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                  return;
                }

                if (videoFileName.isNotEmpty && videoDataUri.isEmpty) {
                  sheetMessenger?.showSnackBar(
                    const SnackBar(
                      content: Text('يجب إكمال رفع الفيديو قبل حفظ المنتج'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                  return;
                }

                isProductSaveInProgress = true;
                saveLocked = true;
                isSavingDialog = true;
                dialogSetState(() {});

                try {
                  final effectiveCoverImageUri = selectedImages.isNotEmpty
                      ? selectedImages[normalizeCoverIndex(
                          coverIndex, selectedImages.length)]
                      : '';

                  final payload = buildMerchantProductPayload(
                    existingProduct: product,
                    merchantId: widget.ownerMerchantId ?? currentProfile.id,
                    name: nameController.text,
                    categoryText: categoryController.text,
                    mainCategoryId: selectedMainCategoryId,
                    mainCategoryName: selectedMainCategoryName(),
                    subcategoryId: selectedSubcategoryId,
                    subcategoryName: selectedSubcategoryName(),
                    imageUris: selectedImages,
                    coverImageUri: effectiveCoverImageUri,
                    videoDataUri: videoDataUri,
                    available: isAvailable,
                    description: descriptionController.text,
                    colors: selectedColors.toList(),
                    colorImageUrls: selectedColorImages,
                    sizes: selectedSizes.toList(),
                    hasSizes: hasSizes,
                    price: double.tryParse(priceController.text.trim()) ?? 0,
                    stock: int.tryParse(stockController.text.trim()) ?? 0,
                    currencyCode: selectedCurrency.code,
                    currencySymbol: selectedCurrency.symbol,
                    currencyName: selectedCurrency.title,
                  );

                  if (widget.adminManaged) {
                    payload['merchant_name'] = widget.ownerMerchantName ?? '';
                    if (product == null) {
                      final now = DateTime.now().toUtc().toIso8601String();
                      payload
                        ..['approval_status'] = 'approved'
                        ..['available'] = isAvailable
                        ..['requested_available'] = isAvailable
                        ..['reviewed_at'] = now
                        ..['reviewed_by'] = currentProfile.id
                        ..['created_at'] = now
                        ..['created_by_admin_id'] = currentProfile.id;
                    }
                    payload['commission_mode_override'] =
                        commissionEnabled ? commissionMode : null;
                    payload['commission_value_override'] =
                        commissionEnabled ? customCommission : null;
                  }

                  final id = payload['id'].toString();
                  final isPriceChangePending =
                      payload['price_change_status'] == 'pending';

                  await FirebaseDatabaseService.instance
                      .write('products/$id', payload);

                  if (mounted) {
                    setState(() {
                      _upsertProductInCache(payload);
                      _visibleCount = _pageSize;
                      _productsFuture =
                          Future.value(_lastMerchantProductsCache);
                    });
                  }

                  if (context.mounted) {
                    dialogSetState(() {
                      allowProductFormExit = true;
                    });
                    await WidgetsBinding.instance.endOfFrame;
                    if (!context.mounted) return;
                    Navigator.pop(context, true);
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      SnackBar(
                        content: Text(
                          isPriceChangePending
                              ? 'تم إرسال طلب تعديل السعر إلى المسؤول'
                              : widget.adminManaged && product == null
                                  ? 'تم إنشاء المنتج واعتماده للتاجر'
                                  : 'جارٍ إرسال المنتج لمراجعة المسؤول...',
                        ),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }

                  if (mounted) {
                    _refreshProducts();
                  }
                } on ArgumentError catch (error) {
                  sheetMessenger?.showSnackBar(
                    SnackBar(
                      content: Text(error.message.toString()),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                } catch (_) {
                  sheetMessenger?.showSnackBar(
                    const SnackBar(
                      content: Text('تعذر حفظ المنتج، حاول مرة أخرى'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                } finally {
                  isProductSaveInProgress = false;
                  saveLocked = false;
                  if (mounted) {
                    isSavingDialog = false;
                    dialogSetState(() {});
                  }
                }
              }

              return PopScope<Object?>(
                canPop: allowProductFormExit,
                onPopInvokedWithResult: (didPop, result) {
                  if (!didPop) {
                    confirmProductFormExit();
                  }
                },
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 18,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.88,
                      maxWidth: 560,
                    ),
                    child: SingleChildScrollView(
                      child: Form(
                        key: formKey,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 52,
                              height: 5,
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE5E7EB),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  product == null
                                      ? 'إضافة منتج'
                                      : 'تحديث المنتج',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                                IconButton(
                                  onPressed: isSavingDialog ||
                                          isUploadingVideo ||
                                          isUploadingImages
                                      ? null
                                      : confirmProductFormExit,
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(18),
                                border:
                                    Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  buildSectionTitle(
                                      Icons.image_outlined, 'الصور'),
                                  const SizedBox(height: 12),
                                  if (selectedImages.isNotEmpty)
                                    SizedBox(
                                      height: 92,
                                      child: ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: selectedImages.length,
                                        separatorBuilder: (_, __) =>
                                            const SizedBox(width: 8),
                                        itemBuilder: (context, index) {
                                          final image = selectedImages[index];
                                          return GestureDetector(
                                            onTap: () => dialogSetState(() {
                                              coverIndex = index;
                                              reconcileDraft();
                                            }),
                                            child: Stack(
                                              children: [
                                                ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  child:
                                                      buildImagePreview(image),
                                                ),
                                                Positioned(
                                                  right: 4,
                                                  top: 4,
                                                  child: Icon(
                                                    index == coverIndex
                                                        ? Icons
                                                            .radio_button_checked
                                                        : Icons
                                                            .radio_button_unchecked,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    )
                                  else
                                    const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 8),
                                      child: Text(
                                        'لم يتم اختيار صور بعد',
                                        style: TextStyle(
                                          color: Color(0xFF6B7280),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  if (selectedImages.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                            color: const Color(0xFFE5E7EB)),
                                      ),
                                      child: Row(
                                        children: [
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            child: buildImagePreview(
                                              selectedImages[
                                                  normalizeCoverIndex(
                                                coverIndex,
                                                selectedImages.length,
                                              )],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'معاينة صورة الغلاف',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                    color: Color(0xFF374151),
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  '${selectedImages.length} صورة مختارة',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Color(0xFF6B7280),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: isUploadingImages ||
                                                  selectedImages.length >= 6
                                              ? null
                                              : () async {
                                                  await addImagesToDraft(
                                                    source: ImageSource.gallery,
                                                    onChanged: () =>
                                                        dialogSetState(() {}),
                                                  );
                                                  dialogSetState(() {
                                                    reconcileDraft();
                                                  });
                                                },
                                          icon: const Icon(
                                              Icons.photo_library_rounded),
                                          label: Text(
                                            isUploadingImages
                                                ? 'جارٍ رفع الصور...'
                                                : 'المعرض (${selectedImages.length}/6)',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: isUploadingImages ||
                                                  selectedImages.length >= 6
                                              ? null
                                              : () async {
                                                  await addImagesToDraft(
                                                    source: ImageSource.camera,
                                                    onChanged: () =>
                                                        dialogSetState(() {}),
                                                  );
                                                  dialogSetState(() {
                                                    reconcileDraft();
                                                  });
                                                },
                                          icon: const Icon(
                                              Icons.camera_alt_rounded),
                                          label: const Text('تصوير صورة'),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (imageUploadError != null) ...[
                                    const SizedBox(height: 8),
                                    buildUploadErrorNotice(imageUploadError!),
                                  ],
                                  if (selectedImages.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: TextButton.icon(
                                        onPressed: isUploadingImages
                                            ? null
                                            : () => dialogSetState(() {
                                                  if (selectedImages.isEmpty) {
                                                    coverIndex = 0;
                                                    return;
                                                  }

                                                  final safeIndex =
                                                      normalizeCoverIndex(
                                                    coverIndex,
                                                    selectedImages.length,
                                                  );
                                                  selectedImages
                                                      .removeAt(safeIndex);
                                                  selectedColorImages
                                                      .removeWhere(
                                                    (_, image) =>
                                                        !selectedImages
                                                            .contains(image),
                                                  );
                                                  if (selectedImages.isEmpty) {
                                                    coverIndex = 0;
                                                  } else {
                                                    coverIndex =
                                                        normalizeCoverIndex(
                                                      coverIndex,
                                                      selectedImages.length,
                                                    );
                                                  }
                                                }),
                                        icon: const Icon(
                                            Icons.delete_outline_rounded),
                                        label: const Text(
                                            'حذف صورة الغلاف المحددة'),
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: isUploadingVideo
                                              ? null
                                              : () => addVideoToDraft(
                                                    context,
                                                    () => dialogSetState(() {}),
                                                    source: ImageSource.gallery,
                                                  ),
                                          icon: isUploadingVideo
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                )
                                              : const Icon(
                                                  Icons.video_library_rounded,
                                                ),
                                          label: Text(
                                            isUploadingVideo
                                                ? 'جارٍ رفع الفيديو...'
                                                : videoDataUri.isEmpty
                                                    ? 'اختيار فيديو'
                                                    : 'استبدال الفيديو',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: isUploadingVideo
                                              ? null
                                              : () => addVideoToDraft(
                                                    context,
                                                    () => dialogSetState(() {}),
                                                    source: ImageSource.camera,
                                                  ),
                                          icon: const Icon(
                                            Icons.videocam_rounded,
                                          ),
                                          label: Text(
                                            videoDataUri.isEmpty
                                                ? 'تصوير فيديو'
                                                : 'استبدال بتصوير',
                                          ),
                                        ),
                                      ),
                                      if (videoDataUri.isNotEmpty ||
                                          videoFileName.isNotEmpty)
                                        IconButton(
                                          tooltip: 'حذف الفيديو',
                                          onPressed: isUploadingVideo
                                              ? null
                                              : () => dialogSetState(() {
                                                    videoDataUri = '';
                                                    videoFileName = '';
                                                    videoUploadDetails = '';
                                                    videoPreviewPath = null;
                                                    videoPreviewBytes = null;
                                                  }),
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (videoUploadError != null) ...[
                                    const SizedBox(height: 8),
                                    buildUploadErrorNotice(videoUploadError!),
                                  ],
                                  const SizedBox(height: 4),
                                  if (videoPreviewBytes != null)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.memory(
                                        videoPreviewBytes!,
                                        width: double.infinity,
                                        height: 180,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  if (videoPreviewBytes != null)
                                    const SizedBox(height: 8),
                                  if (videoPreviewPath != null ||
                                      videoDataUri.isNotEmpty)
                                    Align(
                                      alignment:
                                          AlignmentDirectional.centerStart,
                                      child: OutlinedButton.icon(
                                        onPressed: showVideoPreview,
                                        icon: const Icon(
                                          Icons.play_circle_outline_rounded,
                                        ),
                                        label: const Text('معاينة الفيديو'),
                                      ),
                                    ),
                                  Text(
                                    videoFileName.isNotEmpty
                                        ? 'الفيديو: $videoFileName • $videoUploadDetails'
                                        : videoDataUri.isEmpty
                                            ? 'يُضغط الفيديو تلقائيًا عند الحاجة (حد أقصى 12 ميجابايت)'
                                            : 'يوجد فيديو مرفوع لهذا المنتج',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF6B7280),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFAFAF9),
                                borderRadius: BorderRadius.circular(18),
                                border:
                                    Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  buildSectionTitle(Icons.info_outline_rounded,
                                      'معلومات المنتج'),
                                  const SizedBox(height: 12),
                                  Focus(
                                    onFocusChange: (hasFocus) {
                                      if (hasFocus) {
                                        moveCursorToEnd(nameController);
                                      }
                                    },
                                    child: TextFormField(
                                      key: nameFieldKey,
                                      controller: nameController,
                                      textDirection: TextDirection.rtl,
                                      textAlign: TextAlign.right,
                                      validator: (value) {
                                        if (value == null ||
                                            value.trim().isEmpty) {
                                          return 'يرجى إدخال اسم المنتج';
                                        }
                                        return null;
                                      },
                                      decoration: const InputDecoration(
                                        labelText: 'اسم المنتج',
                                        alignLabelWithHint: true,
                                        border: OutlineInputBorder(),
                                        filled: true,
                                        fillColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  if (categories.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.only(bottom: 12),
                                      child: Text(
                                        'لا توجد أقسام متاحة من المسؤول',
                                        style:
                                            TextStyle(color: Color(0xFF6B7280)),
                                      ),
                                    )
                                  else
                                    FormField<String>(
                                      key: categoryFieldKey,
                                      validator: (_) {
                                        if (selectedMainCategoryId.isEmpty ||
                                            selectedSubcategoryId.isEmpty ||
                                            selectedCategories.length != 1) {
                                          return 'اختر القسم الرئيسي والقسم الفرعي للمنتج';
                                        }
                                        return null;
                                      },
                                      builder: (fieldState) {
                                        ProductCategory? selectedParent;
                                        for (final category in categories) {
                                          if (category.id ==
                                              selectedMainCategoryId) {
                                            selectedParent = category;
                                            break;
                                          }
                                        }
                                        final subcategories = selectedParent
                                                ?.activeSubcategories ??
                                            const <ProductSubcategory>[];

                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'اختر القسم الرئيسي أولاً، ثم اختر القسم الفرعي التابع له.',
                                              style: TextStyle(
                                                color: Color(0xFF6B7280),
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            DropdownButtonFormField<String>(
                                              initialValue:
                                                  selectedMainCategoryId.isEmpty
                                                      ? null
                                                      : selectedMainCategoryId,
                                              isExpanded: true,
                                              decoration: const InputDecoration(
                                                labelText: 'القسم الرئيسي',
                                                border: OutlineInputBorder(),
                                                filled: true,
                                                fillColor: Colors.white,
                                              ),
                                              items: categories
                                                  .map(
                                                    (category) =>
                                                        DropdownMenuItem<
                                                            String>(
                                                      value: category.id,
                                                      child: Text(
                                                        category.name,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  )
                                                  .toList(),
                                              onChanged: (id) {
                                                dialogSetState(() {
                                                  selectedMainCategoryId =
                                                      id ?? '';
                                                  selectedSubcategoryId = '';
                                                  selectedCategories.clear();
                                                  categoryController.clear();
                                                  fieldState.didChange(null);
                                                });
                                              },
                                            ),
                                            const SizedBox(height: 10),
                                            DropdownButtonFormField<String>(
                                              key: ValueKey(
                                                'subcategory-$selectedMainCategoryId',
                                              ),
                                              initialValue: subcategories.any(
                                                (subcategory) =>
                                                    subcategory.id ==
                                                    selectedSubcategoryId,
                                              )
                                                  ? selectedSubcategoryId
                                                  : null,
                                              isExpanded: true,
                                              decoration: InputDecoration(
                                                labelText: 'القسم الفرعي',
                                                helperText: selectedParent ==
                                                            null ||
                                                        subcategories.isEmpty
                                                    ? 'لا توجد أقسام فرعية نشطة لهذا القسم'
                                                    : null,
                                                border:
                                                    const OutlineInputBorder(),
                                                filled: true,
                                                fillColor: Colors.white,
                                              ),
                                              items: subcategories
                                                  .map(
                                                    (subcategory) =>
                                                        DropdownMenuItem<
                                                            String>(
                                                      value: subcategory.id,
                                                      child: Text(
                                                        subcategory.name,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  )
                                                  .toList(),
                                              onChanged: subcategories.isEmpty
                                                  ? null
                                                  : (id) {
                                                      dialogSetState(() {
                                                        selectedSubcategoryId =
                                                            id ?? '';
                                                        final name =
                                                            selectedSubcategoryName();
                                                        selectedCategories
                                                          ..clear()
                                                          ..addAll(
                                                            name.isEmpty
                                                                ? const <String>[]
                                                                : <String>[
                                                                    name
                                                                  ],
                                                          );
                                                        categoryController
                                                            .text = name;
                                                        fieldState
                                                            .didChange(id);
                                                      });
                                                    },
                                            ),
                                            if (fieldState.hasError)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 8),
                                                child: Text(
                                                  fieldState.errorText ?? '',
                                                  style: const TextStyle(
                                                    color: Color(0xFFDC2626),
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        );
                                      },
                                    ),
                                  const SizedBox(height: 12),
                                  SwitchListTile.adaptive(
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    title: const Text('حالة المنتج'),
                                    subtitle: Text(
                                      isAvailable
                                          ? 'متاح للطلب'
                                          : 'غير متاح حالياً',
                                      textDirection: TextDirection.rtl,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    value: isAvailable,
                                    onChanged: (value) => dialogSetState(
                                        () => isAvailable = value),
                                  ),
                                  const SizedBox(height: 12),
                                  Focus(
                                    onFocusChange: (hasFocus) {
                                      if (hasFocus) {
                                        moveCursorToEnd(descriptionController);
                                      }
                                    },
                                    child: TextField(
                                      controller: descriptionController,
                                      minLines: 4,
                                      maxLines: 10,
                                      textDirection: TextDirection.rtl,
                                      textAlign: TextAlign.right,
                                      decoration: const InputDecoration(
                                        labelText: 'الوصف',
                                        alignLabelWithHint: true,
                                        border: OutlineInputBorder(),
                                        filled: true,
                                        fillColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  _ProductColorsEditor(
                                    selectedColors: selectedColors,
                                    selectedImages: selectedImages,
                                    selectedColorImages: selectedColorImages,
                                    buildImagePreview: buildImagePreview,
                                    onChanged: () => dialogSetState(() {}),
                                  ),
                                  const SizedBox(height: 12),
                                  SwitchListTile.adaptive(
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    title:
                                        const Text('المنتج يحتوي على مقاسات'),
                                    subtitle: Text(
                                      hasSizes
                                          ? 'سيختار العميل مقاس المنتج'
                                          : 'لن يُطلب من العميل اختيار مقاس',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF6B7280),
                                      ),
                                    ),
                                    value: hasSizes,
                                    onChanged: (value) => dialogSetState(() {
                                      hasSizes = value;
                                      if (!hasSizes) selectedSizes.clear();
                                    }),
                                  ),
                                  if (hasSizes) ...[
                                    const SizedBox(height: 12),
                                    _ProductSizesEditor(
                                      selectedSizes: selectedSizes,
                                      onChanged: () => dialogSetState(() {}),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Focus(
                                    onFocusChange: (hasFocus) {
                                      if (hasFocus) {
                                        moveCursorToEnd(priceController);
                                      }
                                    },
                                    child: TextFormField(
                                      key: priceFieldKey,
                                      controller: priceController,
                                      enabled: workingProduct[
                                              'price_change_status'] !=
                                          'pending',
                                      validator: (value) {
                                        final parsedPrice = double.tryParse(
                                            value?.trim() ?? '');
                                        if (parsedPrice == null ||
                                            parsedPrice <= 0) {
                                          return 'يرجى إدخال سعر المنتج';
                                        }
                                        return null;
                                      },
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      textDirection: TextDirection.rtl,
                                      textAlign: TextAlign.right,
                                      decoration: InputDecoration(
                                        labelText: 'سعر المنتج',
                                        helperText: workingProduct[
                                                    'price_change_status'] ==
                                                'pending'
                                            ? 'يوجد طلب تعديل سعر قيد المراجعة'
                                            : product != null &&
                                                    resolveProductApprovalStatus(
                                                            product) ==
                                                        'approved'
                                                ? 'سيُرسل تغيير السعر للمسؤول للموافقة'
                                                : null,
                                        alignLabelWithHint: true,
                                        border: OutlineInputBorder(),
                                        filled: true,
                                        fillColor: Colors.white,
                                      ),
                                      onChanged: (_) => dialogSetState(() {}),
                                    ),
                                  ),
                                  if (widget.adminManaged) ...[
                                    const SizedBox(height: 12),
                                    Builder(
                                      builder: (context) {
                                        final basePrice = double.tryParse(
                                                priceController.text) ??
                                            0;
                                        final configuredCommission =
                                            pricingConfig.commissionByMerchant[
                                                    widget.ownerMerchantId] ??
                                                pricingConfig
                                                        .commissionByCategory[
                                                    selectedSubcategoryName()] ??
                                                pricingConfig.commissionValue;
                                        final commissionValue =
                                            commissionEnabled
                                                ? double.tryParse(
                                                        commissionController
                                                            .text
                                                            .trim()) ??
                                                    0
                                                : configuredCommission;
                                        final effectiveMode = commissionEnabled
                                            ? commissionMode
                                            : pricingConfig.commissionMode;
                                        final commissionAmount = ProductModel
                                            .commissionAmountForPrice(
                                          price: basePrice,
                                          mode: effectiveMode,
                                          value: commissionValue,
                                        );

                                        return Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF8FAFC),
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            border: Border.all(
                                              color: const Color(0xFFE2E8F0),
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              SwitchListTile.adaptive(
                                                contentPadding: EdgeInsets.zero,
                                                title: const Text(
                                                  'تحديد عمولة خاصة لهذا المنتج',
                                                ),
                                                subtitle: const Text(
                                                  'اتركها متوقفة لاستخدام إعدادات التاجر والفئة',
                                                ),
                                                value: commissionEnabled,
                                                onChanged: (value) =>
                                                    dialogSetState(() {
                                                  commissionEnabled = value;
                                                }),
                                              ),
                                              if (commissionEnabled) ...[
                                                DropdownButtonFormField<String>(
                                                  value: commissionMode,
                                                  decoration:
                                                      const InputDecoration(
                                                    labelText: 'طريقة العمولة',
                                                    border:
                                                        OutlineInputBorder(),
                                                  ),
                                                  items: const [
                                                    DropdownMenuItem(
                                                      value: 'percent',
                                                      child: Text('نسبة مئوية'),
                                                    ),
                                                    DropdownMenuItem(
                                                      value: 'fixed',
                                                      child: Text(
                                                          'مبلغ ثابت لكل قطعة'),
                                                    ),
                                                  ],
                                                  onChanged: (value) {
                                                    if (value == null) return;
                                                    dialogSetState(() {
                                                      commissionMode = value;
                                                    });
                                                  },
                                                ),
                                                const SizedBox(height: 8),
                                                TextField(
                                                  controller:
                                                      commissionController,
                                                  keyboardType:
                                                      const TextInputType
                                                          .numberWithOptions(
                                                    decimal: true,
                                                  ),
                                                  decoration: InputDecoration(
                                                    labelText: commissionMode ==
                                                            'fixed'
                                                        ? 'مبلغ العمولة لكل قطعة'
                                                        : 'نسبة العمولة',
                                                    suffixText:
                                                        commissionMode ==
                                                                'fixed'
                                                            ? selectedCurrency
                                                                .symbol
                                                            : '%',
                                                    border:
                                                        const OutlineInputBorder(),
                                                  ),
                                                  onChanged: (_) =>
                                                      dialogSetState(() {}),
                                                ),
                                              ],
                                              const SizedBox(height: 8),
                                              Text(
                                                'سعر البيع بعد العمولة: '
                                                '${(basePrice + commissionAmount).toStringAsFixed(2)} '
                                                '${selectedCurrency.symbol}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF047857),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  DropdownButtonFormField<String>(
                                    value: selectedCurrency.code,
                                    decoration: const InputDecoration(
                                      labelText: 'العملة',
                                      border: OutlineInputBorder(),
                                      filled: true,
                                      fillColor: Colors.white,
                                    ),
                                    items: currencies
                                        .map((currency) => DropdownMenuItem(
                                              value: currency.code,
                                              child: Text(
                                                  '${currency.title} (${currency.symbol})'),
                                            ))
                                        .toList(),
                                    onChanged: (code) {
                                      if (code == null) return;
                                      dialogSetState(() {
                                        selectedCurrency =
                                            currencies.firstWhere((currency) =>
                                                currency.code == code);
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  Focus(
                                    onFocusChange: (hasFocus) {
                                      if (hasFocus) {
                                        moveCursorToEnd(stockController);
                                      }
                                    },
                                    child: TextField(
                                      controller: stockController,
                                      keyboardType: TextInputType.number,
                                      textDirection: TextDirection.rtl,
                                      textAlign: TextAlign.right,
                                      decoration: const InputDecoration(
                                        labelText: 'المخزون',
                                        alignLabelWithHint: true,
                                        border: OutlineInputBorder(),
                                        filled: true,
                                        fillColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: isSavingDialog ||
                                          isUploadingVideo ||
                                          isUploadingImages
                                      ? null
                                      : confirmProductFormExit,
                                  child: const Text('إلغاء'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: isSavingDialog || isUploadingVideo
                                      ? null
                                      : () async {
                                          if (isSavingDialog) return;
                                          await saveProductDraft();
                                        },
                                  child: isSavingDialog
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text('حفظ'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );

    nameController.dispose();
    categoryController.dispose();
    descriptionController.dispose();
    priceController.dispose();
    stockController.dispose();
    commissionController.dispose();
    if (result != true || currentProfile == null) return;

    // The actual save is already executed inside the dialog-local save flow.
    // Keeping the outer block empty prevents duplicate writes when the user
    // taps Save repeatedly before the modal closes.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.adminManaged && widget.ownerMerchantName?.isNotEmpty == true
              ? 'منتجات ${widget.ownerMerchantName}'
              : 'إدارة المنتجات',
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث المنتجات وحالات المراجعة',
            onPressed: _isRefreshingProducts ? null : _refreshProducts,
            icon: RotationTransition(
              turns: _refreshAnimationController,
              child: const Icon(Icons.refresh_rounded),
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: FloatingActionButton(
        mini: true,
        tooltip: 'إضافة منتج جديد',
        onPressed: _isProductDialogOpen ? null : () => _showAddOrEditDialog(),
        child: const Icon(Icons.add_rounded),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _productsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'تعذر تحميل المنتجات، حاول مرة أخرى',
                style: TextStyle(color: Color(0xFF374151)),
              ),
            );
          }

          final allProducts = snapshot.data ?? const <Map<String, dynamic>>[];
          final filteredProducts = _applyProductFiltersAndSort(allProducts);

          if (filteredProducts.isEmpty) {
            final emptyText = _searchQuery.isNotEmpty
                ? 'لا توجد منتجات تطابق البحث الحالي'
                : _availabilityFilter == 'all'
                    ? 'لا توجد منتجات حتى الآن'
                    : _availabilityFilter == 'available'
                        ? 'لا توجد منتجات متاحة حاليًا'
                        : 'لا توجد منتجات غير متاحة حاليًا';

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: TextField(
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                        _visibleCount = _pageSize;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'ابحث باسم المنتج أو الفئة',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _buildAvailabilityChip('all', 'الكل'),
                      _buildAvailabilityChip('available', 'متاحة'),
                      _buildAvailabilityChip('unavailable', 'غير متاحة'),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(emptyText),
                  ),
                ),
              ],
            );
          }

          final visibleProducts = filteredProducts.take(_visibleCount).toList();
          final hasMore = _visibleCount < filteredProducts.length;

          if (hasMore && visibleProducts.length >= filteredProducts.length) {
            _visibleCount = filteredProducts.length;
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                      _visibleCount = _pageSize;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'ابحث باسم المنتج أو الفئة',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: const Color(0xFFF9FAFB),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildAvailabilityChip('all', 'الكل'),
                            _buildAvailabilityChip('available', 'متاحة'),
                            _buildAvailabilityChip('unavailable', 'غير متاحة'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: _sortBy,
                      underline: const SizedBox(),
                      icon: const Icon(Icons.sort_rounded),
                      items: const [
                        DropdownMenuItem(
                            value: 'newest', child: Text('الأحدث')),
                        DropdownMenuItem(
                            value: 'oldest', child: Text('الأقدم')),
                        DropdownMenuItem(value: 'name', child: Text('الاسم')),
                        DropdownMenuItem(
                            value: 'category', child: Text('الفئة')),
                        DropdownMenuItem(
                            value: 'price_asc', child: Text('السعر: من الأقل')),
                        DropdownMenuItem(
                            value: 'price_desc',
                            child: Text('السعر: من الأعلى')),
                        DropdownMenuItem(
                            value: 'stock_asc',
                            child: Text('الكمية: من الأقل')),
                        DropdownMenuItem(
                            value: 'stock_desc',
                            child: Text('الكمية: من الأعلى')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _sortBy = value;
                          _visibleCount = _pageSize;
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: visibleProducts.length + (hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= visibleProducts.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Text(
                            'جاري تحميل المزيد...',
                            style: TextStyle(
                              color: Color(0xFF6B7280),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      );
                    }

                    final product = visibleProducts[index];
                    final productId = (product['id'] ?? '').toString();
                    final isProcessingProduct = _isProductDialogOpen ||
                        _processingProductIds.contains(productId);
                    final price = product['price'];
                    final currencyLabel = resolveProductCurrencyLabel(product);
                    final available =
                        resolveMerchantProductAvailability(product);
                    final approvalStatus =
                        resolveProductApprovalStatus(product);
                    final reviewReason =
                        (product['review_reason'] ?? '').toString().trim();
                    final imageUrl = resolveProductPrimaryImage(product);
                    final approvalLabel = switch (approvalStatus) {
                      'pending' => 'قيد مراجعة المسؤول',
                      'rejected' => 'مرفوض',
                      _ => available ? 'معتمد ومنشور' : 'معتمد ومخفي',
                    };
                    final approvalColor = switch (approvalStatus) {
                      'pending' => const Color(0xFFB45309),
                      'rejected' => const Color(0xFFB91C1C),
                      _ => available
                          ? const Color(0xFF166534)
                          : const Color(0xFF475569),
                    };

                    final category = (product['category'] ?? '').toString();

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0F172A12),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            clipBehavior: Clip.hardEdge,
                            child: imageUrl.isNotEmpty
                                ? (MediaUploadService.isDataUri(imageUrl)
                                    ? Image.memory(
                                        MediaUploadService.decodeDataUriToBytes(
                                                imageUrl) ??
                                            Uint8List(0),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(Icons
                                                .image_not_supported_rounded),
                                      )
                                    : Image(
                                        image: CachedNetworkImageProvider(
                                          imageUrl,
                                        ),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(
                                          Icons.image_not_supported_rounded,
                                          color: Color(0xFF9CA3AF),
                                        ),
                                      ))
                                : const Icon(
                                    Icons.image_rounded,
                                    color: Color(0xFF9CA3AF),
                                  ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        (product['name'] ?? 'منتج').toString(),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: Color(0xFF111827),
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: approvalColor.withOpacity(0.12),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        approvalLabel,
                                        style: TextStyle(
                                          color: approvalColor,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                if (category.isNotEmpty)
                                  Text(
                                    category,
                                    style: const TextStyle(
                                      color: Color(0xFF6B7280),
                                      fontSize: 12,
                                    ),
                                  ),
                                if (approvalStatus == 'pending' ||
                                    approvalStatus == 'rejected' ||
                                    reviewReason.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    approvalStatus == 'pending'
                                        ? 'لن يظهر المنتج للعملاء حتى اعتماده.'
                                        : approvalStatus == 'rejected'
                                            ? 'سبب الرفض: ${reviewReason.isEmpty ? 'عدّل المنتج ثم أعد إرساله للمراجعة.' : reviewReason}'
                                            : 'ملاحظة المسؤول: $reviewReason',
                                    style: TextStyle(
                                      color: approvalStatus == 'rejected'
                                          ? const Color(0xFFB91C1C)
                                          : const Color(0xFF6B7280),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                                if ((product['price_change_status'] ?? '')
                                    .toString()
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    switch (
                                        (product['price_change_status'] ?? '')
                                            .toString()) {
                                      'pending' =>
                                        'طلب تعديل السعر قيد مراجعة المسؤول: '
                                            '${product['requested_price'] ?? ''} $currencyLabel',
                                      'approved' => 'تمت الموافقة على تعديل السعر'
                                          '${(product['price_change_review_reason'] ?? '').toString().trim().isEmpty ? '' : ': ${product['price_change_review_reason']}'}',
                                      'rejected' => 'رُفض طلب تعديل السعر: '
                                          '${(product['price_change_review_reason'] ?? '').toString().trim().isEmpty ? 'عدّل السعر ثم أعد إرساله.' : product['price_change_review_reason']}',
                                      _ => '',
                                    },
                                    style: TextStyle(
                                      color: product['price_change_status'] ==
                                              'rejected'
                                          ? const Color(0xFFB91C1C)
                                          : product['price_change_status'] ==
                                                  'pending'
                                              ? const Color(0xFFB45309)
                                              : const Color(0xFF166534),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Text(
                                  'السعر: '
                                  '${price is num ? price.toStringAsFixed(2) : (double.tryParse(price?.toString() ?? '') ?? 0).toStringAsFixed(2)} '
                                  '$currencyLabel',
                                  style: const TextStyle(
                                    color: Color(0xFF0F172A),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'المخزون: ${product['stock'] ?? product['inventory'] ?? 0}',
                                  style: const TextStyle(
                                    color: Color(0xFF4B5563),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildProductActionButton(
                                icon: available
                                    ? Icons.visibility_rounded
                                    : Icons.visibility_off_rounded,
                                color: const Color(0xFF2563EB),
                                onPressed: isProcessingProduct
                                    ? null
                                    : () => _toggleAvailability(product),
                              ),
                              const SizedBox(height: 8),
                              _buildProductActionButton(
                                icon: Icons.edit_rounded,
                                color: const Color(0xFF059669),
                                onPressed: isProcessingProduct
                                    ? null
                                    : () => _showAddOrEditDialog(product),
                              ),
                              const SizedBox(height: 8),
                              _buildProductActionButton(
                                icon: Icons.delete_rounded,
                                color: const Color(0xFFDC2626),
                                onPressed: isProcessingProduct
                                    ? null
                                    : () => _deleteProduct(product),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAvailabilityChip(String value, String label) {
    final selected = _availabilityFilter == value;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() {
            _availabilityFilter = value;
            _visibleCount = _pageSize;
          });
        },
        selectedColor: const Color(0xFFE0F2FE),
        labelStyle: TextStyle(
          color: selected ? const Color(0xFF0F172A) : const Color(0xFF374151),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildProductActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: 38,
      height: 38,
      child: Material(
        color: color.withValues(alpha: onPressed == null ? 0.06 : 0.12),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Icon(
            icon,
            color: onPressed == null ? color.withValues(alpha: 0.45) : color,
            size: 18,
          ),
        ),
      ),
    );
  }
}

class _ProductColorsEditor extends StatefulWidget {
  const _ProductColorsEditor({
    required this.selectedColors,
    required this.selectedImages,
    required this.selectedColorImages,
    required this.buildImagePreview,
    required this.onChanged,
  });

  final Set<String> selectedColors;
  final List<String> selectedImages;
  final Map<String, String> selectedColorImages;
  final Widget Function(String, {double size}) buildImagePreview;
  final VoidCallback onChanged;

  @override
  State<_ProductColorsEditor> createState() => _ProductColorsEditorState();
}

class _ProductColorsEditorState extends State<_ProductColorsEditor> {
  void _addColor(String value) {
    final color = value.trim();
    if (color.isEmpty || !widget.selectedColors.add(color)) return;
    widget.onChanged();
  }

  Future<void> _addCustomColor() async {
    final color = await showCustomProductColorDialog(context);
    if (!mounted || color == null) return;
    _addColor(color);
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = productColorSuggestions
        .where((color) => !widget.selectedColors.contains(color))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'الألوان المتوفرة (اختياري)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 8),
        if (widget.selectedColors.isEmpty)
          const Text(
            'اختر الألوان التي سيظهر بها المنتج للعميل',
            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.selectedColors
                .map(
                  (color) => InputChip(
                    avatar: ProductColorSwatch(
                      name: color,
                      showName: false,
                    ),
                    label: Text(color),
                    onDeleted: () {
                      widget.selectedColors.remove(color);
                      widget.selectedColorImages.remove(color);
                      widget.onChanged();
                    },
                  ),
                )
                .toList(),
          ),
        if (widget.selectedColors.isNotEmpty &&
            widget.selectedImages.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'صورة كل لون (اختياري)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 8),
          ...widget.selectedColors.map((color) {
            final assignedImage = widget.selectedColorImages[color];
            final selectedImage = widget.selectedImages.contains(assignedImage)
                ? assignedImage!
                : '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: DropdownButtonFormField<String>(
                initialValue: selectedImage,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: color,
                  prefixIcon: const Icon(Icons.image_outlined),
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('بدون صورة مخصصة'),
                  ),
                  ...widget.selectedImages.indexed.map(
                    (entry) => DropdownMenuItem<String>(
                      value: entry.$2,
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: widget.buildImagePreview(
                              entry.$2,
                              size: 36,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('الصورة ${entry.$1 + 1}'),
                        ],
                      ),
                    ),
                  ),
                ],
                onChanged: (value) {
                  if (value == null || value.isEmpty) {
                    widget.selectedColorImages.remove(color);
                  } else {
                    widget.selectedColorImages[color] = value;
                  }
                  widget.onChanged();
                },
              ),
            );
          }),
        ],
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'اختيارات سريعة',
            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 78,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: suggestions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, index) {
                final color = suggestions[index];
                return ProductColorSwatch(
                  name: color,
                  onTap: () => _addColor(color),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _addCustomColor,
            icon: const Icon(Icons.colorize_rounded),
            label: const Text('إضافة لون مخصص'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              foregroundColor: const Color(0xFF111827),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

const _productSizePresets = <String, List<String>>{
  'ملابس': ['XS', 'S', 'M', 'L', 'XL', 'XXL', '3XL'],
  'أطفال': [
    '0-3 أشهر',
    '3-6 أشهر',
    '6-12 أشهر',
    '1-2 سنة',
    '3-4 سنوات',
    '5-6 سنوات',
    '7-8 سنوات'
  ],
  'أحذية': ['35', '36', '37', '38', '39', '40', '41', '42', '43', '44', '45'],
  'أرقام': ['26', '28', '30', '32', '34', '36', '38', '40', '42', '44', '46'],
};

class _ProductSizesEditor extends StatefulWidget {
  const _ProductSizesEditor({
    required this.selectedSizes,
    required this.onChanged,
  });

  final Set<String> selectedSizes;
  final VoidCallback onChanged;

  @override
  State<_ProductSizesEditor> createState() => _ProductSizesEditorState();
}

class _ProductSizesEditorState extends State<_ProductSizesEditor> {
  String _selectedPreset = 'ملابس';

  void _toggleSize(String size) {
    if (widget.selectedSizes.contains(size)) {
      widget.selectedSizes.remove(size);
    } else {
      widget.selectedSizes.add(size);
    }
    widget.onChanged();
  }

  Future<void> _addCustomSize() async {
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _CustomSizeDialog(),
    );
    if (!mounted || result == null) return;
    final value = result.trim();
    if (value.isEmpty || !widget.selectedSizes.add(value)) return;
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _productSizePresets[_selectedPreset]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'المقاسات المتوفرة (اختياري)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'اختر مجموعة مناسبة أو أضف مقاسًا خاصًا للمنتج',
          style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
        ),
        const SizedBox(height: 12),
        if (widget.selectedSizes.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.selectedSizes
                .map(
                  (size) => InputChip(
                    label: Text(size),
                    avatar: const Icon(Icons.straighten_rounded, size: 16),
                    onDeleted: () {
                      widget.selectedSizes.remove(size);
                      widget.onChanged();
                    },
                  ),
                )
                .toList(),
          ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _selectedPreset,
          decoration: const InputDecoration(
            labelText: 'نوع المقاسات',
            prefixIcon: Icon(Icons.category_outlined),
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ),
          items: _productSizePresets.keys
              .map(
                (preset) => DropdownMenuItem<String>(
                  value: preset,
                  child: Text(preset),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) setState(() => _selectedPreset = value);
          },
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: suggestions
              .map(
                (size) => FilterChip(
                  label: Text(size),
                  selected: widget.selectedSizes.contains(size),
                  onSelected: (_) => _toggleSize(size),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _addCustomSize,
            icon: const Icon(Icons.add_rounded),
            label: const Text('إضافة مقاس مخصص أو نطاق'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
              foregroundColor: const Color(0xFF111827),
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CustomSizeDialog extends StatefulWidget {
  @override
  State<_CustomSizeDialog> createState() => _CustomSizeDialogState();
}

class _CustomSizeDialogState extends State<_CustomSizeDialog> {
  final _controller = TextEditingController();
  String _type = 'نصي';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة مقاس مخصص'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            value: _type,
            decoration: const InputDecoration(
              labelText: 'نوع المقاس',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'نصي', child: Text('نصي مثل 2XL')),
              DropdownMenuItem(value: 'رقمي', child: Text('رقمي مثل 47')),
              DropdownMenuItem(value: 'نطاق', child: Text('نطاق مثل 30-32')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _type = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: _type == 'رقمي'
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              labelText: _type == 'نطاق' ? 'النطاق' : 'المقاس',
              hintText: _type == 'نطاق' ? 'مثال: 30-32' : 'مثال: 2XL أو 47',
              prefixIcon: const Icon(Icons.straighten_rounded),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.add_rounded),
          label: const Text('إضافة'),
        ),
      ],
    );
  }
}

class MerchantOrderManagementScreen extends StatefulWidget {
  final List<Map<String, dynamic>> orders;
  final String currencySymbol;

  const MerchantOrderManagementScreen({
    super.key,
    this.orders = const <Map<String, dynamic>>[],
    this.currencySymbol = 'ر.ي',
  });

  @override
  State<MerchantOrderManagementScreen> createState() =>
      _MerchantOrderManagementScreenState();
}

class _MerchantOrderManagementScreenState
    extends State<MerchantOrderManagementScreen> {
  static const int _pageSize = 8;

  final ScrollController _scrollController = ScrollController();
  String _selectedStatus = 'all';
  int _visibleCount = _pageSize;
  late Future<List<Map<String, dynamic>>> _ordersFuture;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _ordersFuture = _loadOrders();
  }

  Future<List<Map<String, dynamic>>> _loadOrders() async {
    final authService = AuthService();
    final profile = await authService.loadSession() ??
        await authService.getCurrentProfile();

    if (profile != null) {
      final liveOrders = await OrderService().getOrdersByMerchant(profile.id);
      final products = await FirebaseDatabaseService.instance.read('products');
      final productOwners = OrderService.productOwnersById(products);
      final merchantProductIds = productOwners.entries
          .where((entry) => entry.value == profile.id)
          .map((entry) => entry.key)
          .toSet();
      final currencies = await CurrencyService().getCurrencies();
      return liveOrders.map((order) {
        final data = order.toJson();
        if (!order.hasExplicitCurrencyCode) {
          data.remove('currency_code');
          data.remove('currency_symbol');
        }
        data['merchant_items'] = order.items
            .where((item) => OrderService.orderItemBelongsToMerchant(
                  item: item.toJson(),
                  merchantId: profile.id,
                  productOwners: productOwners,
                  merchantProductIds: merchantProductIds,
                ))
            .map((item) => item.toJson())
            .toList();
        data['merchant_product_images'] = merchantOrderProductImages(
          order: data,
          merchantId: profile.id,
          productsSnapshot: products,
        );
        final totalInYER = merchantProductsTotalInYER(
          data,
          merchantId: profile.id,
          productOwners: productOwners,
          merchantProductIds: merchantProductIds,
          currencies: currencies,
        );
        if (totalInYER != null) data['report_total_yer'] = totalInYER;
        return data;
      }).toList();
    }

    return MerchantManagementScreen.filterVisibleMerchantOrders(widget.orders);
  }

  Future<void> _refreshOrders() async {
    final future = _loadOrders();
    setState(() => _ordersFuture = future);
    await future;
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    if (position.extentAfter < 300) {
      setState(() {
        _visibleCount = (_visibleCount + _pageSize).clamp(0, 9999);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filters = {
      'all': 'الكل',
      'new': 'طلب جديد',
      'pending_payment': 'قيد الدفع',
      'confirmed': 'مؤكد',
      'preparing': 'قيد التجهيز',
      'shipped': 'جاهز للاستلام من المتجر',
      'delivered': 'مكتمل',
      'cancelled': 'ملغي',
    };

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _ordersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('إدارة الطلبات')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('إدارة الطلبات')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('تعذر تحميل الطلبات'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _refreshOrders,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          );
        }

        final orders =
            sortMerchantOrdersNewestFirst(snapshot.data ?? widget.orders);
        final pendingCount = orders.where((order) {
          final status = (order['status'] ?? 'pending_payment').toString();
          return status == 'new' ||
              status == 'pending_payment' ||
              status == 'awaiting_confirmation';
        }).length;
        final activeCount = orders.where((order) {
          final status = (order['status'] ?? '').toString();
          return status == 'confirmed' ||
              status == 'accepted' ||
              status == 'preparing' ||
              status == 'shipped' ||
              status == 'picked_up';
        }).length;
        final filteredOrders = orders.where((order) {
          if (_selectedStatus == 'all') return true;
          final status = (order['status'] ?? 'pending_payment').toString();
          return status == _selectedStatus;
        }).toList();

        final visibleOrders = filteredOrders.take(_visibleCount).toList();
        final hasMore = _visibleCount < filteredOrders.length;

        final rows = visibleOrders.isEmpty
            ? const <Widget>[]
            : visibleOrders.map((order) {
                final id = OrderNumber.fromOrder(order);
                final totalText = _merchantOrderTotalLabel(order);
                final status =
                    (order['status'] ?? 'pending_payment').toString();
                final rawItems = order['merchant_items'] ?? order['items'];
                final rejectedCount = rawItems is List
                    ? rawItems.where((item) {
                        return item is Map &&
                            item['status']?.toString() == 'rejected';
                      }).length
                    : 0;
                final color = switch (status) {
                  'preparing' => const Color(0xFF3B82F6),
                  'shipped' => const Color(0xFF10B981),
                  'delivered' => const Color(0xFF8B5CF6),
                  'cancelled' => const Color(0xFFB91C1C),
                  _ => const Color(0xFFF59E0B),
                };
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  leading: MerchantOrderProductThumbnails(
                    orderId: id,
                    imageUrls: _merchantOrderImageUrls(order),
                    size: 50,
                  ),
                  tileColor: status == 'new' ? const Color(0xFFFFFBEB) : null,
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'الطلب $id',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: status == 'new'
                                ? FontWeight.w800
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (status == 'new') ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFFF59E0B).withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'جديد',
                            style: TextStyle(
                              color: Color(0xFFB45309),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'الحالة: ${DeliveryService.statusLabel(status)}'
                        '${rejectedCount > 0 ? ' • $rejectedCount منتج غير متوفر' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.calendar_today_rounded,
                            size: 14,
                            color: Color(0xFF6B7280),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              formatMerchantOrderDateTime(order),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  trailing: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          totalText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            DeliveryService.statusLabel(status),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.bold,
                                fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MerchantOrderDetailScreen(
                          order: order,
                          currencySymbol: widget.currencySymbol,
                        ),
                      ),
                    );
                  },
                );
              }).toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('إدارة الطلبات'),
            actions: [
              IconButton(
                tooltip: 'تحديث الطلبات',
                onPressed: _refreshOrders,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _refreshOrders,
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 0.9,
                  children: [
                    _MetricCard(
                      label: 'إجمالي الطلبات',
                      value: orders.length.toString(),
                      color: const Color(0xFF111827),
                      icon: Icons.receipt_long_rounded,
                    ),
                    _MetricCard(
                      label: 'جديدة',
                      value: pendingCount.toString(),
                      color: const Color(0xFFF59E0B),
                      icon: Icons.new_releases_rounded,
                    ),
                    _MetricCard(
                      label: 'قيد التنفيذ',
                      value: activeCount.toString(),
                      color: const Color(0xFF3B82F6),
                      icon: Icons.local_shipping_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: filters.entries.map((entry) {
                      final selected = _selectedStatus == entry.key;
                      final color = switch (entry.key) {
                        'confirmed' => const Color(0xFF3B82F6),
                        'preparing' => const Color(0xFF8B5CF6),
                        'shipped' => const Color(0xFF10B981),
                        'delivered' => const Color(0xFF14B8A6),
                        _ => const Color(0xFFF59E0B),
                      };
                      return Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ChoiceChip(
                          label: Text(entry.value),
                          selected: selected,
                          onSelected: (_) {
                            setState(() {
                              _selectedStatus = entry.key;
                              _visibleCount = _pageSize;
                            });
                          },
                          selectedColor: color.withValues(alpha: 0.12),
                          backgroundColor: Colors.white,
                          labelStyle: TextStyle(
                            color: selected ? color : const Color(0xFF374151),
                            fontWeight: FontWeight.bold,
                          ),
                          side: BorderSide(
                            color: selected ? color : const Color(0xFFE5E7EB),
                            width: 1,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                if (filteredOrders.isEmpty)
                  const Center(child: Text('لا توجد طلبات في هذا التصنيف'))
                else
                  ...rows,
                if (hasMore)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'جاري تحميل المزيد...',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class MerchantInventoryScreen extends StatefulWidget {
  const MerchantInventoryScreen({super.key});

  @override
  State<MerchantInventoryScreen> createState() =>
      _MerchantInventoryScreenState();
}

class _MerchantInventoryScreenState extends State<MerchantInventoryScreen> {
  late Future<List<Map<String, dynamic>>> _productsFuture;
  String _searchQuery = '';
  String _sortBy = 'name';
  String _stockFilter = 'all';
  final Set<String> _updatingProductIds = <String>{};
  final Map<String, String> _stockDrafts = <String, String>{};

  @override
  void initState() {
    super.initState();
    _refreshProducts();
  }

  void _refreshProducts() {
    final cachedProducts = _lastMerchantProductsCache;
    final refreshFuture = _loadProducts();

    if (cachedProducts.isEmpty) {
      _productsFuture = refreshFuture.then((data) {
        _lastMerchantProductsCache = data;
        return data;
      });
      return;
    }

    _productsFuture = Future.value(cachedProducts).then((data) async {
      final refreshed = await refreshFuture;
      _lastMerchantProductsCache = refreshed;
      return refreshed;
    });
  }

  Future<List<Map<String, dynamic>>> _loadProducts() async {
    try {
      final auth = AuthService();
      final profile =
          await auth.loadSession() ?? await auth.getCurrentProfile();
      if (profile == null) return const <Map<String, dynamic>>[];

      final snapshot = await FirebaseDatabaseService.instance.read('products');
      final items = snapshot.values
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      return MerchantManagementScreen.filterMerchantRecords(
        merchantId: profile.id,
        records: items,
      );
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<void> _updateStock(Map<String, dynamic> product, int delta) async {
    final current = resolveProductStock(product);
    await _saveStock(product, current + delta);
  }

  Future<void> _saveStock(Map<String, dynamic> product, int stock) async {
    final id = product['id']?.toString();
    if (id == null || id.isEmpty || _updatingProductIds.contains(id)) return;

    final next = stock.clamp(0, 9999).toInt();
    setState(() => _updatingProductIds.add(id));
    try {
      await FirebaseDatabaseService.instance
          .update('products/$id', {'stock': next});

      _stockDrafts.remove(id);
      if (mounted) setState(_refreshProducts);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تحديث المخزون، حاول مرة أخرى')),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingProductIds.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة المخزون')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _productsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'تعذر تحميل المخزون، حاول مرة أخرى',
                style: TextStyle(color: Color(0xFF374151)),
              ),
            );
          }

          final products = snapshot.data ?? const <Map<String, dynamic>>[];
          final query = _searchQuery.trim().toLowerCase();
          final totalUnits = products.fold<int>(
            0,
            (sum, product) => sum + resolveProductStock(product),
          );
          final outOfStockCount = products
              .where((product) => resolveProductStock(product) == 0)
              .length;
          final lowStockCount = products
              .where((product) => resolveProductStock(product) > 0)
              .where((product) => resolveProductStock(product) <= 5)
              .length;
          final filteredProducts =
              MerchantManagementScreen.sortProductsForMerchantPanel(
            records: products.where((product) {
              if (query.isEmpty) return true;
              final name = (product['name'] ?? '').toString().toLowerCase();
              final category =
                  (product['category'] ?? '').toString().toLowerCase();
              final matchesQuery =
                  name.contains(query) || category.contains(query);
              final matchesStock = _stockFilter == 'all' ||
                  resolveInventoryStatus(resolveProductStock(product)) ==
                      _stockFilter;
              return matchesQuery && matchesStock;
            }).toList(),
            sortBy: _sortBy,
          );

          if (filteredProducts.isEmpty) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: TextField(
                    onChanged: (value) {
                      setState(() => _searchQuery = value);
                    },
                    decoration: InputDecoration(
                      hintText: 'ابحث باسم المنتج أو الفئة',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const Expanded(
                  child: Center(
                    child: Text('لا توجد منتجات في المخزون'),
                  ),
                ),
              ],
            );
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Row(
                  children: [
                    _InventorySummaryTile(
                      label: 'إجمالي الوحدات',
                      value: totalUnits.toString(),
                      icon: Icons.inventory_2_outlined,
                      color: const Color(0xFF2563EB),
                    ),
                    const SizedBox(width: 8),
                    _InventorySummaryTile(
                      label: 'مخزون منخفض',
                      value: lowStockCount.toString(),
                      icon: Icons.warning_amber_rounded,
                      color: const Color(0xFFD97706),
                    ),
                    const SizedBox(width: 8),
                    _InventorySummaryTile(
                      label: 'نافد',
                      value: outOfStockCount.toString(),
                      icon: Icons.remove_shopping_cart_outlined,
                      color: const Color(0xFFDC2626),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  onChanged: (value) {
                    setState(() => _searchQuery = value);
                  },
                  decoration: InputDecoration(
                    hintText: 'ابحث باسم المنتج أو الفئة',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: const Color(0xFFF9FAFB),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _InventoryFilterChip(
                      label: 'الكل',
                      selected: _stockFilter == 'all',
                      onSelected: () => setState(() => _stockFilter = 'all'),
                    ),
                    _InventoryFilterChip(
                      label: 'متوفر',
                      selected: _stockFilter == 'in_stock',
                      onSelected: () =>
                          setState(() => _stockFilter = 'in_stock'),
                    ),
                    _InventoryFilterChip(
                      label: 'منخفض',
                      selected: _stockFilter == 'low_stock',
                      onSelected: () =>
                          setState(() => _stockFilter = 'low_stock'),
                    ),
                    _InventoryFilterChip(
                      label: 'نافد',
                      selected: _stockFilter == 'out_of_stock',
                      onSelected: () =>
                          setState(() => _stockFilter = 'out_of_stock'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: DropdownButton<String>(
                    value: _sortBy,
                    underline: const SizedBox(),
                    icon: const Icon(Icons.sort_rounded),
                    items: const [
                      DropdownMenuItem(
                          value: 'name', child: Text('ترتيب: الاسم')),
                      DropdownMenuItem(
                          value: 'category', child: Text('ترتيب: الفئة')),
                      DropdownMenuItem(
                          value: 'price_asc',
                          child: Text('ترتيب: السعر من الأقل')),
                      DropdownMenuItem(
                          value: 'price_desc',
                          child: Text('ترتيب: السعر من الأعلى')),
                      DropdownMenuItem(
                          value: 'stock_asc',
                          child: Text('ترتيب: الكمية من الأقل')),
                      DropdownMenuItem(
                          value: 'stock_desc',
                          child: Text('ترتيب: الكمية من الأعلى')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _sortBy = value);
                    },
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: filteredProducts.length,
                  itemBuilder: (context, index) {
                    final product = filteredProducts[index];
                    final stock = resolveProductStock(product);
                    final productId = product['id']?.toString() ?? '';
                    final isUpdating = _updatingProductIds.contains(productId);
                    final status = resolveInventoryStatus(stock);
                    final name = (product['name'] ?? 'منتج').toString();
                    final imageUrl = resolveProductPrimaryImage(product);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              margin: const EdgeInsets.only(left: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              clipBehavior: Clip.hardEdge,
                              child: imageUrl.isNotEmpty
                                  ? (MediaUploadService.isDataUri(imageUrl)
                                      ? Image.memory(
                                          MediaUploadService
                                                  .decodeDataUriToBytes(
                                                      imageUrl) ??
                                              Uint8List(0),
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(
                                            Icons.image_not_supported_rounded,
                                            color: Color(0xFF9CA3AF),
                                          ),
                                        )
                                      : Image(
                                          image: CachedNetworkImageProvider(
                                            imageUrl,
                                          ),
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(
                                            Icons.image_not_supported_rounded,
                                            color: Color(0xFF9CA3AF),
                                          ),
                                        ))
                                  : const Icon(
                                      Icons.image_rounded,
                                      color: Color(0xFF9CA3AF),
                                    ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: 82,
                                        child: TextFormField(
                                          key: ValueKey('$productId-$stock'),
                                          initialValue:
                                              _stockDrafts[productId] ??
                                                  stock.toString(),
                                          keyboardType: TextInputType.number,
                                          textInputAction: TextInputAction.done,
                                          textAlign: TextAlign.center,
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                          ],
                                          decoration: const InputDecoration(
                                            labelText: 'الكمية',
                                            isDense: true,
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 8,
                                            ),
                                          ),
                                          onChanged: (value) =>
                                              _stockDrafts[productId] = value,
                                          onFieldSubmitted: (value) {
                                            final enteredStock =
                                                int.tryParse(value);
                                            if (enteredStock != null) {
                                              _saveStock(product, enteredStock);
                                            }
                                          },
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'حفظ الكمية',
                                        onPressed: isUpdating
                                            ? null
                                            : () {
                                                final enteredStock =
                                                    int.tryParse(
                                                  _stockDrafts[productId] ??
                                                      stock.toString(),
                                                );
                                                if (enteredStock != null) {
                                                  _saveStock(
                                                    product,
                                                    enteredStock,
                                                  );
                                                }
                                              },
                                        icon: const Icon(
                                          Icons.check_rounded,
                                          size: 20,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    status == 'out_of_stock'
                                        ? 'نفد المخزون'
                                        : status == 'low_stock'
                                            ? 'يحتاج إلى إعادة التوريد'
                                            : 'متوفر للبيع',
                                    style: TextStyle(
                                      color: status == 'out_of_stock'
                                          ? const Color(0xFFDC2626)
                                          : status == 'low_stock'
                                              ? const Color(0xFFD97706)
                                              : const Color(0xFF15803D),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  onPressed: isUpdating || stock == 0
                                      ? null
                                      : () => _updateStock(product, -1),
                                  icon: const Icon(
                                    Icons.remove_circle_outline_rounded,
                                  ),
                                ),
                                IconButton(
                                  onPressed: isUpdating
                                      ? null
                                      : () => _updateStock(product, 1),
                                  icon: const Icon(
                                    Icons.add_circle_outline_rounded,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InventorySummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _InventorySummaryTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _InventoryFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _InventoryFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
        showCheckmark: false,
      ),
    );
  }
}

class MerchantOrderDetailScreen extends StatefulWidget {
  final Map<String, dynamic> order;
  final String currencySymbol;

  const MerchantOrderDetailScreen({
    super.key,
    required this.order,
    this.currencySymbol = 'ر.ي',
  });

  @override
  State<MerchantOrderDetailScreen> createState() =>
      _MerchantOrderDetailScreenState();
}

class _MerchantOrderDetailScreenState extends State<MerchantOrderDetailScreen> {
  late String _status =
      (widget.order['status'] ?? 'pending_payment').toString();
  String _merchantId = '';
  Map<String, String> _merchantProductOwners = const {};
  Set<String> _merchantProductIds = const {};
  List<CurrencyOption> _currencies = const [];
  bool _saving = false;
  bool _restoringPickupOtp = false;

  @override
  void initState() {
    super.initState();
    if (_status == 'shipped') {
      _restoringPickupOtp = true;
      _restorePickupOtp();
    }
    _loadMerchantId();
  }

  Future<void> _restorePickupOtp() async {
    if (mounted && !_restoringPickupOtp) {
      setState(() => _restoringPickupOtp = true);
    }
    final orderId = (widget.order['id'] ?? '').toString();
    final updated = orderId.isEmpty
        ? null
        : await OrderService().prepareDeliveryOtp(orderId);
    if (!mounted) return;

    setState(() {
      _restoringPickupOtp = false;
      if (updated != null) {
        widget.order['pickup_otp'] = updated.pickupOtp;
      }
    });
    if (updated == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر استعادة رمز استلام الطلب، حاول مرة أخرى'),
        ),
      );
    }
  }

  Future<void> _loadMerchantId() async {
    final authService = AuthService();
    final profile = await authService.loadSession() ??
        await authService.getCurrentProfile();
    if (!mounted) return;
    final merchantId = profile?.id.trim() ?? '';
    setState(() {
      _merchantId = merchantId;
    });
    if (merchantId.isEmpty) return;

    try {
      final products = await FirebaseDatabaseService.instance.read('products');
      final productOwners = OrderService.productOwnersById(products);
      final merchantProductIds = productOwners.entries
          .where((entry) => entry.value == merchantId)
          .map((entry) => entry.key)
          .toSet();
      final currencies = await CurrencyService().getCurrencies();
      if (!mounted) return;
      setState(() {
        _merchantProductOwners = productOwners;
        _merchantProductIds = merchantProductIds;
        _currencies = currencies;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر تحميل منتجات المتجر وأسعار العملات'),
        ),
      );
    }
  }

  String _readItemString(Map<String, dynamic> item, List<String> keys,
      {String fallback = 'منتج'}) {
    for (final key in keys) {
      final value = item[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    return fallback;
  }

  num _readNumber(Object? value, {num fallback = 0}) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? fallback;
    return fallback;
  }

  String _money(num value) =>
      '${value.toStringAsFixed(0)} ${widget.currencySymbol}';

  Future<void> _rejectItemForOutOfStock(
    int itemIndex,
    String productName,
  ) async {
    if (_saving || _merchantId.isEmpty) return;
    final shouldReject = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('رفض المنتج'),
        content: Text(
          'هل تريد استبعاد "$productName" من هذا الطلب؟ السبب: نفدت الكمية. '
          'سيستمر تجهيز بقية المنتجات.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('تأكيد الاستبعاد'),
          ),
        ],
      ),
    );
    if (shouldReject != true || !mounted) return;

    setState(() => _saving = true);
    final updated = await OrderService().rejectOrderItemForOutOfStock(
      orderId: (widget.order['id'] ?? '').toString(),
      itemIndex: itemIndex,
      merchantId: _merchantId,
    );
    if (!mounted) return;

    if (updated != null) {
      setState(() {
        _status = updated.status;
        widget.order
          ..['status'] = updated.status
          ..['items'] = updated.items.map((item) => item.toJson()).toList()
          ..['subtotal'] = updated.subtotal
          ..['commission'] = updated.commission
          ..['total'] = updated.total
          ..['cancelled_by'] = updated.cancelledBy
          ..['cancellation_reason'] = updated.cancellationReason
          ..['cancelled_at'] = updated.cancelledAt?.toIso8601String();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            updated.status == 'cancelled'
                ? 'تعذر إتمام الطلب لأن جميع المنتجات نفدت كميتها'
                : 'تم استبعاد المنتج وإبلاغ العميل، وسيتم إتمام بقية الطلب',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر استبعاد المنتج. تحقق من ملكية المنتج وحالة الطلب ثم أعد المحاولة.',
          ),
        ),
      );
    }
    setState(() => _saving = false);
  }

  Future<void> _advanceStatus() async {
    if (_saving) return;

    final nextStatus = nextMerchantOrderStatus(_status);

    if (nextStatus == null) {
      return;
    }

    final shouldAdvance = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد تغيير حالة الطلب'),
        content: Text(
          'سيتم تغيير حالة الطلب من '
          '${DeliveryService.statusLabel(_status)} إلى '
          '${DeliveryService.statusLabel(nextStatus)}. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );

    if (shouldAdvance != true || !mounted) return;

    setState(() => _saving = true);

    final orderService = OrderService();
    final updated = nextStatus == 'shipped'
        ? await orderService.prepareDeliveryOtp(
            (widget.order['id'] ?? '').toString(),
          )
        : await orderService.updateOrderStatus(
            orderId: (widget.order['id'] ?? '').toString(),
            status: nextStatus,
          );

    if (!mounted) return;

    if (updated != null) {
      setState(() {
        _status = updated.status;
        widget.order['status'] = updated.status;
        if (nextStatus == 'shipped') {
          widget.order['pickup_otp'] = updated.pickupOtp;
          widget.order['pickup_otp_verified'] = false;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم تحديث حالة الطلب إلى ${DeliveryService.statusLabel(updated.status)}',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحديث حالة الطلب، حاول مرة أخرى')),
      );
    }

    setState(() => _saving = false);
  }

  Future<void> _rejectOrder() async {
    if (_saving || _status == 'delivered' || _status == 'cancelled') return;

    final shouldReject = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('رفض الطلب'),
        content: const Text(
          'سيتم تغيير حالة الطلب إلى مرفوض ولن يمكن متابعة تجهيزه. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('رفض الطلب'),
          ),
        ],
      ),
    );

    if (shouldReject != true || !mounted) return;

    setState(() => _saving = true);
    final updated = await OrderService().updateOrderStatus(
      orderId: (widget.order['id'] ?? '').toString(),
      status: 'cancelled',
      cancelledBy: 'merchant',
      cancellationReason: 'تم رفض الطلب من التاجر',
    );

    if (!mounted) return;

    if (updated != null) {
      setState(() {
        _status = updated.status;
        widget.order['status'] = updated.status;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم رفض الطلب وإبلاغ العميل بالحالة')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر رفض الطلب، حاول مرة أخرى')),
      );
    }

    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final id = OrderNumber.fromOrder(widget.order);
    final items = (widget.order['items'] ?? const <dynamic>[]) as List<dynamic>;
    final merchantTotal = merchantProductsTotalInYER(
      widget.order,
      merchantId: _merchantId,
      productOwners: _merchantProductOwners,
      merchantProductIds: _merchantProductIds,
      currencies: _currencies,
    );
    final merchantItems = items.asMap().entries.where((entry) {
      final item = entry.value;
      if (item is! Map) return false;
      return isMerchantOrderItem(
        item: Map<String, dynamic>.from(item),
        merchantId: _merchantId,
        productOwners: _merchantProductOwners,
        merchantProductIds: _merchantProductIds,
      );
    });
    final nextActionLabel = switch (_status) {
      'new' => 'قبول الطلب وبدء التجهيز',
      'pending_payment' => 'تأكيد الطلب',
      'confirmed' => 'بدء التجهيز',
      'preparing' => 'تسليم للسائق',
      'shipped' => 'بانتظار تأكيد السائق',
      _ => 'تم توصيل المنتج للعميل',
    };

    final statusColors = {
      'new': const Color(0xFFF59E0B),
      'pending_payment': const Color(0xFFF59E0B),
      'confirmed': const Color(0xFF3B82F6),
      'preparing': const Color(0xFF8B5CF6),
      'shipped': const Color(0xFF10B981),
      'delivered': const Color(0xFF14B8A6),
    };
    final badgeColor = _status == 'cancelled'
        ? const Color(0xFFB91C1C)
        : statusColors[_status] ?? const Color(0xFFF59E0B);

    return Scaffold(
      appBar: AppBar(
        title: Text('تفاصيل الطلب $id'),
        actions: [
          IconButton(
            tooltip: 'تحديث حالة الطلب',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('حالة الطلب محدثة حاليًا')),
            ),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'حالة الطلب',
                        style:
                            TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          DeliveryService.statusLabel(_status),
                          style: TextStyle(
                            color: badgeColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'الطلب #$id',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      OrderNumberCopyButton(orderNumber: id),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded,
                          size: 16, color: Color(0xFF6B7280)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'تاريخ ووقت الطلب: '
                          '${formatMerchantOrderDateTime(widget.order)}',
                          style: const TextStyle(color: Color(0xFF6B7280)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_status == 'cancelled')
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Text(
                  'سبب الإلغاء: ${widget.order['cancellation_reason'] ?? 'غير محدد'}\n'
                  'بواسطة: ${widget.order['cancelled_by'] ?? 'غير محدد'}',
                  style: const TextStyle(
                    color: Color(0xFF991B1B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (_status == 'cancelled') const SizedBox(height: 20),
            const SizedBox(height: 20),
            const Text(
              'العناصر',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (merchantItems.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('لا توجد منتجات مرتبطة بمتجرك في هذا الطلب'),
                ),
              )
            else
              ...merchantItems.map((entry) {
                final itemIndex = entry.key;
                final item = entry.value;
                final product = item is Map
                    ? Map<String, dynamic>.from(item)
                    : <String, dynamic>{};
                final qty =
                    _readNumber(product['quantity'] ?? product['qty'] ?? 1);
                final unitPrice = merchantProductUnitPrice(product) ??
                    _readNumber(product['unit_price'] ??
                        product['unitPrice'] ??
                        product['price']);
                final imageUrl = _readItemString(
                    product,
                    [
                      'image_url',
                      'imageUrl',
                      'cover_image_url',
                      'coverImageUrl',
                    ],
                    fallback: '');
                final selectedColor = _readItemString(
                    product,
                    [
                      'selected_color',
                      'selectedColor',
                      'color',
                    ],
                    fallback: '');
                final selectedSize = _readItemString(
                    product,
                    [
                      'selected_size',
                      'selectedSize',
                      'size',
                    ],
                    fallback: '');
                final name = _readItemString(product, [
                  'product_name',
                  'productName',
                  'name',
                ]);
                final itemCurrency = resolveProductCurrencyLabel(product);
                final totalForItem = unitPrice * qty;
                final itemStatus = product['status']?.toString() ?? 'available';
                final isRejected = itemStatus == 'rejected';
                final canReject = !isRejected &&
                    isMerchantOrderItem(
                      item: product,
                      merchantId: _merchantId,
                      productOwners: _merchantProductOwners,
                      merchantProductIds: _merchantProductIds,
                    ) &&
                    _merchantId.isNotEmpty &&
                    !{'shipped', 'picked_up', 'delivered', 'cancelled'}
                        .contains(_status);

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: imageUrl.isNotEmpty &&
                                MediaUploadService.imageProvider(imageUrl) !=
                                    null
                            ? Image(
                                image: MediaUploadService.imageProvider(
                                  imageUrl,
                                )!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.image_not_supported_rounded,
                                  color: Color(0xFF9CA3AF),
                                ),
                              )
                            : const Icon(
                                Icons.image_rounded,
                                color: Color(0xFF9CA3AF),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'الكمية: ${qty.toInt()}',
                              style: const TextStyle(color: Color(0xFF6B7280)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'سعر الوحدة: ${unitPrice.toStringAsFixed(0)} '
                              '$itemCurrency',
                              style: const TextStyle(color: Color(0xFF6B7280)),
                            ),
                            if (selectedColor.isNotEmpty ||
                                selectedSize.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  if (selectedColor.isNotEmpty)
                                    Chip(
                                      avatar: const Icon(Icons.palette_outlined,
                                          size: 16),
                                      label: Text('اللون: $selectedColor'),
                                    ),
                                  if (selectedSize.isNotEmpty)
                                    Chip(
                                      avatar: const Icon(Icons.straighten,
                                          size: 16),
                                      label: Text('المقاس: $selectedSize'),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            isRejected
                                ? 'غير محسوب'
                                : '${totalForItem.toStringAsFixed(0)} '
                                    '$itemCurrency',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isRejected
                                  ? const Color(0xFFB91C1C)
                                  : const Color(0xFF111827),
                            ),
                          ),
                          if (isRejected)
                            Text(
                              'سبب الرفض: ${product['rejection_reason'] ?? 'نفدت الكمية'}',
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                color: Color(0xFFB91C1C),
                                fontSize: 11,
                              ),
                            )
                          else if (canReject)
                            TextButton.icon(
                              onPressed: _saving
                                  ? null
                                  : () => _rejectItemForOutOfStock(
                                        itemIndex,
                                        name,
                                      ),
                              icon: const Icon(
                                Icons.remove_shopping_cart_outlined,
                                size: 16,
                              ),
                              label: const Text('نفدت الكمية'),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _MerchantOrderSummaryRow(
                      label: 'إجمالي منتجات متجرك',
                      value: merchantTotal == null
                          ? 'غير متاح'
                          : _money(merchantTotal),
                      isStrong: true,
                    ),
                  ],
                ),
              ),
            ),
            if (_status == 'shipped')
              Container(
                margin: const EdgeInsets.only(top: 14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFCD34D)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'رمز استلام الطلب للسائق',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    if ((widget.order['pickup_otp']?.toString().isNotEmpty ??
                            false) &&
                        !_restoringPickupOtp)
                      Text(
                        widget.order['pickup_otp'].toString(),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4,
                        ),
                      )
                    else if (_restoringPickupOtp)
                      const LinearProgressIndicator()
                    else
                      TextButton(
                        onPressed: _restorePickupOtp,
                        child: const Text('إعادة محاولة استعادة الرمز'),
                      ),
                    const Text(
                      'أعطِ هذا الرمز للسائق. لن يبدأ التوصيل قبل التحقق منه.',
                      style: TextStyle(color: Color(0xFF92400E)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ||
                            _status == 'delivered' ||
                            _status == 'shipped' ||
                            _status == 'cancelled'
                        ? null
                        : _advanceStatus,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.update_rounded),
                    label: Text(nextActionLabel),
                  ),
                ),
                if (_status != 'delivered' &&
                    _status != 'shipped' &&
                    _status != 'cancelled') ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _rejectOrder,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFB91C1C),
                        side: const BorderSide(color: Color(0xFFB91C1C)),
                      ),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('رفض الطلب'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MerchantOrderSummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isStrong;

  const _MerchantOrderSummaryRow({
    required this.label,
    required this.value,
    this.isStrong = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color:
                  isStrong ? const Color(0xFF111827) : const Color(0xFF6B7280),
              fontWeight: isStrong ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.left,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isStrong
                    ? const Color(0xFF111827)
                    : const Color(0xFF374151),
                fontWeight: isStrong ? FontWeight.bold : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MerchantStoreSettingsScreen extends StatefulWidget {
  const MerchantStoreSettingsScreen({super.key});

  static Map<String, double>? parseLocationFromText(String? value) {
    final source = value?.trim();
    if (source == null || source.isEmpty) {
      return null;
    }

    final match = RegExp(
      r'([-+]?\d+(?:\.\d+)?)\s*[,\s]+\s*([-+]?\d+(?:\.\d+)?)',
    ).firstMatch(source);

    if (match == null) {
      return null;
    }

    final latitude = double.tryParse(match.group(1)!);
    final longitude = double.tryParse(match.group(2)!);
    if (latitude == null || longitude == null) {
      return null;
    }

    if (latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return null;
    }

    return {'latitude': latitude, 'longitude': longitude};
  }

  @override
  State<MerchantStoreSettingsScreen> createState() =>
      _MerchantStoreSettingsScreenState();
}

class _MerchantWalletControllers {
  _MerchantWalletControllers({String provider = '', String accountNumber = ''})
      : provider = TextEditingController(text: provider),
        accountNumber = TextEditingController(text: accountNumber);

  final TextEditingController provider;
  final TextEditingController accountNumber;
  final providerFocusNode = FocusNode();
  final accountNumberFocusNode = FocusNode();

  void dispose() {
    provider.dispose();
    accountNumber.dispose();
    providerFocusNode.dispose();
    accountNumberFocusNode.dispose();
  }
}

class _MerchantStoreSettingsScreenState
    extends State<MerchantStoreSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _locationController = TextEditingController();
  final _shopRegionController = TextEditingController();
  final _nameFocusNode = FocusNode();
  final _phoneFocusNode = FocusNode();
  final _shopRegionFocusNode = FocusNode();
  final _addressFocusNode = FocusNode();
  final List<TextEditingController> _contactPhoneControllers = [];
  final List<_MerchantWalletControllers> _walletControllers = [];
  String _bannerPreview = '';
  UserModel? _profile;
  bool _loading = true;
  bool _saving = false;
  bool _deletingAccount = false;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _locationController.dispose();
    _shopRegionController.dispose();
    _nameFocusNode.dispose();
    _phoneFocusNode.dispose();
    _shopRegionFocusNode.dispose();
    _addressFocusNode.dispose();
    for (final controller in _contactPhoneControllers) {
      controller.dispose();
    }
    for (final controller in _walletControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickStoreBanner() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final compact = await MediaUploadService.compactImageBytes(bytes);
    if (compact == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر ضغط صورة المتجر. جرّب صورة أخرى')),
      );
      return;
    }

    final bannerUrl = await MediaUploadService.uploadImage(
      compact,
      fileName: picked.name,
      mediaType: 'profiles',
    );

    if (!mounted) return;
    if (bannerUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر رفع صورة المتجر إلى خادم الصور')),
      );
      return;
    }
    setState(() => _bannerPreview = bannerUrl);
  }

  Future<void> _loadProfile() async {
    final auth = AuthService();
    final profile = await auth.loadSession() ?? await auth.getCurrentProfile();
    if (!mounted || profile == null) {
      setState(() => _loading = false);
      return;
    }

    _nameController.text = profile.shopName ?? profile.fullName;
    _categoryController.text = profile.shopCategory ?? 'عام';
    _phoneController.text = profile.phone;
    _addressController.text = profile.address ?? '';
    _shopRegionController.text = profile.shopRegion ?? profile.city ?? '';
    _locationController.text =
        profile.shopLocation ?? profile.address ?? profile.shopLocation ?? '';
    _contactPhoneControllers
      ..clear()
      ..addAll(profile.shopContactPhones.map(
        (phone) => TextEditingController(text: phone),
      ));
    _walletControllers
      ..clear()
      ..addAll(profile.shopWallets.map(
        (wallet) => _MerchantWalletControllers(
          provider: wallet['provider'] ?? '',
          accountNumber: wallet['account_number'] ?? '',
        ),
      ));
    if (_contactPhoneControllers.isEmpty) {
      _contactPhoneControllers.add(TextEditingController());
    }
    if (_walletControllers.isEmpty) {
      _walletControllers.add(_MerchantWalletControllers());
    }
    _bannerPreview = profile.shopBannerUrl ?? '';
    setState(() {
      _profile = profile;
      _loading = false;
    });
  }

  Future<void> _deleteMerchantAccount() async {
    final profile = _profile;
    if (profile == null || profile.role != 'merchant' || _deletingAccount) {
      return;
    }
    final password = await showAccountDeletionDialog(
      context,
      accountName: (profile.shopName ?? profile.fullName).trim(),
      accountDescription: 'متجر التاجر',
    );
    if (password == null || !mounted) return;

    setState(() => _deletingAccount = true);
    try {
      await AccountDeletionService().deleteAccount(
        profileId: profile.id,
        requesterPhone: profile.phone,
        password: password,
      );
      await AuthService().clearSession();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        slideFadeRoute(page: const PhoneLoginScreen()),
        (route) => false,
      );
    } on AccountDeletionException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر حذف الحساب. حاول مرة أخرى.')),
        );
      }
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
  }

  Future<void> _changePassword() async {
    final changed = await showPasswordChangeDialog(context);
    if (!mounted || !changed) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تغيير كلمة المرور بنجاح')),
    );
  }

  void _addContactPhone() {
    setState(() => _contactPhoneControllers.add(TextEditingController()));
  }

  void _removeContactPhone(int index) {
    final controller = _contactPhoneControllers.removeAt(index);
    controller.dispose();
    setState(() {});
  }

  void _addWallet() {
    setState(() => _walletControllers.add(_MerchantWalletControllers()));
  }

  void _removeWallet(int index) {
    final controllers = _walletControllers.removeAt(index);
    controllers.dispose();
    setState(() {});
  }

  void _focusField(FocusNode focusNode) {
    final fieldContext = focusNode.context;
    if (fieldContext == null) return;
    FocusScope.of(fieldContext).requestFocus(focusNode);
    Scrollable.ensureVisible(
      fieldContext,
      duration: const Duration(milliseconds: 300),
      alignment: 0.25,
    );
  }

  void _focusFirstInvalidField() {
    if (_nameController.text.trim().isEmpty) {
      _focusField(_nameFocusNode);
      return;
    }
    if (_phoneController.text.trim().isEmpty) {
      _focusField(_phoneFocusNode);
      return;
    }
    for (final wallet in _walletControllers) {
      final hasProvider = wallet.provider.text.trim().isNotEmpty;
      final hasAccountNumber = wallet.accountNumber.text.trim().isNotEmpty;
      if (hasProvider && !hasAccountNumber) {
        _focusField(wallet.accountNumberFocusNode);
        return;
      }
      if (hasAccountNumber && !hasProvider) {
        _focusField(wallet.providerFocusNode);
        return;
      }
    }
    if (_shopRegionController.text.trim().isEmpty) {
      _focusField(_shopRegionFocusNode);
      return;
    }
    if (_addressController.text.trim().isEmpty) {
      _focusField(_addressFocusNode);
    }
  }

  Future<void> _useCurrentLocation() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw StateError('يرجى السماح للتطبيق بالوصول إلى موقعك');
      }
      if (permission == LocationPermission.deniedForever) {
        final opened = await Geolocator.openAppSettings();
        if (!opened) {
          throw StateError(
              'تم رفض الوصول إلى الموقع بشكل دائم. افتح الإعدادات يدوياً');
        }
        return;
      }

      if (!await Geolocator.isLocationServiceEnabled()) {
        final opened = await Geolocator.openLocationSettings();
        if (!opened) {
          throw StateError('يرجى تفعيل خدمة الموقع في إعدادات الجهاز');
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      final formatted =
          '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
      _locationController.text = formatted;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديد موقع المتجر الحالي تلقائيًا')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppErrorMessage.from(error)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<bool> _saveProfile() async {
    if (_saving) return false;
    setState(() => _saving = true);
    try {
      final hasIncompleteWallet = _walletControllers.any((wallet) {
        final hasProvider = wallet.provider.text.trim().isNotEmpty;
        final hasAccountNumber = wallet.accountNumber.text.trim().isNotEmpty;
        return hasProvider != hasAccountNumber;
      });
      if (hasIncompleteWallet) {
        throw StateError('أكمل اسم المحفظة ورقمها أو احذف الحقل الفارغ');
      }

      final auth = AuthService();
      final profile =
          await auth.loadSession() ?? await auth.getCurrentProfile();
      if (profile == null) {
        throw StateError('لم يتم العثور على حساب التاجر');
      }

      final updated = profile.copyWith(
        shopName: _nameController.text.trim(),
        shopCategory: _categoryController.text.trim(),
        phone: _phoneController.text.trim(),
        shopContactPhones: _contactPhoneControllers
            .map((controller) => controller.text.trim())
            .where((phone) => phone.isNotEmpty)
            .toList(),
        shopWallets: _walletControllers
            .map((wallet) => {
                  'provider': wallet.provider.text.trim(),
                  'account_number': wallet.accountNumber.text.trim(),
                })
            .where((wallet) =>
                wallet['provider']!.isNotEmpty &&
                wallet['account_number']!.isNotEmpty)
            .toList(),
        address: _addressController.text.trim(),
        shopRegion: _shopRegionController.text.trim(),
        shopLocation: _locationController.text.trim(),
        shopBannerUrl: _bannerPreview.isEmpty ? null : _bannerPreview,
      );

      await FirebaseDatabaseService.instance.update('profiles/${updated.id}', {
        'shop_name': updated.shopName,
        'shop_category': updated.shopCategory,
        'phone': updated.phone,
        'shop_contact_phones': updated.shopContactPhones,
        'shop_wallets': updated.shopWallets,
        'address': updated.address,
        'shop_region': updated.shopRegion,
        'shop_location': updated.shopLocation,
        'shop_banner': updated.shopBannerUrl,
      });
      await auth.saveSession(updated);
      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ إعدادات المتجر')),
      );
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppErrorMessage.from(error))),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات المتجر')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    Container(
                      height: 170,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF111827), Color(0xFF3B82F6)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: _bannerPreview.isNotEmpty
                          ? (MediaUploadService.isDataUri(_bannerPreview)
                              ? Image.memory(
                                  MediaUploadService.decodeDataUriToBytes(
                                          _bannerPreview) ??
                                      Uint8List(0),
                                  width: double.infinity,
                                  height: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const SizedBox(),
                                )
                              : Image(
                                  image: CachedNetworkImageProvider(
                                    _bannerPreview,
                                  ),
                                  width: double.infinity,
                                  height: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const SizedBox(),
                                ))
                          : const Center(
                              child: Text(
                                'لا توجد صورة غلاف بعد',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickStoreBanner,
                            icon: const Icon(Icons.image_rounded),
                            label: const Text('تغيير صورة المتجر'),
                          ),
                        ),
                        if (_bannerPreview.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                setState(() => _bannerPreview = '');
                              },
                              icon: const Icon(Icons.delete_outline_rounded),
                              label: const Text('إزالة'),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _nameController,
                      focusNode: _nameFocusNode,
                      decoration:
                          const InputDecoration(labelText: 'اسم المتجر *'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'هذا الحقل مطلوب'
                              : null,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _categoryController,
                      decoration:
                          const InputDecoration(labelText: 'فئة المتجر'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneController,
                      focusNode: _phoneFocusNode,
                      decoration:
                          const InputDecoration(labelText: 'رقم الهاتف *'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'هذا الحقل مطلوب'
                              : null,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'أرقام التواصل الإضافية',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    ..._contactPhoneControllers.asMap().entries.map((entry) {
                      final index = entry.key;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: entry.value,
                                keyboardType: TextInputType.phone,
                                decoration: InputDecoration(
                                  labelText: 'رقم التواصل ${index + 1}',
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'حذف الرقم',
                              onPressed: () => _removeContactPhone(index),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ],
                        ),
                      );
                    }),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: OutlinedButton.icon(
                        onPressed: _addContactPhone,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('إضافة رقم تواصل'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'أرقام المحافظ الإلكترونية لاستلام المستحقات',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    ..._walletControllers.asMap().entries.map((entry) {
                      final index = entry.key;
                      final wallet = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: wallet.provider,
                                focusNode: wallet.providerFocusNode,
                                decoration: InputDecoration(
                                  labelText: 'المحفظة ${index + 1}',
                                  hintText: 'اسم المحفظة',
                                ),
                                validator: (value) {
                                  final hasAccountNumber = wallet
                                      .accountNumber.text
                                      .trim()
                                      .isNotEmpty;
                                  return hasAccountNumber &&
                                          (value == null ||
                                              value.trim().isEmpty)
                                      ? 'هذا الحقل مطلوب'
                                      : null;
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: wallet.accountNumber,
                                focusNode: wallet.accountNumberFocusNode,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  labelText: 'رقم المحفظة',
                                ),
                                validator: (value) {
                                  final hasProvider =
                                      wallet.provider.text.trim().isNotEmpty;
                                  return hasProvider &&
                                          (value == null ||
                                              value.trim().isEmpty)
                                      ? 'هذا الحقل مطلوب'
                                      : null;
                                },
                              ),
                            ),
                            IconButton(
                              tooltip: 'حذف المحفظة',
                              onPressed: () => _removeWallet(index),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ],
                        ),
                      );
                    }),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: OutlinedButton.icon(
                        onPressed: _addWallet,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('إضافة محفظة إلكترونية'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _locationController,
                      readOnly: true,
                      onTap: _isLocating ? null : _useCurrentLocation,
                      decoration: const InputDecoration(
                        labelText: 'موقع المتجر',
                        hintText: '24.713600, 46.675300',
                        suffixIcon: Icon(Icons.lock_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isLocating ? null : _useCurrentLocation,
                            icon: _isLocating
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.my_location_rounded),
                            label: Text(
                              _isLocating
                                  ? 'جارٍ تحديد الموقع...'
                                  : 'تحديد الموقع الحالي',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue:
                          yemeniCities.contains(_shopRegionController.text)
                              ? _shopRegionController.text
                              : null,
                      isExpanded: true,
                      focusNode: _shopRegionFocusNode,
                      decoration: const InputDecoration(
                        labelText: 'مدينة المتجر *',
                        hintText: 'اختر مدينة المتجر',
                        helperText: 'تُستخدم لتحديد سعر التوصيل حسب المدينة.',
                      ),
                      items: yemeniCities
                          .map((city) => DropdownMenuItem(
                                value: city,
                                child: Text(city),
                              ))
                          .toList(),
                      onChanged: (city) {
                        if (city != null) {
                          _shopRegionController.text = city;
                        }
                      },
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'هذا الحقل مطلوب'
                              : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _addressController,
                      focusNode: _addressFocusNode,
                      minLines: 3,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'عنوان المتجر *',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'هذا الحقل مطلوب'
                              : null,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'أمان الحساب',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _changePassword,
                      icon: const Icon(Icons.lock_reset_rounded),
                      label: const Text('تغيير كلمة المرور'),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _saving
                          ? null
                          : () async {
                              if (!_formKey.currentState!.validate()) {
                                _focusFirstInvalidField();
                                return;
                              }
                              final navigator = Navigator.of(context);
                              final saved = await _saveProfile();
                              if (!mounted) return;
                              if (saved) navigator.pop();
                            },
                      icon: const Icon(Icons.save_rounded),
                      label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ التغييرات'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _deletingAccount || _saving
                          ? null
                          : _deleteMerchantAccount,
                      icon: const Icon(Icons.delete_forever_rounded),
                      label: Text(
                        _deletingAccount
                            ? 'جارٍ حذف الحساب...'
                            : 'حذف حساب المتجر نهائياً',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFB91C1C),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class MerchantWalletScreen extends StatefulWidget {
  const MerchantWalletScreen({super.key});

  @override
  State<MerchantWalletScreen> createState() => _MerchantWalletScreenState();
}

class _MerchantWalletScreenState extends State<MerchantWalletScreen> {
  final _walletService = MerchantWalletService();
  late Future<MerchantWalletSnapshot> _walletFuture;
  String _merchantId = '';

  @override
  void initState() {
    super.initState();
    _walletFuture = _loadWallet();
  }

  Future<MerchantWalletSnapshot> _loadWallet() async {
    final profile = await AuthService().loadSession() ??
        await AuthService().getCurrentProfile();
    _merchantId = profile?.id.trim() ?? '';
    return _walletService.load(_merchantId);
  }

  void _refresh() {
    setState(() => _walletFuture = _loadWallet());
  }

  Future<void> _requestWithdrawal(MerchantWalletSnapshot wallet) async {
    final amountController = TextEditingController();
    final nameController = TextEditingController();
    final accountController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final profile = await AuthService().loadSession() ??
        await AuthService().getCurrentProfile();
    if (!mounted) return;
    final savedWallets = profile?.shopWallets ?? const [];
    int? selectedWalletIndex = savedWallets.isEmpty ? null : 0;
    if (selectedWalletIndex != null) {
      nameController.text = savedWallets.first['provider'] ?? '';
      accountController.text = savedWallets.first['account_number'] ?? '';
    }
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('طلب سحب رصيد'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                      'المتاح للسحب: ${wallet.withdrawableBalance.toStringAsFixed(2)} ${wallet.currencySymbol}'),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'المبلغ'),
                    validator: (value) {
                      final amount = double.tryParse(value?.trim() ?? '');
                      return amount == null || !amount.isFinite || amount <= 0
                          ? 'أدخل مبلغًا صحيحًا'
                          : null;
                    },
                  ),
                  if (savedWallets.isNotEmpty)
                    DropdownButtonFormField<int>(
                      initialValue: selectedWalletIndex,
                      decoration:
                          const InputDecoration(labelText: 'محفظة محفوظة'),
                      items: [
                        for (var index = 0;
                            index < savedWallets.length;
                            index++)
                          DropdownMenuItem(
                            value: index,
                            child: Text(
                              '${savedWallets[index]['provider']}: '
                              '${savedWallets[index]['account_number']}',
                            ),
                          ),
                      ],
                      onChanged: (index) {
                        if (index == null) return;
                        setDialogState(() {
                          selectedWalletIndex = index;
                          nameController.text =
                              savedWallets[index]['provider'] ?? '';
                          accountController.text =
                              savedWallets[index]['account_number'] ?? '';
                        });
                      },
                    ),
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'اسم المحفظة'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'أدخل اسم المحفظة'
                        : null,
                  ),
                  TextFormField(
                    controller: accountController,
                    decoration: const InputDecoration(
                        labelText: 'رقم الحساب أو المحفظة'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'أدخل رقم الحساب'
                        : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final amount = double.parse(amountController.text.trim());
                if (amount > wallet.withdrawableBalance) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('المبلغ يتجاوز الرصيد القابل للسحب')),
                  );
                  return;
                }
                try {
                  final request = await _walletService.requestWithdrawal(
                    merchantId: _merchantId,
                    amount: amount,
                    currencySymbol: wallet.currencySymbol,
                    accountName: nameController.text,
                    accountNumber: accountController.text,
                  );
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext, request != null);
                } catch (error) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text(AppErrorMessage.from(error))),
                  );
                }
              },
              child: const Text('إرسال الطلب'),
            ),
          ],
        ),
      ),
    );
    amountController.dispose();
    nameController.dispose();
    accountController.dispose();
    if (submitted == true && mounted) {
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال طلب السحب للمراجعة')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('محفظة التاجر'),
          actions: [
            IconButton(
                onPressed: _refresh, icon: const Icon(Icons.refresh_rounded))
          ],
        ),
        body: FutureBuilder<MerchantWalletSnapshot>(
          future: _walletFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cloud_off_rounded,
                        size: 44,
                        color: Color(0xFFB91C1C),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'تعذر تحميل بيانات المحفظة',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppErrorMessage.from(snapshot.error!),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final wallet = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _WalletBalanceCard(
                  title: 'القابل للسحب الآن',
                  value: wallet.withdrawableBalance,
                  symbol: wallet.currencySymbol,
                  color: const Color(0xFF047857),
                  icon: Icons.payments_rounded,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                        child: _WalletMetric(
                            title: 'مبيعات معلقة',
                            value: wallet.pendingSales,
                            symbol: wallet.currencySymbol)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _WalletMetric(
                            title: 'إجمالي المبيعات',
                            value: wallet.totalSales,
                            symbol: wallet.currencySymbol)),
                  ],
                ),
                if (wallet.unconvertedOrderCount > 0) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: const Color(0xFFFFFBEB),
                    child: ListTile(
                      leading: const Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFB45309),
                      ),
                      title: const Text('طلبات لم تُحتسب في الرصيد'),
                      subtitle: Text(
                        'تعذر تحويل قيمة ${wallet.unconvertedOrderCount} طلب. '
                        'يرجى مراجعة أسعار الصرف أو بيانات المنتجات مع الإدارة.',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.schedule_rounded,
                        color: Color(0xFFD97706)),
                    title: const Text('فترة حماية العميل'),
                    subtitle: Text(
                        '${wallet.pendingOrders} طلب بانتظار التسليم أو اكتمال فترة الحماية'),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: wallet.withdrawableBalance > 0
                      ? () => _requestWithdrawal(wallet)
                      : null,
                  icon: const Icon(Icons.request_page_rounded),
                  label: const Text('طلب سحب الرصيد'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'تنتقل قيمة البيع إلى الرصيد القابل للسحب بعد تسليم الطلب ومرور 3 أيام دون استرداد. كل طلب سحب يخضع لمراجعة المسؤول.',
                  style: TextStyle(color: Color(0xFF6B7280), height: 1.5),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WalletBalanceCard extends StatelessWidget {
  const _WalletBalanceCard(
      {required this.title,
      required this.value,
      required this.symbol,
      required this.color,
      required this.icon});
  final String title;
  final double value;
  final String symbol;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
                color: color.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 8))
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 34),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 5),
              Text('${value.toStringAsFixed(2)} $symbol',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w900)),
            ]),
          ],
        ),
      );
}

class _WalletMetric extends StatelessWidget {
  const _WalletMetric(
      {required this.title, required this.value, required this.symbol});
  final String title;
  final double value;
  final String symbol;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
            const SizedBox(height: 5),
            Text('${value.toStringAsFixed(2)} $symbol',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
        ),
      );
}

class MerchantReportsScreen extends StatefulWidget {
  const MerchantReportsScreen({
    super.key,
    this.currencySymbol = 'ر.ي',
  });

  final String currencySymbol;

  @override
  State<MerchantReportsScreen> createState() => _MerchantReportsScreenState();
}

class _MerchantReportsScreenState extends State<MerchantReportsScreen> {
  late Future<List<Map<String, dynamic>>> _ordersFuture;

  @override
  void initState() {
    super.initState();
    _ordersFuture = _loadOrders();
  }

  void _refresh() {
    setState(() => _ordersFuture = _loadOrders());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _ordersFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('التقارير والحسابات')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cloud_off_rounded,
                      size: 44,
                      color: Color(0xFFB91C1C),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'تعذر تحميل تقارير المتجر',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppErrorMessage.from(snapshot.error!),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('التقارير والحسابات')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final orders = snapshot.data ?? const <Map<String, dynamic>>[];
        final totalRevenue = orders.fold<double>(0, (sum, order) {
          if (!MerchantOrderAccounting.countsAsSale(order)) return sum;
          final value = order['report_total_yer'];
          return sum + (value is num ? value.toDouble() : 0);
        });
        final unconvertedOrderCount = orders
            .where(MerchantOrderAccounting.countsAsSale)
            .where((order) => order['report_total_yer'] == null)
            .length;
        final activeOrders = orders.where((order) {
          final status = (order['status'] ?? '').toString();
          return status == 'preparing' ||
              status == 'shipped' ||
              status == 'confirmed' ||
              status == 'accepted';
        }).length;
        final pendingOrders = orders.where((order) {
          final status = (order['status'] ?? '').toString();
          return status == 'new' ||
              status == 'pending_payment' ||
              status == 'awaiting_confirmation';
        }).length;

        return Scaffold(
          appBar: AppBar(
            title: const Text('التقارير والحسابات'),
            actions: [
              IconButton(
                tooltip: 'تحديث التقارير',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.3,
                children: [
                  _MetricCard(
                    label: 'إيراد المبيعات',
                    value: '${totalRevenue.round()} ${widget.currencySymbol}',
                    color: const Color(0xFF10B981),
                    icon: Icons.trending_up_rounded,
                  ),
                  if (unconvertedOrderCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        'تعذّر تحويل قيمة $unconvertedOrderCount طلب إلى الريال اليمني. '
                        'تأكد من إدخال أسعار الصرف أو مراجعة الطلبات القديمة متعددة العملات.',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  _MetricCard(
                    label: 'الطلبات',
                    value: orders.length.toString(),
                    color: const Color(0xFF3B82F6),
                    icon: Icons.receipt_long_rounded,
                  ),
                  _MetricCard(
                    label: 'قيد التنفيذ',
                    value: activeOrders.toString(),
                    color: const Color(0xFF8B5CF6),
                    icon: Icons.local_shipping_rounded,
                  ),
                  _MetricCard(
                    label: 'معلقة',
                    value: pendingOrders.toString(),
                    color: const Color(0xFFF59E0B),
                    icon: Icons.pending_actions_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'ملخص الطلبات',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 12),
              if (orders.isEmpty)
                const _EmptyState(message: 'لا توجد بيانات تقارير حاليًا')
              else
                ...orders.take(8).map((order) {
                  final id = OrderNumber.fromOrder(order);
                  final amount = _merchantOrderTotalLabel(order);
                  final status =
                      (order['status'] ?? 'pending_payment').toString();
                  return ListTile(
                    title: Text(
                      'الطلب $id',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      DeliveryService.statusLabel(status),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 100),
                      child: Text(
                        amount,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _loadOrders() async {
    final auth = AuthService();
    final profile = await auth.loadSession() ?? await auth.getCurrentProfile();
    if (profile == null) return const <Map<String, dynamic>>[];

    final snapshot = await FirebaseDatabaseService.instance.read('orders');
    final orders = snapshot.values
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    final productsSnapshot =
        await FirebaseDatabaseService.instance.read('products');
    final productOwners = OrderService.productOwnersById(productsSnapshot);
    final merchantProductIds = productOwners.entries
        .where((entry) => entry.value == profile.id)
        .map((entry) => entry.key)
        .toSet();
    final merchantOrders = MerchantManagementScreen.filterOrdersForMerchant(
      merchantId: profile.id,
      orders: orders,
      productOwners: productOwners,
      merchantProductIds: merchantProductIds,
    );
    final currencies = await CurrencyService().getCurrencies();
    return merchantOrders.map((order) {
      final converted = merchantProductsTotalInYER(
        order,
        merchantId: profile.id,
        productOwners: productOwners,
        merchantProductIds: merchantProductIds,
        currencies: currencies,
      );
      return {
        ...order,
        if (converted != null) 'report_total_yer': converted,
      };
    }).toList();
  }
}

class _ProductCard extends StatelessWidget {
  final String label;
  final String price;
  final String stock;
  final bool active;
  final VoidCallback? onTap;

  const _ProductCard({
    required this.label,
    required this.price,
    required this.stock,
    required this.active,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.image_rounded, color: Color(0xFF3B82F6)),
                const Spacer(),
                Flexible(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 110),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: active
                          ? const Color(0xFF10B981).withValues(alpha: 0.12)
                          : const Color(0xFFF59E0B).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      active ? 'متوفر' : 'غير متوفر',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: active
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF59E0B),
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              price,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF3B82F6),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'المخزون: $stock',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class MerchantDashboardData {
  final String merchantName;
  final String merchantCategory;
  final String merchantPhone;
  final String shopAddress;
  final String? bannerUrl;
  final double? shopLatitude;
  final double? shopLongitude;
  final double totalRevenue;
  final int unconvertedOrderCount;
  final String currencySymbol;
  final int totalOrders;
  final int activeOrders;
  final int pendingOrders;
  final int productCount;
  final List<Map<String, dynamic>> recentOrders;

  const MerchantDashboardData({
    required this.merchantName,
    required this.merchantCategory,
    required this.merchantPhone,
    required this.shopAddress,
    this.bannerUrl,
    required this.shopLatitude,
    required this.shopLongitude,
    required this.totalRevenue,
    this.unconvertedOrderCount = 0,
    this.currencySymbol = 'ر.ي',
    required this.totalOrders,
    required this.activeOrders,
    required this.pendingOrders,
    this.productCount = 0,
    required this.recentOrders,
  });

  MerchantDashboardData copyWith({
    String? merchantName,
    String? merchantCategory,
    String? merchantPhone,
    String? shopAddress,
    String? bannerUrl,
    double? shopLatitude,
    double? shopLongitude,
    double? totalRevenue,
    int? unconvertedOrderCount,
    String? currencySymbol,
    int? totalOrders,
    int? activeOrders,
    int? pendingOrders,
    int? productCount,
    List<Map<String, dynamic>>? recentOrders,
  }) {
    return MerchantDashboardData(
      merchantName: merchantName ?? this.merchantName,
      merchantCategory: merchantCategory ?? this.merchantCategory,
      merchantPhone: merchantPhone ?? this.merchantPhone,
      shopAddress: shopAddress ?? this.shopAddress,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      shopLatitude: shopLatitude ?? this.shopLatitude,
      shopLongitude: shopLongitude ?? this.shopLongitude,
      totalRevenue: totalRevenue ?? this.totalRevenue,
      unconvertedOrderCount:
          unconvertedOrderCount ?? this.unconvertedOrderCount,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      totalOrders: totalOrders ?? this.totalOrders,
      activeOrders: activeOrders ?? this.activeOrders,
      pendingOrders: pendingOrders ?? this.pendingOrders,
      productCount: productCount ?? this.productCount,
      recentOrders: recentOrders ?? this.recentOrders,
    );
  }

  static MerchantDashboardData buildFromProfile({
    UserModel? sessionProfile,
    required List<Map<String, dynamic>> orders,
    Map<String, dynamic>? merchantProfile,
    List<CurrencyOption> currencies = const [],
    Map<String, String> productOwners = const {},
    Set<String> merchantProductIds = const {},
  }) {
    final effectiveMerchantProfile = sessionProfile == null
        ? merchantProfile
        : {
            'id': sessionProfile.id,
            'full_name': sessionProfile.fullName,
            'phone': sessionProfile.phone,
            'shop_name': sessionProfile.shopName,
            'shop_category': sessionProfile.shopCategory,
            'shop_location': sessionProfile.shopLocation,
            'address': sessionProfile.address,
          };

    final merchant = effectiveMerchantProfile ?? const <String, dynamic>{};

    final ordersWithYERValues =
        sortMerchantOrdersNewestFirst(orders).map((order) {
      final totalInYER = merchantProductsTotalInYER(
        order,
        merchantId:
            sessionProfile?.id ?? (merchantProfile?['id'] ?? '').toString(),
        productOwners: productOwners,
        merchantProductIds: merchantProductIds,
        currencies: currencies,
      );
      return {
        ...order,
        if (totalInYER != null) 'report_total_yer': totalInYER,
      };
    }).toList();
    final totalRevenue = ordersWithYERValues.fold<double>(
      0,
      (sum, order) => MerchantOrderAccounting.countsAsSale(order)
          ? sum + ((order['report_total_yer'] as num?)?.toDouble() ?? 0)
          : sum,
    );
    final unconvertedOrderCount = ordersWithYERValues
        .where(MerchantOrderAccounting.countsAsSale)
        .where((order) => order['report_total_yer'] == null)
        .length;

    final activeOrders = orders.where((order) {
      final status = (order['status'] ?? '').toString();
      return status == 'preparing' ||
          status == 'shipped' ||
          status == 'confirmed' ||
          status == 'accepted';
    }).length;

    final pendingOrders = orders.where((order) {
      final status = (order['status'] ?? '').toString();
      return status == 'new' ||
          status == 'pending_payment' ||
          status == 'awaiting_confirmation';
    }).length;

    double? lat;
    double? lng;
    var shopAddress = 'لم يتم إدخال عنوان المتجر';

    final locationText =
        (merchant['shop_location'] ?? sessionProfile?.shopLocation)?.toString();
    final parsedLocation = MerchantStoreSettingsScreen.parseLocationFromText(
      locationText,
    );

    final latVal = merchant['latitude'];
    final lngVal = merchant['longitude'];
    if (latVal is num) lat = latVal.toDouble();
    if (lngVal is num) lng = lngVal.toDouble();
    if (latVal is String) lat = double.tryParse(latVal);
    if (lngVal is String) lng = double.tryParse(lngVal);
    if (parsedLocation != null) {
      lat ??= parsedLocation['latitude'];
      lng ??= parsedLocation['longitude'];
    }

    final rawAddress = merchant['address']?.toString();
    if (rawAddress != null && rawAddress.isNotEmpty) {
      shopAddress = rawAddress;
    } else if (merchant['shop_location'] != null) {
      shopAddress = merchant['shop_location'].toString();
    }

    final merchantName =
        merchant['shop_name']?.toString().trim().isNotEmpty == true
            ? merchant['shop_name'].toString().trim()
            : 'اسم المتجر غير متوفر';
    final merchantCategory =
        merchant['shop_category']?.toString().trim().isNotEmpty == true
            ? merchant['shop_category'].toString().trim()
            : 'الفئة غير محددة';
    final merchantPhone =
        merchant['phone']?.toString().trim().isNotEmpty == true
            ? merchant['phone'].toString().trim()
            : 'رقم الهاتف غير متوفر';
    final bannerUrl = merchant['shop_banner']?.toString() ??
        sessionProfile?.shopBannerUrl ??
        '';

    return MerchantDashboardData(
      merchantName: merchantName,
      merchantCategory: merchantCategory,
      merchantPhone: merchantPhone,
      shopAddress:
          merchant['shop_location']?.toString().trim().isNotEmpty == true
              ? merchant['shop_location'].toString().trim()
              : shopAddress,
      bannerUrl: bannerUrl.isNotEmpty ? bannerUrl : null,
      shopLatitude: lat,
      shopLongitude: lng,
      totalRevenue: totalRevenue,
      unconvertedOrderCount: unconvertedOrderCount,
      activeOrders: activeOrders,
      pendingOrders: pendingOrders,
      totalOrders: orders.length,
      recentOrders: ordersWithYERValues,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;

  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.receipt_long_outlined,
            size: 42,
            color: Color(0xFF9CA3AF),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final valueFontSize = constraints.maxWidth < 130 ? 18.0 : 22.0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              Text(
                value,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  fontSize: valueFontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 12,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  final VoidCallback? onTap;

  const _ActionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncomingMerchantOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback onTap;

  const _IncomingMerchantOrderCard({
    required this.order,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final orderId = OrderNumber.fromOrder(order);
    final total = _merchantOrderTotalLabel(order);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF3E8C8)),
          ),
          child: Row(
            children: [
              MerchantOrderProductThumbnails(
                orderId: orderId,
                imageUrls: _merchantOrderImageUrls(order),
                size: 42,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'الطلب $orderId',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF111827),
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'جديد',
                          style: TextStyle(
                            color: Color(0xFFB45309),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      merchantOrderItemsSummary(order),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      formatMerchantOrderDateTime(order),
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 105),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      total,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 13,
                      color: Color(0xFF9CA3AF),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  final String orderId;
  final String customer;
  final String total;
  final String status;
  final Color statusColor;
  final List<String> productImages;
  final VoidCallback? onTap;

  const _OrderRow({
    required this.orderId,
    required this.customer,
    required this.total,
    required this.status,
    required this.statusColor,
    this.productImages = const [],
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MerchantOrderProductThumbnails(
                orderId: orderId,
                imageUrls: productImages,
                size: 48,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الطلب $orderId',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      customer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      total,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MerchantProductVideoPreviewDialog extends StatefulWidget {
  const _MerchantProductVideoPreviewDialog({
    required this.filePath,
    required this.videoUrl,
  });

  final String? filePath;
  final String videoUrl;

  @override
  State<_MerchantProductVideoPreviewDialog> createState() =>
      _MerchantProductVideoPreviewDialogState();
}

class _MerchantProductVideoPreviewDialogState
    extends State<_MerchantProductVideoPreviewDialog> {
  VideoPlayerController? _controller;
  ProductVideoControllerLease? _videoLease;
  String? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeVideo());
  }

  Future<void> _initializeVideo() async {
    final lease = widget.filePath != null
        ? ProductVideoCache.acquireFile(widget.filePath!)
        : _networkLease();
    if (lease == null) {
      setState(() {
        _error = 'رابط الفيديو غير صالح';
        _isLoading = false;
      });
      return;
    }

    _videoLease = lease;
    final controller = lease.controller;
    _controller = controller;
    controller.addListener(_handleControllerUpdate);
    try {
      if (!controller.value.isInitialized) {
        await controller.initialize();
      }
      if (!controller.value.isLooping) await controller.setLooping(true);
      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (error, stackTrace) {
      debugPrint('Could not initialize merchant product video preview: $error');
      debugPrintStack(stackTrace: stackTrace);
      ProductVideoCache.invalidate(lease);
      if (!mounted) return;
      setState(() {
        _error = 'تعذر تشغيل معاينة الفيديو';
        _isLoading = false;
      });
    }
  }

  ProductVideoControllerLease? _networkLease() {
    final uri = Uri.tryParse(widget.videoUrl.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    return ProductVideoCache.acquireNetwork(uri.toString());
  }

  void _handleControllerUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    controller?.removeListener(_handleControllerUpdate);
    final lease = _videoLease;
    if (lease != null) {
      unawaited(ProductVideoCache.release(lease));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final aspectRatio = controller != null &&
            controller.value.isInitialized &&
            controller.value.aspectRatio > 0
        ? controller.value.aspectRatio
        : 16 / 9;

    return AlertDialog(
      title: const Text('معاينة الفيديو'),
      content: SizedBox(
        width: 480,
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: ColoredBox(
            color: Colors.black,
            child: _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  )
                : _isLoading ||
                        controller == null ||
                        !controller.value.isInitialized
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : Stack(
                        alignment: Alignment.center,
                        children: [
                          VideoPlayer(controller),
                          Positioned(
                            left: 8,
                            right: 8,
                            bottom: 4,
                            child: Row(
                              children: [
                                IconButton(
                                  tooltip: controller.value.isPlaying
                                      ? 'إيقاف مؤقت'
                                      : 'تشغيل الفيديو',
                                  onPressed: _togglePlayback,
                                  color: Colors.white,
                                  icon: Icon(
                                    controller.value.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                  ),
                                ),
                                Expanded(
                                  child: VideoProgressIndicator(
                                    controller,
                                    allowScrubbing: true,
                                    colors: const VideoProgressColors(
                                      playedColor: Colors.pink,
                                      bufferedColor: Colors.white54,
                                      backgroundColor: Colors.white24,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إغلاق'),
        ),
      ],
    );
  }
}
