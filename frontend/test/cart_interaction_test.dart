import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/models/product_model.dart';
import 'package:she_m_app/data/services/cart_service.dart';
import 'package:she_m_app/data/services/catalog_service.dart';
import 'package:she_m_app/data/services/currency_service.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/presentation/cart/cart_screen.dart';
import 'package:she_m_app/presentation/common/cart_interaction.dart';

class _CartCatalogDatabase implements DatabaseService {
  const _CartCatalogDatabase(this.data, {this.currencyRead});

  final Map<String, dynamic> data;
  final Future<Map<String, dynamic>>? currencyRead;

  @override
  Future<Map<String, dynamic>> read(String path) async {
    if (path == 'settings/currencies' && currencyRead != null) {
      return currencyRead!;
    }
    return Map<String, dynamic>.from(data[path] ?? const {});
  }

  @override
  Future<Map<String, dynamic>> write(
    String path,
    Map<String, dynamic> value,
  ) async =>
      value;

  @override
  Future<Map<String, dynamic>> update(
    String path,
    Map<String, dynamic> value,
  ) async =>
      value;

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
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      secureStorageChannel,
      (_) async => null,
    );
  });

  const product = ProductModel(
    id: 'p-1',
    name: 'قميص',
    price: 199,
    category: 'ملابس',
    description: 'وصف',
    imageUrl: '',
    available: true,
    merchantId: 'm-1',
  );

  setUp(() {
    CartService.instance.clear();
    CartService.instance.addProduct(product);
  });

  testWidgets(
      'cart waits for currency rates before showing a missing-rate warning',
      (tester) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final currencyRead = Completer<Map<String, dynamic>>();
    final database = _CartCatalogDatabase(
      const {'products': <String, dynamic>{}},
      currencyRead: currencyRead.future,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CartScreen(
          catalogService: CatalogService(databaseService: database),
          currencyService: CurrencyService(databaseService: database),
        ),
      ),
    );

    expect(
      find.text('سعر صرف إحدى العملات غير محدد من المدير.'),
      findsNothing,
    );

    currencyRead.complete({
      'SAR': {
        'code': 'SAR',
        'title': 'ريال سعودي',
        'symbol': 'ر.س',
        'rate_to_yer': 68,
      },
    });
    await tester.pumpAndSettle();

    expect(
      find.text('سعر صرف إحدى العملات غير محدد من المدير.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('cart summary appears to the right of checkout', (tester) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: CartScreen()),
    );

    final summary = find.text('ملخص الطلب');
    final checkout = find.text('إتمام الطلب');
    final selectedCount = find.byKey(const ValueKey('checkout_selected_count'));
    expect(summary, findsOneWidget);
    expect(checkout, findsOneWidget);
    expect(find.text('تُحسب أجرة التوصيل بعد تحديد العنوان'), findsOneWidget);
    expect(find.text('الإجمالي قبل التوصيل'), findsOneWidget);
    expect(find.text('التوصيل مجاني'), findsNothing);
    expect(find.descendant(of: selectedCount, matching: find.text('1')),
        findsOneWidget);
    expect(tester.getCenter(summary).dx,
        greaterThan(tester.getCenter(checkout).dx));

    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pump();
    expect(find.descendant(of: selectedCount, matching: find.text('0')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cart shows available products from matching categories',
      (tester) async {
    const matchingProduct = ProductModel(
      id: 'p-2',
      name: 'وشاح قطني',
      price: 120,
      category: 'ملابس',
      description: 'وشاح ناعم',
      imageUrl: '',
      available: true,
      merchantId: 'm-1',
    );
    const unrelatedProduct = ProductModel(
      id: 'p-3',
      name: 'مصباح مكتبي',
      price: 80,
      category: 'إلكترونيات',
      description: 'مصباح صغير',
      imageUrl: '',
      available: true,
      merchantId: 'm-2',
    );
    final catalogService = CatalogService(
      databaseService: _CartCatalogDatabase({
        'products': {
          product.id: product.toJson(),
          matchingProduct.id: matchingProduct.toJson(),
          unrelatedProduct.id: unrelatedProduct.toJson(),
        },
      }),
    );

    await tester.pumpWidget(
      MaterialApp(home: CartScreen(catalogService: catalogService)),
    );
    await tester.pumpAndSettle();

    expect(find.text('منتجات قد تناسبك'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('recommendation_product_p-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('recommendation_product_p-3')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('cart item displays its product cover image', (tester) async {
    const productWithImage = ProductModel(
      id: 'p-with-image',
      name: 'منتج بصورته',
      price: 199,
      category: 'ملابس',
      description: 'وصف',
      imageUrl: 'https://example.com/product-cover.jpg',
      available: true,
      merchantId: 'm-1',
    );
    CartService.instance
      ..clear()
      ..addProduct(productWithImage);

    await tester.pumpWidget(const MaterialApp(home: CartScreen()));

    final image = find.byKey(const ValueKey('cart-product-image-p-with-image'));
    expect(image, findsOneWidget);
    expect(
      find.descendant(of: image, matching: find.byType(Image)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling a duplicate addition leaves quantity unchanged',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                if (await confirmCartAddition(context, product)) {
                  CartService.instance.addProduct(product);
                }
              },
              child: const Text('إضافة'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('إضافة'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'المنتج موجود مسبقاً في السلة. هل تريد إضافته مجدداً؟ '
        'ستؤدي الموافقة إلى زيادة الكمية.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();

    expect(CartService.instance.items.single.quantity, 1);
  });

  testWidgets('confirming a duplicate addition increments quantity',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                if (await confirmCartAddition(context, product)) {
                  CartService.instance.addProduct(product);
                }
              },
              child: const Text('إضافة'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('إضافة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('موافقة'));
    await tester.pumpAndSettle();

    expect(CartService.instance.items.single.quantity, 2);
  });

  testWidgets('cart confirmation snackbar opens cart and disappears in time',
      (tester) async {
    var openedCart = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCartAddedSnackBar(
                context,
                onOpenCart: () => openedCart = true,
              ),
              child: const Text('إظهار الإشعار'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('إظهار الإشعار'));
    await tester.pumpAndSettle();
    expect(find.text('تمت إضافة المنتج إلى السلة'), findsOneWidget);
    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.behavior, SnackBarBehavior.floating);
    expect(tester.getSize(find.byType(SnackBar)).height, lessThanOrEqualTo(64));
    await tester.tap(find.text('فتح السلة'));
    expect(openedCart, isTrue);

    await tester.tap(find.text('إظهار الإشعار'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('تمت إضافة المنتج إلى السلة'), findsNothing);
  });
}
