import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:she_m_app/core/errors/app_error.dart';

abstract interface class SearchHistoryStore {
  Future<List<String>> load(String userId);
  Future<List<String>> addSearch(String userId, String query);
  Future<void> clear(String userId);
}

class SecureSearchHistoryStore implements SearchHistoryStore {
  const SecureSearchHistoryStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const int maxSearches = 8;

  final FlutterSecureStorage _storage;

  String _storageKey(String userId) {
    final normalizedUserId = userId.trim();
    return 'she_m_product_searches_${normalizedUserId.isEmpty ? 'guest' : normalizedUserId}';
  }

  @override
  Future<List<String>> load(String userId) async {
    try {
      final stored = await _storage.read(key: _storageKey(userId));
      if (stored == null || stored.trim().isEmpty) return const [];

      final decoded = jsonDecode(stored);
      if (decoded is! List) return const [];

      final seen = <String>{};
      return decoded
          .whereType<String>()
          .map((query) => query.trim())
          .where((query) => query.isNotEmpty && seen.add(query.toLowerCase()))
          .take(maxSearches)
          .toList();
    } catch (error) {
      AppErrorReporter.report(error);
      return const [];
    }
  }

  @override
  Future<List<String>> addSearch(String userId, String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return load(userId);

    final searches = await load(userId);
    final updated = [
      normalizedQuery,
      ...searches.where(
        (search) => search.toLowerCase() != normalizedQuery.toLowerCase(),
      ),
    ].take(maxSearches).toList();

    try {
      await _storage.write(
        key: _storageKey(userId),
        value: jsonEncode(updated),
      );
    } catch (error) {
      AppErrorReporter.report(error);
    }

    return updated;
  }

  @override
  Future<void> clear(String userId) async {
    try {
      await _storage.delete(key: _storageKey(userId));
    } catch (error) {
      AppErrorReporter.report(error);
    }
  }
}
