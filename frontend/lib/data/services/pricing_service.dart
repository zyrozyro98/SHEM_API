import 'dart:math' as math;

import 'package:she_m_app/data/models/product_model.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';

class FreeDeliveryRule {
  final String type;
  final double threshold;

  const FreeDeliveryRule({required this.type, required this.threshold});

  factory FreeDeliveryRule.fromJson(Map<String, dynamic> json) {
    return FreeDeliveryRule(
      type: json['type']?.toString() ?? '',
      threshold: double.tryParse(json['threshold']?.toString() ?? '') ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'threshold': threshold,
      };
}

class PricingConfig {
  final String commissionMode;
  final double commissionValue;
  final Map<String, double> commissionByCategory;
  final Map<String, double> commissionByMerchant;
  final double vatRate;
  final Map<String, double> vatByCategory;
  final Set<String> vatExemptProductIds;
  final Set<String> vatExemptMerchantIds;
  final String deliveryMode;
  final double deliveryValue;
  final double deliveryBaseFee;
  final double deliveryPerKm;
  final double fallbackDistanceKm;
  final double? merchantDisplayDeliveryFee;
  final Map<String, double> deliveryByRegion;
  final Map<String, double> deliveryByMerchantRegion;
  final Set<String> deliveryExemptProductIds;
  final Set<String> deliveryExemptMerchantIds;
  final List<FreeDeliveryRule> freeDeliveryRules;

  const PricingConfig({
    this.commissionMode = 'percent',
    this.commissionValue = 10,
    this.commissionByCategory = const {},
    this.commissionByMerchant = const {},
    this.vatRate = 0,
    this.vatByCategory = const {},
    this.vatExemptProductIds = const {},
    this.vatExemptMerchantIds = const {},
    this.deliveryMode = 'distance',
    this.deliveryValue = 0,
    this.deliveryBaseFee = 1500,
    this.deliveryPerKm = 65,
    this.fallbackDistanceKm = 12,
    this.merchantDisplayDeliveryFee,
    this.deliveryByRegion = const {},
    this.deliveryByMerchantRegion = const {},
    this.deliveryExemptProductIds = const {},
    this.deliveryExemptMerchantIds = const {},
    this.freeDeliveryRules = const [],
  });

  factory PricingConfig.fromJson(Map<String, dynamic> json) {
    Map<String, double> numberMap(Object? raw) {
      final result = <String, double>{};
      if (raw is Map) {
        for (final entry in raw.entries) {
          final key = entry.key.toString().trim();
          final value = double.tryParse(entry.value.toString());
          if (key.isNotEmpty && value != null) result[key] = value;
        }
      }
      return result;
    }

    final rawCategories = json['commission_by_category'];
    final categories = <String, double>{};
    if (rawCategories is Map) {
      for (final entry in rawCategories.entries) {
        final value = double.tryParse(entry.value.toString());
        if (value != null) categories[entry.key.toString()] = value;
      }
    }
    final merchantCommissions = numberMap(json['commission_by_merchant']);
    final rawVatCategories = json['vat_by_category'];
    final vatCategories = <String, double>{};
    if (rawVatCategories is Map) {
      for (final entry in rawVatCategories.entries) {
        final value = double.tryParse(entry.value.toString());
        if (value != null) vatCategories[entry.key.toString()] = value;
      }
    }
    Set<String> stringSet(Object? value) => value is Iterable
        ? value
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toSet()
        : <String>{};
    double number(String key, double fallback) =>
        double.tryParse(json[key]?.toString() ?? '') ?? fallback;
    double? optionalNonNegativeNumber(String key) {
      final value = double.tryParse(json[key]?.toString() ?? '');
      return value != null && value.isFinite && value >= 0 ? value : null;
    }

    return PricingConfig(
      commissionMode: json['commission_mode']?.toString() ?? 'percent',
      commissionValue: number('commission_value', 10),
      commissionByCategory: categories,
      commissionByMerchant: merchantCommissions,
      vatRate: number('vat_rate', 0),
      vatByCategory: vatCategories,
      vatExemptProductIds: stringSet(json['vat_exempt_product_ids']),
      vatExemptMerchantIds: stringSet(json['vat_exempt_merchant_ids']),
      deliveryMode: json['delivery_mode']?.toString() ?? 'distance',
      deliveryValue: number('delivery_value', 0),
      deliveryBaseFee: number('delivery_base_fee', 1500),
      deliveryPerKm: number('delivery_per_km', 65),
      merchantDisplayDeliveryFee:
          optionalNonNegativeNumber('merchant_display_delivery_fee'),
      fallbackDistanceKm: number('fallback_distance_km', 12),
      deliveryByRegion: numberMap(json['delivery_by_region']),
      deliveryByMerchantRegion: numberMap(json['delivery_by_merchant_region']),
      deliveryExemptProductIds: stringSet(json['delivery_exempt_product_ids']),
      deliveryExemptMerchantIds:
          stringSet(json['delivery_exempt_merchant_ids']),
      freeDeliveryRules: json['free_delivery_rules'] is Iterable
          ? (json['free_delivery_rules'] as Iterable)
              .whereType<Map>()
              .map((rule) =>
                  FreeDeliveryRule.fromJson(Map<String, dynamic>.from(rule)))
              .where((rule) =>
                  const {
                    'vat_any',
                    'commission_any',
                    'subtotal_single_merchant',
                    'vat_multi_merchant',
                    'commission_multi_merchant',
                  }.contains(rule.type) &&
                  rule.threshold >= 0 &&
                  rule.threshold.isFinite)
              .toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'commission_mode': commissionMode,
        'commission_value': commissionValue,
        'commission_by_category': commissionByCategory,
        'commission_by_merchant': commissionByMerchant,
        'delivery_mode': deliveryMode,
        'delivery_value': deliveryValue,
        'delivery_base_fee': deliveryBaseFee,
        'delivery_per_km': deliveryPerKm,
        if (merchantDisplayDeliveryFee != null)
          'merchant_display_delivery_fee': merchantDisplayDeliveryFee,
        'fallback_distance_km': fallbackDistanceKm,
        'delivery_by_region': deliveryByRegion,
        'delivery_by_merchant_region': deliveryByMerchantRegion,
        'delivery_exempt_product_ids': deliveryExemptProductIds.toList(),
        'delivery_exempt_merchant_ids': deliveryExemptMerchantIds.toList(),
        'free_delivery_rules':
            freeDeliveryRules.map((rule) => rule.toJson()).toList(),
      };
}

class PricingService {
  static const _path = 'settings/pricing';
  final DatabaseService _database;

  PricingService({DatabaseService? database})
      : _database = database ?? FirebaseDatabaseService.instance;

  Future<PricingConfig> load() async {
    try {
      final value = await _database.read(_path);
      return value.isEmpty
          ? const PricingConfig()
          : PricingConfig.fromJson(value);
    } catch (_) {
      return const PricingConfig();
    }
  }

  Future<bool> save(PricingConfig config) async {
    if (!{'percent', 'fixed'}.contains(config.commissionMode) ||
        !config.commissionValue.isFinite ||
        config.commissionValue < 0 ||
        config.commissionByCategory.values.any(
          (rate) => !rate.isFinite || rate < 0,
        ) ||
        config.commissionByMerchant.values.any(
          (rate) => !rate.isFinite || rate < 0,
        ) ||
        config.deliveryValue < 0 ||
        config.deliveryBaseFee < 0 ||
        config.deliveryPerKm < 0 ||
        !config.deliveryValue.isFinite ||
        !config.deliveryBaseFee.isFinite ||
        !config.deliveryPerKm.isFinite ||
        (config.merchantDisplayDeliveryFee != null &&
            (!config.merchantDisplayDeliveryFee!.isFinite ||
                config.merchantDisplayDeliveryFee! < 0)) ||
        config.deliveryByRegion.values.any(
          (fee) => !fee.isFinite || fee < 0,
        ) ||
        config.deliveryByMerchantRegion.values.any(
          (fee) => !fee.isFinite || fee < 0,
        ) ||
        config.freeDeliveryRules.any(
          (rule) => !rule.threshold.isFinite || rule.threshold < 0,
        )) {
      return false;
    }
    try {
      await _database.write(_path, config.toJson());
      return true;
    } catch (_) {
      return false;
    }
  }

  static double vatRateForProduct({
    required PricingConfig config,
    required String productId,
    required String merchantId,
    required String category,
    double? productRateOverride,
    bool productExempt = false,
  }) {
    return 0;
  }

  static ({String mode, double value}) commissionForProduct({
    required PricingConfig config,
    required ProductModel product,
  }) {
    if (product.commissionModeOverride != null &&
        product.commissionValueOverride != null) {
      return (
        mode: product.commissionModeOverride!,
        value: product.commissionValueOverride!,
      );
    }
    final merchantValue = config.commissionByMerchant[product.merchantId];
    if (merchantValue != null) {
      return (mode: config.commissionMode, value: merchantValue);
    }
    return (
      mode: config.commissionMode,
      value: config.commissionByCategory[product.category] ??
          config.commissionValue,
    );
  }

  static double commissionForProducts(
    Iterable<ProductModel> products,
    Iterable<int> quantities,
    PricingConfig config,
  ) {
    var total = 0.0;
    var index = 0;
    for (final product in products) {
      final quantity = quantities.elementAt(index++);
      final resolved = commissionForProduct(config: config, product: product);
      final rateOrAmount = product.effectiveCommissionValue ?? resolved.value;
      final commissionMode = product.effectiveCommissionMode ?? resolved.mode;
      total += ProductModel.commissionAmountForPrice(
            price: product.price,
            mode: commissionMode,
            value: rateOrAmount,
          ) *
          quantity;
    }
    return total;
  }

  static double commissionIncludedInProductPrices(
    Iterable<ProductModel> products,
    Iterable<int> quantities,
  ) {
    var total = 0.0;
    var index = 0;
    for (final product in products) {
      total += product.commissionAmount * quantities.elementAt(index++);
    }
    return total;
  }

  static double deliveryFee({
    required double subtotal,
    required double distanceKm,
    required PricingConfig config,
    String customerRegion = '',
    Iterable<String> merchantRegions = const [],
    Iterable<String> productIds = const [],
    Iterable<String> merchantIds = const [],
    double commission = 0,
  }) {
    final normalizedProducts =
        productIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet();
    final normalizedMerchants =
        merchantIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet();
    final normalizedRegions = merchantRegions
        .map((region) => region.trim())
        .where((region) => region.isNotEmpty)
        .toSet();
    final merchantCount = normalizedMerchants.length;
    final hasDeliveryExemption = normalizedProducts
            .intersection(config.deliveryExemptProductIds)
            .isNotEmpty ||
        normalizedMerchants
            .intersection(config.deliveryExemptMerchantIds)
            .isNotEmpty;

    if (!hasDeliveryExemption &&
        config.freeDeliveryRules.any((rule) {
          switch (rule.type) {
            case 'vat_any':
            case 'commission_any':
              return commission > rule.threshold;
            case 'subtotal_single_merchant':
              return merchantCount == 1 && subtotal > rule.threshold;
            case 'vat_multi_merchant':
            case 'commission_multi_merchant':
              return merchantCount > 1 && commission > rule.threshold;
            default:
              return false;
          }
        })) {
      return 0;
    }

    switch (config.deliveryMode) {
      case 'fixed':
        return config.deliveryValue;
      case 'percent':
        return subtotal * config.deliveryValue / 100;
      case 'region':
        return config.deliveryByRegion[customerRegion.trim()] ??
            config.deliveryValue;
      case 'merchant_region':
        if (hasDeliveryExemption) {
          return config.deliveryBaseFee +
              math.max(0, distanceKm) * config.deliveryPerKm;
        }
        final matchingFees = normalizedRegions
            .where(config.deliveryByMerchantRegion.containsKey)
            .map((region) => config.deliveryByMerchantRegion[region]!)
            .toList();
        return matchingFees.isEmpty
            ? config.deliveryBaseFee +
                math.max(0, distanceKm) * config.deliveryPerKm
            : matchingFees.reduce(
                (first, second) => math.max(first, second).toDouble(),
              );
      case 'distance':
      default:
        return config.deliveryBaseFee +
            math.max(0, distanceKm) * config.deliveryPerKm;
    }
  }

  static double distanceBetweenKm(
    double latitude1,
    double longitude1,
    double latitude2,
    double longitude2,
  ) {
    const earthRadiusKm = 6371.0;
    final latitudeDelta = (latitude2 - latitude1) * math.pi / 180;
    final longitudeDelta = (longitude2 - longitude1) * math.pi / 180;
    final a = math.pow(math.sin(latitudeDelta / 2), 2) +
        math.cos(latitude1 * math.pi / 180) *
            math.cos(latitude2 * math.pi / 180) *
            math.pow(math.sin(longitudeDelta / 2), 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}
