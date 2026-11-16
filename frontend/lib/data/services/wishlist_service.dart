import 'package:flutter/foundation.dart';
import 'package:she_m_app/core/errors/app_error.dart';
import 'package:she_m_app/data/models/product_model.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';

class WishlistService extends ChangeNotifier {
  WishlistService({DatabaseService? databaseService})
      : _databaseService = databaseService ?? FirebaseDatabaseService.instance;

  static final WishlistService instance = WishlistService();

  final DatabaseService _databaseService;
  final List<ProductModel> _items = [];
  final Set<String> _favoriteIds = {};
  final Map<String, int> _writeVersions = {};
  String? _customerId;

  List<ProductModel> get items => List.unmodifiable(_items);

  bool contains(String productId) =>
      _favoriteIds.contains(productId) ||
      _items.any((product) => product.id == productId);

  Future<void> loadForCustomer(String customerId) async {
    final normalizedId = customerId.trim();
    if (normalizedId.isEmpty) return;
    _customerId = normalizedId;
    try {
      final snapshot = await _databaseService.read(
        'customers/$normalizedId/wishlist',
      );
      _favoriteIds
        ..clear()
        ..addAll(snapshot.entries
            .where((entry) => entry.value == true || entry.value is Map)
            .map((entry) => entry.key));
      _items.removeWhere((item) => !_favoriteIds.contains(item.id));
      notifyListeners();
    } catch (error) {
      AppErrorReporter.report(error);
    }
  }

  void syncProducts(Iterable<ProductModel> products) {
    final byId = {for (final product in products) product.id: product};
    _items
      ..clear()
      ..addAll(_favoriteIds.map((id) => byId[id]).whereType<ProductModel>());
    notifyListeners();
  }

  bool toggle(ProductModel product) {
    final wasFavorite = contains(product.id);
    if (wasFavorite) {
      _favoriteIds.remove(product.id);
      _items.removeWhere((item) => item.id == product.id);
    } else {
      _favoriteIds.add(product.id);
      _items.add(product);
    }
    notifyListeners();
    _persist(
      productId: product.id,
      favorite: contains(product.id),
      previousFavorite: wasFavorite,
      product: product,
    );
    return contains(product.id);
  }

  void remove(String productId) {
    final previousFavorite = _favoriteIds.contains(productId);
    ProductModel? product;
    for (final item in _items) {
      if (item.id == productId) {
        product = item;
        break;
      }
    }
    _favoriteIds.remove(productId);
    _items.removeWhere((item) => item.id == productId);
    notifyListeners();
    _persist(
      productId: productId,
      favorite: false,
      previousFavorite: previousFavorite,
      product: product,
    );
  }

  Future<void> _persist({
    required String productId,
    required bool favorite,
    required bool previousFavorite,
    ProductModel? product,
  }) async {
    final customerId = _customerId;
    if (customerId == null || productId.trim().isEmpty) return;
    final version = (_writeVersions[productId] ?? 0) + 1;
    _writeVersions[productId] = version;
    try {
      if (favorite) {
        await _databaseService.write(
          'customers/$customerId/wishlist/$productId',
          {
            'product_id': productId,
            'created_at': DateTime.now().toIso8601String(),
          },
        );
      } else {
        await _databaseService.delete(
          'customers/$customerId/wishlist/$productId',
        );
      }
    } catch (error) {
      if (_writeVersions[productId] == version) {
        if (previousFavorite) {
          _favoriteIds.add(productId);
          if (product != null &&
              !_items.any((item) => item.id == productId)) {
            _items.add(product);
          }
        } else {
          _favoriteIds.remove(productId);
          _items.removeWhere((item) => item.id == productId);
        }
        notifyListeners();
      }
      AppErrorReporter.report(error);
    }
  }
}
