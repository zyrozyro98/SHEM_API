import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/presentation/admin/admin_management_detail_screens.dart';

void main() {
  testWidgets('searches and saves selected exempt products and merchants',
      (tester) async {
    final database = _PricingManagementDatabase({
      'settings': {'pricing': <String, dynamic>{}},
      'product_categories': <String, dynamic>{},
      'products': {
        'product-1': {
          'id': 'product-1',
          'name': 'قميص قطني',
          'category': 'ملابس',
        },
        'product-2': {
          'id': 'product-2',
          'name': 'سماعة لاسلكية',
          'category': 'إلكترونيات',
        },
      },
      'profiles': {
        'merchant-1': {
          'id': 'merchant-1',
          'role': 'merchant',
          'shop_name': 'متجر صنعاء',
        },
        'customer-1': {
          'id': 'customer-1',
          'role': 'customer',
          'full_name': 'عميل',
        },
      },
    });

    await tester.pumpWidget(
      MaterialApp(home: PricingManagementScreen(database: database)),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('منتجات مستثناة من تسعير منطقة التاجر والتوصيل المجاني'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('اختيار').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'قميص');
    await tester.pumpAndSettle();

    expect(find.text('قميص قطني'), findsOneWidget);
    expect(find.text('سماعة لاسلكية'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey(
        'منتجات مستثناة من تسعير منطقة التاجر والتوصيل المجاني_product-1',
      )),
    );
    await tester.tap(find.text('اعتماد الاختيار'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('تجار مستثنون من تسعير منطقة التاجر والتوصيل المجاني'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('اختيار').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'صنعاء');
    await tester.pumpAndSettle();

    expect(find.text('متجر صنعاء'), findsOneWidget);
    expect(find.text('عميل'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey(
        'تجار مستثنون من تسعير منطقة التاجر والتوصيل المجاني_merchant-1',
      )),
    );
    await tester.tap(find.text('اعتماد الاختيار'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('حفظ الإعدادات'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('حفظ الإعدادات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ الإعدادات'));
    await tester.pumpAndSettle();

    expect(
      database.savedPricing?['delivery_exempt_product_ids'],
      ['product-1'],
    );
    expect(
      database.savedPricing?['delivery_exempt_merchant_ids'],
      ['merchant-1'],
    );
  });

  testWidgets('manages one commission rate without separate VAT settings',
      (tester) async {
    final database = _PricingManagementDatabase({
      'settings': {
        'pricing': {
          'commission_by_category': {'ملابس': 7},
          'merchant_display_delivery_fee': 900,
        },
      },
      'product_categories': {
        'clothes': {'name': 'ملابس', 'active': true},
        'electronics': {'name': 'إلكترونيات', 'active': true},
      },
    });

    await tester.pumpWidget(
      MaterialApp(home: PricingManagementScreen(database: database)),
    );
    await tester.pumpAndSettle();

    expect(find.text('ملابس'), findsWidgets);
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إلكترونيات').last);
    await tester.pumpAndSettle();
    expect(find.text('إلكترونيات'), findsWidgets);

    expect(find.text('عمولة حسب الفئة'), findsOneWidget);
    expect(find.text('نسبة ضريبة القيمة المضافة (%)'), findsNothing);
    expect(find.text('اختيار التجار لإعفاء منتجاتهم'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('حفظ الإعدادات'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('حفظ الإعدادات'));
    await tester.pumpAndSettle();
    expect(
      database.savedPricing?['commission_by_category'],
      {'إلكترونيات': 7},
    );
    expect(database.savedPricing?['merchant_display_delivery_fee'], 900);
    expect(database.savedPricing?.containsKey('vat_rate'), isFalse);
    expect(database.savedPricing?.containsKey('vat_by_category'), isFalse);
  });

  testWidgets('warns before replacing a product commission with new rules',
      (tester) async {
    final database = _PricingManagementDatabase({
      'settings': {
        'pricing': {
          'commission_mode': 'percent',
          'commission_value': 10,
          'commission_by_category': {'ملابس': 3},
        },
      },
      'product_categories': {
        'clothes': {'name': 'ملابس', 'active': true},
      },
      'products': {
        'product-1': {
          'id': 'product-1',
          'name': 'قميص قطني',
          'price': 100,
          'category': 'ملابس',
          'merchant_id': 'merchant-1',
          'commission_mode_override': 'percent',
          'commission_value_override': 2,
          'description': 'قميص كامل التفاصيل',
          'stock': 12,
        },
        'product-2': {
          'id': 'product-2',
          'name': 'بنطال قطني',
          'price': 120,
          'category': 'ملابس',
          'merchant_id': 'merchant-1',
          'commission_mode_override': 'percent',
          'commission_value_override': 4,
        },
      },
      'profiles': {
        'merchant-1': {
          'id': 'merchant-1',
          'role': 'merchant',
          'shop_name': 'متجر صنعاء',
        },
      },
    });

    await tester.pumpWidget(
      MaterialApp(home: PricingManagementScreen(database: database)),
    );
    await tester.pumpAndSettle();

    final categoryRate = find.byKey(
      const ValueKey('category-commission-value-0'),
    );
    await tester.ensureVisible(categoryRate);
    await tester.enterText(categoryRate, '7');

    await tester.scrollUntilVisible(
      find.text('إضافة تاجر'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('إضافة تاجر'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('merchant-commission-merchant-0')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('متجر صنعاء').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('merchant-commission-value-0')),
      '8',
    );

    await tester.scrollUntilVisible(
      find.text('حفظ الإعدادات'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('حفظ الإعدادات'));
    await tester.pumpAndSettle();

    expect(find.text('مراجعة المنتجات ذات العمولة الخاصة'), findsOneWidget);
    expect(find.textContaining('قميص قطني'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('بنطال قطني'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.textContaining('بنطال قطني'), findsOneWidget);
    expect(find.textContaining('قميص كامل التفاصيل'), findsOneWidget);
    expect(find.textContaining('عمولته الخاصة الحالية'), findsWidgets);
    expect(find.textContaining('السعر الجديد 108.00'), findsOneWidget);

    final conflictTile =
        find.byKey(const ValueKey('commission-conflict-product-1'));
    await tester.ensureVisible(conflictTile);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: conflictTile,
      matching: find.byType(Checkbox),
    ));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckboxListTile>(
            conflictTile,
          )
          .value,
      isTrue,
    );
    expect(find.text('تأكيد وحفظ (1)'), findsOneWidget);
    await tester.tap(find.text('تأكيد وحفظ (1)'));
    await tester.pumpAndSettle();

    expect(
      find.text('تم حفظ السياسة وتطبيق العمولة الجديدة على المنتجات المحددة'),
      findsOneWidget,
    );
    expect(database.savedPricing?['commission_by_category'], {'ملابس': 7});
    expect(database.savedPricing?['commission_by_merchant'], {'merchant-1': 8});
    expect(database.updatePaths, ['products/product-1']);
    expect(database.products['product-1']!['commission_mode_override'], isNull);
    expect(
        database.products['product-1']!['commission_value_override'], isNull);
    expect(
        database.products['product-2']!['commission_mode_override'], 'percent');
    expect(database.products['product-2']!['commission_value_override'], 4);
  });
}

class _PricingManagementDatabase implements DatabaseService {
  final Map<String, dynamic> data;
  Map<String, dynamic>? savedPricing;
  final List<String> updatePaths = [];
  final Map<String, Map<String, dynamic>> products = {};

  _PricingManagementDatabase(this.data) {
    final rawProducts = data['products'];
    if (rawProducts is Map) {
      for (final entry in rawProducts.entries) {
        if (entry.value is Map) {
          products[entry.key.toString()] =
              Map<String, dynamic>.from(entry.value as Map);
        }
      }
    }
  }

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
    Map<String, dynamic> value,
  ) async {
    if (path == 'settings/pricing') {
      savedPricing = Map<String, dynamic>.from(value);
      (data['settings'] as Map)['pricing'] = Map<String, Object>.from(value);
    }
    return value;
  }

  @override
  Future<Map<String, dynamic>> update(
    String path,
    Map<String, dynamic> value,
  ) async {
    updatePaths.add(path);
    if (path.startsWith('products/')) {
      final id = path.substring('products/'.length);
      final product = products[id];
      final rawProduct = (data['products'] as Map)[id];
      if (product != null && rawProduct is Map) {
        for (final entry in value.entries) {
          if (entry.value == null) {
            product.remove(entry.key);
            rawProduct.remove(entry.key);
          } else {
            product[entry.key] = entry.value;
            rawProduct[entry.key] = entry.value;
          }
        }
      }
    }
    return value;
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
