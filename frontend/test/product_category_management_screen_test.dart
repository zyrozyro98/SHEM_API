import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/data/services/merchant_category_service.dart';
import 'package:she_m_app/presentation/admin/admin_management_detail_screens.dart';

void main() {
  test('merchant choices include active child sections only', () async {
    final service = MerchantCategoryService(
      database: _CategoryManagementDatabase({
        'product_categories': <String, dynamic>{
          'clothes': <String, dynamic>{
            'name': 'ملابس',
            'active': true,
            'subcategories': <String, dynamic>{
              'mens': <String, dynamic>{'name': 'رجالي', 'active': true},
              'womens': <String, dynamic>{'name': 'نسائي', 'active': false},
            },
          },
          'inactive': <String, dynamic>{
            'name': 'أجهزة قديمة',
            'active': false,
            'subcategories': <String, dynamic>{
              'old': <String, dynamic>{'name': 'قديم', 'active': true},
            },
          },
        },
      }),
    );

    final categories = await service.getActiveProductCategoryTree();
    expect(categories.map((category) => category.name), ['ملابس']);
    expect(
      categories.single.activeSubcategories.map((category) => category.name),
      ['رجالي'],
    );
    expect(await service.getActiveProductCategories(), ['رجالي']);
  });

  test('adding a child migrates a legacy flat category safely', () async {
    final database = _CategoryManagementDatabase({
      'product_categories': <String, dynamic>{'clothes': 'ملابس'},
    });
    final service = MerchantCategoryService(database: database);

    await service.addProductSubcategory('clothes', 'رجالي');

    final parent =
        (database.data['product_categories'] as Map)['clothes'] as Map;
    expect(parent['name'], 'ملابس');
    expect(parent['active'], isTrue);
    expect(
      (parent['subcategories'] as Map)
          .values
          .any((subcategory) => subcategory['name'] == 'رجالي'),
      isTrue,
    );
  });

  testWidgets('manages primary and child product categories', (tester) async {
    final database = _CategoryManagementDatabase({
      'product_categories': <String, dynamic>{
        'clothes': <String, dynamic>{
          'name': 'ملابس',
          'active': true,
          'subcategories': <String, dynamic>{
            'mens': <String, dynamic>{'name': 'رجالي', 'active': true},
            'womens': <String, dynamic>{'name': 'نسائي', 'active': false},
          },
        },
        'electronics': <String, dynamic>{
          'name': 'إلكترونيات',
          'active': false,
          'subcategories': <String, dynamic>{},
        },
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ProductCategoryManagementScreen(database: database),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ملابس'), findsOneWidget);
    expect(find.text('رجالي'), findsNothing);
    expect(find.text('أقسام رئيسية نشطة: 1'), findsOneWidget);
    expect(find.text('أقسام فرعية نشطة: 1'), findsOneWidget);
    expect(find.text('أقسام فرعية موقوفة: 1'), findsOneWidget);

    await tester.tap(find.text('ملابس'));
    await tester.pumpAndSettle();
    expect(find.text('رجالي'), findsOneWidget);
    expect(find.text('نسائي'), findsAtLeastNWidgets(1));

    await tester.enterText(find.byType(TextField).first, 'نسائي');
    await tester.pumpAndSettle();
    expect(find.text('نسائي'), findsAtLeastNWidgets(1));
    expect(find.text('رجالي'), findsNothing);

    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();
    expect(
      ((database.data['product_categories'] as Map)['clothes']['subcategories']
          as Map)['womens']['active'],
      isTrue,
    );
  });

  testWidgets('admin can change the order of primary sections', (tester) async {
    final database = _CategoryManagementDatabase({
      'product_categories': <String, dynamic>{
        'clothes': <String, dynamic>{
          'name': 'ملابس',
          'active': true,
          'sort_order': 1,
          'subcategories': <String, dynamic>{},
        },
        'electronics': <String, dynamic>{
          'name': 'إلكترونيات',
          'active': true,
          'sort_order': 0,
          'subcategories': <String, dynamic>{},
        },
      },
      'products': <String, dynamic>{
        'shirt': <String, dynamic>{
          'main_category_id': 'clothes',
          'main_category': 'ملابس',
          'category': 'ملابس',
          'available': true,
        },
        'phone': <String, dynamic>{
          'main_category_id': 'electronics',
          'main_category': 'إلكترونيات',
          'category': 'إلكترونيات',
          'available': true,
        },
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ProductCategoryManagementScreen(database: database),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('إلكترونيات')).dy,
      lessThan(tester.getTopLeft(find.text('ملابس')).dy),
    );

    final electronicsTile = find.ancestor(
      of: find.text('إلكترونيات'),
      matching: find.byType(ExpansionTile),
    );
    await tester.tap(
      find.descendant(
        of: electronicsTile,
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('تحريك للأسفل'));
    await tester.pumpAndSettle();

    final categories = database.data['product_categories'] as Map;
    expect(categories['clothes']['sort_order'], 0);
    expect(categories['electronics']['sort_order'], 1);
    final products = database.data['products'] as Map;
    expect(products['shirt']['main_category_sort_order'], 0);
    expect(products['phone']['main_category_sort_order'], 1);
    expect(
      tester.getTopLeft(find.text('ملابس')).dy,
      lessThan(tester.getTopLeft(find.text('إلكترونيات')).dy),
    );
  });

  testWidgets('adds primary sections and their child sections', (tester) async {
    final database = _CategoryManagementDatabase({
      'product_categories': <String, dynamic>{},
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ProductCategoryManagementScreen(database: database),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('إضافة قسم رئيسي'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'إلكترونيات');
    await tester.tap(find.widgetWithText(FilledButton, 'إضافة'));
    await tester.pumpAndSettle();

    final categories = database.data['product_categories'] as Map;
    final parentEntry = categories.entries.singleWhere(
      (entry) => entry.value['name'] == 'إلكترونيات',
    );
    expect(parentEntry.value['subcategories'], isA<Map>());

    await tester.tap(find.text('إلكترونيات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إضافة قسم فرعي'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'هواتف');
    await tester.tap(find.widgetWithText(FilledButton, 'إضافة'));
    await tester.pumpAndSettle();

    final subcategories = parentEntry.value['subcategories'] as Map;
    expect(
      subcategories.values.any((value) => value['name'] == 'هواتف'),
      isTrue,
    );
  });

  testWidgets('deletes a primary section and its child sections',
      (tester) async {
    final database = _CategoryManagementDatabase({
      'product_categories': <String, dynamic>{
        'clothes': <String, dynamic>{
          'name': 'ملابس',
          'active': true,
          'subcategories': <String, dynamic>{
            'mens': <String, dynamic>{'name': 'رجالي', 'active': true},
          },
        },
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ProductCategoryManagementScreen(database: database),
      ),
    );
    await tester.pumpAndSettle();

    final parentTile = find.ancestor(
      of: find.text('ملابس'),
      matching: find.byType(ExpansionTile),
    );
    await tester.tap(
      find.descendant(
        of: parentTile,
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف القسم'));
    await tester.pumpAndSettle();
    expect(find.text('حذف القسم الرئيسي'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'حذف'));
    await tester.pumpAndSettle();

    expect(
      (database.data['product_categories'] as Map).containsKey('clothes'),
      isFalse,
    );
  });

  testWidgets('merchant category deletion requires confirmation',
      (tester) async {
    final database = _CategoryManagementDatabase({
      'merchant_categories': <String, dynamic>{
        'fashion': <String, dynamic>{'name': 'أزياء', 'active': true},
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MerchantCategoryManagementScreen(database: database),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('حذف الفئة'));
    await tester.pumpAndSettle();
    expect(find.text('حذف فئة المتجر'), findsOneWidget);
    expect(
      (database.data['merchant_categories'] as Map).containsKey('fashion'),
      isTrue,
    );

    await tester.tap(find.widgetWithText(TextButton, 'إلغاء'));
    await tester.pumpAndSettle();
    expect(
      (database.data['merchant_categories'] as Map).containsKey('fashion'),
      isTrue,
    );

    await tester.tap(find.byTooltip('حذف الفئة'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'حذف'));
    await tester.pumpAndSettle();
    expect(
      (database.data['merchant_categories'] as Map).containsKey('fashion'),
      isFalse,
    );
  });
}

class _CategoryManagementDatabase implements DatabaseService {
  _CategoryManagementDatabase(this.data);

  final Map<String, dynamic> data;

  @override
  Future<Map<String, dynamic>> read(String path) async {
    dynamic value = data;
    for (final part in path.split('/')) {
      if (value is! Map) return <String, dynamic>{};
      value = value[part];
    }
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String) return {'value': value};
    return <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> write(
    String path,
    Map<String, dynamic> value,
  ) async {
    _set(path, value);
    return value;
  }

  @override
  Future<Map<String, dynamic>> update(
    String path,
    Map<String, dynamic> value,
  ) async {
    if (value.keys.any((key) => key.toString().contains('/'))) {
      for (final entry in value.entries) {
        _setValue('$path/${entry.key}', entry.value);
      }
      return read(path);
    }
    final current = await read(path);
    final updated = {...current, ...value};
    _set(path, updated);
    return updated;
  }

  @override
  Future<Map<String, dynamic>?> updateIf(
    String path, {
    required bool Function(Map<String, dynamic> current) condition,
    required Map<String, dynamic> updates,
  }) async =>
      updates;

  @override
  Future<void> delete(String path) async {
    final parts = path.split('/');
    dynamic parent = data;
    for (final part in parts.take(parts.length - 1)) {
      if (parent is! Map) return;
      parent = parent[part];
    }
    if (parent is Map) parent.remove(parts.last);
  }

  void _set(String path, Map<String, dynamic> value) {
    _setValue(path, value);
  }

  void _setValue(String path, Object? value) {
    final parts = path.split('/');
    dynamic parent = data;
    for (final part in parts.take(parts.length - 1)) {
      if (parent is! Map) return;
      parent = parent[part];
    }
    if (parent is Map) parent[parts.last] = value;
  }
}
