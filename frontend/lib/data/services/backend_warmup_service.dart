import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:she_m_app/core/constants/app_constants.dart';

class BackendWarmupService {
  BackendWarmupService({
    required http.Client client,
    String? baseUrl,
    this.requestTimeout = const Duration(seconds: 65),
    this.retryDelay = const Duration(seconds: 2),
  })  : _client = client,
        _baseUrl = (baseUrl ?? AppConstants.mediaApiBaseUrl)
            .trim()
            .replaceAll(RegExp(r'/+$'), '');

  static final BackendWarmupService instance = BackendWarmupService(
    client: http.Client(),
  );
  static const _readyCacheDuration = Duration(minutes: 5);

  final http.Client _client;
  final String _baseUrl;
  final Duration requestTimeout;
  final Duration retryDelay;
  Future<bool>? _pendingWarmup;
  DateTime? _lastReadyAt;

  Future<bool> ensureReady() {
    final lastReadyAt = _lastReadyAt;
    if (lastReadyAt != null &&
        DateTime.now().difference(lastReadyAt) < _readyCacheDuration) {
      return Future.value(true);
    }
    return _pendingWarmup ??= _warmUp();
  }

  Future<bool> _warmUp() async {
    try {
      for (var attempt = 1; attempt <= 2; attempt++) {
        try {
          final response = await _client
              .get(Uri.parse('$_baseUrl/'))
              .timeout(requestTimeout);
          if (response.statusCode >= 200 && response.statusCode < 300) {
            _lastReadyAt = DateTime.now();
            return true;
          }
          debugPrint(
            'Backend warm-up returned HTTP ${response.statusCode} '
            '(attempt $attempt/2)',
          );
        } catch (error) {
          debugPrint('Backend warm-up attempt $attempt/2 failed: $error');
        }

        if (attempt < 2) {
          await Future<void>.delayed(retryDelay);
        }
      }
      return false;
    } finally {
      _pendingWarmup = null;
    }
  }
}
