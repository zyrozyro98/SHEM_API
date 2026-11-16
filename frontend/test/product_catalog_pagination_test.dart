import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/models/product_model.dart';
import 'package:she_m_app/data/services/catalog_service.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/data/services/search_history_service.dart';
import 'package:she_m_app/presentation/catalog/product_catalog.dart';

class _CatalogPaginationDatabase implements DatabaseService {
  _CatalogPaginationDatabase(this.data);

  final Map<String, dynamic> data;

  @override
  Future<Map<String, dynamic>> read(String path) async =>
      Map<String, dynamic>.from(data[path] as Map? ?? const {});

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
      null;

  @override
  Future<void> delete(String path) async {}
}

class _CatalogPaginationSearchHistory implements SearchHistoryStore {
  @override
  Future<List<String>> addSearch(String userId, String query) async => [];

  @override
  Future<void> clear(String userId) async {}

  @override
  Future<List<String>> load(String userId) async => [];
}

void main() {
  testWidgets('catalog loads the next batch automatically when scrolling',
      (tester) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final catalogDatabase = _CatalogPaginationDatabase({
      'products': {
        for (var index = 0; index < 24; index++)
          'product-${index.toString().padLeft(2, '0')}': ProductModel(
            id: 'product-$index',
            name: 'منتج $index',
            price: (10 + index).toDouble(),
            category: 'عام',
            description: '',
            imageUrl: '',
            available: true,
            merchantId: 'merchant-1',
            submittedAt:
                DateTime.utc(2026, 11, 4).add(Duration(minutes: index)),
          ).toJson(),
      },
      'profiles': {
        'merchant-1': {'shop_name': 'المتجر'},
      },
    });
    final catalog = CatalogService(databaseService: catalogDatabase);

    await tester.pumpWidget(
      MaterialApp(
        home: ProductCatalogScreen(
          catalogService: catalog,
          searchHistoryStore: _CatalogPaginationSearchHistory(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('منتج 11'), findsOneWidget);
    expect(find.text('منتج 12'), findsNothing);

    await tester.drag(find.byType(GridView), const Offset(0, -1800));
    await tester.pumpAndSettle();

    expect(find.text('منتج 12'), findsOneWidget);

    final products = catalogDatabase.data['products'] as Map;
    final firstProduct = Map<String, dynamic>.from(
      products['product-00'] as Map,
    )..['name'] = 'منتج محدث';
    products['product-00'] = firstProduct;

    await tester.tap(find.byKey(const ValueKey('refresh_product_catalog')));
    await tester.pumpAndSettle();

    expect(find.text('منتج محدث'), findsOneWidget);
  });
}
