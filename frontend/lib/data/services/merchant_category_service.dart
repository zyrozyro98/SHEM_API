import 'package:she_m_app/data/services/firebase_database_service.dart';

class ProductSubcategory {
  const ProductSubcategory({
    required this.id,
    required this.name,
    required this.active,
  });

  final String id;
  final String name;
  final bool active;
}

class ProductCategory {
  const ProductCategory({
    required this.id,
    required this.name,
    required this.active,
    required this.subcategories,
    this.logoImageUrl,
    this.coverImageUrl,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final bool active;
  final List<ProductSubcategory> subcategories;
  final String? logoImageUrl;
  final String? coverImageUrl;
  final int sortOrder;

  List<ProductSubcategory> get activeSubcategories =>
      subcategories.where((category) => category.active).toList();
}

class MerchantCategoryService {
  factory MerchantCategoryService({DatabaseService? database}) {
    if (database == null) {
      return _shared ??= MerchantCategoryService._(
        FirebaseDatabaseService.instance,
      );
    }
    return MerchantCategoryService._(database);
  }

  MerchantCategoryService._(DatabaseService database) : _database = database;

  static const Duration _categoryCacheTtl = Duration(minutes: 1);
  static MerchantCategoryService? _shared;

  final DatabaseService _database;
  Map<String, dynamic>? _cachedProductCategories;
  DateTime? _lastProductCategoriesLoad;
  Future<Map<String, dynamic>>? _pendingProductCategoriesLoad;

  void _invalidateProductCategoryCache() {
    _cachedProductCategories = null;
    _lastProductCategoriesLoad = null;
  }

  Future<List<String>> getActiveCategories() async {
    try {
      final data = await _database.read('merchant_categories');
      final categories = <String>[];

      for (final entry in data.entries) {
        final value = entry.value;
        if (value is String && value.trim().isNotEmpty) {
          categories.add(value.trim());
        } else if (value is Map && value['active'] != false) {
          final name = value['name']?.toString().trim() ?? '';
          if (name.isNotEmpty) categories.add(name);
        }
      }

      categories.sort();
      return categories.toSet().toList();
    } catch (_) {
      return const <String>[];
    }
  }

  Future<List<String>> getActiveProductCategories() async {
    final categories = await getActiveProductCategoryTree();
    return categories
        .expand((category) => category.activeSubcategories)
        .map((category) => category.name)
        .toSet()
        .toList()
      ..sort();
  }

  Future<List<ProductCategory>> getActiveProductCategoryTree({
    Map<String, dynamic>? categoryData,
  }) async {
    try {
      final data = categoryData ?? await _database.read('product_categories');
      final categories = <ProductCategory>[];

      for (final entry in data.entries) {
        final value = entry.value;
        final record = value is Map ? value : <String, dynamic>{};
        final name = (record['name'] ?? (value is String ? value : ''))
            .toString()
            .trim();
        if (name.isEmpty || record['active'] == false) continue;

        final rawSubcategories = record['subcategories'];
        final subcategories = <ProductSubcategory>[];
        if (rawSubcategories is Map) {
          for (final subcategory in rawSubcategories.entries) {
            final subValue = subcategory.value;
            final subRecord = subValue is Map ? subValue : <String, dynamic>{};
            final subName =
                (subRecord['name'] ?? (subValue is String ? subValue : ''))
                    .toString()
                    .trim();
            if (subName.isEmpty) continue;
            subcategories.add(
              ProductSubcategory(
                id: subcategory.key.toString(),
                name: subName,
                active: subRecord['active'] != false,
              ),
            );
          }
        }
        subcategories
            .sort((first, second) => first.name.compareTo(second.name));
        categories.add(
          ProductCategory(
            id: entry.key,
            name: name,
            active: true,
            subcategories: subcategories,
            logoImageUrl: _imageUrl(
              record['logo_image_url'] ??
                  record['logo_url'] ??
                  record['image_url'],
            ),
            coverImageUrl: _imageUrl(
              record['cover_image_url'] ??
                  record['cover_url'] ??
                  record['banner_image_url'],
            ),
            sortOrder: _sortOrder(record['sort_order'] ?? record['sortOrder']),
          ),
        );
      }

      categories.sort((first, second) {
        final order = first.sortOrder.compareTo(second.sortOrder);
        return order == 0 ? first.name.compareTo(second.name) : order;
      });
      return categories;
    } catch (_) {
      return const <ProductCategory>[];
    }
  }

  Future<Map<String, dynamic>> getAllProductCategories({
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now();
    final cached = _cachedProductCategories;
    if (!forceRefresh &&
        cached != null &&
        _lastProductCategoriesLoad != null &&
        now.difference(_lastProductCategoriesLoad!) < _categoryCacheTtl) {
      return cached;
    }

    final pending = _pendingProductCategoriesLoad;
    if (pending != null) return pending;

    final load = _database.read('product_categories');
    _pendingProductCategoriesLoad = load;
    try {
      final categories = Map<String, dynamic>.unmodifiable(await load);
      _cachedProductCategories = categories;
      _lastProductCategoriesLoad = DateTime.now();
      return categories;
    } finally {
      if (identical(_pendingProductCategoriesLoad, load)) {
        _pendingProductCategoriesLoad = null;
      }
    }
  }

  Future<void> setProductCategoryImage(
    String id, {
    required bool cover,
    String? imageUrl,
  }) async {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError.value(id, 'id', 'معرف القسم مطلوب');
    }

    await _database.update('product_categories/$normalizedId', {
      (cover ? 'cover_image_url' : 'logo_image_url'):
          imageUrl?.trim().isEmpty == true ? null : imageUrl?.trim(),
    });
    _invalidateProductCategoryCache();
  }

  Future<void> setProductCategoryOrder(List<String> orderedCategoryIds) async {
    final ids = orderedCategoryIds.map((id) => id.trim()).toList();
    if (ids.any((id) => id.isEmpty) || ids.toSet().length != ids.length) {
      throw ArgumentError.value(
        orderedCategoryIds,
        'orderedCategoryIds',
        'ترتيب الأقسام غير صالح',
      );
    }
    if (ids.isEmpty) return;

    final snapshots = await Future.wait<Object>([
      getAllProductCategories(),
      _database.read('products'),
    ]);
    final categories = snapshots[0] as Map<String, dynamic>;
    final products = snapshots[1] as Map<String, dynamic>;
    final sortOrderById = {
      for (var index = 0; index < ids.length; index++) ids[index]: index,
    };
    final categoryIdByName = <String, String>{};
    final subcategoryParentIdByName = <String, String>{};
    for (final entry in categories.entries) {
      final record = entry.value is Map
          ? Map<String, dynamic>.from(entry.value as Map)
          : <String, dynamic>{};
      final name = (record['name'] ?? entry.value)?.toString().trim() ?? '';
      if (name.isNotEmpty) {
        categoryIdByName[_normalizeName(name)] = entry.key;
      }
      final rawSubcategories = record['subcategories'];
      if (rawSubcategories is Map) {
        for (final subcategory in rawSubcategories.values) {
          final subcategoryName = subcategory is Map
              ? subcategory['name']?.toString().trim() ?? ''
              : subcategory.toString().trim();
          if (subcategoryName.isNotEmpty) {
            subcategoryParentIdByName[_normalizeName(subcategoryName)] =
                entry.key;
          }
        }
      }
    }

    await Future.wait([
      for (var index = 0; index < ids.length; index++)
        _setCategorySortOrder(
          ids[index],
          index,
          categories[ids[index]],
        ),
    ]);

    final productUpdates = <String, dynamic>{};
    for (final entry in products.entries) {
      if (entry.value is! Map || entry.value['is_archived'] == true) continue;
      final product = Map<String, dynamic>.from(entry.value as Map);
      final mainCategoryId =
          (product['main_category_id'] ?? product['mainCategoryId'])
                  ?.toString()
                  .trim() ??
              '';
      final mainCategoryName =
          (product['main_category'] ?? product['mainCategory'])
                  ?.toString()
                  .trim() ??
              '';
      final productCategoryName = product['category']?.toString().trim() ?? '';
      final categoryId = sortOrderById.containsKey(mainCategoryId)
          ? mainCategoryId
          : categoryIdByName[_normalizeName(mainCategoryName)] ??
              categoryIdByName[_normalizeName(productCategoryName)] ??
              subcategoryParentIdByName[_normalizeName(productCategoryName)];
      final sortOrder = sortOrderById[categoryId];
      if (sortOrder != null &&
          (product['main_category_sort_order'] == null ||
              _sortOrder(product['main_category_sort_order']) != sortOrder)) {
        productUpdates['${entry.key}/main_category_sort_order'] = sortOrder;
      }
    }
    if (productUpdates.isNotEmpty) {
      await _database.update('products', productUpdates);
    }
    _invalidateProductCategoryCache();
  }

  Future<void> addProductCategory(String name) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'اسم الفئة مطلوب');
    }

    final categories = await getAllProductCategories();
    if (_containsCategoryName(categories, normalizedName)) {
      throw StateError('توجد فئة أخرى بهذا الاسم');
    }

    var nextSortOrder = 0;
    for (final category in categories.values) {
      final order = category is Map
          ? _sortOrder(category['sort_order'] ?? category['sortOrder'])
          : 0;
      if (order >= nextSortOrder) nextSortOrder = order + 1;
    }

    final key = _newCategoryId(normalizedName);
    await _database.write('product_categories/$key', {
      'name': normalizedName,
      'active': true,
      'sort_order': nextSortOrder,
      'subcategories': <String, dynamic>{},
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    _invalidateProductCategoryCache();
  }

  Future<void> addProductSubcategory(String parentId, String name) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'اسم القسم الفرعي مطلوب');
    }

    final parentPath = 'product_categories/$parentId';
    var parent = await _database.read(parentPath);
    if (parent.isEmpty || parent['active'] == false) {
      throw StateError('القسم الرئيسي غير موجود أو موقوف');
    }
    if (parent.length == 1 && parent['value'] is String) {
      parent = await _database.write(parentPath, {
        'name': parent['value'],
        'active': true,
        'subcategories': <String, dynamic>{},
      });
    }
    final rawSubcategories = parent['subcategories'];
    final subcategories = rawSubcategories is Map
        ? Map<String, dynamic>.from(rawSubcategories)
        : <String, dynamic>{};
    if (_containsCategoryName(subcategories, normalizedName)) {
      throw StateError('يوجد قسم فرعي آخر بهذا الاسم');
    }

    final key = _newCategoryId(normalizedName);
    await _database.write(
      'product_categories/$parentId/subcategories/$key',
      {
        'name': normalizedName,
        'active': true,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
    _invalidateProductCategoryCache();
  }

  Future<void> setProductCategoryActive(String id, bool active) async {
    final path = 'product_categories/$id';
    final current = await _database.read(path);
    if (current.isEmpty) {
      throw StateError('الفئة غير موجودة');
    }

    final value = current['value'];
    if (current.length == 1 && value is String) {
      await _database.write(path, {
        'name': value,
        'active': active,
      });
      _invalidateProductCategoryCache();
      return;
    }

    await _database.update(path, {'active': active});
    _invalidateProductCategoryCache();
  }

  Future<void> setProductSubcategoryActive(
    String parentId,
    String id,
    bool active,
  ) async {
    final path = 'product_categories/$parentId/subcategories/$id';
    final current = await _database.read(path);
    if (current.isEmpty) {
      throw StateError('القسم الفرعي غير موجود');
    }
    final value = current['value'];
    if (current.length == 1 && value is String) {
      await _database.write(path, {'name': value, 'active': active});
      _invalidateProductCategoryCache();
      return;
    }
    await _database.update(path, {'active': active});
    _invalidateProductCategoryCache();
  }

  Future<void> deleteProductCategory(String id) async {
    await _database.delete('product_categories/$id');
    _invalidateProductCategoryCache();
  }

  Future<void> deleteProductSubcategory(String parentId, String id) async {
    await _database.delete(
      'product_categories/$parentId/subcategories/$id',
    );
    _invalidateProductCategoryCache();
  }

  String _newCategoryId(String name) =>
      '${DateTime.now().microsecondsSinceEpoch}_${name.hashCode.abs()}';

  String? _imageUrl(Object? value) {
    final normalized = value?.toString().trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  int _sortOrder(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _normalizeName(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll(RegExp(r'\s+'), ' ');

  Future<void> _setCategorySortOrder(
    String id,
    int sortOrder,
    Object? category,
  ) async {
    final path = 'product_categories/$id';
    if (category is String) {
      await _database.write(path, {
        'name': category,
        'active': true,
        'sort_order': sortOrder,
        'subcategories': <String, dynamic>{},
      });
      return;
    }
    await _database.update(path, {'sort_order': sortOrder});
  }

  bool _containsCategoryName(
    Map<String, dynamic> categories,
    String name, {
    String? exceptId,
  }) {
    final normalizedName = name.trim().toLowerCase();
    for (final entry in categories.entries) {
      if (entry.key == exceptId) continue;
      final value = entry.value;
      final categoryName =
          value is Map ? value['name']?.toString() ?? '' : value.toString();
      if (categoryName.trim().toLowerCase() == normalizedName) return true;
    }
    return false;
  }

  Future<Map<String, dynamic>> getAllCategories() async {
    try {
      return await _database.read('merchant_categories');
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  Future<void> addCategory(String name) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) return;

    final key =
        '${DateTime.now().millisecondsSinceEpoch}_${normalizedName.hashCode.abs()}';
    await _database.write('merchant_categories/$key', {
      'name': normalizedName,
      'active': true,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> deleteCategory(String id) {
    return _database.delete('merchant_categories/$id');
  }
}
