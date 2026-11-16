import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';

enum AppUpdateImportance {
  optional,
  mandatory,
  repeat,
}

class AppUpdateNotice {
  const AppUpdateNotice({
    required this.active,
    required this.latestVersion,
    required this.title,
    required this.message,
    required this.downloadUrl,
    required this.targetRoles,
    required this.importance,
  });

  const AppUpdateNotice.disabled()
      : active = false,
        latestVersion = '',
        title = '',
        message = '',
        downloadUrl = '',
        targetRoles = const [],
        importance = AppUpdateImportance.optional;

  static const supportedRoles = <String>[
    'customer',
    'merchant',
    'driver',
    'central_dispatcher',
    'manager',
    'admin',
  ];

  final bool active;
  final String latestVersion;
  final String title;
  final String message;
  final String downloadUrl;
  final List<String> targetRoles;
  final AppUpdateImportance importance;

  factory AppUpdateNotice.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('active') && json['active'] is! bool) {
      throw const FormatException('حالة إشعار التحديث غير صحيحة');
    }
    final active = json['active'] == true;
    final importance = AppUpdateImportance.values.firstWhere(
      (value) => value.name == json['importance'],
      orElse: () => AppUpdateImportance.optional,
    );
    final rawRoles = json['target_roles'];
    if (active && rawRoles is! List) {
      throw const FormatException('إعدادات التحديث غير مكتملة');
    }
    final targetRoles = rawRoles is List
        ? rawRoles.whereType<String>().where(supportedRoles.contains).toList()
        : const <String>[];
    if (active && targetRoles.isEmpty) {
      throw const FormatException('إعدادات التحديث لا تحتوي أدوارًا صالحة');
    }

    final notice = AppUpdateNotice(
      active: active,
      latestVersion: json['latest_version']?.toString().trim() ?? '',
      title: json['title']?.toString().trim() ?? '',
      message: json['message']?.toString().trim() ?? '',
      downloadUrl: json['download_url']?.toString().trim() ?? '',
      targetRoles: targetRoles,
      importance: importance,
    );
    if (active) {
      if (!AppUpdateImportance.values.any(
        (value) => value.name == json['importance'],
      )) {
        throw const FormatException('أهمية التحديث غير معروفة');
      }
      notice.validate();
    }
    return notice;
  }

  bool targetsRole(String role) => targetRoles.contains(role);

  Map<String, dynamic> toJson() => {
        'active': active,
        'latest_version': latestVersion,
        'title': title,
        'message': message,
        'download_url': downloadUrl,
        'target_roles': targetRoles,
        'importance': importance.name,
      };

  void validate() {
    if (!active) return;
    if (!_isValidVersion(latestVersion)) {
      throw ArgumentError('أدخل رقم إصدار صحيحًا مثل 1.2.3');
    }
    if (title.isEmpty || message.isEmpty) {
      throw ArgumentError('أدخل عنوان التنبيه ونصه');
    }
    if (targetRoles.isEmpty ||
        targetRoles.any((role) => !supportedRoles.contains(role))) {
      throw ArgumentError('حدد نوع مستخدم واحدًا على الأقل');
    }
    final uri = Uri.tryParse(downloadUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw ArgumentError('رابط التحميل يجب أن يكون رابط HTTPS صالحًا');
    }
  }

  static bool _isValidVersion(String version) =>
      RegExp(r'^\d+(?:\.\d+){1,3}$').hasMatch(version);

  static int compareVersions(String first, String second) {
    if (!_isValidVersion(first) || !_isValidVersion(second)) {
      throw const FormatException('صيغة رقم الإصدار غير صحيحة');
    }
    final firstParts = first.split('.').map(int.parse).toList();
    final secondParts = second.split('.').map(int.parse).toList();
    final length = firstParts.length > secondParts.length
        ? firstParts.length
        : secondParts.length;
    for (var index = 0; index < length; index++) {
      final firstPart = index < firstParts.length ? firstParts[index] : 0;
      final secondPart = index < secondParts.length ? secondParts[index] : 0;
      if (firstPart != secondPart) return firstPart.compareTo(secondPart);
    }
    return 0;
  }
}

class AppUpdateService {
  AppUpdateService({
    DatabaseService? databaseService,
    AuthService? authService,
    FlutterSecureStorage? secureStorage,
  })  : _databaseService = databaseService ?? FirebaseDatabaseService.instance,
        _authService = authService ?? AuthService(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const String _settingsPath = 'app_settings/app_update_notice';
  static const String _dismissedVersionKey = 'app_update_dismissed_version';

  final DatabaseService _databaseService;
  final AuthService _authService;
  final FlutterSecureStorage _secureStorage;

  Future<AppUpdateNotice> getNotice() async {
    final settings = await _databaseService.read(_settingsPath);
    if (settings.isEmpty) return const AppUpdateNotice.disabled();
    return AppUpdateNotice.fromJson(settings);
  }

  Future<void> saveNotice(AppUpdateNotice notice) async {
    final profile = await _authService.loadSession();
    if (profile?.role != 'admin') {
      throw StateError('يلزم تسجيل الدخول بحساب مسؤول لإدارة تحديث التطبيق');
    }
    notice.validate();
    await _databaseService.write(_settingsPath, {
      ...notice.toJson(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<bool> wasDismissed(String version) async {
    return await _secureStorage.read(key: _dismissedVersionKey) == version;
  }

  Future<void> saveDismissedVersion(String version) async {
    await _secureStorage.write(
      key: _dismissedVersionKey,
      value: version,
    );
  }
}
