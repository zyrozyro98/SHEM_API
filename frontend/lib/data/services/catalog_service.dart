import 'package:she_m_app/data/models/product_model.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/data/services/pricing_service.dart';

class ProductCatalogPage {
  const ProductCatalogPage({
    required this.products,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<ProductModel> products;
  final String? nextCursor;
  final bool hasMore;
}

class CatalogService {
  factory CatalogService({DatabaseService? databaseService}) {
    if (databaseService == null) {
      return _shared ??= CatalogService._(FirebaseDatabaseService.instance);
    }
    return CatalogService._(databaseService);
  }

  CatalogService._(DatabaseService databaseService)
      : _databaseService = databaseService,
        _pricingService = PricingService(
          database: databaseService,
        );

  static const Duration _cacheTtl = Duration(minutes: 5);
  static const int _databasePageSize = 12;
  static CatalogService? _shared;

  final DatabaseService _databaseService;
  final PricingService _pricingService;
  List<ProductModel> _cachedProducts = const [];
  DateTime? _lastProductsLoad;
  Future<List<ProductModel>>? _pendingProductsLoad;
  PricingConfig? _cachedPricingConfig;
  DateTime? _lastVatRateLoad;

  List<ProductModel> get cachedProducts => List.unmodifiable(_cachedProducts);

  void clearCache() {
    _cachedProducts = const [];
    _lastProductsLoad = null;
  }

  Future<List<ProductModel>> getProducts({bool forceRefresh = false}) async {
    final now = DateTime.now();
    final cacheIsFresh = _lastProductsLoad != null &&
        _cachedProducts.isNotEmpty &&
        now.difference(_lastProductsLoad!) < _cacheTtl &&
        !forceRefresh;

    if (cacheIsFresh) {
      return List.unmodifiable(await _applyVatRate(_cachedProducts));
    }

    final pendingLoad = _pendingProductsLoad;
    if (pendingLoad != null) return pendingLoad;

    final load = _loadProductsFromDatabase();
    _pendingProductsLoad = load;
    try {
      return await load;
    } finally {
      if (identical(_pendingProductsLoad, load)) {
        _pendingProductsLoad = null;
      }
    }
  }

  Future<List<ProductModel>> _loadProductsFromDatabase() async {
    try {
      final snapshot = await _databaseService.read('products');
      if (snapshot.isEmpty) {
        _cachedProducts = const [];
        _lastProductsLoad = DateTime.now();
        return const [];
      }

      final items = snapshot.values
          .whereType<Map>()
          .where((value) => value['is_archived'] != true)
          .map((value) =>
              ProductModel.fromJson(Map<String, dynamic>.from(value)))
          .where((product) => product.available)
          .toList();

      final enriched = await _attachMerchantNames(items);
      final pricedProducts = await _applyVatRate(enriched);
      _cachedProducts = List.unmodifiable(pricedProducts);
      _lastProductsLoad = DateTime.now();
      return List.unmodifiable(pricedProducts);
    } catch (_) {
      if (_cachedProducts.isNotEmpty) {
        return List.unmodifiable(await _applyVatRate(_cachedProducts));
      }
      return const [];
    }
  }

  Future<List<ProductModel>> getProductsPage({
    required int offset,
    required int limit,
    bool forceRefresh = false,
  }) async {
    if (_databaseService is FirebaseDatabaseService) {
      final page = await getProductsPageAfter(limit: offset + limit);
      return page.skip(offset).take(limit).toList();
    }

    final allProducts = await getProducts(forceRefresh: forceRefresh);
    final end = (offset + limit).clamp(0, allProducts.length);
    return allProducts.sublist(offset, end);
  }

  Future<List<ProductModel>> getProductsPageAfter({
    String? startAfter,
    required int limit,
  }) async {
    final page = await getProductCatalogPageAfter(
      startAfter: startAfter,
      limit: limit,
    );
    return page.products;
  }

  Future<ProductCatalogPage> getProductCatalogPageAfter({
    String? startAfter,
    required int limit,
    bool forceRefresh = false,
  }) async {
    if (limit <= 0) {
      return const ProductCatalogPage(
        products: [],
        nextCursor: null,
        hasMore: false,
      );
    }

    if (_databaseService is! FirebaseDatabaseService) {
      final allProducts = await getProducts(forceRefresh: forceRefresh);
      final offset = startAfter == null
          ? 0
          : allProducts.indexWhere((product) => product.id == startAfter) + 1;
      final start = offset < 0 ? 0 : offset;
      final end = (start + limit).clamp(0, allProducts.length);
      final products = allProducts.sublist(start, end);
      return ProductCatalogPage(
        products: products,
        nextCursor: products.isEmpty ? startAfter : products.last.id,
        hasMore: end < allProducts.length,
      );
    }

    final initialCursor = startAfter;
    final products = <ProductModel>[];
    var cursor = startAfter;
    try {
      while (products.length < limit) {
        final query = <String, String>{
          'orderBy': '"\u0024key"',
          'limitToLast': _databasePageSize.toString(),
        };
        if (cursor != null && cursor.trim().isNotEmpty) {
          query['endAt'] = '"${cursor.trim()}"';
        }

        final snapshot = await _databaseService.readWithQuery(
          'products',
          query: query,
        );
        final entries = snapshot.entries
            .where((entry) => entry.key != cursor)
            .toList()
            .reversed
            .toList();
        if (entries.isEmpty) {
          return ProductCatalogPage(
            products: await _applyVatRate(await _attachMerchantNames(products)),
            nextCursor: cursor,
            hasMore: false,
          );
        }

        for (var index = 0; index < entries.length; index++) {
          final entry = entries[index];
          cursor = entry.key;
          final value = entry.value;
          if (value is! Map || value['is_archived'] == true) continue;
          final product = ProductModel.fromJson(
            Map<String, dynamic>.from(value),
          );
          if (!product.available) continue;
          products.add(
            product.id.isEmpty ? product.copyWith(id: entry.key) : product,
          );
          if (products.length == limit) {
            return ProductCatalogPage(
              products:
                  await _applyVatRate(await _attachMerchantNames(products)),
              nextCursor: cursor,
              hasMore: index + 1 < entries.length ||
                  snapshot.length == _databasePageSize,
            );
          }
        }

        if (snapshot.length < _databasePageSize) {
          return ProductCatalogPage(
            products: await _applyVatRate(await _attachMerchantNames(products)),
            nextCursor: cursor,
            hasMore: false,
          );
        }
      }

      return ProductCatalogPage(
        products: await _applyVatRate(await _attachMerchantNames(products)),
        nextCursor: cursor,
        hasMore: true,
      );
    } catch (_) {
      try {
        return await _getProductCatalogPageFromFullRead(
          startAfter: initialCursor,
          limit: limit,
        );
      } catch (_) {
        return ProductCatalogPage(
          products: const [],
          nextCursor: cursor,
          hasMore: false,
        );
      }
    }
  }

  Future<ProductCatalogPage> _getProductCatalogPageFromFullRead({
    required String? startAfter,
    required int limit,
  }) async {
    final snapshot = await _databaseService.read('products');
    final sortedEntries = snapshot.entries.toList()
      ..sort((first, second) => second.key.compareTo(first.key));
    final eligibleEntries = <MapEntry<String, ProductModel>>[];

    for (final entry in sortedEntries) {
      if (startAfter != null && entry.key.compareTo(startAfter) >= 0) {
        continue;
      }
      if (entry.value is! Map || entry.value['is_archived'] == true) continue;

      final product = ProductModel.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
      if (!product.available) continue;
      eligibleEntries.add(MapEntry(
        entry.key,
        product.id.isEmpty ? product.copyWith(id: entry.key) : product,
      ));
    }

    final pageEntries = eligibleEntries.take(limit).toList();
    final pageProducts = await _attachMerchantNames(
      pageEntries.map((entry) => entry.value).toList(),
    );
    return ProductCatalogPage(
      products: await _applyVatRate(pageProducts),
      nextCursor: pageEntries.isEmpty ? startAfter : pageEntries.last.key,
      hasMore: eligibleEntries.length > pageEntries.length,
    );
  }

  Future<List<ProductModel>> getProductsByMerchant(String merchantId,
      {bool forceRefresh = false}) async {
    final normalized = merchantId.trim();
    if (normalized.isEmpty) {
      return const [];
    }

    final cachedProducts = _cachedProducts;
    if (!forceRefresh && cachedProducts.isNotEmpty) {
      final filtered = cachedProducts
          .where((product) =>
              product.available && product.merchantId == normalized)
          .toList();
      if (filtered.isNotEmpty || cachedProducts.isNotEmpty) {
        return List.unmodifiable(await _applyVatRate(filtered));
      }
    }

    try {
      final snapshot = await _databaseService.read('products');
      if (snapshot.isEmpty) {
        return const [];
      }

      final items = snapshot.values
          .whereType<Map>()
          .where((value) => value['is_archived'] != true)
          .map((value) =>
              ProductModel.fromJson(Map<String, dynamic>.from(value)))
          .where((product) =>
              product.available && product.merchantId == normalized)
          .toList();

      final enriched = await _attachMerchantNames(items);
      if (enriched.isNotEmpty) {
        _cachedProducts = List.unmodifiable([
          ...cachedProducts,
          ...enriched.where((product) =>
              !cachedProducts.any((entry) => entry.id == product.id)),
        ]);
      }
      return List.unmodifiable(await _applyVatRate(enriched));
    } catch (_) {
      if (cachedProducts.isNotEmpty) {
        return List.unmodifiable(await _applyVatRate(
          cachedProducts
              .where((product) =>
                  product.available && product.merchantId == normalized)
              .toList(),
        ));
      }
      return const [];
    }
  }

  Future<List<ProductModel>> _applyVatRate(List<ProductModel> products) async {
    final now = DateTime.now();
    if (_cachedPricingConfig == null ||
        _lastVatRateLoad == null ||
        now.difference(_lastVatRateLoad!) >= _cacheTtl) {
      _cachedPricingConfig = await _pricingService.load();
      _lastVatRateLoad = now;
    }
    return products.map((product) {
      final config = _cachedPricingConfig!;
      final commission =
          PricingService.commissionForProduct(config: config, product: product);
      return product.copyWith(
        vatRate: PricingService.vatRateForProduct(
          config: config,
          productId: product.id,
          merchantId: product.merchantId,
          category: product.category,
          productRateOverride: product.vatRateOverride,
          productExempt: product.vatExempt,
        ),
        effectiveCommissionMode: commission.mode,
        effectiveCommissionValue: commission.value,
      );
    }).toList();
  }

  Future<List<ProductModel>> _attachMerchantNames(
    List<ProductModel> products,
  ) async {
    if (products.isEmpty) return products;

    try {
      final profiles = await _databaseService.read('profiles');
      final merchantNames = <String, String>{};
      final archivedMerchantIds = <String>{};

      for (final entry in profiles.entries) {
        final value = entry.value;
        if (value is! Map) continue;

        final map = Map<String, dynamic>.from(value);
        final profileId = map['id']?.toString() ?? entry.key;
        if (map['is_archived'] == true) {
          archivedMerchantIds.add(profileId);
          continue;
        }
        final shopName = map['shop_name']?.toString() ??
            map['shopName']?.toString() ??
            map['full_name']?.toString() ??
            '';

        if (profileId.isNotEmpty && shopName.isNotEmpty) {
          merchantNames[profileId] = shopName;
        }
      }

      return products
          .where((product) => !archivedMerchantIds.contains(product.merchantId))
          .map((product) => product.copyWith(
                merchantName: merchantNames[product.merchantId] ?? '',
              ))
          .toList();
    } catch (_) {
      return products;
    }
  }

  Future<ProductModel?> getProductById(String id) async {
    final products = await getProducts();
    final matches = products.where((product) => product.id == id).toList();
    if (matches.isNotEmpty) return matches.first;
    return null;
  }
}
