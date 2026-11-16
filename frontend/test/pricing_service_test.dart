import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/models/product_model.dart';
import 'package:she_m_app/data/models/order_model.dart';
import 'package:she_m_app/data/models/user_model.dart';
import 'package:she_m_app/data/services/catalog_service.dart';
import 'package:she_m_app/data/services/cart_service.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/data/services/pricing_service.dart';

void main() {
  final product = ProductModel(
    id: 'p1',
    name: 'Test',
    price: 100,
    category: 'إلكترونيات',
    description: '',
    imageUrl: '',
    available: true,
    merchantId: 'm1',
  );

  test('calculates category commission as a percentage', () {
    const config = PricingConfig(
      commissionMode: 'percent',
      commissionValue: 10,
      commissionByCategory: {'إلكترونيات': 5},
    );
    expect(
      PricingService.commissionForProducts([product], [2], config),
      10,
    );
  });

  test('round trips the global merchant display delivery fee', () {
    final config = PricingConfig.fromJson({
      'merchant_display_delivery_fee': 900,
    });

    expect(config.merchantDisplayDeliveryFee, 900);
    expect(config.toJson()['merchant_display_delivery_fee'], 900);
    expect(
      PricingConfig.fromJson({'merchant_display_delivery_fee': -1})
          .merchantDisplayDeliveryFee,
      isNull,
    );
  });

  test('category and product commissions do not affect other products', () {
    const config = PricingConfig(
      commissionMode: 'percent',
      commissionValue: 10,
      commissionByCategory: {
        'إلكترونيات': 5,
        'ملابس': 15,
      },
    );
    final productWithOverride = product.copyWith(
      commissionModeOverride: 'percent',
      commissionValueOverride: 2,
    );
    final otherCategoryProduct = product.copyWith(
      id: 'clothing',
      category: 'ملابس',
    );
    final defaultRateProduct = product.copyWith(
      id: 'uncategorized',
      category: 'عام',
    );

    expect(
      PricingService.commissionForProducts(
        [productWithOverride, otherCategoryProduct, defaultRateProduct],
        [1, 1, 1],
        config,
      ),
      27,
    );
  });

  test('product commission overrides category and global commission', () {
    const config = PricingConfig(
      commissionMode: 'percent',
      commissionValue: 10,
      commissionByCategory: {'إلكترونيات': 5},
    );
    final percentageOverride = ProductModel.fromJson({
      'id': 'override-percent',
      'name': 'Special rate',
      'price': 100,
      'category': 'إلكترونيات',
      'description': '',
      'image_url': '',
      'available': true,
      'merchant_id': 'm1',
      'commission_mode_override': 'percent',
      'commission_value_override': 2,
    });
    final fixedOverride = percentageOverride.copyWith(
      id: 'override-fixed',
      commissionModeOverride: 'fixed',
      commissionValueOverride: 7,
    );

    expect(
      PricingService.commissionForProducts(
        [percentageOverride, fixedOverride],
        [2, 3],
        config,
      ),
      25,
    );
    expect(
      ProductModel.fromJson(fixedOverride.toJson()).commissionModeOverride,
      'fixed',
    );
    expect(
      ProductModel.fromJson(fixedOverride.toJson()).commissionValueOverride,
      7,
    );
  });

  test('product override is included in sale price and not double charged', () {
    const config = PricingConfig(
      commissionMode: 'percent',
      commissionValue: 10,
    );
    final productWithOverride = product.copyWith(
      commissionModeOverride: 'percent',
      commissionValueOverride: 10,
    );

    expect(productWithOverride.price, 100);
    expect(productWithOverride.priceIncludingCommission, 110);
    expect(productWithOverride.priceIncludingVat, 110);
    expect(
      PricingService.commissionForProducts(
        [productWithOverride],
        [2],
        config,
      ),
      20,
    );
    expect(
      PricingService.commissionIncludedInProductPrices(
        [productWithOverride],
        [2],
      ),
      20,
    );
    final subtotal =
        CartEntry(product: productWithOverride, quantity: 2).lineTotal;
    expect(subtotal, 220);
    expect(
      subtotal +
          PricingService.commissionForProducts(
            [productWithOverride],
            [2],
            config,
          ) -
          PricingService.commissionIncludedInProductPrices(
            [productWithOverride],
            [2],
          ),
      220,
    );

    final fixedCommissionProduct = product.copyWith(
      commissionModeOverride: 'fixed',
      commissionValueOverride: 7,
    );
    expect(fixedCommissionProduct.priceIncludingCommission, 107);
  });

  test('catalog applies product, category, and global commission to prices',
      () async {
    final catalog = CatalogService(
      databaseService: _PricingDatabase({
        'products': {
          'product-override': {
            'id': 'product-override',
            'name': 'عمولة خاصة',
            'price': 100,
            'category': 'ملابس',
            'available': true,
            'merchant_id': 'm1',
            'commission_mode_override': 'fixed',
            'commission_value_override': 7,
          },
          'category-rate': {
            'id': 'category-rate',
            'name': 'عمولة الفئة',
            'price': 100,
            'category': 'ملابس',
            'available': true,
            'merchant_id': 'm1',
          },
          'global-rate': {
            'id': 'global-rate',
            'name': 'العمولة العامة',
            'price': 100,
            'category': 'أخرى',
            'available': true,
            'merchant_id': 'm1',
          },
          'merchant-rate': {
            'id': 'merchant-rate',
            'name': 'عمولة التاجر',
            'price': 100,
            'category': 'ملابس',
            'available': true,
            'merchant_id': 'm2',
          },
        },
        'settings': {
          'pricing': {
            'commission_mode': 'percent',
            'commission_value': 10,
            'commission_by_category': {'ملابس': 5},
            'commission_by_merchant': {'m2': 12},
          },
        },
      }),
    );

    final products = await catalog.getProducts();
    final byId = {for (final item in products) item.id: item};

    expect(byId['product-override']!.priceIncludingCommission, 107);
    expect(byId['category-rate']!.priceIncludingCommission, 105);
    expect(byId['global-rate']!.priceIncludingCommission, 110);
    expect(byId['merchant-rate']!.priceIncludingCommission, 112);
    expect(
      ProductModel.fromJson(byId['category-rate']!.toJson())
          .priceIncludingCommission,
      105,
    );
    expect(
      PricingService.commissionForProducts(
        [
          byId['product-override']!,
          byId['category-rate']!,
          byId['global-rate']!,
          byId['merchant-rate']!,
        ],
        [1, 1, 1, 1],
        const PricingConfig(
          commissionMode: 'percent',
          commissionValue: 10,
          commissionByCategory: {'ملابس': 5},
          commissionByMerchant: {'m2': 12},
        ),
      ),
      34,
    );
  });

  test('legacy product VAT metadata does not change the product price', () {
    final taxableProduct = ProductModel.fromJson({
      'id': 'vat-product',
      'name': 'منتج ضريبي',
      'price': 200,
      'vat_rate': 15,
      'category': 'عام',
      'description': '',
      'image_url': '',
      'available': true,
      'merchant_id': 'm1',
    });

    expect(taxableProduct.price, 200);
    expect(taxableProduct.vatAmount, 0);
    expect(taxableProduct.priceIncludingVat, 200);
    expect(taxableProduct.toJson()['vat_rate'], 15);
  });

  test('cart and order snapshots use the product price without separate VAT',
      () {
    final taxableProduct = product.copyWith(vatRate: 15);
    final cartEntry = CartEntry(product: taxableProduct, quantity: 2);
    final orderItem = OrderItem(
      productId: taxableProduct.id,
      productName: taxableProduct.name,
      quantity: cartEntry.quantity,
      unitPrice: taxableProduct.priceIncludingVat,
      baseUnitPrice: taxableProduct.price,
      vatAmount: cartEntry.vatTotal,
      total: cartEntry.lineTotal,
    );

    expect(cartEntry.vatTotal, 0);
    expect(cartEntry.lineTotal, 200);
    expect(orderItem.unitPrice, 100);
    expect(orderItem.total, 200);
    expect(orderItem.toJson()['base_unit_price'], 100);
    expect(orderItem.toJson()['vat_amount'], 0);
  });

  test('pricing configuration ignores legacy VAT settings when saving', () {
    final config = PricingConfig.fromJson({'vat_rate': 15});

    expect(config.vatRate, 15);
    expect(config.toJson().containsKey('vat_rate'), isFalse);
  });

  test('merchant profile persists its delivery pricing region', () {
    final profile = UserModel.fromJson({
      'id': 'merchant-1',
      'role': 'merchant',
      'shop_region': 'صنعاء',
      'created_at': '2026-01-01T00:00:00.000Z',
    });

    expect(profile.shopRegion, 'صنعاء');
    expect(profile.copyWith(shopRegion: 'إب').toJson()['shop_region'], 'إب');
  });

  test('legacy VAT rules do not change the unified commission price', () {
    final config = PricingConfig.fromJson({
      'vat_rate': 12,
      'vat_by_category': {'إلكترونيات': 8, 'ملابس': 5},
      'vat_exempt_product_ids': ['exempt-product'],
      'vat_exempt_merchant_ids': ['exempt-merchant'],
    });

    double rate({
      String productId = 'product',
      String merchantId = 'merchant',
      String category = '',
      double? override,
      bool exempt = false,
    }) =>
        PricingService.vatRateForProduct(
          config: config,
          productId: productId,
          merchantId: merchantId,
          category: category,
          productRateOverride: override,
          productExempt: exempt,
        );

    expect(rate(productId: 'exempt-product', override: 20), 0);
    expect(rate(merchantId: 'exempt-merchant', override: 20), 0);
    expect(rate(override: 20, category: 'ملابس'), 0);
    expect(rate(category: 'ملابس / إلكترونيات'), 0);
    expect(rate(category: 'غير محددة'), 0);
    expect(rate(exempt: true, override: 20), 0);
  });

  test('pricing configuration drops legacy VAT settings when saved', () {
    final config = PricingConfig.fromJson({
      'vat_by_category': {'ملابس': 15},
      'vat_exempt_product_ids': ['p1'],
      'vat_exempt_merchant_ids': ['m1'],
    });

    expect(config.toJson().containsKey('vat_by_category'), isFalse);
    expect(config.toJson().containsKey('vat_exempt_product_ids'), isFalse);
    expect(config.toJson().containsKey('vat_exempt_merchant_ids'), isFalse);
  });

  test('pricing service ignores legacy VAT values when saving', () async {
    final service = PricingService(database: _PricingDatabase({}));

    expect(
      await service.save(const PricingConfig(vatRate: double.nan)),
      isTrue,
    );
    expect(
      await service.save(const PricingConfig(vatRate: 101)),
      isTrue,
    );
    expect(await service.save(const PricingConfig(vatRate: 100)), isTrue);
  });

  test('catalog does not add legacy VAT to product prices', () async {
    final catalog = CatalogService(
      databaseService: _PricingDatabase({
        'products': {
          'p1': {
            'id': 'p1',
            'name': 'منتج',
            'price': 200,
            'category': 'عام',
            'available': true,
            'merchant_id': 'm1',
          },
        },
        'settings': {
          'pricing': {'vat_rate': 15},
        },
      }),
    );

    final products = await catalog.getProducts();

    expect(products.single.price, 200);
    expect(products.single.priceIncludingCommission, 220);
    expect(products.single.priceIncludingVat, 220);
  });

  test('catalog applies product and category VAT rules with exemptions',
      () async {
    final catalog = CatalogService(
      databaseService: _PricingDatabase({
        'products': {
          'category-product': {
            'id': 'category-product',
            'name': 'منتج فئة',
            'price': 100,
            'category': 'ملابس',
            'available': true,
            'merchant_id': 'm1',
          },
          'override-product': {
            'id': 'override-product',
            'name': 'منتج بنسبة خاصة',
            'price': 100,
            'category': 'ملابس',
            'vat_rate_override': 20,
            'available': true,
            'merchant_id': 'm1',
          },
          'exempt-product': {
            'id': 'exempt-product',
            'name': 'منتج معفى',
            'price': 100,
            'category': 'ملابس',
            'available': true,
            'merchant_id': 'm1',
          },
        },
        'settings': {
          'pricing': {
            'vat_rate': 12,
            'vat_by_category': {'ملابس': 5},
            'vat_exempt_product_ids': ['exempt-product'],
          },
        },
      }),
    );

    final products = await catalog.getProducts();
    final productsById = {for (final item in products) item.id: item};

    expect(productsById['category-product']!.vatRate, 0);
    expect(productsById['override-product']!.vatRate, 0);
    expect(productsById['exempt-product']!.vatRate, 0);
  });

  test('calculates fixed delivery fee', () {
    const config = PricingConfig(
      deliveryMode: 'fixed',
      deliveryValue: 25,
    );
    expect(
      PricingService.deliveryFee(
        subtotal: 500,
        distanceKm: 20,
        config: config,
      ),
      25,
    );
  });

  test('calculates delivery from distance', () {
    const config = PricingConfig(
      deliveryMode: 'distance',
      deliveryBaseFee: 10,
      deliveryPerKm: 2,
    );
    expect(
      PricingService.deliveryFee(
        subtotal: 500,
        distanceKm: 8,
        config: config,
      ),
      26,
    );
  });

  test('calculates customer-region delivery price', () {
    final config = PricingConfig.fromJson({
      'delivery_mode': 'region',
      'delivery_value': 99,
      'delivery_by_region': {'صنعاء': 20},
    });

    expect(
      PricingService.deliveryFee(
        subtotal: 500,
        distanceKm: 8,
        customerRegion: 'صنعاء',
        config: config,
      ),
      20,
    );
    expect(
      PricingService.deliveryFee(
        subtotal: 500,
        distanceKm: 8,
        customerRegion: 'إب',
        config: config,
      ),
      99,
    );
  });

  test('calculates merchant-region delivery and falls back when exempt', () {
    final config = PricingConfig.fromJson({
      'delivery_mode': 'merchant_region',
      'delivery_base_fee': 10,
      'delivery_per_km': 2,
      'delivery_by_merchant_region': {'صنعاء': 25, 'إب': 30},
      'delivery_exempt_product_ids': ['exempt-product'],
    });

    expect(
      PricingService.deliveryFee(
        subtotal: 500,
        distanceKm: 8,
        merchantRegions: ['صنعاء', 'إب'],
        productIds: ['regular-product'],
        merchantIds: ['merchant-1', 'merchant-2'],
        config: config,
      ),
      30,
    );
    expect(
      PricingService.deliveryFee(
        subtotal: 500,
        distanceKm: 8,
        merchantRegions: ['صنعاء'],
        productIds: ['exempt-product'],
        merchantIds: ['merchant-1'],
        config: config,
      ),
      26,
    );
  });

  test('applies free delivery conditions and their product exceptions', () {
    final config = PricingConfig.fromJson({
      'delivery_mode': 'fixed',
      'delivery_value': 15,
      'free_delivery_rules': [
        {'type': 'commission_any', 'threshold': 50},
        {'type': 'subtotal_single_merchant', 'threshold': 200},
        {'type': 'commission_multi_merchant', 'threshold': 30},
      ],
      'delivery_exempt_product_ids': ['excluded'],
    });

    double fee({
      double subtotal = 100,
      double commission = 0,
      List<String> productIds = const ['eligible'],
      List<String> merchantIds = const ['merchant-1'],
    }) =>
        PricingService.deliveryFee(
          subtotal: subtotal,
          distanceKm: 1,
          commission: commission,
          productIds: productIds,
          merchantIds: merchantIds,
          config: config,
        );

    expect(fee(commission: 51), 0);
    expect(fee(subtotal: 201), 0);
    expect(
      fee(
        commission: 31,
        merchantIds: const ['merchant-1', 'merchant-2'],
      ),
      0,
    );
    expect(
      fee(commission: 51, productIds: const ['excluded']),
      15,
    );
  });

  test('calculates geographic distance', () {
    final distance = PricingService.distanceBetweenKm(0, 0, 0, 1);
    expect(distance, closeTo(111.2, 0.5));
  });
}

class _PricingDatabase implements DatabaseService {
  _PricingDatabase(this.data);

  final Map<String, dynamic> data;

  @override
  Future<Map<String, dynamic>> read(String path) async {
    dynamic value = data;
    for (final part in path.split('/')) {
      if (value is! Map) return <String, dynamic>{};
      value = value[part];
    }
    if (value is! Map) return <String, dynamic>{};
    return Map<String, dynamic>.from(value);
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
