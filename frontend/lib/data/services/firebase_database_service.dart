import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import 'package:she_m_app/core/constants/app_constants.dart';
import 'package:she_m_app/core/errors/app_error.dart';

abstract class DatabaseService {
  Future<Map<String, dynamic>> read(String path);
  Future<Map<String, dynamic>> write(String path, Map<String, dynamic> data);
  Future<Map<String, dynamic>> update(String path, Map<String, dynamic> data);
  Future<Map<String, dynamic>?> updateIf(
    String path, {
    required bool Function(Map<String, dynamic> current) condition,
    required Map<String, dynamic> updates,
  });
  Future<void> delete(String path);
}

class FirebaseDatabaseService implements DatabaseService {
  FirebaseDatabaseService._internal()
      : _client = http.Client(),
        _databaseUrl = AppConstants.firebaseDatabaseUrl,
        _idTokenProvider = _getCurrentIdToken;

  FirebaseDatabaseService.forTesting({
    required http.Client client,
    required String databaseUrl,
    Future<String?> Function()? idTokenProvider,
  })  : _client = client,
        _databaseUrl = databaseUrl,
        _idTokenProvider = idTokenProvider ?? _noIdToken;

  static const _requestTimeout = Duration(seconds: 20);
  static final FirebaseDatabaseService instance =
      FirebaseDatabaseService._internal();
  final http.Client _client;
  final String _databaseUrl;
  final Future<String?> Function() _idTokenProvider;

  Uri _buildUri(String path, {Map<String, String>? query}) {
    final base = _databaseUrl.trim();
    final normalizedBase =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final uri = Uri.parse('$normalizedBase/$path.json');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  static Future<String?> _getCurrentIdToken() async {
    if (Firebase.apps.isEmpty) return null;
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser ?? await auth.authStateChanges().first;
    return user?.getIdToken();
  }

  static Future<String?> _noIdToken() async => null;

  @override
  Future<Map<String, dynamic>> read(String path) async {
    return _readFromUri(_buildUri(path));
  }

  Future<Map<String, dynamic>> readWithQuery(
    String path, {
    required Map<String, String> query,
  }) async {
    return _readFromUri(_buildUri(path, query: query));
  }

  Future<Map<String, dynamic>> _readFromUri(Uri uri) async {
    final response = await _send(uri, (authenticatedUri) {
      return _client.get(authenticatedUri);
    });
    _ensureSuccessful(response);
    return _decodeResponseMap(response);
  }

  @override
  Future<Map<String, dynamic>> write(
      String path, Map<String, dynamic> data) async {
    final response = await _send(
      _buildUri(path),
      (uri) => _client.put(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      ),
    );
    _ensureSuccessful(response);
    return _decodeResponseMap(response);
  }

  Future<bool> createIfAbsent(String path, Map<String, dynamic> data) async {
    final response = await _send(
      _buildUri(path),
      (uri) => _client.put(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'If-Match': 'null_etag',
        },
        body: jsonEncode(data),
      ),
    );
    if (response.statusCode == 412) return false;
    _ensureSuccessful(response);
    return true;
  }

  @override
  Future<Map<String, dynamic>> update(
      String path, Map<String, dynamic> data) async {
    final response = await _send(
      _buildUri(path),
      (uri) => _client.patch(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      ),
    );
    _ensureSuccessful(response);
    return _decodeResponseMap(response);
  }

  @override
  Future<Map<String, dynamic>?> updateIf(
    String path, {
    required bool Function(Map<String, dynamic> current) condition,
    required Map<String, dynamic> updates,
  }) async {
    final readResponse = await _send(
      _buildUri(path),
      (uri) => _client.get(
        uri,
        headers: const {'X-Firebase-ETag': 'true'},
      ),
    );
    _ensureSuccessful(readResponse);

    final etag = readResponse.headers['etag'];
    if (etag == null || etag.isEmpty) {
      _fail(
        const AppException(
          AppErrorMessage.invalidData,
          kind: AppErrorKind.invalidData,
        ),
      );
    }

    final decoded = _decodeResponse(readResponse);
    if (decoded is! Map) return null;
    final current = Map<String, dynamic>.from(decoded);
    if (!condition(current)) return null;

    final response = await _send(
      _buildUri(path),
      (uri) => _client.put(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'If-Match': etag,
        },
        body: jsonEncode({...current, ...updates}),
      ),
    );

    if (response.statusCode == 412) return null;
    _ensureSuccessful(response);
    return _decodeResponseMap(response);
  }

  @override
  Future<void> delete(String path) async {
    final response = await _send(
      _buildUri(path),
      (uri) => _client.delete(uri),
    );
    _ensureSuccessful(response);
  }

  void close() => _client.close();

  Future<http.Response> _send(
    Uri uri,
    Future<http.Response> Function(Uri uri) request,
  ) async {
    try {
      final token = await _idTokenProvider().timeout(_requestTimeout);
      final authenticatedUri = token == null || token.isEmpty
          ? uri
          : uri.replace(
              queryParameters: {...uri.queryParameters, 'auth': token},
            );
      return await request(authenticatedUri).timeout(_requestTimeout);
    } on SocketException {
      _fail(
        const AppException(
          AppErrorMessage.network,
          kind: AppErrorKind.network,
        ),
      );
    } on http.ClientException {
      _fail(
        const AppException(
          AppErrorMessage.network,
          kind: AppErrorKind.network,
        ),
      );
    } on TimeoutException {
      _fail(
        const AppException(
          AppErrorMessage.timeout,
          kind: AppErrorKind.timeout,
        ),
      );
    } on IOException {
      _fail(
        const AppException(
          AppErrorMessage.network,
          kind: AppErrorKind.network,
        ),
      );
    }
  }

  void _ensureSuccessful(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;

    final statusCode = response.statusCode;
    final kind = statusCode == 401 || statusCode == 403
        ? AppErrorKind.access
        : statusCode == 408
            ? AppErrorKind.timeout
            : statusCode == 429 || statusCode >= 500
                ? AppErrorKind.server
                : AppErrorKind.unexpected;
    final message = switch (kind) {
      AppErrorKind.access => AppErrorMessage.access,
      AppErrorKind.server => AppErrorMessage.server,
      AppErrorKind.timeout => AppErrorMessage.timeout,
      _ => AppErrorMessage.unexpected,
    };
    _fail(AppException(message, kind: kind, statusCode: statusCode));
  }

  Map<String, dynamic> _decodeResponseMap(http.Response response) {
    if (response.body.trim().isEmpty || response.body.trim() == 'null') {
      return <String, dynamic>{};
    }
    final decoded = _decodeResponse(response);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return <String, dynamic>{'value': decoded};
  }

  Object? _decodeResponse(http.Response response) {
    try {
      return jsonDecode(response.body);
    } on FormatException {
      _fail(
        const AppException(
          AppErrorMessage.invalidData,
          kind: AppErrorKind.invalidData,
        ),
      );
    }
  }

  Never _fail(AppException exception) {
    AppErrorReporter.report(exception);
    throw exception;
  }
}
