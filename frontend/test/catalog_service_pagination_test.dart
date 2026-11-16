import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:she_m_app/data/models/product_model.dart';
import 'package:she_m_app/data/services/catalog_service.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';

void main() {
  test('products sort by submitted date instead of database insertion order',
      () {
    final products = [
      ProductModel.fromJson({
        'id': 'older',
        'name': 'منتج أقدم',
        'submitted_at': '2026-11-03T10:00:00.000Z',
      }),
      ProductModel.fromJson({
        'id': 'boss-watch',
        'name': 'ساعة BOSS رجالية',
        'submitted_at': '2026-11-04T02:14:47.608781Z',
      }),
    ]..sort(ProductModel.compareNewestFirst);

    expect(products.first.id, 'boss-watch');
  });

  test('concurrent product loads share one database request', () async {
    final requestStarted = Completer<void>();
    final releaseResponse = Completer<void>();
    var productReadCount = 0;
    final catalog = CatalogService(
      databaseService: _ConcurrentCatalogDatabase(
        onProductsRead: () {
          productReadCount++;
          requestStarted.complete();
          return releaseResponse.future;
        },
      ),
    );

    final firstLoad = catalog.getProducts();
    await requestStarted.future;
    final secondLoad = catalog.getProducts();
    releaseResponse.complete();
    final results = await Future.wait([firstLoad, secondLoad]);

    expect(productReadCount, 1);
    expect(results.first.map((product) => product.id), ['product-1']);
    expect(results[0], results[1]);
  });

  test('catalog pages show newest available products before pending records',
      () async {
    final products = <String, Map<String, dynamic>>{
      for (var index = 0; index < 12; index++)
        'product-${index.toString().padLeft(2, '0')}': {
          'id': 'product-$index',
          'name': 'بانتظار الموافقة',
          'available': false,
        },
      for (var index = 12; index < 25; index++)
        'product-${index.toString().padLeft(2, '0')}': {
          'id': 'merchant-id-$index',
          'name': 'منتج معتمد $index',
          'available': true,
          'submitted_at': DateTime.utc(2026, 11, 4)
              .add(Duration(minutes: index))
              .toIso8601String(),
        },
    };

    final client = MockClient((request) async {
      if (request.url.path.endsWith('/products.json')) {
        final keys = products.keys.toList()..sort();
        final rawEndAt = request.url.queryParameters['endAt'];
        final endAt = rawEndAt == null ? null : jsonDecode(rawEndAt);
        final eligibleKeys = endAt == null
            ? keys
            : keys.where((key) => key.compareTo(endAt) <= 0).toList();
        final limit = int.parse(
          request.url.queryParameters['limitToLast'] ??
              request.url.queryParameters['limitToFirst'] ??
              '0',
        );
        final selectedKeys =
            request.url.queryParameters.containsKey('limitToLast')
                ? eligibleKeys.skip(
                    (eligibleKeys.length - limit).clamp(0, eligibleKeys.length))
                : eligibleKeys.take(limit);
        final page = <String, dynamic>{
          for (final key in selectedKeys) key: products[key],
        };
        return http.Response.bytes(
          utf8.encode(jsonEncode(page)),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }

      return http.Response('{}', 200);
    });
    final database = FirebaseDatabaseService.forTesting(
      client: client,
      databaseUrl: 'https://test.firebaseio.com',
    );
    final catalog = CatalogService(databaseService: database);

    final firstPage = await catalog.getProductCatalogPageAfter(limit: 12);
    final secondPage = await catalog.getProductCatalogPageAfter(
      startAfter: firstPage.nextCursor,
      limit: 12,
    );

    expect(firstPage.products, hasLength(12));
    expect(firstPage.products.first.name, 'منتج معتمد 24');
    expect(firstPage.nextCursor, 'product-13');
    expect(firstPage.hasMore, isTrue);
    expect(secondPage.products, hasLength(1));
    expect(secondPage.products.single.name, 'منتج معتمد 12');
    expect(secondPage.nextCursor, 'product-00');
    expect(secondPage.hasMore, isFalse);
  });

  test('catalog falls back to full read when Firebase rejects a page query',
      () async {
    final products = <String, Map<String, dynamic>>{
      'product-a': {
        'name': 'منتج أ',
        'available': true,
      },
      'product-b': {
        'name': 'منتج ب',
        'available': true,
      },
    };
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/products.json')) {
        if (request.url.queryParameters.containsKey('orderBy')) {
          return http.Response('{"error":"query rejected"}', 400);
        }
        return http.Response.bytes(
          utf8.encode(jsonEncode(products)),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }

      return http.Response('{}', 200);
    });
    final database = FirebaseDatabaseService.forTesting(
      client: client,
      databaseUrl: 'https://test.firebaseio.com',
    );
    final catalog = CatalogService(databaseService: database);

    final page = await catalog.getProductCatalogPageAfter(limit: 1);

    expect(page.products, hasLength(1));
    expect(page.products.single.id, 'product-b');
    expect(page.nextCursor, 'product-b');
    expect(page.hasMore, isTrue);

    final nextPage = await catalog.getProductCatalogPageAfter(
      startAfter: page.nextCursor,
      limit: 1,
    );

    expect(nextPage.products.single.id, 'product-a');
    expect(nextPage.nextCursor, 'product-a');
    expect(nextPage.hasMore, isFalse);
  });
}

class _ConcurrentCatalogDatabase implements DatabaseService {
  _ConcurrentCatalogDatabase({required this.onProductsRead});

  final Future<void> Function() onProductsRead;

  @override
  Future<Map<String, dynamic>> read(String path) async {
    if (path == 'products') {
      await onProductsRead();
      return {
        'product-1': {
          'id': 'product-1',
          'name': 'منتج',
          'available': true,
        },
      };
    }
    return const {};
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
      null;

  @override
  Future<void> delete(String path) async {}
}
