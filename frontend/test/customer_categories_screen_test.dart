import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/core/errors/app_error.dart';
import 'package:she_m_app/data/services/catalog_service.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/data/services/merchant_category_service.dart';
import 'package:she_m_app/data/services/promotion_service.dart';
import 'package:she_m_app/presentation/catalog/product_catalog.dart';
import 'package:she_m_app/presentation/dashboard/customer_dashboard_screen.dart';

class _CategoriesDatabase implements DatabaseService {
  _CategoriesDatabase(this.data, {this.failReads = const {}});

  final Map<String, dynamic> data;
  final Set<String> failReads;
  String? lastUpdatedPath;
  Map<String, dynamic>? lastUpdatedValues;

  @override
  Future<Map<String, dynamic>> read(String path) async {
    if (failReads.contains(path)) {
      throw const AppException(
        AppErrorMessage.access,
        kind: AppErrorKind.access,
      );
    }
    return Map<String, dynamic>.from(data[path] as Map? ?? const {});
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
    Map<String, dynamic> values,
  ) async {
    lastUpdatedPath = path;
    lastUpdatedValues = values;
    return values;
  }

  @override
  Future<Map<String, dynamic>?> updateIf(
    String path, {
    required bool Function(Map<String, dynamic> current) condition,
    required Map<String, dynamic> updates,
  }) async =>
      null;

  @override
  Future<void> delete(String path) async {}
}

void main() {
  test('category tree reads selected logo and cover image urls', () async {
    final database = _CategoriesDatabase({
      'product_categories': {
        'clothes': {
          'name': 'ملابس',
          'active': true,
          'logo_image_url': 'https://example.test/logo.jpg',
          'cover_image_url': 'https://example.test/cover.jpg',
        },
      },
    });
    final service = MerchantCategoryService(database: database);

    final categories = await service.getActiveProductCategoryTree();
    expect(categories.single.logoImageUrl, 'https://example.test/logo.jpg');
    expect(categories.single.coverImageUrl, 'https://example.test/cover.jpg');

    await service.setProductCategoryImage(
      'clothes',
      cover: false,
      imageUrl: 'https://example.test/new-logo.jpg',
    );
    expect(database.lastUpdatedPath, 'product_categories/clothes');
    expect(
      database.lastUpdatedValues,
      {'logo_image_url': 'https://example.test/new-logo.jpg'},
    );

    await service.setProductCategoryImage('clothes', cover: true);
    expect(database.lastUpdatedValues, {'cover_image_url': null});
  });

  test('category tree honors the admin-defined sort order', () async {
    final service = MerchantCategoryService(
      database: _CategoriesDatabase({
        'product_categories': {
          'second': {'name': 'الثاني', 'active': true, 'sort_order': 2},
          'first': {'name': 'الأول', 'active': true, 'sort_order': 1},
        },
      }),
    );

    final categories = await service.getActiveProductCategoryTree();
    expect(
      categories.map((category) => category.name),
      ['الأول', 'الثاني'],
    );
  });

  testWidgets('customer home groups products into category cards',
      (tester) async {
    final database = _CategoriesDatabase({
      'products': {
        'shirt-1': {
          'id': 'shirt-1',
          'name': 'قميص',
          'price': 35,
          'category': 'قمصان',
          'main_category_id': 'clothes',
          'main_category': 'ملابس',
          'subcategory_id': 'tops',
          'subcategory': 'قمصان',
          'available': true,
        },
        'shirt-2': {
          'id': 'shirt-2',
          'name': 'قميص طويل الاسم لاختبار عرضه داخل بطاقة المنتج',
          'price': 125,
          'category': 'قمصان',
          'main_category_id': 'clothes',
          'main_category': 'ملابس',
          'subcategory_id': 'tops',
          'subcategory': 'قمصان',
          'available': true,
        },
        'watch-1': {
          'id': 'watch-1',
          'name': 'ساعة',
          'price': 90,
          'category': 'ساعات',
          'main_category_id': 'accessories',
          'main_category': 'إكسسوارات',
          'available': true,
        },
      },
      'product_categories': {
        'clothes': {'name': 'ملابس', 'active': true},
        'accessories': {'name': 'إكسسوارات', 'active': true},
      },
    });
    final catalog = CatalogService(databaseService: database);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerHomeScreen(
            profile: null,
            orders: const [],
            currencySymbol: 'ر.س',
            onRefresh: () async {},
            catalogService: catalog,
            categoryService: MerchantCategoryService(database: database),
            promotionService: PromotionService(databaseService: database),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-category-clothes')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-category-accessories')),
      findsOneWidget,
    );
    final longProductName =
        find.text('قميص طويل الاسم لاختبار عرضه داخل بطاقة المنتج');
    await tester.scrollUntilVisible(
      longProductName,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<Text>(longProductName).maxLines, 2);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-category-clothes')),
        matching: find.textContaining('ر.س'),
      ),
      findsNWidgets(2),
    );
    expect(find.text('وصلت للنهاية'), findsNWidgets(2));
    await tester.scrollUntilVisible(
      find.text('اكتشف جميع الفئات'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('اكتشف جميع الفئات'), findsOneWidget);

    final categoryHeader = find.descendant(
      of: find.byKey(const ValueKey('home-category-clothes')),
      matching: find.text('تصفح منتجات القسم'),
    );
    await tester.ensureVisible(categoryHeader);
    await tester.pumpAndSettle();
    await tester.tap(categoryHeader);
    await tester.pumpAndSettle();

    expect(find.byType(ProductCatalogScreen), findsOneWidget);
    expect(find.text('قميص'), findsOneWidget);
    expect(find.text('ساعة'), findsNothing);
  });

  testWidgets(
      'guest catalog uses product categories when tree access is denied',
      (tester) async {
    final database = _CategoriesDatabase(
      {
        'products': {
          'shirt-1': {
            'id': 'shirt-1',
            'name': 'قميص',
            'category': 'قمصان',
            'main_category': 'ملابس',
            'main_category_sort_order': 1,
            'available': true,
          },
          'watch-1': {
            'id': 'watch-1',
            'name': 'ساعة',
            'category': 'ساعات',
            'main_category': 'إكسسوارات',
            'main_category_sort_order': 0,
            'available': true,
          },
        },
      },
      failReads: {'product_categories'},
    );
    final catalog = CatalogService(databaseService: database);
    final categoryService = MerchantCategoryService(database: database);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerHomeScreen(
            profile: null,
            orders: const [],
            currencySymbol: 'ر.س',
            onRefresh: () async {},
            catalogService: catalog,
            categoryService: categoryService,
            promotionService: PromotionService(databaseService: database),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('home-category-legacy:ملابس')),
      findsOneWidget,
    );
    expect(
      tester
          .getTopLeft(
            find.byKey(const ValueKey('home-category-legacy:اكسسوارات')),
          )
          .dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('home-category-legacy:ملابس')),
            )
            .dy,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CustomerCategoriesScreen(
          catalogService: catalog,
          categoryService: categoryService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('category-legacy:ملابس')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('category-legacy:اكسسوارات')),
      findsOneWidget,
    );
    expect(find.text('تعذر تحميل الأقسام'), findsNothing);
  });

  testWidgets('category screen follows the active product category tree',
      (tester) async {
    final database = _CategoriesDatabase({
      'products': {
        'shirt-1': {
          'id': 'shirt-1',
          'name': 'قميص',
          'category': 'قمصان',
          'main_category_id': 'clothes',
          'main_category': 'ملابس',
          'subcategory_id': 'tops',
          'subcategory': 'قمصان',
          'available': true,
        },
        'abaya-1': {
          'id': 'abaya-1',
          'name': 'عباءة',
          'category': 'عبايات',
          'main_category_id': 'clothes',
          'main_category': 'ملابس',
          'subcategory_id': 'abayas',
          'subcategory': 'عبايات',
          'available': true,
        },
        'watch-1': {
          'id': 'watch-1',
          'name': 'ساعة',
          'category': 'ساعات',
          'main_category_id': 'accessories',
          'main_category': 'إكسسوارات',
          'subcategory_id': 'watches',
          'subcategory': 'ساعات',
          'available': true,
        },
        'food-1': {
          'id': 'food-1',
          'name': 'طعام غير متاح',
          'category': 'أطعمة',
          'main_category_id': 'food',
          'main_category': 'أطعمة',
          'subcategory_id': 'food-items',
          'subcategory': 'أطعمة',
          'available': false,
        },
      },
      'product_categories': {
        'clothes': {
          'name': 'ملابس',
          'active': true,
          'subcategories': {
            'tops': {'name': 'قمصان', 'active': true},
            'abayas': {'name': 'عبايات', 'active': true},
            'empty': {'name': 'حقائب', 'active': true},
          },
        },
        'accessories': {
          'name': 'إكسسوارات',
          'active': true,
          'subcategories': {
            'watches': {'name': 'ساعات', 'active': true},
          },
        },
        'food': {
          'name': 'أطعمة',
          'active': false,
          'subcategories': {
            'food-items': {'name': 'مواد غذائية', 'active': true},
          },
        },
        'empty': {
          'name': 'قسم فارغ',
          'active': true,
          'subcategories': {
            'empty-items': {'name': 'منتجات فارغة', 'active': true},
          },
        },
      },
    });
    final catalog = CatalogService(databaseService: database);

    await tester.pumpWidget(
      MaterialApp(
        home: CustomerCategoriesScreen(
          catalogService: catalog,
          categoryService: MerchantCategoryService(database: database),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('category-clothes')), findsOneWidget);
    expect(find.byKey(const ValueKey('category-accessories')), findsOneWidget);
    expect(find.byKey(const ValueKey('category-food')), findsNothing);
    expect(find.byKey(const ValueKey('category-empty')), findsNothing);
    expect(find.text('2 منتج'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('category_search_field')),
      'اكسسوارات',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('category-accessories')), findsOneWidget);
    expect(find.byKey(const ValueKey('category-clothes')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('category_search_field')),
      '',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('expand-category-clothes')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('subcategory-clothes-tops')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('subcategory-clothes-empty')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('subcategory-clothes-tops')));
    await tester.pumpAndSettle();

    expect(find.byType(ProductCatalogScreen), findsOneWidget);
    expect(find.text('قميص'), findsOneWidget);
    expect(find.text('عباءة'), findsNothing);
  });

  testWidgets('legacy products still provide fallback categories',
      (tester) async {
    final database = _CategoriesDatabase({
      'products': {
        'shirt-1': {
          'id': 'shirt-1',
          'name': 'قميص',
          'category': 'ملابس',
          'main_category': 'ملابس',
          'available': true,
        },
        'watch-1': {
          'id': 'watch-1',
          'name': 'ساعة',
          'category': 'ساعات',
          'main_category': 'إكسسوارات',
          'available': true,
        },
      },
    });
    final catalog = CatalogService(databaseService: database);

    await tester.pumpWidget(
      MaterialApp(
        home: CustomerCategoriesScreen(
          catalogService: catalog,
          categoryService: MerchantCategoryService(database: database),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('category-legacy:ملابس')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('category-legacy:اكسسوارات')),
      findsOneWidget,
    );
  });

  testWidgets('inactive configured categories are not restored as legacy',
      (tester) async {
    final database = _CategoriesDatabase({
      'products': {
        'old-product': {
          'id': 'old-product',
          'name': 'منتج قديم',
          'category': 'قديم',
          'main_category': 'قديم',
          'available': true,
        },
      },
      'product_categories': {
        'old': {'name': 'قديم', 'active': false},
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        home: CustomerCategoriesScreen(
          catalogService: CatalogService(databaseService: database),
          categoryService: MerchantCategoryService(database: database),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('لا توجد أقسام تحتوي على منتجات حاليًا'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('category-legacy:قديم')), findsNothing);
  });
}
