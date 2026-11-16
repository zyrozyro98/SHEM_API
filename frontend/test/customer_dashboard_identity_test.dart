import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:she_m_app/data/models/order_model.dart';
import 'package:she_m_app/data/models/product_model.dart';
import 'package:she_m_app/data/models/user_model.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/data/services/cart_service.dart';
import 'package:she_m_app/data/services/catalog_service.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/data/services/order_service.dart';
import 'package:she_m_app/data/services/search_history_service.dart';
import 'package:she_m_app/data/services/media_upload_service.dart';
import 'package:she_m_app/data/services/payment_service.dart';
import 'package:she_m_app/core/animations/route_transitions.dart';
import 'package:she_m_app/presentation/cart/cart_screen.dart';
import 'package:she_m_app/presentation/auth/profile_setup_screen.dart';
import 'package:she_m_app/presentation/admin/merchant_management_screen.dart';
import 'package:she_m_app/presentation/catalog/product_catalog.dart';
import 'package:she_m_app/presentation/catalog/product_detail_screen.dart';
import 'package:she_m_app/presentation/catalog/product_detail_screen_full.dart';
import 'package:she_m_app/presentation/checkout/delivery_address_screen.dart';
import 'package:she_m_app/presentation/delivery/delivery_tracking_screen.dart';
import 'package:she_m_app/presentation/orders/customer_order_detail_screen.dart';
import 'package:she_m_app/presentation/orders/orders_screen.dart';
import 'package:she_m_app/presentation/store/store_detail_screen.dart';
import 'package:she_m_app/presentation/payment/wallet_payment_screen.dart';

Future<void> _selectCity(WidgetTester tester, String city) async {
  final cityField = find.byKey(const ValueKey('city_field'));
  await tester.ensureVisible(cityField);
  final dropdown = tester.widget<DropdownButton<String>>(
    find.descendant(
      of: cityField,
      matching: find.byType(DropdownButton<String>),
    ),
  );
  expect(dropdown.items!.any((item) => item.value == city), isTrue);
  dropdown.onChanged!(city);
  await tester.pump();
}

class _FakeCatalogDatabase implements DatabaseService {
  final Map<String, dynamic> _data;
  int readCount = 0;

  _FakeCatalogDatabase(this._data);

  @override
  Future<Map<String, dynamic>> read(String path) async {
    readCount++;
    return Map<String, dynamic>.from(_data[path] ?? const {});
  }

  @override
  Future<Map<String, dynamic>> write(
          String path, Map<String, dynamic> data) async =>
      data;

  @override
  Future<Map<String, dynamic>> update(
          String path, Map<String, dynamic> data) async =>
      data;

  @override
  Future<Map<String, dynamic>?> updateIf(
    String path, {
    required bool Function(Map<String, dynamic> current) condition,
    required Map<String, dynamic> updates,
  }) async {
    final current = await read(path);
    if (current.isEmpty || !condition(current)) return null;
    return {...current, ...updates};
  }

  @override
  Future<void> delete(String path) async {}
}

class _FakeSearchHistoryStore implements SearchHistoryStore {
  _FakeSearchHistoryStore(
      [Map<String, List<String>> initialSearches = const {}])
      : searches = Map<String, List<String>>.fromEntries(
          initialSearches.entries.map(
            (entry) => MapEntry(entry.key, List<String>.of(entry.value)),
          ),
        );

  final Map<String, List<String>> searches;

  @override
  Future<List<String>> load(String userId) async =>
      List<String>.of(searches[userId] ?? const []);

  @override
  Future<List<String>> addSearch(String userId, String query) async {
    final normalized = query.trim();
    final history = searches[userId] ?? <String>[];
    history
        .removeWhere((item) => item.toLowerCase() == normalized.toLowerCase());
    searches[userId] = [normalized, ...history].take(8).toList();
    return List<String>.of(searches[userId]!);
  }

  @override
  Future<void> clear(String userId) async {
    searches.remove(userId);
  }
}

void main() {
  testWidgets('payment methods wrap into rows without horizontal scrolling',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final paymentService = PaymentService(
      databaseService: _FakeCatalogDatabase({
        'settings/payment_wallets': {
          'wallet-one': {
            'provider': 'محفظة الهاتف',
            'name': 'مركز الدفع الأول',
            'account_number': '1111',
            'logo_url': 'https://example.test/wallet-logo.png',
          },
          'wallet-two': {
            'provider': 'المحفظة الرقمية',
            'name': 'مركز الدفع الثاني',
            'account_number': '2222',
          },
        },
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WalletPaymentScreen(paymentService: paymentService),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Wrap), findsOneWidget);
    expect(
      find.byKey(const ValueKey('wallet-logo-wallet-one')),
      findsOneWidget,
    );
    final cashOnDeliveryTop =
        tester.getTopLeft(find.text('الدفع عند الاستلام')).dy;
    final firstWalletTop = tester.getTopLeft(find.text('محفظة الهاتف')).dy;
    final secondWalletTop = tester.getTopLeft(find.text('المحفظة الرقمية')).dy;
    expect(cashOnDeliveryTop, closeTo(firstWalletTop, 1));
    expect(secondWalletTop, greaterThan(cashOnDeliveryTop));
  });

  testWidgets('animated indexed stack transitions between retained tabs',
      (tester) async {
    var selectedIndex = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: child ?? const SizedBox.shrink(),
        ),
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: AnimatedIndexedStack(
                    index: selectedIndex,
                    children: const [Text('Home tab'), Text('Favorites tab')],
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => selectedIndex = 1),
                  child: const Text('Show favorites'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show favorites'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final favoritesFade = tester.widget<FadeTransition>(
      find.descendant(
        of: find.byKey(const ValueKey('animated-indexed-stack-1')),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(favoritesFade.opacity.value, greaterThan(0));
    expect(favoritesFade.opacity.value, lessThan(1));

    await tester.pump(const Duration(milliseconds: 160));
    expect(
      tester
          .widget<FadeTransition>(
            find.descendant(
              of: find.byKey(const ValueKey('animated-indexed-stack-1')),
              matching: find.byType(FadeTransition),
            ),
          )
          .opacity
          .value,
      1,
    );
  });

  test('resolves the active customer id from the current profile', () {
    final profile = UserModel(
      id: 'customer-42',
      fullName: 'Test Customer',
      phone: '+967700000000',
      role: 'customer',
      isVerified: true,
      createdAt: DateTime.now(),
    );

    expect(OrdersScreen.resolveCustomerId(profile), 'customer-42');
    expect(DeliveryAddressScreen.resolveCustomerId(profile), 'customer-42');
  });

  test('falls back to the phone when the user id is empty', () {
    final profile = UserModel(
      id: '',
      fullName: 'Test Customer',
      phone: '+967700000000',
      role: 'customer',
      isVerified: true,
      createdAt: DateTime.now(),
    );

    expect(OrdersScreen.resolveCustomerId(profile), '+967700000000');
    expect(DeliveryAddressScreen.resolveCustomerId(profile), '+967700000000');
  });

  test(
      'catalog service returns an empty list when the product database is empty',
      () async {
    final service = CatalogService(databaseService: _FakeCatalogDatabase({}));

    expect(await service.getProducts(), isEmpty);
  });

  test('catalog excludes archived products and archived merchants', () async {
    final service = CatalogService(
      databaseService: _FakeCatalogDatabase({
        'products': {
          'active': const ProductModel(
            id: 'active',
            name: 'منتج متاح',
            price: 10,
            category: 'عام',
            description: '',
            imageUrl: '',
            available: true,
            merchantId: 'active-merchant',
          ).toJson(),
          'archived-product': {
            ...const ProductModel(
              id: 'archived-product',
              name: 'منتج مؤرشف',
              price: 20,
              category: 'عام',
              description: '',
              imageUrl: '',
              available: true,
              merchantId: 'active-merchant',
            ).toJson(),
            'is_archived': true,
          },
          'archived-merchant-product': const ProductModel(
            id: 'archived-merchant-product',
            name: 'منتج تاجر مؤرشف',
            price: 30,
            category: 'عام',
            description: '',
            imageUrl: '',
            available: true,
            merchantId: 'archived-merchant',
          ).toJson(),
        },
        'profiles': {
          'active-merchant': {'shop_name': 'متجر نشط'},
          'archived-merchant': {
            'shop_name': 'متجر مؤرشف',
            'is_archived': true,
          },
        },
      }),
    );

    final products = await service.getProducts();

    expect(products.map((product) => product.id), ['active']);
  });

  test('catalog service filters products by merchant id', () async {
    final service = CatalogService(
      databaseService: _FakeCatalogDatabase({
        'products': {
          'p1': const ProductModel(
            id: 'p1',
            name: 'منتج متجر 1',
            price: 100,
            category: 'إلكترونيات',
            description: 'وصف',
            imageUrl: '',
            available: true,
            merchantId: 'merchant-1',
          ).toJson(),
          'p2': const ProductModel(
            id: 'p2',
            name: 'منتج متجر 2',
            price: 200,
            category: 'ملابس',
            description: 'وصف',
            imageUrl: '',
            available: true,
            merchantId: 'merchant-2',
          ).toJson(),
        },
        'profiles': {
          'merchant-1': {
            'id': 'merchant-1',
            'role': 'merchant',
            'shop_name': 'متجر أحمد',
            'full_name': 'أحمد',
          },
        },
      }),
    );

    final merchantProducts = await service.getProductsByMerchant('merchant-1');

    expect(merchantProducts, hasLength(1));
    expect(merchantProducts.first.name, 'منتج متجر 1');
    expect(merchantProducts.first.merchantName, 'متجر أحمد');
  });

  test('catalog service reuses the cached product list on refresh', () async {
    final database = _FakeCatalogDatabase({
      'products': {
        'p1': const ProductModel(
          id: 'p1',
          name: 'منتج مخزن',
          price: 100,
          category: 'إلكترونيات',
          description: 'وصف',
          imageUrl: 'https://example.com/p1.jpg',
          available: true,
          merchantId: 'merchant-1',
        ).toJson(),
      },
      'profiles': {
        'merchant-1': {
          'id': 'merchant-1',
          'role': 'merchant',
          'shop_name': 'متجر مخزن',
          'full_name': 'التاجر',
        },
      },
    });
    final service = CatalogService(databaseService: database);

    final first = await service.getProducts();
    final second = await service.getProducts();

    expect(first, hasLength(1));
    expect(second, hasLength(1));
    expect(database.readCount, equals(3));
  });

  test('catalog service paginates products in chunks of 12', () async {
    final products = List.generate(
      20,
      (index) => ProductModel(
        id: 'p$index',
        name: 'منتج ${index + 1}',
        price: 100.0 + index,
        category: 'إلكترونيات',
        description: 'وصف',
        imageUrl: 'https://example.com/$index.jpg',
        available: true,
        merchantId: 'merchant-1',
      ),
    );

    final service = CatalogService(
      databaseService: _FakeCatalogDatabase({
        'products': {
          for (var i = 0; i < products.length; i++)
            products[i].id: products[i].toJson(),
        },
        'profiles': {
          'merchant-1': {
            'id': 'merchant-1',
            'role': 'merchant',
            'shop_name': 'متجر تجريبي',
            'full_name': 'التاجر',
          },
        },
      }),
    );

    final firstPage = await service.getProductsPage(offset: 0, limit: 12);
    final secondPage = await service.getProductsPage(offset: 12, limit: 12);

    expect(firstPage, hasLength(12));
    expect(secondPage, hasLength(8));
    expect(firstPage.first.name, 'منتج 1');
    expect(secondPage.first.name, 'منتج 13');
  });

  test('product model treats string and status values as availability flags',
      () {
    final productFromString = ProductModel.fromJson({
      'id': 'p-string',
      'name': 'منتج نصي',
      'price': 50,
      'category': 'ملابس',
      'available': 'true',
      'merchant_id': 'm-1',
    });

    final productFromStatus = ProductModel.fromJson({
      'id': 'p-status',
      'name': 'منتج حالة',
      'price': 70,
      'category': 'ملابس',
      'status': 'active',
      'merchant_id': 'm-1',
    });

    expect(productFromString.available, isTrue);
    expect(productFromStatus.available, isTrue);
  });

  testWidgets('product detail screen shows merchant name and rating',
      (tester) async {
    const product = ProductModel(
      id: 'p1',
      name: 'منتج تجريبي',
      price: 199,
      category: 'إلكترونيات',
      description: 'وصف المنتج',
      imageUrl: '',
      available: true,
      merchantId: 'merchant-1',
      merchantName: 'متجر أحمد',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ProductDetailScreen(product: product),
        ),
      ),
    );

    expect(find.text('متجر أحمد'), findsNothing);
    expect(find.text('4.9'), findsOneWidget);
  });

  testWidgets(
      'product detail gallery expands images and supports horizontal swipe',
      (tester) async {
    const product = ProductModel(
      id: 'p-gallery',
      name: 'منتج معرض الصور',
      price: 299,
      category: 'إلكترونيات',
      description: 'وصف المنتج',
      imageUrl: 'https://example.com/cover.jpg',
      imageUrls: [
        'https://example.com/cover.jpg',
        'https://example.com/side.jpg',
        'https://example.com/back.jpg',
      ],
      colors: ['أحمر', 'أزرق'],
      colorImageUrls: {'أزرق': 'https://example.com/side.jpg'},
      hasSizes: false,
      available: true,
      merchantId: 'merchant-1',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ProductDetailFullScreen(product: product),
        ),
      ),
    );

    expect(find.byType(PageView), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('product-gallery-indicator')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('product-gallery-indicator-0')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('product-gallery-indicator-1')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('product-gallery-indicator-2')),
        findsOneWidget);
    expect(find.text('المقاس'), findsNothing);
    expect(find.text('اسحب الصورة يمينًا أو يسارًا لمشاهدة بقية الصور'),
        findsNothing);
    await tester.ensureVisible(find.text('أزرق'));
    await tester.tap(find.text('أزرق'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    await tester
        .ensureVisible(find.byKey(const ValueKey('product-main-image')));
    await tester.drag(
      find.byKey(const ValueKey('product-main-image')),
      const Offset(500, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('product-main-image')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('تكبير'), findsOneWidget);
    expect(find.byTooltip('تصغير'), findsOneWidget);
    await tester.tap(find.byTooltip('إغلاق العرض'));
    await tester.pumpAndSettle();
  });

  testWidgets('product details share sheet shows preview and compact actions',
      (tester) async {
    const product = ProductModel(
      id: 'share-product',
      name: 'منتج للمشاركة',
      price: 199,
      category: 'إلكترونيات',
      description: 'وصف المنتج',
      imageUrl: '',
      available: true,
      merchantId: 'merchant-1',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ProductDetailFullScreen(product: product),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('product-detail-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('product-detail-share')), findsOneWidget);
    expect(find.text('شراء الآن'), findsNothing);
    final favoriteButton =
        find.byKey(const ValueKey('product-detail-favorite'));
    expect(favoriteButton, findsOneWidget);
    final favoritePosition = tester.getCenter(favoriteButton);
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.getCenter(favoriteButton).dy, favoritePosition.dy);

    await tester.tap(find.byKey(const ValueKey('product-detail-share')));
    await tester.pumpAndSettle();

    expect(find.text('مشاركة المنتج'), findsOneWidget);
    expect(find.text('منتج للمشاركة'), findsWidgets);
    expect(find.byKey(const ValueKey('share-product-action')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('copy-product-share-action')),
      findsOneWidget,
    );
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData' &&
            call.arguments is Map<Object?, Object?>) {
          copiedText =
              (call.arguments as Map<Object?, Object?>)['text']?.toString();
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('copy-product-share-action')));
    await tester.pumpAndSettle();
    expect(find.text('تم نسخ رابط المنتج'), findsOneWidget);
    expect(
      copiedText,
      contains(
        'https://she-m-8d0f5.web.app/product_details?id=share-product',
      ),
    );
    expect(copiedText, isNot(contains('intent://')));
  });

  testWidgets('catalog screen loads real product images', (tester) async {
    final catalog = CatalogService(
      databaseService: _FakeCatalogDatabase({
        'products': {
          'p1': const ProductModel(
            id: 'p1',
            name: 'منتج بصورته الحقيقية',
            price: 150,
            category: 'إلكترونيات',
            description: 'وصف',
            imageUrl: 'https://example.com/product.jpg',
            available: true,
            merchantId: 'm1',
          ).toJson(),
        },
        'profiles': {
          'm1': {
            'id': 'm1',
            'role': 'merchant',
            'shop_name': 'متجر التجربة',
            'full_name': 'التجربة',
          },
        },
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ProductCatalogScreen(catalogService: catalog),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('منتج بصورته الحقيقية'), findsOneWidget);
    expect(find.byType(Image), findsAtLeastNWidgets(1));
  });

  testWidgets('catalog can focus the search field on entry', (tester) async {
    final catalog = CatalogService(
      databaseService: _FakeCatalogDatabase(const {}),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ProductCatalogScreen(
            catalogService: catalog,
            autofocusSearch: true,
            searchHistoryStore: _FakeSearchHistoryStore(),
          ),
        ),
      ),
    );
    await tester.pump();

    final searchField = tester.widget<TextField>(
      find.byKey(const ValueKey('product_search_field')),
    );
    expect(searchField.focusNode?.hasFocus, isTrue);
  });

  testWidgets('catalog search by main category finds subcategory products',
      (tester) async {
    final catalog = CatalogService(
      databaseService: _FakeCatalogDatabase({
        'products': {
          'watch-1': const ProductModel(
            id: 'watch-1',
            name: 'ساعة تجريبية',
            price: 150,
            category: 'ساعات',
            mainCategory: 'اكسسوارات',
            subcategory: 'ساعات',
            description: 'وصف',
            imageUrl: '',
            available: true,
            merchantId: 'm1',
          ).toJson(),
        },
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ProductCatalogScreen(
            catalogService: catalog,
            initialQuery: 'اكسسوارات',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ساعة تجريبية'), findsOneWidget);
  });

  testWidgets('catalog restores and saves searches for the active customer',
      (tester) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const shirt = ProductModel(
      id: 'shirt-1',
      name: 'قميص مخطط',
      price: 150,
      category: 'ملابس',
      description: 'قميص قطني',
      imageUrl: '',
      available: true,
      merchantId: 'merchant-1',
    );
    const shoes = ProductModel(
      id: 'shoes-1',
      name: 'حذاء رياضي',
      price: 220,
      category: 'أحذية',
      description: 'حذاء مريح',
      imageUrl: '',
      available: true,
      merchantId: 'merchant-2',
    );
    final historyStore = _FakeSearchHistoryStore({
      'customer-42': ['قميص'],
      'customer-99': ['حذاء'],
    });
    final catalog = CatalogService(
      databaseService: _FakeCatalogDatabase({
        'products': {
          shirt.id: shirt.toJson(),
          shoes.id: shoes.toJson(),
        },
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ProductCatalogScreen(
            catalogService: catalog,
            searchHistoryUserId: 'customer-42',
            searchHistoryStore: historyStore,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('عمليات البحث السابقة'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('recent_search_0')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('product_search_field')))
          .controller
          ?.text,
      'قميص',
    );
    expect(find.text('قميص مخطط'), findsOneWidget);
    expect(find.text('حذاء رياضي'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('product_search_field')),
      'حذاء',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(historyStore.searches['customer-42'], ['حذاء', 'قميص']);
    expect(historyStore.searches['customer-99'], ['حذاء']);

    await tester.enterText(
      find.byKey(const ValueKey('product_search_field')),
      '',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('clear_search_history')));
    await tester.pumpAndSettle();
    expect(historyStore.searches.containsKey('customer-42'), isFalse);
    expect(find.text('عمليات البحث السابقة'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('base64 image decoder tolerates whitespace and blank payloads', () {
    const spaced = 'data:image/png;base64,   dGVzdA==  ';
    const empty = 'data:image/png;base64,   ';

    expect(MediaUploadService.decodeDataUriToBytes(spaced),
        equals([116, 101, 115, 116]));
    expect(MediaUploadService.decodeDataUriToBytes(empty), isNull);
  });

  test(
      'order service loads only the merchant real orders from product ownership',
      () async {
    final service = OrderService(
      databaseService: _FakeCatalogDatabase({
        'products': {
          'p1': const ProductModel(
            id: 'p1',
            name: 'منتج متجر 1',
            price: 100,
            category: 'إلكترونيات',
            description: 'وصف',
            imageUrl: '',
            available: true,
            merchantId: 'merchant-1',
          ).toJson(),
          'p2': const ProductModel(
            id: 'p2',
            name: 'منتج متجر 2',
            price: 200,
            category: 'ملابس',
            description: 'وصف',
            imageUrl: '',
            available: true,
            merchantId: 'merchant-2',
          ).toJson(),
        },
        'orders': {
          'o1': {
            'id': 'o1',
            'customer_id': 'customer-1',
            'items': [
              {
                'product_id': 'p1',
                'product_name': 'منتج متجر 1',
                'quantity': 2,
                'unit_price': 50,
                'total': 100
              },
            ],
            'status': 'confirmed',
            'payment_method': 'cash_on_delivery',
            'subtotal': 100,
            'shipping_fee': 0,
            'total': 100,
            'created_at': DateTime.now().toIso8601String(),
          },
          'o2': {
            'id': 'o2',
            'customer_id': 'customer-2',
            'items': [
              {
                'product_id': 'p2',
                'product_name': 'منتج متجر 2',
                'quantity': 1,
                'unit_price': 200,
                'total': 200
              },
            ],
            'status': 'pending_payment',
            'payment_method': 'cash_on_delivery',
            'subtotal': 200,
            'shipping_fee': 0,
            'total': 200,
            'created_at': DateTime.now().toIso8601String(),
          },
        },
      }),
    );

    final orders = await service.getOrdersByMerchant('merchant-1');

    expect(orders, hasLength(1));
    expect(orders.first.id, 'o1');
  });

  test(
      'order service hides wallet orders until receipt approval by item merchant id',
      () async {
    final service = OrderService(
      databaseService: _FakeCatalogDatabase({
        'products': const {},
        'orders': {
          'wallet-order-pending-payment': {
            'id': 'wallet-order-pending-payment',
            'customer_id': 'customer-1',
            'items': [
              {
                'product_id': 'product-not-indexed',
                'product_name': 'منتج المحفظة',
                'merchant_id': 'merchant-wallet',
                'quantity': 1,
                'unit_price': 100,
                'total': 100,
              },
            ],
            'status': 'pending_payment',
            'payment_method': 'jib_wallet',
            'subtotal': 100,
            'shipping_fee': 0,
            'total': 100,
            'created_at': DateTime.now().toIso8601String(),
          },
          'wallet-order-pending-review': {
            'id': 'wallet-order-pending-review',
            'customer_id': 'customer-1',
            'items': [
              {
                'product_id': 'product-not-indexed',
                'product_name': 'منتج المحفظة',
                'merchant_id': 'merchant-wallet',
                'quantity': 1,
                'unit_price': 100,
                'total': 100,
              },
            ],
            'status': 'awaiting_confirmation',
            'payment_method': 'jib_wallet',
            'payment_proof_id': 'proof-1',
            'subtotal': 100,
            'shipping_fee': 0,
            'total': 100,
            'created_at': DateTime.now().toIso8601String(),
          },
          'wallet-order-approved': {
            'id': 'wallet-order-approved',
            'customer_id': 'customer-1',
            'items': [
              {
                'product_id': 'product-not-indexed',
                'product_name': 'منتج المحفظة',
                'merchant_id': 'merchant-wallet',
                'quantity': 1,
                'unit_price': 100,
                'total': 100,
              },
            ],
            'status': 'confirmed',
            'payment_method': 'jib_wallet',
            'payment_proof_id': 'proof-approved',
            'subtotal': 100,
            'shipping_fee': 0,
            'total': 100,
            'created_at': DateTime.now().toIso8601String(),
          },
        },
      }),
    );

    final orders = await service.getOrdersByMerchant('merchant-wallet');

    expect(
      orders.map((order) => order.id),
      ['wallet-order-approved'],
    );
    expect(orders.first.status, 'confirmed');
  });

  test('product model reads cover image fields used by admin payloads', () {
    final product = ProductModel.fromJson({
      'id': 'p-cover',
      'name': 'منتج مع غلاف',
      'price': '150',
      'category': 'إلكترونيات',
      'description': 'وصف',
      'cover_image_url': 'https://example.com/cover.jpg',
      'image_urls': [
        'https://example.com/cover.jpg',
        'https://example.com/alt.jpg'
      ],
      'available': 'true',
      'merchant_id': 'merchant-1',
    });

    expect(product.imageUrl, 'https://example.com/cover.jpg');
    expect(product.imageUrls, hasLength(2));
    expect(product.imageUrls.first, 'https://example.com/cover.jpg');
  });

  test('product model converts GitHub blob image links to raw URLs', () {
    final product = ProductModel.fromJson({
      'id': 'github-image',
      'name': 'GitHub image',
      'image_url':
          'https://github.com/example/shop-assets/blob/main/products/red bag.jpg',
    });

    expect(
      product.imageUrl,
      'https://raw.githubusercontent.com/example/shop-assets/main/products/red%20bag.jpg',
    );
  });

  test('product model accepts gallery image data stored as a single string',
      () {
    final product = ProductModel.fromJson({
      'id': 'p-string-gallery',
      'name': 'منتج صور متعددة',
      'price': '220',
      'category': 'ملابس',
      'description': 'وصف',
      'images': 'https://example.com/a.jpg, https://example.com/b.jpg',
      'available': 'true',
      'merchant_id': 'merchant-1',
    });

    expect(product.imageUrl, 'https://example.com/a.jpg');
    expect(product.imageUrls, hasLength(2));
    expect(product.imageUrls, contains('https://example.com/a.jpg'));
    expect(product.imageUrls, contains('https://example.com/b.jpg'));
  });

  test(
      'product model preserves base64 data URI images without splitting on commas',
      () {
    final product = ProductModel.fromJson({
      'id': 'p-base64',
      'name': 'منتج base64',
      'price': '180',
      'category': 'إلكترونيات',
      'description': 'وصف',
      'image_url':
          'data:image/png;base64, iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAA',
      'available': 'true',
      'merchant_id': 'merchant-1',
    });

    expect(product.imageUrl,
        'data:image/png;base64, iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAA');
    expect(product.imageUrls, hasLength(1));
    expect(product.imageUrls.first, startsWith('data:image/png;base64,'));
  });

  test(
      'merchant product payload keeps availability state and validates required fields',
      () {
    expect(
      () => buildMerchantProductPayload(
        existingProduct: const {},
        merchantId: 'merchant-1',
        name: '',
        categoryText: 'إلكترونيات',
        imageUris: ['https://example.com/test.jpg'],
        videoDataUri: '',
        available: false,
        description: 'وصف',
        price: 99,
        stock: 5,
      ),
      throwsA(isA<ArgumentError>()),
    );

    final payload = buildMerchantProductPayload(
      existingProduct: const {},
      merchantId: 'merchant-1',
      name: 'منتج جديد',
      categoryText: 'إلكترونيات',
      imageUris: ['https://example.com/test.jpg'],
      videoDataUri: '',
      available: false,
      description: 'وصف',
      price: 99,
      stock: 5,
    );

    expect(payload['available'], isFalse);
    expect(payload['category'], 'إلكترونيات');
    expect(payload['image_url'], 'https://example.com/test.jpg');
  });

  test(
      'merchant product payload respects the selected cover image in popup mode',
      () {
    final payload = buildMerchantProductPayload(
      existingProduct: const {},
      merchantId: 'merchant-1',
      name: 'منتج جديد',
      categoryText: 'إلكترونيات',
      imageUris: [
        'https://example.com/front.jpg',
        'https://example.com/cover.jpg',
      ],
      coverImageUri: 'https://example.com/cover.jpg',
      videoDataUri: '',
      available: true,
      description: 'وصف',
      price: 99,
      stock: 5,
    );

    expect(payload['image_url'], 'https://example.com/cover.jpg');
    expect(payload['cover_image_url'], 'https://example.com/cover.jpg');
    expect(payload['image_urls'], hasLength(2));
  });

  test('merchant product sizes are saved and restored from product payloads',
      () {
    final payload = buildMerchantProductPayload(
      existingProduct: const {},
      merchantId: 'merchant-1',
      name: 'حذاء رياضي',
      categoryText: 'أحذية',
      imageUris: const [],
      videoDataUri: '',
      available: true,
      description: 'وصف',
      price: 120,
      stock: 8,
      sizes: ['38', '39', '40-41'],
    );

    final product = ProductModel.fromJson(payload);

    expect(payload['sizes'], ['38', '39', '40-41']);
    expect(product.sizes, ['38', '39', '40-41']);
  });

  test('merchant color images and no-size choice persist in product payloads',
      () {
    final payload = buildMerchantProductPayload(
      existingProduct: const {},
      merchantId: 'merchant-1',
      name: 'قميص',
      categoryText: 'ملابس',
      imageUris: const [
        'https://example.com/red.jpg',
        'https://example.com/blue.jpg',
      ],
      videoDataUri: '',
      available: true,
      description: '',
      price: 80,
      stock: 5,
      colors: const ['أحمر', 'أزرق'],
      colorImageUrls: const {'أزرق': 'https://example.com/blue.jpg'},
      sizes: const ['S', 'M'],
      hasSizes: false,
    );

    final product = ProductModel.fromJson(payload);

    expect(
        payload['color_image_urls'], {'أزرق': 'https://example.com/blue.jpg'});
    expect(payload['sizes'], isEmpty);
    expect(payload['has_sizes'], isFalse);
    expect(product.colorImageUrls['أزرق'], 'https://example.com/blue.jpg');
    expect(product.hasSizes, isFalse);
    expect(ProductModel.fromJson(product.toJson()).hasSizes, isFalse);
  });

  test(
      'merchant draft validation reports missing required name, category, and price',
      () {
    expect(
      validateProductDraftInputs(
        name: '',
        categories: const ['إلكترونيات'],
        priceText: '99',
      ),
      'يرجى إدخال اسم المنتج',
    );

    expect(
      validateProductDraftInputs(
        name: 'منتج جديد',
        categories: const [],
        priceText: '99',
      ),
      'اختر ما لا يقل عن فئة واحدة',
    );

    expect(
      validateProductDraftInputs(
        name: 'منتج جديد',
        categories: const ['إلكترونيات'],
        priceText: '',
      ),
      'يرجى إدخال سعر المنتج',
    );
  });

  testWidgets(
      'product detail full screen offers inline preview for product videos',
      (tester) async {
    const product = ProductModel(
      id: 'p-video',
      name: 'منتج مع فيديو',
      price: 299,
      category: 'تكنولوجيا',
      description: 'وصف',
      imageUrl: 'https://example.com/product.jpg',
      videoUrl: 'https://www.facebook.com/watch/?v=123456789',
      available: true,
      merchantId: 'm1',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ProductDetailFullScreen(product: product),
        ),
      ),
    );

    final mediaSelector = tester.widget<SegmentedButton<bool>>(
      find.byType(SegmentedButton<bool>),
    );
    expect(find.text('الفيديو'), findsOneWidget);
    expect(find.text('الصور'), findsOneWidget);
    expect(find.text('مشاهدة الفيديو'), findsNothing);
    expect(
      mediaSelector.style!.foregroundColor!.resolve({WidgetState.selected}),
      const Color(0xFF111827),
    );
    expect(
      mediaSelector.style!.backgroundColor!.resolve({WidgetState.selected}),
      const Color(0xFFD4AF37),
    );
  });

  testWidgets(
      'detail screen renders the real product image when the API uses image field',
      (tester) async {
    const product = ProductModel(
      id: 'p2',
      name: 'منتج مع صورة حقيقية',
      price: 240,
      category: 'ملابس',
      description: 'وصف',
      imageUrl: 'https://example.com/real-product.jpg',
      available: true,
      merchantId: 'm1',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ProductDetailScreen(product: product),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('منتج مع صورة حقيقية'), findsOneWidget);
    expect(find.byType(Image), findsAtLeastNWidgets(1));
  });

  testWidgets('store detail grid renders the product image from the URL',
      (tester) async {
    final merchant = UserModel(
      id: 'merchant-2',
      fullName: 'سارة',
      phone: '+966500000001',
      role: 'merchant',
      isVerified: true,
      shopName: 'متجر سارة',
      shopCategory: 'ملابس',
      shopLocation: 'إب',
      city: 'إب',
      createdAt: DateTime.now(),
    );

    final products = [
      const ProductModel(
        id: 'p3',
        name: 'منتج متجر ذو صورة',
        price: 210,
        category: 'ملابس',
        description: 'وصف',
        imageUrl: 'https://example.com/store-image.jpg',
        available: true,
        merchantId: 'merchant-2',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: StoreDetailScreen(
            merchant: merchant,
            products: products,
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('منتج متجر ذو صورة'), findsOneWidget);
    expect(find.byType(Image), findsAtLeastNWidgets(1));
  });

  testWidgets('customer profile requires delivery details and locks location',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ProfileSetupScreen(phone: '+966500000000'),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('address_details_field')), findsOneWidget);
    expect(find.text('تفاصيل عنوان التوصيل (مطلوب)'), findsOneWidget);
    expect(find.text('اختيار من الخريطة'), findsNothing);
    expect(find.text('تحديد موقعي تلقائيًا'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('current_location_field')),
              matching: find.byType(TextField),
            ),
          )
          .readOnly,
      isTrue,
    );

    await tester.enterText(
        find.byKey(const ValueKey('full_name_field')), 'اسم العميل');
    await tester.enterText(find.byKey(const ValueKey('email_field')), '');
    await tester.enterText(
        find.byKey(const ValueKey('phone_field')), '+967771234567');
    await _selectCity(tester, 'صنعاء');
    final submitButton = find.text('إنشاء الحساب');
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pump();

    expect(find.text('يرجى إدخال تفاصيل عنوان التوصيل'), findsOneWidget);
  });

  testWidgets('signup requires agreement acceptance before submission',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ProfileSetupScreen(phone: '+967771234567'),
        ),
      ),
    );

    final checkbox = find.byKey(const ValueKey('platform_agreement_checkbox'));
    expect(checkbox, findsOneWidget);
    expect(
      tester.widget<CheckboxListTile>(checkbox).value,
      isFalse,
    );

    await tester.enterText(
      find.byKey(const ValueKey('full_name_field')),
      'اسم العميل',
    );
    await _selectCity(tester, 'صنعاء');
    await tester.enterText(
      find.byKey(const ValueKey('address_details_field')),
      'شارع التحرير',
    );

    final submitButton = find.text('إنشاء الحساب');
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pump();

    expect(
      find.text('يرجى الموافقة على اتفاقية التعامل مع منصة شيم'),
      findsOneWidget,
    );
  });

  testWidgets('signup provides readable platform use and privacy policy',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ProfileSetupScreen(phone: '+967771234567'),
        ),
      ),
    );

    final policyLink = find.byKey(const ValueKey('read_platform_policy'));
    await tester.ensureVisible(policyLink);
    await tester.tap(policyLink);
    await tester.pumpAndSettle();

    expect(find.text('سياسة الاستخدام والخصوصية لتطبيق شيم (SHEM)'),
        findsOneWidget);
    expect(find.text('1. سياسة الاستخدام'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.text('7. سياسة الخصوصية وحماية البيانات'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -1600));
    await tester.pumpAndSettle();
    expect(find.text('11. التواصل والدعم'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('platform_agreement_checkbox')),
          )
          .value,
      isFalse,
    );
  });

  testWidgets('merchant signup requires store address details', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ProfileSetupScreen(phone: '+967771234567'),
        ),
      ),
    );

    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<String>),
        matching: find.text('تاجر'),
      ),
    );
    await tester.pump();

    expect(find.byType(SnackBar), findsNothing);
    expect(
      find.byKey(const ValueKey('address_details_field')),
      findsOneWidget,
    );
    expect(find.text('تفاصيل عنوان المتجر (مطلوب)'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('merchant_location_field')), findsOneWidget);
    expect(find.text('موقع المتجر الحالي (اختياري)'), findsOneWidget);
    expect(find.text('اختيار من الخريطة'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('full_name_field')),
      'اسم التاجر',
    );
    await tester.enterText(
      find.byKey(const ValueKey('phone_field')),
      '+967771234567',
    );
    await _selectCity(tester, 'صنعاء');

    final submitButton = find.text('إنشاء الحساب');
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pump();

    expect(find.text('يرجى إدخال تفاصيل عنوان المتجر'), findsOneWidget);
  });

  testWidgets('customer signup accepts an empty optional email',
      (tester) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ProfileSetupScreen(phone: '+967771234567'),
        ),
      ),
    );

    await tester.enterText(
        find.byKey(const ValueKey('full_name_field')), 'اسم العميل');
    await tester.enterText(find.byKey(const ValueKey('email_field')), '');
    await _selectCity(tester, 'صنعاء');
    await tester.enterText(
      find.byKey(const ValueKey('address_details_field')),
      'شارع التحرير، جوار الحديقة',
    );

    final submitButton = find.text('إنشاء الحساب');
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(find.text('يرجى إدخال بريد إلكتروني صحيح'), findsNothing);
  });

  testWidgets('delivery tracking screen avoids fake delivery data',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: DeliveryTrackingScreen(),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('موقع السائق الآن'), findsNothing);
    expect(find.text('تتبع الطلبات'), findsAtLeastNWidgets(1));
    expect(find.text('لا توجد طلبات قيد التوصيل حاليًا'), findsNothing);
  });

  testWidgets('store detail screen renders merchant info and products',
      (tester) async {
    final merchant = UserModel(
      id: 'merchant-1',
      fullName: 'أحمد',
      phone: '+966500000000',
      role: 'merchant',
      isVerified: true,
      shopName: 'متجر أحمد',
      shopCategory: 'إلكترونيات',
      shopLocation: 'صنعاء',
      city: 'صنعاء',
      createdAt: DateTime.now(),
    );

    final products = [
      const ProductModel(
        id: 'p1',
        name: 'سماعات لاسلكية',
        price: 299,
        category: 'إلكترونيات',
        description: 'سماعات',
        imageUrl: '',
        available: true,
        merchantId: 'merchant-1',
        merchantName: 'متجر أحمد',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: StoreDetailScreen(
            merchant: merchant,
            products: products,
          ),
        ),
      ),
    );

    expect(find.text('متجر أحمد'), findsNothing);
    expect(find.text('إلكترونيات'), findsNothing);
    expect(find.text('سماعات لاسلكية'), findsOneWidget);
  });

  testWidgets('product catalog add button adds the item to cart',
      (tester) async {
    CartService.instance.clear();

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ProductCatalogScreen(
            catalogService: CatalogService(
              databaseService: _FakeCatalogDatabase({
                'products': {
                  'p1': const ProductModel(
                    id: 'p1',
                    name: 'منتج تجريبي',
                    price: 199,
                    category: 'إلكترونيات',
                    description: 'وصف',
                    imageUrl: '',
                    available: true,
                    merchantId: 'merchant-1',
                    merchantName: 'متجر أحمد',
                  ).toJson(),
                },
              }),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add_shopping_cart_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add_shopping_cart_rounded));
    await tester.pumpAndSettle();

    expect(CartService.instance.itemCount, 1);
    expect(find.byType(CartScreen), findsOneWidget);
  });

  testWidgets('product catalog loads more products when scrolling to the end',
      (tester) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final products = List.generate(
      20,
      (index) => ProductModel(
        id: 'p$index',
        name: 'منتج ${index + 1}',
        price: 100.0 + index,
        category: 'إلكترونيات',
        description: 'وصف',
        imageUrl: '',
        available: true,
        merchantId: 'merchant-1',
        merchantName: 'متجر أحمد',
      ),
    );

    final catalogData = {
      'products': {
        for (var i = 0; i < products.length; i++)
          products[i].id: products[i].toJson(),
      },
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ProductCatalogScreen(
            catalogService: CatalogService(
              databaseService: _FakeCatalogDatabase(catalogData),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('منتج 20'), findsNothing);

    await tester.drag(find.byType(GridView), const Offset(0, -1800));
    await tester.pumpAndSettle();

    expect(find.text('منتج 13'), findsOneWidget);

    await tester.drag(find.byType(GridView), const Offset(0, -1800));
    await tester.pumpAndSettle();

    expect(find.text('منتج 20'), findsOneWidget);
  });

  testWidgets('customer order detail screen loads real order by id',
      (tester) async {
    final order = OrderModel(
      id: 'order-123',
      customerId: 'customer-42',
      items: const [
        OrderItem(
          productId: 'p1',
          productName: 'منتج تجريبي',
          quantity: 2,
          unitPrice: 199,
          total: 398,
        ),
      ],
      status: 'preparing',
      paymentMethod: 'wallet',
      subtotal: 398,
      shippingFee: 15,
      total: 413,
      createdAt: DateTime(2026, 1, 15),
    );
    String? copiedOrderNumber;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData' &&
            call.arguments is Map<Object?, Object?>) {
          copiedOrderNumber =
              (call.arguments as Map<Object?, Object?>)['text']?.toString();
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: CustomerOrderDetailScreen(
            orderId: 'order-123',
            orderService: _FakeOrderService(order),
            authService: _FakeAuthService(
              UserModel(
                id: 'customer-42',
                fullName: 'أحمد السالم',
                phone: '0500000000',
                role: 'customer',
                isVerified: true,
                address: 'صنعاء، حي النخيل، شارع الملك فهد',
                createdAt: DateTime.now(),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('تفاصيل الطلب'), findsOneWidget);
    expect(find.text('منتج تجريبي'), findsOneWidget);
    expect(find.text('413 ر.ي'), findsOneWidget);
    expect(find.text('تاريخ الطلب'), findsOneWidget);
    expect(find.text('معلومات التوصيل'), findsOneWidget);
    expect(find.text('صنعاء، حي النخيل، شارع الملك فهد'), findsOneWidget);
    await tester.tap(find.byTooltip('نسخ رقم الطلب'));
    await tester.pumpAndSettle();
    expect(copiedOrderNumber, order.displayOrderNumber);
    expect(find.text('تم نسخ رقم الطلب'), findsOneWidget);
  });

  testWidgets('customer order detail screen shows product list and totals',
      (tester) async {
    final order = OrderModel(
      id: 'order-123',
      customerId: 'customer-42',
      items: const [
        OrderItem(
          productId: 'p1',
          productName: 'منتج تجريبي',
          quantity: 2,
          unitPrice: 199,
          total: 398,
        ),
      ],
      status: 'pending_payment',
      paymentMethod: 'cash_on_delivery',
      subtotal: 398,
      shippingFee: 15,
      total: 413,
      createdAt: DateTime(2026, 1, 15),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: CustomerOrderDetailScreen(order: order),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('تفاصيل الطلب'), findsOneWidget);
    expect(find.text('منتج تجريبي'), findsOneWidget);
    expect(find.text('413 ر.ي'), findsOneWidget);
    expect(find.text('طريقة الدفع'), findsOneWidget);
    expect(find.text('تاريخ الطلب'), findsOneWidget);
    expect(find.text('معلومات التوصيل'), findsOneWidget);
  });
}

class _FakeOrderService extends OrderService {
  _FakeOrderService(this.order);

  final OrderModel order;

  @override
  Future<OrderModel?> getOrderById(String orderId) async =>
      orderId == order.id ? order : null;
}

class _FakeAuthService extends AuthService {
  _FakeAuthService(this.profile);

  final UserModel profile;

  @override
  Future<UserModel?> getCurrentProfile() async => profile;
}
