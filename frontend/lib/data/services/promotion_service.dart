import 'package:she_m_app/data/models/promotion_model.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';

class PromotionService {
  PromotionService({DatabaseService? databaseService})
      : _databaseService = databaseService ?? FirebaseDatabaseService.instance;

  final DatabaseService _databaseService;
  List<PromotionModel>? _cachedPromotions;
  DateTime? _cacheTime;
  static List<PromotionModel>? _sharedPromotions;
  static DateTime? _sharedCacheTime;
  static const Duration _cacheTtl = Duration(minutes: 2);

  void clearCache() {
    _cachedPromotions = null;
    _cacheTime = null;
    _sharedPromotions = null;
    _sharedCacheTime = null;
  }

  Future<List<PromotionModel>> getVisiblePromotions() async {
    final promotions = await getAllPromotions();
    return promotions
        .where(
          (promotion) => promotion.isVisible && promotion.imageUrl.isNotEmpty,
        )
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  Future<List<PromotionModel>> getAllPromotions() async {
    final canUseSharedCache = _databaseService is FirebaseDatabaseService;
    if (_cachedPromotions != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheTtl) {
      return List.unmodifiable(_cachedPromotions!);
    }
    if (canUseSharedCache &&
        _sharedPromotions != null &&
        _sharedCacheTime != null &&
        DateTime.now().difference(_sharedCacheTime!) < _cacheTtl) {
      _cachedPromotions = _sharedPromotions;
      _cacheTime = _sharedCacheTime;
      return List.unmodifiable(_sharedPromotions!);
    }
    final snapshot = await _databaseService.read('promotions');
    final promotions = snapshot.entries
        .where((entry) => entry.value is Map)
        .map((entry) => PromotionModel.fromJson(
              Map<String, dynamic>.from(entry.value as Map),
              id: entry.key,
            ))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    _cachedPromotions = promotions;
    _cacheTime = DateTime.now();
    _sharedPromotions = promotions;
    _sharedCacheTime = _cacheTime;
    return List.unmodifiable(promotions);
  }

  Future<String> createPromotion(PromotionModel promotion) async {
    final result = await _databaseService.write(
      'promotions/${promotion.id}',
      promotion.toJson(),
    );
    clearCache();
    return (result['id'] ?? promotion.id).toString();
  }

  Future<void> updatePromotion(PromotionModel promotion) async {
    await _databaseService.update(
      'promotions/${promotion.id}',
      promotion.toJson(),
    );
    clearCache();
  }

  Future<void> deletePromotion(String id) async {
    await _databaseService.delete('promotions/$id');
    clearCache();
  }
}
