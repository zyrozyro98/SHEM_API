import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:she_m_app/data/models/product_model.dart';
import 'package:she_m_app/presentation/admin/merchant_management_screen.dart';
import 'package:she_m_app/presentation/common/product_color_selector.dart';

void main() {
  test('normalizeSelectedCategories keeps up to three categories', () {
    expect(
      normalizeSelectedCategories(['أطعمة', 'ملابس', 'إلكترونيات', 'مستلزمات'],
          maxCount: 3),
      ['أطعمة', 'ملابس', 'إلكترونيات'],
    );

    expect(
      normalizeSelectedCategories(['أطعمة', 'ملابس'], maxCount: 3),
      ['أطعمة', 'ملابس'],
    );

    expect(
      normalizeSelectedCategories(['أطعمة', 'أطعمة', 'ملابس', 'إلكترونيات'],
          maxCount: 3),
      ['أطعمة', 'ملابس', 'إلكترونيات'],
    );
  });

  test('product category validation requires exactly one primary category', () {
    expect(
      validateProductDraftInputs(
        name: 'منتج تجريبي',
        categories: const [],
        priceText: '25',
      ),
      'اختر القسم الرئيسي والقسم الفرعي للمنتج',
    );
    expect(
      validateProductDraftInputs(
        name: 'منتج تجريبي',
        categories: const ['أطعمة', 'مشروبات'],
        priceText: '25',
      ),
      'اختر فئة واحدة فقط للمنتج',
    );
    expect(
      validateProductDraftInputs(
        name: 'منتج تجريبي',
        categories: const ['أطعمة'],
        priceText: '25',
      ),
      isNull,
    );
  });

  test('merchant product payload rejects multiple categories', () {
    expect(
      () => buildMerchantProductPayload(
        existingProduct: null,
        merchantId: 'merchant-1',
        name: 'منتج تجريبي',
        categoryText: 'أطعمة / مشروبات',
        imageUris: const [],
        videoDataUri: '',
        available: true,
        description: '',
        price: 25,
        stock: 1,
      ),
      throwsArgumentError,
    );
  });

  test('product colors resolve Arabic names and hex values', () {
    expect(productColorValue('أحمر'), const Color(0xFFDC2626));
    expect(productColorValue('#D4AF37'), const Color(0xFFD4AF37));
    expect(productColorValue('custom'), const Color(0xFFE2E8F0));
  });

  test('product list uses the stored currency label', () {
    expect(
      resolveProductCurrencyLabel({
        'currency_symbol': r'$',
        'currency_code': 'USD',
      }),
      r'$',
    );
    expect(
      resolveProductCurrencyLabel({'currency_code': 'AED'}),
      'AED',
    );
    expect(resolveProductCurrencyLabel({}), 'ر.س');
  });

  test('merchant product submissions stay hidden until admin approval', () {
    final product = buildMerchantProductPayload(
      existingProduct: null,
      merchantId: 'merchant-1',
      name: 'منتج تجريبي',
      categoryText: 'عناية',
      imageUris: const [],
      videoDataUri: '',
      available: true,
      description: 'وصف المنتج',
      price: 25,
      stock: 4,
    );

    expect(product['approval_status'], 'pending');
    expect(product['available'], isFalse);
    expect(product['requested_available'], isTrue);
    expect(product['review_reason'], isEmpty);
  });

  test('merchant product payload stores the selected category hierarchy', () {
    final product = buildMerchantProductPayload(
      existingProduct: null,
      merchantId: 'merchant-1',
      name: 'هاتف تجريبي',
      categoryText: 'هواتف',
      mainCategoryId: 'electronics',
      mainCategoryName: 'إلكترونيات',
      subcategoryId: 'phones',
      subcategoryName: 'هواتف',
      imageUris: const [],
      videoDataUri: '',
      available: true,
      description: '',
      price: 250,
      stock: 3,
    );

    expect(product['category'], 'هواتف');
    expect(product['main_category_id'], 'electronics');
    expect(product['main_category'], 'إلكترونيات');
    expect(product['subcategory_id'], 'phones');
    expect(product['subcategory'], 'هواتف');
    expect(product['categories'], ['هواتف']);
  });

  test('product model preserves the selected category hierarchy', () {
    final product = ProductModel.fromJson({
      'id': 'product-1',
      'name': 'هاتف تجريبي',
      'price': 250,
      'category': 'هواتف',
      'main_category_id': 'electronics',
      'main_category': 'إلكترونيات',
      'subcategory_id': 'phones',
      'subcategory': 'هواتف',
      'description': '',
      'image_url': '',
      'available': true,
      'merchant_id': 'merchant-1',
    });

    expect(product.mainCategoryId, 'electronics');
    expect(product.mainCategory, 'إلكترونيات');
    expect(product.subcategoryId, 'phones');
    expect(product.subcategory, 'هواتف');
    expect(product.toJson()['subcategory_id'], 'phones');
  });

  test('merchant product payload does not persist a separate VAT rate', () {
    final product = buildMerchantProductPayload(
      existingProduct: null,
      merchantId: 'merchant-1',
      name: 'منتج بسعر موحد',
      categoryText: 'عناية',
      imageUris: const [],
      videoDataUri: '',
      available: true,
      description: '',
      price: 200,
      stock: 1,
    );

    expect(product['price'], 200);
    expect(product.containsKey('vat_rate'), isFalse);
  });

  test(
      'approved product price edits create a pending request and keep live price',
      () {
    final product = buildMerchantProductPayload(
      existingProduct: {
        'id': 'product-1',
        'name': 'منتج تجريبي',
        'price': 25,
        'available': true,
        'requested_available': true,
        'approval_status': 'approved',
      },
      merchantId: 'merchant-1',
      name: 'منتج تجريبي',
      categoryText: 'عناية',
      imageUris: const [],
      videoDataUri: '',
      available: true,
      description: 'وصف',
      price: 30,
      stock: 4,
    );

    expect(product['price'], 25);
    expect(product['requested_price'], 30);
    expect(product['price_change_status'], 'pending');
    expect(product['approval_status'], 'approved');
    expect(product['available'], isTrue);
  });

  test(
      'editing approved product details without changing price needs no review',
      () {
    final product = buildMerchantProductPayload(
      existingProduct: {
        'id': 'product-1',
        'name': 'الاسم السابق',
        'price': 25,
        'available': true,
        'requested_available': true,
        'approval_status': 'approved',
      },
      merchantId: 'merchant-1',
      name: 'اسم جديد',
      categoryText: 'عناية',
      imageUris: const [],
      videoDataUri: '',
      available: true,
      description: 'وصف',
      price: 25,
      stock: 4,
    );

    expect(product['price'], 25);
    expect(product['approval_status'], 'approved');
    expect(product['price_change_status'], isNull);
    expect(product['available'], isTrue);
  });

  test('merchant product edits preserve admin commission overrides', () {
    final product = buildMerchantProductPayload(
      existingProduct: {
        'id': 'product-1',
        'name': 'منتج تجريبي',
        'price': 25,
        'available': true,
        'requested_available': true,
        'approval_status': 'approved',
        'commission_mode_override': 'fixed',
        'commission_value_override': 12,
      },
      merchantId: 'merchant-1',
      name: 'منتج محدث',
      categoryText: 'عناية',
      imageUris: const [],
      videoDataUri: '',
      available: true,
      description: 'وصف',
      price: 25,
      stock: 4,
    );

    expect(product['commission_mode_override'], 'fixed');
    expect(product['commission_value_override'], 12);
  });

  test('editing other fields keeps an existing price request pending', () {
    final product = buildMerchantProductPayload(
      existingProduct: {
        'id': 'product-1',
        'name': 'منتج تجريبي',
        'price': 25,
        'requested_price': 30,
        'price_change_status': 'pending',
        'approval_status': 'approved',
        'available': true,
        'requested_available': true,
      },
      merchantId: 'merchant-1',
      name: 'اسم معدل',
      categoryText: 'عناية',
      imageUris: const [],
      videoDataUri: '',
      available: true,
      description: 'وصف',
      price: 30,
      stock: 4,
    );

    expect(product['price'], 25);
    expect(product['requested_price'], 30);
    expect(product['price_change_status'], 'pending');
  });

  test('new merchant products do not include claimed original price', () {
    final product = buildMerchantProductPayload(
      existingProduct: null,
      merchantId: 'merchant-1',
      name: 'منتج تجريبي',
      categoryText: 'عناية',
      imageUris: const [],
      videoDataUri: '',
      available: true,
      description: 'وصف المنتج',
      price: 25,
      stock: 4,
    );

    expect(product.containsKey('merchant_claimed_original_price'), isFalse);
  });

  test('editing a product preserves its previously claimed original price', () {
    final product = buildMerchantProductPayload(
      existingProduct: {
        'id': 'product-1',
        'merchant_claimed_original_price': 17.5,
      },
      merchantId: 'merchant-1',
      name: 'منتج تجريبي',
      categoryText: 'عناية',
      imageUris: const [],
      videoDataUri: '',
      available: true,
      description: 'وصف المنتج',
      price: 25,
      stock: 4,
    );

    expect(product['merchant_claimed_original_price'], 17.5);
  });

  test('merchant availability changes do not require product approval', () {
    final pendingProduct = {
      'approval_status': 'pending',
      'available': false,
      'requested_available': false,
    };
    final requestedAvailability = buildMerchantProductAvailabilityUpdates(
      product: pendingProduct,
      available: true,
    );

    expect(requestedAvailability, {
      'available': false,
      'requested_available': true,
    });
    expect(resolveMerchantProductAvailability(requestedAvailability), isTrue);
    expect(requestedAvailability.containsKey('approval_status'), isFalse);

    final approvedProduct = {
      'approval_status': 'approved',
      'available': true,
      'requested_available': true,
    };
    expect(
      buildMerchantProductAvailabilityUpdates(
        product: approvedProduct,
        available: false,
      ),
      {
        'available': false,
        'requested_available': false,
      },
    );
  });

  test('inventory stock resolves legacy values and status thresholds', () {
    expect(resolveProductStock({'stock': '7'}), 7);
    expect(resolveProductStock({'inventory': 0}), 0);
    expect(resolveProductStock({'stock': -2}), 0);
    expect(resolveInventoryStatus(0), 'out_of_stock');
    expect(resolveInventoryStatus(5), 'low_stock');
    expect(resolveInventoryStatus(6), 'in_stock');
  });
}
