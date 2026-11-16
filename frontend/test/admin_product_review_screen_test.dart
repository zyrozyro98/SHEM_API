import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/models/product_model.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/presentation/admin/admin_management_detail_screens.dart';

void main() {
  testWidgets('admin product review shows all merchant product details',
      (tester) async {
    final database = _ProductReviewDatabase();
    await tester.pumpWidget(
      MaterialApp(
        home: ProductManagementAdminScreen(databaseService: database),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('معاينة ومراجعة'));
    await tester.pumpAndSettle();

    expect(find.text('صور المنتج (2)'), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-product-image-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-product-image-1')), findsOneWidget);
    expect(find.text('الفئة: عناية بالبشرة'), findsOneWidget);
    expect(find.text('السعر: 125 ر.س'), findsOneWidget);
    expect(find.text('الكمية المتاحة: 14'), findsOneWidget);
    expect(find.text('المقاسات: صغير، كبير'), findsOneWidget);
    expect(find.text('الألوان: أحمر، أزرق'), findsOneWidget);
    expect(find.text('الوصف والتفاصيل: وصف تفصيلي للمنتج'), findsOneWidget);
    expect(find.text('مشاهدة فيديو المنتج'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('admin-product-image-0')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('تكبير'), findsOneWidget);
    expect(find.byTooltip('تصغير'), findsOneWidget);
    await tester.tap(find.byTooltip('إغلاق العرض'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('مشاهدة فيديو المنتج'));
    await tester.tap(find.text('مشاهدة فيديو المنتج'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('تكبير'), findsOneWidget);
    expect(find.byTooltip('تصغير'), findsOneWidget);
    await tester.tap(find.byTooltip('إغلاق العرض'));
    await tester.pumpAndSettle();
  });

  testWidgets('reject reason is entered and confirmed in a separate dialog',
      (tester) async {
    final database = _ProductReviewDatabase();
    await tester.pumpWidget(
      MaterialApp(
        home: ProductManagementAdminScreen(databaseService: database),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('معاينة ومراجعة'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('admin-product-rejection-reason')),
      findsNothing,
    );

    await tester.tap(find.text('رفض مع السبب'));
    await tester.pumpAndSettle();
    final reasonField =
        find.byKey(const ValueKey('admin-product-rejection-reason'));
    expect(reasonField, findsOneWidget);

    await tester.tap(find.text('تأكيد الرفض'));
    await tester.pumpAndSettle();
    expect(find.text('سبب الرفض مطلوب'), findsOneWidget);

    await tester.enterText(reasonField, 'صورة المنتج غير واضحة');
    await tester.tap(find.text('تأكيد الرفض'));
    await tester.pumpAndSettle();

    expect(database.products['product-1']!['approval_status'], 'rejected');
    expect(
      database.products['product-1']!['review_reason'],
      'صورة المنتج غير واضحة',
    );
  });

  testWidgets('product commission updates only the selected database record',
      (tester) async {
    final database = _ProductReviewDatabase();
    database.products['product-1']!['id'] = 'incorrect-shared-id';
    database.products['product-2'] = {
      ...database.products['product-1']!,
      'name': 'منتج آخر',
    };

    await tester.pumpWidget(
      MaterialApp(
        home: ProductManagementAdminScreen(databaseService: database),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'منتج تجريبي');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('معاينة ومراجعة'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('تحديد عمولة خاصة لهذا المنتج'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تحديد عمولة خاصة لهذا المنتج'));
    await tester.pumpAndSettle();
    final commissionField =
        find.byKey(const ValueKey('admin-product-commission-value'));
    expect(tester.widget<TextFormField>(commissionField).initialValue, '');
    expect(find.text('نسبة من سعر المنتج'), findsOneWidget);
    await tester.ensureVisible(commissionField);
    await tester.pumpAndSettle();
    await tester.tap(commissionField);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, 'إلغاء'), findsNothing);
    expect(find.text('رفض مع السبب'), findsNothing);
    expect(find.text('اعتماد ونشر'), findsNothing);
    await tester.enterText(commissionField, '3');
    await tester.pumpAndSettle();
    expect(find.text('سعر البيع بعد العمولة: 128.75 ر.س'), findsOneWidget);
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, 'إلغاء'), findsOneWidget);
    expect(find.text('رفض مع السبب'), findsOneWidget);
    expect(find.text('اعتماد ونشر'), findsOneWidget);
    await tester.tap(find.text('اعتماد ونشر'));
    await tester.pumpAndSettle();

    expect(database.lastUpdatedPath, 'products/product-1');
    expect(database.products['product-1']!['commission_value_override'], 3);
    expect(
      ProductModel.fromJson(database.products['product-1']!)
          .priceIncludingCommission,
      128.75,
    );
    expect(
        database.products['product-2']!['commission_value_override'], isNull);
  });

  testWidgets(
      'admin can search for a merchant and edit only their delivery fee',
      (tester) async {
    final database = _ProductReviewDatabase();
    await tester.pumpWidget(
      MaterialApp(
        home: ProductManagementAdminScreen(databaseService: database),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('إضافة منتج لتاجر'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('admin-merchant-picker-search')),
      'مخبز',
    );
    await tester.pumpAndSettle();

    expect(find.text('مخبز الصباح'), findsOneWidget);
    expect(find.text('متجر تجريبي'), findsNothing);

    await tester.tap(find.byTooltip('تعديل أجرة التوصيل لهذا التاجر'));
    await tester.pumpAndSettle();
    expect(find.text('أجرة التوصيل الظاهرة للتاجر'), findsOneWidget);
    expect(find.text('جميع التجار'), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog).last,
        matching: find.text('إلغاء'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('مخبز الصباح'));
    await tester.pumpAndSettle();
    expect(find.text('اختيار وإضافة منتج'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog).last,
        matching: find.text('إلغاء'),
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('active product orders are shown and prevent deletion',
      (tester) async {
    final database = _ProductReviewDatabase()
      ..orders['order-1'] = {
        'id': 'order-1',
        'order_number': 'SHEM-102',
        'status': 'preparing',
        'customer_name': 'عميل الاختبار',
        'driver_id': 'driver-1',
        'items': [
          {'product_id': 'product-1', 'quantity': 2},
        ],
      };

    await tester.pumpWidget(
      MaterialApp(
        home: ProductManagementAdminScreen(databaseService: database),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('حذف المنتج'));
    await tester.pumpAndSettle();

    expect(find.text('لا يمكن حذف المنتج الآن'), findsOneWidget);
    expect(find.text('رقم الطلب: SHEM-102'), findsOneWidget);
    expect(find.text('العميل: عميل الاختبار'), findsOneWidget);
    expect(find.text('السائق: driver-1'), findsOneWidget);
    expect(find.text('تأكيد الحذف'), findsNothing);

    await tester.tap(find.text('إغلاق'));
    await tester.pumpAndSettle();
    expect(database.lastDeletedPath, isNull);
  });

  testWidgets('completed product orders require review before deletion',
      (tester) async {
    final database = _ProductReviewDatabase()
      ..orders['order-2'] = {
        'id': 'order-2',
        'order_number': 'SHEM-103',
        'status': 'delivered',
        'customer_name': 'عميلة سابقة',
        'driver_name': 'سائق سابق',
        'items': [
          {'product_id': 'product-1', 'quantity': 1},
        ],
      };

    await tester.pumpWidget(
      MaterialApp(
        home: ProductManagementAdminScreen(databaseService: database),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('حذف المنتج'));
    await tester.pumpAndSettle();

    expect(find.text('مراجعة حذف المنتج'), findsOneWidget);
    expect(find.text('رقم الطلب: SHEM-103'), findsOneWidget);
    expect(find.text('العميل: عميلة سابقة'), findsOneWidget);
    expect(find.text('السائق: سائق سابق'), findsOneWidget);

    await tester.tap(find.text('تأكيد الحذف'));
    await tester.pumpAndSettle();

    expect(database.lastDeletedPath, 'products/product-1');
    expect(database.products.containsKey('product-1'), isFalse);
  });

  testWidgets('product deletion is blocked when order lookup fails',
      (tester) async {
    final database = _ProductReviewDatabase()..failOrdersRead = true;

    await tester.pumpWidget(
      MaterialApp(
        home: ProductManagementAdminScreen(databaseService: database),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('حذف المنتج'));
    await tester.pumpAndSettle();

    expect(find.textContaining('تعذر التحقق من طلبات المنتج'), findsOneWidget);
    expect(database.lastDeletedPath, isNull);
  });

  testWidgets('a newly active order blocks deletion after confirmation',
      (tester) async {
    final database = _ProductReviewDatabase()
      ..addActiveOrderAfterFirstLookup = true;

    await tester.pumpWidget(
      MaterialApp(
        home: ProductManagementAdminScreen(databaseService: database),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('حذف المنتج'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تأكيد الحذف'));
    await tester.pumpAndSettle();

    expect(find.text('توقف حذف المنتج'), findsOneWidget);
    expect(find.text('رقم الطلب: NEW'), findsOneWidget);
    expect(database.lastDeletedPath, isNull);
  });
}

class _ProductReviewDatabase implements DatabaseService {
  final Map<String, Map<String, dynamic>> products = {
    'product-1': {
      'id': 'product-1',
      'name': 'منتج تجريبي',
      'merchant_id': 'merchant-1',
      'merchant_name': 'متجر تجريبي',
      'approval_status': 'pending',
      'category': 'عناية بالبشرة',
      'price': 125,
      'currency_symbol': 'ر.س',
      'stock': 14,
      'sizes': ['صغير', 'كبير'],
      'colors': ['أحمر', 'أزرق'],
      'description': 'وصف تفصيلي للمنتج',
      'image_url': 'https://example.com/cover.jpg',
      'image_urls': [
        'https://example.com/cover.jpg',
        'https://example.com/side.jpg',
      ],
      'video_url': 'https://example.com/product.mp4',
    },
  };
  final Map<String, Map<String, dynamic>> orders = {};
  String? lastUpdatedPath;
  String? lastDeletedPath;
  bool failOrdersRead = false;
  bool addActiveOrderAfterFirstLookup = false;
  int _ordersRead = 0;

  @override
  Future<Map<String, dynamic>> read(String path) async {
    if (path == 'products') return Map<String, dynamic>.from(products);
    if (path == 'orders') {
      if (failOrdersRead) throw StateError('Order lookup failed');
      _ordersRead++;
      if (_ordersRead == 2 && addActiveOrderAfterFirstLookup) {
        orders['order-new'] = {
          'id': 'order-new',
          'status': 'preparing',
          'items': [
            {'product_id': 'product-1', 'quantity': 1},
          ],
        };
      }
      return Map<String, dynamic>.from(orders);
    }
    if (path == 'profiles') {
      return {
        'merchant-1': {
          'id': 'merchant-1',
          'shop_name': 'متجر تجريبي',
          'role': 'merchant',
        },
        'merchant-2': {
          'id': 'merchant-2',
          'shop_name': 'مخبز الصباح',
          'full_name': 'صاحب المتجر الثاني',
          'phone': '733333333',
          'shop_category': 'مخبز',
          'shop_location': 'إب',
          'role': 'merchant',
        },
      };
    }
    return {};
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
  ) async {
    lastUpdatedPath = path;
    final productId =
        path.startsWith('products/') ? path.substring('products/'.length) : '';
    products[productId]?.addAll(data);
    return data;
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
    lastDeletedPath = path;
    if (path.startsWith('products/')) {
      products.remove(path.substring('products/'.length));
    }
  }
}
