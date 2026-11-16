import 'dart:convert';

import 'package:she_m_app/core/errors/app_error.dart';
import 'package:she_m_app/data/models/product_model.dart';
import 'package:she_m_app/data/services/pricing_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CartEntry {
  ProductModel product;
  String? selectedColor;
  String? selectedSize;
  int quantity;

  CartEntry({
    required this.product,
    this.selectedColor,
    this.selectedSize,
    this.quantity = 1,
  });

  String get customizationSummary {
    final parts = <String>[];
    final color = selectedColor?.trim();
    final size = selectedSize?.trim();

    if (color != null && color.isNotEmpty) {
      parts.add('اللون: $color');
    }
    if (size != null && size.isNotEmpty) {
      parts.add('المقاس: $size');
    }

    return parts.join(' • ');
  }

  double get lineTotal => product.priceIncludingVat * quantity;
  double get vatTotal => product.vatAmount * quantity;
}

class CartService extends ChangeNotifier {
  CartService._();

  static final CartService instance = CartService._();

  final List<CartEntry> _items = [];
  static const _storage = FlutterSecureStorage();
  String? _activeUserId;
  String? _persistenceError;
  Future<void> _persistenceQueue = Future<void>.value();

  String get _storageKey => 'she_m_cart_${_activeUserId ?? 'guest'}';

  List<CartEntry> get items => List.unmodifiable(_items);
  String? get persistenceError => _persistenceError;

  Future<void> loadForUser(String? userId) async {
    final normalized = userId?.trim() ?? '';
    final nextUserId = normalized.isEmpty ? null : normalized;
    final previousUserId = _activeUserId;
    final previousItems = List<CartEntry>.of(_items);
    final guestItems = nextUserId != null && _activeUserId == null
        ? List.of(_items)
        : <CartEntry>[];
    _activeUserId = nextUserId;
    _items.clear();
    try {
      final raw = await _storage.read(key: _storageKey);
      final decoded = raw == null || raw.isEmpty ? null : jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is! Map || item['product'] is! Map) continue;
          final quantity = item['quantity'];
          if (quantity is! num || quantity <= 0) continue;
          _items.add(CartEntry(
            product: ProductModel.fromJson(
              Map<String, dynamic>.from(item['product'] as Map),
            ),
            selectedColor: item['selected_color']?.toString(),
            selectedSize: item['selected_size']?.toString(),
            quantity: quantity.toInt(),
          ));
        }
      }
      _persistenceError = null;
    } catch (error) {
      _items
        ..clear()
        ..addAll(previousUserId == nextUserId ? previousItems : guestItems);
      _persistenceError = AppErrorMessage.from(error);
      AppErrorReporter.report(error);
      notifyListeners();
      return;
    }
    if (nextUserId != null && guestItems.isNotEmpty) {
      for (final guestItem in guestItems) {
        final existingIndex = _items
            .indexWhere((item) => item.product.id == guestItem.product.id);
        if (existingIndex < 0) {
          _items.add(guestItem);
        } else {
          _items[existingIndex].quantity += guestItem.quantity;
        }
      }
      try {
        await _storage.delete(key: 'she_m_cart_guest');
      } catch (error) {
        AppErrorReporter.report(error);
      }
      _persist();
    }
    notifyListeners();
  }

  Future<void> deactivateUser() async {
    _items.clear();
    _activeUserId = null;
    notifyListeners();
  }

  void _persist() {
    final storageKey = _storageKey;
    final payload = _items
        .map((entry) => {
              'product': entry.product.toJson(),
              'selected_color': entry.selectedColor,
              'selected_size': entry.selectedSize,
              'quantity': entry.quantity,
            })
        .toList();
    final serialized = jsonEncode(payload);
    _persistenceQueue = _persistenceQueue.then((_) async {
      try {
        await _storage.write(key: storageKey, value: serialized);
        _persistenceError = null;
      } catch (error) {
        _persistenceError = AppErrorMessage.from(error);
        AppErrorReporter.report(error);
      }
      notifyListeners();
    });
  }

  void updateVatRates(PricingConfig config) {
    for (final item in _items) {
      final product = item.product;
      final commission =
          PricingService.commissionForProduct(config: config, product: product);
      item.product = product.copyWith(
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
    }
    _persist();
    notifyListeners();
  }

  bool addProduct(
    ProductModel product, {
    int quantity = 1,
    String? color,
    String? size,
  }) {
    if (quantity <= 0) return false;

    final normalizedColor = color?.trim();
    final normalizedSize = size?.trim();
    final existing =
        _items.indexWhere((entry) => entry.product.id == product.id);

    if (existing >= 0) {
      _items[existing].quantity += quantity;
      if (normalizedColor != null && normalizedColor.isNotEmpty) {
        _items[existing].selectedColor = normalizedColor;
      }
      if (normalizedSize != null && normalizedSize.isNotEmpty) {
        _items[existing].selectedSize = normalizedSize;
      }
      _persist();
      notifyListeners();
      return true;
    }

    _items.add(CartEntry(
      product: product,
      selectedColor: normalizedColor != null && normalizedColor.isNotEmpty
          ? normalizedColor
          : null,
      selectedSize: normalizedSize != null && normalizedSize.isNotEmpty
          ? normalizedSize
          : null,
      quantity: quantity,
    ));
    _persist();
    notifyListeners();
    return false;
  }

  void removeProduct(String productId) {
    _items.removeWhere((entry) => entry.product.id == productId);
    _persist();
    notifyListeners();
  }

  void removeProducts(Iterable<String> productIds) {
    final ids = productIds.toSet();
    if (ids.isEmpty) return;

    _items.removeWhere((entry) => ids.contains(entry.product.id));
    _persist();
    notifyListeners();
  }

  void updateQuantity(String productId, int quantity) {
    final index = _items.indexWhere((entry) => entry.product.id == productId);
    if (index < 0) return;

    if (quantity <= 0) {
      _items.removeAt(index);
    } else {
      _items[index].quantity = quantity;
    }
    _persist();
    notifyListeners();
  }

  void clear() {
    _items.clear();
    _persist();
    notifyListeners();
  }

  double get subtotal => _items.fold(0.0, (sum, item) => sum + item.lineTotal);

  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);
}
