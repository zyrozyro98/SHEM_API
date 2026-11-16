import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:she_m_app/core/constants/app_constants.dart';
import 'package:she_m_app/core/errors/app_error.dart';
import 'package:she_m_app/data/models/user_model.dart';
import 'package:she_m_app/data/services/cart_service.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';

class SavedAccountSession {
  const SavedAccountSession({
    required this.profileId,
    required this.sessionId,
    required this.sessionSecret,
    required this.expiresAt,
    required this.fullName,
    required this.phone,
    required this.role,
    this.email,
    this.shopName,
    this.profileImageUrl,
  });

  final String profileId;
  final String sessionId;
  final String sessionSecret;
  final DateTime expiresAt;
  final String fullName;
  final String phone;
  final String role;
  final String? email;
  final String? shopName;
  final String? profileImageUrl;

  factory SavedAccountSession.fromJson(Map<String, dynamic> json) {
    final image = (json['profile_image_url'] ?? json['profileImageUrl'])
            ?.toString()
            .trim() ??
        '';
    return SavedAccountSession(
      profileId:
          (json['profile_id'] ?? json['profileId'] ?? '').toString().trim(),
      sessionId:
          (json['session_id'] ?? json['sessionId'] ?? '').toString().trim(),
      sessionSecret: (json['session_secret'] ?? json['sessionSecret'] ?? '')
          .toString()
          .trim(),
      expiresAt: _parseExpiration(json['expires_at'] ?? json['expiresAt']),
      fullName: (json['full_name'] ?? json['fullName'] ?? '').toString().trim(),
      phone: (json['phone'] ?? '').toString().trim(),
      role: (json['role'] ?? 'customer').toString().trim(),
      email: json['email']?.toString(),
      shopName: (json['shop_name'] ?? json['shopName'])?.toString(),
      profileImageUrl:
          image.startsWith('http://') || image.startsWith('https://')
              ? image
              : null,
    );
  }

  static DateTime _parseExpiration(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed != null) return parsed.toUtc();
    final epoch = value is num ? value.toInt() : int.tryParse('$value');
    if (epoch == null || epoch <= 0) {
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
    return DateTime.fromMillisecondsSinceEpoch(
      epoch < 1000000000000 ? epoch * 1000 : epoch,
      isUtc: true,
    );
  }

  factory SavedAccountSession.fromProfile({
    required UserModel profile,
    required String sessionId,
    required String sessionSecret,
    required DateTime expiresAt,
  }) {
    final image = profile.profileImageData?.trim() ?? '';
    return SavedAccountSession(
      profileId: profile.id.trim(),
      sessionId: sessionId,
      sessionSecret: sessionSecret,
      expiresAt: expiresAt.toUtc(),
      fullName: profile.fullName.trim(),
      phone: profile.phone.trim(),
      role: profile.role.trim(),
      email: profile.email,
      shopName: profile.shopName,
      profileImageUrl:
          image.startsWith('http://') || image.startsWith('https://')
              ? image
              : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'profile_id': profileId,
        'session_id': sessionId,
        'session_secret': sessionSecret,
        'expires_at': expiresAt.toUtc().toIso8601String(),
        'full_name': fullName,
        'phone': phone,
        'role': role,
        'email': email,
        'shop_name': shopName,
        'profile_image_url': profileImageUrl,
      };

  SavedAccountSession copyWith({
    String? sessionSecret,
    DateTime? expiresAt,
    String? fullName,
    String? phone,
    String? role,
    String? email,
    String? shopName,
    String? profileImageUrl,
  }) {
    return SavedAccountSession(
      profileId: profileId,
      sessionId: sessionId,
      sessionSecret: sessionSecret ?? this.sessionSecret,
      expiresAt: expiresAt ?? this.expiresAt,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      email: email ?? this.email,
      shopName: shopName ?? this.shopName,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
    );
  }
}

class AuthService {
  AuthService({
    DatabaseService? databaseService,
    http.Client? httpClient,
    String? authApiBaseUrl,
  })  : _databaseService = databaseService ?? FirebaseDatabaseService.instance,
        _httpClient = httpClient,
        _authApiBaseUrl = authApiBaseUrl ?? AppConstants.mediaApiBaseUrl;

  final DatabaseService _databaseService;
  final http.Client? _httpClient;
  final String _authApiBaseUrl;

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _sessionKey = 'she_m_session_profile';
  static const String _sessionExpiryKey = 'she_m_session_expires_at';
  static const String _savedAccountSessionsKey = 'she_m_saved_account_sessions';
  static const Duration _sessionLifetime = Duration(days: 3650);
  static const Duration _signupOtpLifetime = Duration(minutes: 10);
  static final ValueNotifier<Object?> profileUpdated =
      ValueNotifier<Object?>(null);

  static String? _verificationId;
  static String? _verificationPhone;
  static const String _backendVerificationId = 'backend-phone-verification';
  static const Duration _phoneChangeVerificationLifetime = Duration(minutes: 5);
  static bool _updatePhoneOnCurrentUser = false;
  static bool _verificationIsSignup = false;
  static bool _verificationIsPasswordReset = false;
  static String? _passwordResetVerificationPhone;
  static DateTime? _passwordResetVerificationAt;
  static const Duration _passwordResetVerificationLifetime =
      Duration(minutes: 5);
  static String? _verifiedSignupPhone;
  static DateTime? _verifiedSignupAt;
  static String? _verifiedPhoneChangePhone;
  static DateTime? _verifiedPhoneChangeAt;
  String? lastError;

  bool get isFirebaseReady {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  bool get _isFirebaseReady => isFirebaseReady;

  String hashPassword(String password) {
    return sha256.convert(utf8.encode(password.trim())).toString();
  }

  Future<bool> _signInPhoneUserForMedia(
    String phone,
    String password,
  ) async {
    if (!_isFirebaseReady) {
      lastError = 'خدمة المصادقة غير متاحة حاليًا';
      return false;
    }

    try {
      final response = await _callBackendAuthEndpoint('/media/session', {
        'phone': phone,
        'password': password,
      });
      final customToken = response['custom_token']?.toString().trim();
      if (response['success'] != true ||
          customToken == null ||
          customToken.isEmpty) {
        final error = AppException(
          _backendAuthError(
            response,
            fallback: 'تعذر تهيئة جلسة رفع الملفات لهذا الحساب',
          ),
          kind: AppErrorKind.access,
        );
        lastError = error.message;
        AppErrorReporter.report(error);
        return false;
      }

      await FirebaseAuth.instance.signInWithCustomToken(customToken);
      return true;
    } catch (error) {
      lastError = AppErrorMessage.from(error);
      AppErrorReporter.report(error);
      return false;
    }
  }

  Future<void> saveSession(UserModel user) async {
    try {
      await _secureStorage.write(
        key: _sessionKey,
        value: jsonEncode(user.toJson()),
      );
      await _secureStorage.write(
        key: _sessionExpiryKey,
        value: DateTime.now().add(_sessionLifetime).toUtc().toIso8601String(),
      );
      profileUpdated.value = Object();
    } catch (error) {
      lastError = AppErrorMessage.from(error);
      AppErrorReporter.report(error);
    }
    await _refreshSavedAccountProfile(user);
  }

  Future<UserModel?> updateDeliveryAddresses({
    required UserModel profile,
    required List<DeliveryAddress> addresses,
    required String selectedAddressId,
  }) async {
    lastError = null;
    DeliveryAddress? selected;
    for (final address in addresses) {
      if (address.id == selectedAddressId) {
        selected = address;
        break;
      }
    }
    if (selected == null) {
      lastError = 'اختر عنوانًا صالحًا للتوصيل';
      return null;
    }

    final updated = profile.copyWith(
      city: selected.city,
      address: selected.address,
      currentLocation: selected.locationCoordinates,
      deliveryAddresses: List<DeliveryAddress>.unmodifiable(addresses),
      selectedDeliveryAddressId: selected.id,
    );
    try {
      await _databaseService.update('profiles/${profile.id}', {
        'city': updated.city,
        'address': updated.address,
        'current_location': updated.currentLocation,
        'delivery_addresses': updated.deliveryAddresses
            .map((address) => address.toJson())
            .toList(),
        'selected_delivery_address_id': updated.selectedDeliveryAddressId,
      });
      await saveSession(updated);
      return updated;
    } catch (error) {
      lastError = AppErrorMessage.from(error);
      AppErrorReporter.report(error);
      return null;
    }
  }

  Future<List<SavedAccountSession>> getSavedAccountSessions() async {
    final accounts = await _readSavedAccountSessions();
    final active = accounts
        .where((account) => account.expiresAt.isAfter(DateTime.now().toUtc()))
        .toList();
    if (active.length != accounts.length) {
      await _writeSavedAccountSessions(active);
    }
    return active;
  }

  Future<bool> rememberCurrentAccount(UserModel profile) async {
    final firebaseUser =
        _isFirebaseReady ? FirebaseAuth.instance.currentUser : null;
    if (firebaseUser == null) {
      lastError = 'تعذر حفظ جلسة هذا الحساب على الجهاز';
      return false;
    }

    try {
      final idToken = await firebaseUser.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        lastError = 'تعذر التحقق من جلسة الحساب';
        return false;
      }
      final response = await _callBackendAuthEndpoint(
        '/media/switch-sessions',
        const {},
        headers: {'Authorization': 'Bearer $idToken'},
      );
      final sessionId = (response['session_id'] ?? response['sessionId'])
              ?.toString()
              .trim() ??
          '';
      final sessionSecret =
          (response['session_secret'] ?? response['sessionSecret'])
                  ?.toString()
                  .trim() ??
              '';
      final expiresAt = SavedAccountSession._parseExpiration(
        response['expires_at'] ?? response['expiresAt'],
      );
      if (response['success'] != true ||
          sessionId.isEmpty ||
          !RegExp(r'^[a-f0-9]{64}$', caseSensitive: false)
              .hasMatch(sessionSecret) ||
          !expiresAt.isAfter(DateTime.now().toUtc())) {
        lastError = _backendAuthError(
          response,
          fallback: 'تعذر تفعيل التبديل السريع لهذا الحساب',
        );
        return false;
      }

      final saved = SavedAccountSession.fromProfile(
        profile: profile,
        sessionId: sessionId,
        sessionSecret: sessionSecret,
        expiresAt: expiresAt,
      );
      final accounts = await _readSavedAccountSessions();
      accounts.removeWhere((account) =>
          account.profileId == saved.profileId ||
          account.sessionId == saved.sessionId);
      accounts.add(saved);
      await _writeSavedAccountSessions(accounts);
      return true;
    } catch (error, stackTrace) {
      lastError = AppErrorMessage.from(error);
      AppErrorReporter.report(error);
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  Future<UserModel?> switchToSavedAccount(String sessionId) async {
    lastError = null;
    final accounts = await _readSavedAccountSessions();
    final index =
        accounts.indexWhere((account) => account.sessionId == sessionId);
    if (index < 0) {
      lastError = 'الحساب المحفوظ غير موجود على هذا الجهاز';
      return null;
    }
    final account = accounts[index];
    if (!_isFirebaseReady) {
      lastError = 'خدمة المصادقة غير متاحة حاليًا';
      return null;
    }

    try {
      final response = await _callBackendAuthEndpoint(
        '/media/switch-sessions/restore',
        {
          'session_id': account.sessionId,
          'session_secret': account.sessionSecret,
        },
      );
      if (response['success'] != true) {
        lastError = _backendAuthError(
          response,
          fallback: 'تعذر استعادة جلسة هذا الحساب',
        );
        if ({
          'invalid_switch_session',
          'account_not_found',
        }.contains(response['error_code'])) {
          accounts.removeAt(index);
          await _writeSavedAccountSessions(accounts);
        }
        return null;
      }

      final customToken = (response['custom_token'] ?? response['customToken'])
              ?.toString()
              .trim() ??
          '';
      final nextSecret =
          (response['session_secret'] ?? response['sessionSecret'])
                  ?.toString()
                  .trim() ??
              '';
      final expiresAt = SavedAccountSession._parseExpiration(
        response['expires_at'] ?? response['expiresAt'],
      );
      final profileData = response['profile'];
      if (customToken.isEmpty ||
          !RegExp(r'^[a-f0-9]{64}$', caseSensitive: false)
              .hasMatch(nextSecret) ||
          !expiresAt.isAfter(DateTime.now().toUtc()) ||
          profileData is! Map) {
        lastError = 'استجابة استعادة الحساب غير صالحة';
        return null;
      }

      final profile =
          UserModel.fromJson(Map<String, dynamic>.from(profileData));
      final returnedProfileId =
          (response['profile_id'] ?? response['profileId'])
                  ?.toString()
                  .trim() ??
              '';
      final returnedRole = response['role']?.toString().trim() ?? '';
      if (profile.id.trim() != account.profileId ||
          returnedProfileId != account.profileId ||
          profile.role.trim() != returnedRole) {
        lastError = 'بيانات الحساب المحفوظ لا تطابق الحساب المستعاد';
        return null;
      }

      accounts[index] = account.copyWith(
        sessionSecret: nextSecret,
        expiresAt: expiresAt,
        fullName: profile.fullName,
        phone: profile.phone,
        role: profile.role,
        email: profile.email,
        shopName: profile.shopName,
        profileImageUrl: _publicProfileImage(profile.profileImageData),
      );
      try {
        await _writeSavedAccountSessions(accounts);
      } catch (_) {
        lastError =
            'تعذر حفظ جلسة الحساب المستعادة. سجّل الدخول إلى الحساب لإضافته مجددًا.';
        return null;
      }
      await FirebaseAuth.instance.signInWithCustomToken(customToken);
      await saveSession(profile);
      await CartService.instance.loadForUser(profile.id);
      return profile;
    } catch (error, stackTrace) {
      lastError = AppErrorMessage.from(error);
      AppErrorReporter.report(error);
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  Future<bool> removeSavedAccountSession(String sessionId) async {
    lastError = null;
    final accounts = await _readSavedAccountSessions();
    final index =
        accounts.indexWhere((account) => account.sessionId == sessionId);
    if (index < 0) return true;
    final account = accounts[index];

    try {
      final response = await _callBackendAuthEndpoint(
        '/media/switch-sessions/revoke',
        {
          'session_id': account.sessionId,
          'session_secret': account.sessionSecret,
        },
      );
      if (response['success'] != true &&
          response['error_code'] != 'invalid_switch_session') {
        lastError = _backendAuthError(
          response,
          fallback: 'تعذر إزالة الحساب المحفوظ',
        );
        return false;
      }

      accounts.removeAt(index);
      await _writeSavedAccountSessions(accounts);
      return true;
    } catch (error, stackTrace) {
      lastError = AppErrorMessage.from(error);
      AppErrorReporter.report(error);
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  Future<List<SavedAccountSession>> _readSavedAccountSessions() async {
    try {
      final value = await _secureStorage.read(key: _savedAccountSessionsKey);
      if (value == null || value.trim().isEmpty) return [];
      final decoded = jsonDecode(value);
      if (decoded is! List) {
        throw const FormatException('Saved account sessions are invalid');
      }
      return decoded
          .whereType<Map>()
          .map((item) => SavedAccountSession.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .where((account) =>
              account.profileId.isNotEmpty &&
              account.sessionId.isNotEmpty &&
              account.sessionSecret.isNotEmpty)
          .toList();
    } catch (error, stackTrace) {
      lastError = AppErrorMessage.from(error);
      AppErrorReporter.report(error);
      debugPrintStack(stackTrace: stackTrace);
      return [];
    }
  }

  Future<void> _writeSavedAccountSessions(
    List<SavedAccountSession> accounts,
  ) async {
    try {
      await _secureStorage.write(
        key: _savedAccountSessionsKey,
        value: jsonEncode(accounts.map((account) => account.toJson()).toList()),
      );
    } catch (error, stackTrace) {
      lastError = AppErrorMessage.from(error);
      AppErrorReporter.report(error);
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> _refreshSavedAccountProfile(UserModel profile) async {
    try {
      final accounts = await _readSavedAccountSessions();
      final index =
          accounts.indexWhere((account) => account.profileId == profile.id);
      if (index < 0) return;
      accounts[index] = accounts[index].copyWith(
        fullName: profile.fullName,
        phone: profile.phone,
        role: profile.role,
        email: profile.email,
        shopName: profile.shopName,
        profileImageUrl: _publicProfileImage(profile.profileImageData),
      );
      await _writeSavedAccountSessions(accounts);
    } catch (error, stackTrace) {
      lastError = AppErrorMessage.from(error);
      AppErrorReporter.report(error);
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  String? _publicProfileImage(String? value) {
    final image = value?.trim() ?? '';
    return image.startsWith('http://') || image.startsWith('https://')
        ? image
        : null;
  }

  Future<void> clearSession() async {
    try {
      await _secureStorage.delete(key: _sessionKey);
      await _secureStorage.delete(key: _sessionExpiryKey);
    } catch (error) {
      AppErrorReporter.report(error);
    }
    profileUpdated.value = Object();
    _verifiedSignupPhone = null;
    _verifiedSignupAt = null;
    _verifiedPhoneChangePhone = null;
    _verifiedPhoneChangeAt = null;
    _passwordResetVerificationPhone = null;
    _passwordResetVerificationAt = null;
    await CartService.instance.deactivateUser();
    try {
      if (Firebase.apps.isNotEmpty) {
        await FirebaseAuth.instance.signOut();
      }
    } catch (_) {
      // In test mode Firebase may not be initialized; ignore.
    }
  }

  Future<UserModel?> loadSession() async {
    try {
      final profileJson = await _secureStorage.read(key: _sessionKey);
      if (profileJson == null || profileJson.trim().isEmpty) {
        return null;
      }

      final expiryAt = await _secureStorage.read(key: _sessionExpiryKey);
      if (expiryAt != null) {
        final expires = DateTime.tryParse(expiryAt);
        if (expires != null && DateTime.now().isAfter(expires)) {
          await clearSession();
          return null;
        }
      }

      try {
        final decoded = jsonDecode(profileJson);
        if (decoded is! Map) {
          await clearSession();
          return null;
        }
        return UserModel.fromJson(Map<String, dynamic>.from(decoded));
      } catch (_) {
        await clearSession();
        return null;
      }
    } catch (error) {
      AppErrorReporter.report(error);
      return null;
    }
  }

  Future<bool> loginWithPassword({
    required String phone,
    required String password,
  }) async {
    lastError = null;
    final normalized = normalizePhone(phone);
    if (!AppConstants.isYemenPhoneValid(normalized)) {
      lastError = 'يرجى إدخال رقم هاتف يمني صحيح';
      return false;
    }

    try {
      if (_databaseService is FirebaseDatabaseService &&
          !await _signInPhoneUserForMedia(normalized, password)) {
        return false;
      }

      final key = normalized.replaceAll(RegExp(r'[^0-9]'), '');
      final snapshot = await _databaseService.read('profiles/$key');
      if (snapshot.isEmpty) {
        lastError = 'بيانات الدخول غير صحيحة أو الحساب غير موجود';
        await signOutFirebaseOnly();
        return false;
      }

      final user = UserModel.fromJson(snapshot);
      final hashedPassword = hashPassword(password);
      if (user.passwordHash == null || user.passwordHash!.isEmpty) {
        lastError = 'بيانات الدخول غير صحيحة أو الحساب غير موجود';
        await signOutFirebaseOnly();
        return false;
      }
      if (user.passwordHash != hashedPassword) {
        lastError = 'بيانات الدخول غير صحيحة أو الحساب غير موجود';
        await signOutFirebaseOnly();
        return false;
      }

      await saveSession(user);
      await rememberCurrentAccount(user);
      return true;
    } catch (error) {
      lastError = AppErrorMessage.from(error);
      AppErrorReporter.report(error);
      await signOutFirebaseOnly();
      return false;
    }
  }

  Future<bool> loginWithEmailOrPhone({
    required String identifier,
    required String password,
  }) async {
    lastError = null;
    final value = identifier.trim();
    if (value.contains('@')) {
      try {
        final credentials = await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: value, password: password);
        final authUser = credentials.user;
        if (authUser == null) {
          lastError = 'تعذر إنشاء جلسة الدخول';
          return false;
        }

        await authUser.reload();
        if (!authUser.emailVerified) {
          lastError =
              'يرجى تأكيد بريدك الإلكتروني من الرسالة المرسلة إليك أولًا';
          await FirebaseAuth.instance.signOut();
          return false;
        }

        if (_databaseService is FirebaseDatabaseService &&
            !await _syncFirebaseSession()) {
          await FirebaseAuth.instance.signOut();
          return false;
        }

        final index = await FirebaseDatabaseService.instance
            .read('auth_index/${authUser.uid}');
        final phone = index['phone']?.toString() ?? '';
        if (phone.isEmpty) {
          lastError = 'لا يوجد ملف مستخدم مرتبط بهذا البريد';
          return false;
        }
        final profileKey = phone.replaceAll(RegExp(r'[^0-9]'), '');
        final profile =
            await FirebaseDatabaseService.instance.read('profiles/$profileKey');
        if (profile.isEmpty) {
          lastError = 'لا يوجد ملف مستخدم مرتبط بهذا البريد';
          return false;
        }
        final user = UserModel.fromJson(profile);
        await saveSession(user);
        await rememberCurrentAccount(user);
        return true;
      } on FirebaseAuthException catch (error) {
        lastError = friendlyFirebaseError(error);
        return false;
      } catch (error) {
        lastError = AppErrorMessage.from(error);
        AppErrorReporter.report(error);
        return false;
      }
    }

    return loginWithPassword(phone: value, password: password);
  }

  Future<bool> resendEmailVerification() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      await user.sendEmailVerification();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isCurrentEmailVerified() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      await user.reload();
      return FirebaseAuth.instance.currentUser?.emailVerified == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> signOutFirebaseOnly() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      // Ignore sign-out failures while abandoning an unverified signup.
    }
  }

  Future<UserModel?> signInWithGoogle() async {
    if (!_isFirebaseReady) {
      lastError = 'خدمة المصادقة غير متاحة حاليًا';
      return null;
    }

    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        lastError = 'تم إلغاء تسجيل الدخول عبر Google';
        return null;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final firebaseUser = userCredential.user;
      if (firebaseUser == null) {
        lastError = 'تعذر إنشاء جلسة Google';
        return null;
      }

      final profileKey = firebaseUser.uid;
      final existing = await _databaseService.read('profiles/$profileKey');
      if (existing.isNotEmpty) {
        if (_databaseService is FirebaseDatabaseService &&
            !await _syncFirebaseSession()) {
          return null;
        }
        final profile = UserModel.fromJson(existing);
        await saveSession(profile);
        await rememberCurrentAccount(profile);
        return profile;
      }

      final fullName =
          (googleUser.displayName ?? firebaseUser.displayName ?? '').trim();
      return UserModel(
        id: profileKey,
        fullName: fullName.isEmpty ? 'مستخدم Google' : fullName,
        phone: '',
        email: firebaseUser.email,
        role: 'customer',
        isVerified: false,
        profileImageData: googleUser.photoUrl ?? firebaseUser.photoURL,
        createdAt: DateTime.now(),
      );
    } on FirebaseAuthException catch (error) {
      lastError = friendlyFirebaseError(error);
      return null;
    } catch (error) {
      lastError = error.toString().contains('ApiException: 10')
          ? 'إعداد Google غير مكتمل. أضف بصمة SHA-1 لتطبيق Android في Firebase.'
          : 'تعذر تسجيل الدخول عبر Google، حاول مرة أخرى';
      return null;
    }
  }

  Future<UserModel?> completeGoogleProfile({
    required UserModel profile,
    required String phone,
    required String city,
    String? address,
    String? currentLocation,
  }) async {
    final normalizedPhone = normalizePhone(phone);
    if (!AppConstants.isYemenPhoneValid(normalizedPhone)) {
      lastError = 'يرجى إدخال رقم هاتف يمني صحيح';
      return null;
    }
    if (AppConstants.requirePhoneVerificationOnSignup &&
        !_isSignupPhoneVerified(normalizedPhone)) {
      lastError = 'يرجى التحقق من رقم الهاتف قبل إكمال التسجيل';
      return null;
    }
    if (_databaseService is FirebaseDatabaseService &&
        (!_isFirebaseReady || FirebaseAuth.instance.currentUser == null)) {
      lastError = 'سجّل الدخول وتحقق من رقم الهاتف قبل حفظ الملف';
      return null;
    }
    final firebaseUid =
        _isFirebaseReady ? FirebaseAuth.instance.currentUser?.uid : null;

    try {
      final profilePath = 'profiles/${profile.id}';
      final existing = await _databaseService.read(profilePath);
      final phoneKey = normalizedPhone.replaceAll(RegExp(r'[^0-9]'), '');
      final existingByPhone = await _databaseService.read('profiles/$phoneKey');
      if (existingByPhone.isNotEmpty &&
          existingByPhone['id']?.toString() != profile.id) {
        lastError = 'رقم الهاتف مرتبط بحساب آخر';
        return null;
      }

      final saved = existing.isEmpty
          ? await _databaseService.write(profilePath, {
              'id': profile.id,
              'full_name': profile.fullName,
              'phone': normalizedPhone,
              'email': profile.email,
              'role': 'customer',
              'city': city.trim(),
              'address': address?.trim(),
              'current_location': currentLocation?.trim(),
              'auth_uid': firebaseUid,
              'password_hash': null,
              'profile_image': profile.profileImageData,
              'is_verified': false,
              'auth_provider': 'google',
              'created_at': profile.createdAt.toUtc().toIso8601String(),
            })
          : await _databaseService.update(profilePath, {
              'phone': normalizedPhone,
              'city': city.trim(),
              'address': address?.trim(),
              'current_location': currentLocation?.trim(),
              if (existing['auth_uid'] == null) 'auth_uid': firebaseUid,
            });
      if (phoneKey != profile.id) {
        await _databaseService.write('profiles/$phoneKey', saved);
      }
      if (_databaseService is FirebaseDatabaseService &&
          !await _syncFirebaseSession()) {
        return null;
      }
      final completed = profile.copyWith(
        phone: saved['phone']?.toString() ?? normalizedPhone,
        city: saved['city']?.toString() ?? city.trim(),
        address: saved['address']?.toString() ?? address?.trim(),
        currentLocation:
            saved['current_location']?.toString() ?? currentLocation?.trim(),
      );
      await saveSession(completed);
      await rememberCurrentAccount(completed);
      _verifiedSignupPhone = null;
      _verifiedSignupAt = null;
      return completed;
    } catch (_) {
      lastError = 'تعذر حفظ رقم الهاتف، حاول مرة أخرى';
      return null;
    }
  }

  Future<bool> isPhoneAvailableForProfile({
    required UserModel profile,
    required String phone,
  }) async {
    final normalizedPhone = normalizePhone(phone);
    if (!AppConstants.isYemenPhoneValid(normalizedPhone)) return false;
    if (normalizedPhone == normalizePhone(profile.phone)) return true;

    try {
      final key = normalizedPhone.replaceAll(RegExp(r'[^0-9]'), '');
      final existing = await _databaseService.read('profiles/$key');
      return existing.isEmpty || existing['id']?.toString() == profile.id;
    } catch (_) {
      return false;
    }
  }

  Future<UserModel?> updateProfileDetails({
    required UserModel profile,
    required String email,
    required String phone,
    required String city,
    required String address,
    required String? profileImageData,
    String currentPassword = '',
    String? newPassword,
  }) async {
    final normalizedPhone = normalizePhone(phone);
    final normalizedEmail = email.trim().toLowerCase();
    if (!AppConstants.isYemenPhoneValid(normalizedPhone)) {
      lastError = 'يرجى إدخال رقم هاتف يمني صحيح';
      return null;
    }
    if (normalizedEmail.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalizedEmail)) {
      lastError = 'يرجى إدخال بريد إلكتروني صحيح';
      return null;
    }

    final phoneChanged = normalizePhone(profile.phone) != normalizedPhone;
    final emailChanged =
        (profile.email ?? '').trim().toLowerCase() != normalizedEmail;
    User? firebaseUser;
    try {
      firebaseUser = FirebaseAuth.instance.currentUser;
    } catch (_) {}
    if (phoneChanged &&
        !_isPhoneChangeVerified(normalizedPhone) &&
        (firebaseUser?.phoneNumber == null ||
            normalizePhone(firebaseUser!.phoneNumber!) != normalizedPhone)) {
      lastError = 'يرجى التحقق من رقم الهاتف الجديد عبر رمز OTP أولاً';
      return null;
    }

    if (emailChanged && normalizedEmail.isNotEmpty) {
      if (firebaseUser == null) {
        lastError = 'سجّل الدخول مجددًا لإرسال تأكيد البريد الجديد';
        return null;
      }
      try {
        final hasPasswordProvider = firebaseUser.providerData.any(
          (provider) => provider.providerId == 'password',
        );
        if (hasPasswordProvider) {
          final oldEmail = firebaseUser.email ?? profile.email ?? '';
          if (oldEmail.isEmpty || currentPassword.trim().isEmpty) {
            lastError = 'أدخل كلمة المرور الحالية لتأكيد تغيير البريد';
            return null;
          }
          await firebaseUser.reauthenticateWithCredential(
            EmailAuthProvider.credential(
              email: oldEmail,
              password: currentPassword.trim(),
            ),
          );
        }
        await firebaseUser.verifyBeforeUpdateEmail(normalizedEmail);
      } on FirebaseAuthException catch (error) {
        lastError = friendlyFirebaseError(error);
        return null;
      } catch (_) {
        lastError = 'تعذر إرسال رابط تأكيد البريد الجديد';
        return null;
      }
    }

    final oldPhoneKey = profile.phone.replaceAll(RegExp(r'[^0-9]'), '');
    final newPhoneKey = normalizedPhone.replaceAll(RegExp(r'[^0-9]'), '');
    final profilePath = 'profiles/${profile.id}';
    try {
      final currentRecord = await _databaseService.read(profilePath);
      final sourceRecord = currentRecord.isNotEmpty
          ? currentRecord
          : oldPhoneKey.isNotEmpty
              ? await _databaseService.read('profiles/$oldPhoneKey')
              : <String, dynamic>{};
      if (sourceRecord.isEmpty) {
        lastError = 'تعذر العثور على بيانات الحساب';
        return null;
      }

      if (phoneChanged) {
        final existingAtNewPhone =
            await _databaseService.read('profiles/$newPhoneKey');
        if (existingAtNewPhone.isNotEmpty &&
            existingAtNewPhone['id']?.toString() != profile.id) {
          lastError = 'رقم الهاتف الجديد مرتبط بحساب آخر';
          return null;
        }
      }

      final requestedPassword = newPassword?.trim() ?? '';
      if (requestedPassword.isNotEmpty &&
          _databaseService is FirebaseDatabaseService) {
        final passwordChanged = await _changePasswordViaBackend(
          newPassword: requestedPassword,
          currentPassword: currentPassword,
        );
        if (!passwordChanged) return null;
        sourceRecord['password_hash'] = hashPassword(requestedPassword);
      }

      final updatedProfile = profile.copyWith(
        phone: normalizedPhone,
        email: normalizedEmail.isEmpty ? null : normalizedEmail,
        city: city.trim(),
        address: address.trim(),
        profileImageData: profileImageData,
        passwordHash: (newPassword?.trim().isNotEmpty ?? false)
            ? hashPassword(newPassword!)
            : profile.passwordHash,
      );
      final updatedRecord = <String, dynamic>{
        ...sourceRecord,
        ...updatedProfile.toJson(),
        'email_verified': emailChanged ? false : sourceRecord['email_verified'],
        if (emailChanged && normalizedEmail.isNotEmpty)
          'pending_email': normalizedEmail,
        if (!emailChanged) 'pending_email': sourceRecord['pending_email'],
      };

      await _databaseService.write(profilePath, updatedRecord);
      if (phoneChanged && newPhoneKey != profile.id) {
        await _databaseService.write(
          'profiles/$newPhoneKey',
          updatedRecord,
        );
      }
      if (phoneChanged &&
          oldPhoneKey.isNotEmpty &&
          oldPhoneKey != newPhoneKey &&
          oldPhoneKey != profile.id) {
        final oldRecord = await _databaseService.read('profiles/$oldPhoneKey');
        if (oldRecord['id']?.toString() == profile.id) {
          await _databaseService.delete('profiles/$oldPhoneKey');
        }
      } else if (phoneChanged && oldPhoneKey == profile.id) {
        await _databaseService.delete('profiles/$oldPhoneKey');
      }

      if (firebaseUser != null) {
        if (_databaseService is FirebaseDatabaseService) {
          if (!await _syncFirebaseSession()) return null;
        } else {
          await _databaseService.update('auth_index/${firebaseUser.uid}', {
            'phone': normalizedPhone,
            'email': normalizedEmail,
          });
        }
      }

      await saveSession(updatedProfile);
      if (phoneChanged) {
        _verifiedPhoneChangePhone = null;
        _verifiedPhoneChangeAt = null;
      }
      return updatedProfile;
    } catch (error) {
      lastError = AppErrorMessage.from(error);
      AppErrorReporter.report(error);
      return null;
    }
  }

  Future<Map<String, dynamic>> requestPasswordResetOtp({
    required String phone,
  }) async {
    final normalized = normalizePhone(phone);
    if (!AppConstants.isYemenPhoneValid(normalized)) {
      return {
        'success': false,
        'error': 'يرجى إدخال رقم الهاتف اليمني الصحيح',
      };
    }

    final result = await requestOtp(
      phone: normalized,
      forPasswordReset: true,
    );
    if (result['success'] == true) {
      _verificationIsPasswordReset = true;
    }
    return result;
  }

  void _clearOtpState() {
    _verificationId = null;
    _verificationPhone = null;
    _updatePhoneOnCurrentUser = false;
    _verificationIsSignup = false;
    _verificationIsPasswordReset = false;
  }

  bool _isSignupPhoneVerified(String normalizedPhone) {
    final verifiedAt = _verifiedSignupAt;
    if (_verifiedSignupPhone != normalizedPhone || verifiedAt == null) {
      return false;
    }
    if (DateTime.now().difference(verifiedAt) > _signupOtpLifetime) {
      _verifiedSignupPhone = null;
      _verifiedSignupAt = null;
      return false;
    }
    return true;
  }

  bool _isPhoneChangeVerified(String normalizedPhone) {
    final verifiedAt = _verifiedPhoneChangeAt;
    if (_verifiedPhoneChangePhone != normalizedPhone || verifiedAt == null) {
      return false;
    }
    if (DateTime.now().difference(verifiedAt) >
        _phoneChangeVerificationLifetime) {
      _verifiedPhoneChangePhone = null;
      _verifiedPhoneChangeAt = null;
      return false;
    }
    return true;
  }

  Future<Map<String, dynamic>> resetPasswordWithOtp({
    required String phone,
    required String newPassword,
  }) async {
    final normalized = normalizePhone(phone);
    if (!AppConstants.isYemenPhoneValid(normalized)) {
      return {'success': false, 'error': 'رقم الهاتف غير صالح'};
    }
    if (!AppConstants.isStrongPassword(newPassword)) {
      return {
        'success': false,
        'error': 'كلمة المرور يجب ألا تقل عن 6 أحرف',
      };
    }

    final verifiedAt = _passwordResetVerificationAt;
    if (_passwordResetVerificationPhone != normalized ||
        verifiedAt == null ||
        DateTime.now().difference(verifiedAt) >
            _passwordResetVerificationLifetime) {
      _passwordResetVerificationPhone = null;
      _passwordResetVerificationAt = null;
      return {
        'success': false,
        'error': 'تحقق من رمز الهاتف بنجاح قبل تغيير كلمة المرور',
      };
    }

    try {
      final key = normalized.replaceAll(RegExp(r'[^0-9]'), '');
      final profile = await _databaseService.read('profiles/$key');
      if (profile.isEmpty) {
        return {'success': false, 'error': 'لا يوجد حساب مرتبط بهذا الرقم'};
      }

      final currentUser =
          _isFirebaseReady ? FirebaseAuth.instance.currentUser : null;
      if (_databaseService is FirebaseDatabaseService) {
        final passwordChanged = await _changePasswordViaBackend(
          newPassword: newPassword,
        );
        if (!passwordChanged) {
          return {
            'success': false,
            'error': lastError ?? 'تعذر تغيير كلمة المرور، حاول مرة أخرى',
          };
        }
      } else {
        final hasPasswordProvider = currentUser?.providerData.any(
              (provider) => provider.providerId == 'password',
            ) ??
            false;
        if (hasPasswordProvider && currentUser?.email == profile['email']) {
          await currentUser!.updatePassword(newPassword);
        }
        final updated = Map<String, dynamic>.from(profile)
          ..['password_hash'] = hashPassword(newPassword);
        await _databaseService.write('profiles/$key', updated);
      }
      _clearOtpState();
      _passwordResetVerificationPhone = null;
      _passwordResetVerificationAt = null;
      return {'success': true, 'message': 'تم تغيير كلمة المرور بنجاح'};
    } catch (_) {
      return {
        'success': false,
        'error': 'تعذر تغيير كلمة المرور، حاول مرة أخرى'
      };
    }
  }

  String normalizePhone(String phone) {
    var digits = _toWesternDigits(phone.trim()).replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';

    if (digits.startsWith('00')) digits = digits.substring(2);
    if (digits.startsWith('967')) return '+$digits';
    if (digits.startsWith('0')) digits = digits.substring(1);
    return '+967$digits';
  }

  String _toWesternDigits(String value) {
    return value.replaceAllMapped(
      RegExp(r'[\u0660-\u0669\u06F0-\u06F9]'),
      (match) {
        final codeUnit = match.group(0)!.codeUnitAt(0);
        final westernDigit =
            codeUnit >= 0x06F0 ? codeUnit - 0x06F0 : codeUnit - 0x0660;
        return String.fromCharCode(0x30 + westernDigit);
      },
    );
  }

  String friendlyFirebaseError(FirebaseAuthException error) {
    final details = '${error.code} ${error.message ?? ''}'.toUpperCase();
    if (details.contains('BILLING_NOT_ENABLED') ||
        details.contains('BILLING NOT ENABLED')) {
      return 'خدمة المصادقة في Firebase غير مفعّلة للفوترة. تحقّق من إعدادات المشروع ثم أعد المحاولة.';
    }

    switch (error.code) {
      case 'auth/operation-not-allowed':
      case 'auth/invalid-app-credential':
        return 'خدمة المصادقة في Firebase غير مفعّلة لهذا التطبيق.';
      default:
        return error.message ?? 'تعذر إكمال عملية المصادقة.';
    }
  }

  Future<Map<String, dynamic>> _callBackendAuthEndpoint(
    String path,
    Map<String, dynamic> payload, {
    Map<String, String> headers = const {},
  }) async {
    final baseUrl = _authApiBaseUrl.trim();
    if (baseUrl.isEmpty) {
      return {'success': false, 'error': 'لم يتم تكوين رابط الخادم'};
    }

    final cleanBaseUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$cleanBaseUrl$path');
    try {
      final response = await (_httpClient?.post(
                uri,
                headers: {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                  ...headers,
                },
                body: jsonEncode(payload),
              ) ??
              http.post(
                uri,
                headers: {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                  ...headers,
                },
                body: jsonEncode(payload),
              ))
          .timeout(const Duration(seconds: 75));

      Object? decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        decoded = null;
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
        return {'success': true, 'message': 'تمت العملية بنجاح'};
      }

      if (decoded is Map) {
        return {
          ...Map<String, dynamic>.from(decoded),
          'success': false,
          'status_code': response.statusCode,
          'provider': 'backend',
        };
      }
      return {
        'success': false,
        'status_code': response.statusCode,
        'provider': 'backend',
      };
    } catch (error) {
      debugPrint('Auth request $path failed: $error');
      return {
        'success': false,
        'error': 'تعذر الوصول إلى خادم التحقق',
        'error_code': 'auth_server_unreachable',
        'provider': 'backend',
      };
    }
  }

  String _backendAuthError(
    Map<String, dynamic> response, {
    required String fallback,
  }) {
    final code = response['error_code']?.toString();
    final codeMessage = switch (code) {
      'invalid_credentials' => 'بيانات الدخول غير صحيحة أو الحساب غير موجود',
      'too_many_attempts' =>
        'تجاوزت عدد محاولات الدخول. انتظر قليلًا ثم حاول مجددًا.',
      'media_auth_not_configured' ||
      'auth_not_configured' =>
        'خدمة المصادقة غير مهيأة على الخادم. يرجى التواصل مع الدعم.',
      'authentication_required' ||
      'invalid_authentication' =>
        'انتهت جلسة التحقق. سجّل الدخول مجددًا.',
      'account_not_found' => 'لا يوجد حساب مرتبط بهذا الرقم',
      'switch_sessions_unavailable' =>
        'خدمة تبديل الحسابات غير مفعّلة على الخادم حاليًا.',
      'switch_session_creation_failed' =>
        'تعذر حفظ جلسة الحساب للتبديل. أعد المحاولة بعد قليل.',
      'invalid_switch_session' =>
        'انتهت صلاحية جلسة الحساب المحفوظة. سجّل الدخول إليه مجددًا.',
      'forbidden' => AppErrorMessage.access,
      'session_sync_failed' => 'تعذر تهيئة صلاحيات الحساب. حاول مرة أخرى.',
      'auth_server_unreachable' => 'تعذر الوصول إلى خادم التحقق',
      _ => null,
    };
    if (codeMessage != null) return codeMessage;

    final error = response['error']?.toString().trim();
    if (error != null && error.isNotEmpty) return error;

    final statusCode = response['status_code'];
    if (statusCode == 404) {
      return 'خدمة المصادقة غير محدثة على الخادم. حاول لاحقًا أو تواصل مع الدعم.';
    }
    if (statusCode is num && statusCode >= 500) {
      return 'خدمة المصادقة غير متاحة مؤقتًا. حاول لاحقًا.';
    }
    return fallback;
  }

  Future<Map<String, dynamic>> _requestOtpViaBackend(
    String normalizedPhone, {
    bool forSignup = false,
    bool forPasswordReset = false,
  }) async {
    final result = await _callBackendAuthEndpoint('/auth/request-otp', {
      'phone': normalizedPhone,
      if (forSignup) 'for_signup': true,
      if (forPasswordReset) 'for_password_reset': true,
    });

    if (result['success'] == true) {
      return {
        'success': true,
        'message': result['message'] ?? 'تم إرسال رمز التحقق عبر واتساب',
        'phone': result['phone'] ?? normalizedPhone,
        'provider': 'backend',
      };
    }

    return {
      'success': false,
      'error': _backendAuthError(
        result,
        fallback: 'تعذر إرسال رمز التحقق عبر الخادم',
      ),
      if (result['error_code'] != null) 'error_code': result['error_code'],
      'provider': 'backend',
    };
  }

  Future<Map<String, dynamic>> _verifyOtpViaBackend(
    String normalizedPhone,
    String otp,
  ) async {
    final result = await _callBackendAuthEndpoint('/auth/verify-otp', {
      'phone': normalizedPhone,
      'otp': otp,
    });

    if (result['success'] == true) {
      return {
        'success': true,
        'message': result['message'] ?? 'تم التحقق من رقم الهاتف بنجاح',
        'phone': result['phone'] ?? normalizedPhone,
        'custom_token': result['custom_token'],
        'user': result['user'] ?? {'phone': normalizedPhone},
        'provider': 'backend',
      };
    }

    return {
      'success': false,
      'error': _backendAuthError(
        result,
        fallback: 'رمز التحقق غير صحيح',
      ),
      if (result['error_code'] != null) 'error_code': result['error_code'],
      'provider': 'backend',
    };
  }

  Future<bool> _changePasswordViaBackend({
    required String newPassword,
    String? currentPassword,
  }) async {
    if (!_isFirebaseReady) {
      lastError = 'خدمة المصادقة غير متاحة حاليًا';
      return false;
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      lastError = 'سجّل الدخول أو تحقق من رقم الهاتف أولًا';
      return false;
    }

    try {
      final idToken = await firebaseUser.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        lastError = 'تعذر التحقق من جلسة الحساب';
        return false;
      }
      final response = await _callBackendAuthEndpoint(
        '/auth/password/change',
        {
          if (currentPassword != null && currentPassword.isNotEmpty)
            'current_password': currentPassword.trim(),
          'new_password': newPassword,
        },
        headers: {'Authorization': 'Bearer $idToken'},
      );
      if (response['success'] == true) return true;

      lastError = _backendAuthError(
        response,
        fallback: 'تعذر تغيير كلمة المرور، حاول مرة أخرى',
      );
      return false;
    } catch (error) {
      lastError = AppErrorMessage.from(error);
      AppErrorReporter.report(error);
      return false;
    }
  }

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    lastError = null;
    final normalizedCurrentPassword = currentPassword.trim();
    final normalizedNewPassword = newPassword.trim();
    if (normalizedCurrentPassword.isEmpty) {
      lastError = 'أدخل كلمة المرور الحالية';
      return false;
    }
    if (!AppConstants.isStrongPassword(normalizedNewPassword)) {
      lastError = 'كلمة المرور الجديدة يجب ألا تقل عن 6 أحرف';
      return false;
    }

    final changed = await _changePasswordViaBackend(
      newPassword: normalizedNewPassword,
      currentPassword: normalizedCurrentPassword,
    );
    if (!changed) return false;

    final profile = await loadSession();
    if (profile != null) {
      await saveSession(
        profile.copyWith(passwordHash: hashPassword(normalizedNewPassword)),
      );
    }
    return true;
  }

  Future<bool> _syncFirebaseSession() async {
    if (!_isFirebaseReady) {
      lastError = 'خدمة المصادقة غير متاحة حاليًا';
      return false;
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      lastError = 'سجّل الدخول إلى الحساب أولًا';
      return false;
    }

    try {
      final idToken = await firebaseUser.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        lastError = 'تعذر التحقق من جلسة الحساب';
        return false;
      }
      final response = await _callBackendAuthEndpoint(
        '/auth/sync-session',
        const {},
        headers: {'Authorization': 'Bearer $idToken'},
      );
      if (response['success'] != true) {
        lastError = _backendAuthError(
          response,
          fallback: 'تعذر تهيئة صلاحيات الحساب',
        );
        return false;
      }

      await firebaseUser.getIdToken(true);
      return true;
    } catch (error) {
      lastError = AppErrorMessage.from(error);
      AppErrorReporter.report(error);
      return false;
    }
  }

  Future<Map<String, dynamic>> requestOtp({
    required String phone,
    bool forSignup = false,
    bool forPasswordReset = false,
    bool updatePhoneOnCurrentUser = false,
  }) async {
    final normalized = normalizePhone(phone);
    if (!AppConstants.isYemenPhoneValid(normalized)) {
      return {
        'success': false,
        'error': 'يرجى إدخال رقم الهاتف اليمني الصحيح',
        'provider': 'backend',
      };
    }

    if (updatePhoneOnCurrentUser) {
      _verifiedPhoneChangePhone = null;
      _verifiedPhoneChangeAt = null;
    }
    _passwordResetVerificationPhone = null;
    _passwordResetVerificationAt = null;
    _clearOtpState();
    _verifiedSignupPhone = null;
    _verifiedSignupAt = null;

    final result = await _requestOtpViaBackend(
      normalized,
      forSignup: forSignup,
      forPasswordReset: forPasswordReset,
    );
    if (result['success'] != true) return result;

    _verificationId = _backendVerificationId;
    _verificationPhone = normalized;
    _updatePhoneOnCurrentUser = updatePhoneOnCurrentUser;
    _verificationIsSignup = forSignup;
    _verificationIsPasswordReset = forPasswordReset;
    return result;
  }

  Future<Map<String, dynamic>> verifyOtp({
    required String phone,
    required String otp,
  }) async {
    final normalized = normalizePhone(phone);
    if (!AppConstants.isYemenPhoneValid(normalized)) {
      return {
        'success': false,
        'error': 'رقم الهاتف غير صالح',
        'provider': 'backend'
      };
    }

    final cleanedOtp = _toWesternDigits(otp.trim());
    if (cleanedOtp.length != 6 || !RegExp(r'^\d{6}$').hasMatch(cleanedOtp)) {
      return {
        'success': false,
        'error': 'رمز التحقق يجب أن يتكون من 6 أرقام',
        'provider': 'backend'
      };
    }

    if (_verificationId != _backendVerificationId ||
        _verificationPhone != normalized) {
      return {
        'success': false,
        'error': 'يرجى طلب رمز تحقق لهذا الرقم أولاً',
        'provider': 'backend',
      };
    }

    final result = await _verifyOtpViaBackend(normalized, cleanedOtp);
    if (result['success'] != true) return result;

    final currentFirebaseUser =
        _isFirebaseReady ? FirebaseAuth.instance.currentUser : null;
    final shouldSignInWithOtpToken = _verificationIsPasswordReset ||
        (_verificationIsSignup && currentFirebaseUser == null);
    if (_isFirebaseReady && shouldSignInWithOtpToken) {
      final customToken = result['custom_token']?.toString().trim();
      if (customToken == null || customToken.isEmpty) {
        lastError = 'تعذر إنشاء جلسة آمنة بعد التحقق. حاول مجددًا لاحقًا.';
        return {
          'success': false,
          'error': lastError,
          'provider': 'backend',
        };
      }
      try {
        await FirebaseAuth.instance.signInWithCustomToken(customToken);
      } on FirebaseAuthException catch (error) {
        lastError = friendlyFirebaseError(error);
        return {
          'success': false,
          'error': lastError,
          'provider': 'backend',
        };
      }
    }

    if (_verificationIsSignup) {
      _verifiedSignupPhone = normalized;
      _verifiedSignupAt = DateTime.now();
    }
    if (_updatePhoneOnCurrentUser) {
      _verifiedPhoneChangePhone = normalized;
      _verifiedPhoneChangeAt = DateTime.now();
    }
    _clearOtpState();
    return result;
  }

  Future<Map<String, dynamic>> verifyPasswordResetOtp({
    required String phone,
    required String otp,
  }) async {
    final normalized = normalizePhone(phone);
    if (!_verificationIsPasswordReset || _verificationPhone != normalized) {
      return {
        'success': false,
        'error': 'يرجى طلب رمز استعادة كلمة المرور لهذا الرقم أولاً',
        'provider': 'backend',
      };
    }
    final result = await verifyOtp(phone: normalized, otp: otp);
    if (result['success'] == true) {
      _passwordResetVerificationPhone = normalized;
      _passwordResetVerificationAt = DateTime.now();
    }
    return result;
  }

  Future<bool> profileExistsForCurrentUser() async {
    if (!_isFirebaseReady) {
      return false;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return false;
      }

      final snapshot = await _readProfileForFirebaseUser(user);
      return snapshot.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<UserModel?> getCurrentProfile() async {
    if (!_isFirebaseReady) {
      return null;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return null;
      }

      final firebaseKey =
          user.phoneNumber?.replaceAll(RegExp(r'[^0-9]'), '') ?? user.uid;
      final snapshot = await _readProfileForFirebaseUser(user);
      if (snapshot.isEmpty) {
        return null;
      }

      final profileImageValue = snapshot['profile_image'] ??
          snapshot['profileImage'] ??
          snapshot['avatar'];

      final createdProfile = UserModel(
        id: snapshot['id']?.toString() ?? firebaseKey,
        fullName: snapshot['full_name']?.toString() ?? '',
        phone: snapshot['phone']?.toString() ?? user.phoneNumber ?? '',
        email: snapshot['email']?.toString() ?? user.email,
        role: snapshot['role']?.toString() ?? 'customer',
        isVerified: snapshot['is_verified'] == true,
        city: snapshot['city']?.toString(),
        address: snapshot['address']?.toString(),
        currentLocation: snapshot['current_location']?.toString(),
        passwordHash: snapshot['password_hash']?.toString(),
        profileImageData:
            UserModel.normalizeProfileImageValue(profileImageValue),
        shopCategory: snapshot['shop_category']?.toString(),
        shopName: snapshot['shop_name']?.toString(),
        shopRegion: snapshot['shop_region']?.toString() ??
            snapshot['shopRegion']?.toString(),
        shopLocation: snapshot['shop_location']?.toString(),
        shopBannerUrl: snapshot['shop_banner']?.toString() ??
            snapshot['shopBanner']?.toString(),
        vehicleType: snapshot['vehicle_type']?.toString(),
        plateNumber: snapshot['plate_number']?.toString(),
        licensePhotoPath: snapshot['license_photo']?.toString(),
        createdAt:
            DateTime.tryParse(snapshot['created_at']?.toString() ?? '') ??
                DateTime.now(),
      );
      return createdProfile;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _readProfileForFirebaseUser(User user) async {
    final firebaseKey =
        user.phoneNumber?.replaceAll(RegExp(r'[^0-9]'), '') ?? user.uid;
    final profile =
        await FirebaseDatabaseService.instance.read('profiles/$firebaseKey');
    if (profile.isNotEmpty) return profile;

    final authIndex =
        await FirebaseDatabaseService.instance.read('auth_index/${user.uid}');
    final phone = authIndex['phone']?.toString() ?? '';
    final phoneKey = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (phoneKey.isEmpty) return const {};

    return FirebaseDatabaseService.instance.read('profiles/$phoneKey');
  }

  Future<UserModel?> registerUser({
    required String fullName,
    String? email,
    required String phone,
    required String role,
    String? city,
    String? address,
    String? currentLocation,
    String? password,
    String? shopCategory,
    String? shopName,
    String? shopLocation,
    String? shopBannerUrl,
    String? vehicleType,
    String? plateNumber,
    String? licensePhotoPath,
  }) async {
    final normalized = normalizePhone(phone);
    User? authUser;
    var createdAuthUser = false;

    if (AppConstants.requirePhoneVerificationOnSignup &&
        !_isSignupPhoneVerified(normalized)) {
      lastError = 'يرجى التحقق من رقم الهاتف قبل إنشاء الحساب';
      return null;
    }
    if (_databaseService is FirebaseDatabaseService &&
        (!_isFirebaseReady || FirebaseAuth.instance.currentUser == null)) {
      lastError = 'تحقق من رقم الهاتف قبل إنشاء جلسة الحساب';
      return null;
    }

    try {
      final firebaseKey = normalized.replaceAll(RegExp(r'[^0-9]'), '');
      final safePassword = password ?? '';
      final authEmail = email?.trim().toLowerCase() ?? '';

      final existingProfile =
          await _databaseService.read('profiles/$firebaseKey');
      if (existingProfile.isNotEmpty) {
        lastError = 'رقم الهاتف مسجل مسبقاً. سجّل الدخول إلى حسابك.';
        return null;
      }

      if (safePassword.isEmpty) {
        lastError = 'كلمة المرور لا يمكن أن تكون فارغة';
        return null;
      }

      final currentUser =
          _isFirebaseReady ? FirebaseAuth.instance.currentUser : null;
      final currentPhone = currentUser?.phoneNumber;
      final currentUserMatchesPhone =
          currentPhone != null && normalizePhone(currentPhone) == normalized;
      final currentUserMatchesVerifiedSignup = currentUser != null &&
          currentUser.uid == firebaseKey &&
          _isSignupPhoneVerified(normalized);

      if (currentUserMatchesPhone || currentUserMatchesVerifiedSignup) {
        authUser = currentUser;
        if (authEmail.isNotEmpty) {
          final hasPasswordProvider = currentUser!.providerData.any(
            (provider) => provider.providerId == 'password',
          );
          if (hasPasswordProvider &&
              currentUser.email?.toLowerCase() == authEmail) {
            await currentUser.updatePassword(safePassword);
          } else {
            final emailCredential = EmailAuthProvider.credential(
              email: authEmail,
              password: safePassword,
            );
            authUser =
                (await currentUser.linkWithCredential(emailCredential)).user;
          }
        }
        await authUser?.updateDisplayName(fullName);
      } else if (authEmail.isNotEmpty) {
        authUser = (await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: authEmail,
          password: safePassword,
        ))
            .user;
        createdAuthUser = authUser != null;

        await authUser?.updateDisplayName(fullName);
      }

      if (authEmail.isNotEmpty && authUser?.email != null) {
        await authUser?.sendEmailVerification();
      }

      final firebasePayload = {
        'id': firebaseKey,
        'full_name': fullName,
        'phone': normalized,
        'email': authEmail.isEmpty ? null : authEmail,
        'auth_uid': authUser?.uid,
        'role': role,
        'city': city,
        'address': address,
        'current_location': currentLocation,
        'password_hash': hashPassword(safePassword),
        'profile_image': null,
        'shop_category': shopCategory,
        'shop_name': shopName,
        'shop_location': shopLocation,
        'shop_banner': shopBannerUrl,
        'vehicle_type': vehicleType,
        'plate_number': plateNumber,
        'license_photo': licensePhotoPath,
        'is_verified': false,
        'email_verified': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      final profileCreated = _databaseService is FirebaseDatabaseService
          ? await _databaseService.createIfAbsent(
              'profiles/$firebaseKey',
              firebasePayload,
            )
          : await _createProfileForTestableDatabase(
              firebaseKey,
              firebasePayload,
            );
      if (!profileCreated) {
        lastError = 'رقم الهاتف مسجل مسبقاً. سجّل الدخول إلى حسابك.';
        if (createdAuthUser && authUser != null) {
          try {
            await authUser.delete();
          } catch (_) {
            // The profile remains protected even if Firebase Auth cleanup fails.
          }
        }
        return null;
      }
      final saved = firebasePayload;
      if (_databaseService is FirebaseDatabaseService) {
        if (authUser == null || !await _syncFirebaseSession()) {
          lastError ??= 'تعذر تهيئة صلاحيات الحساب';
          return null;
        }
      } else if (createdAuthUser && authUser != null) {
        await _databaseService.write(
          'auth_index/${authUser.uid}',
          {'phone': normalized, 'email': authEmail},
        );
      }

      final createdProfile = UserModel(
        id: saved['id']?.toString() ?? firebaseKey,
        fullName: saved['full_name']?.toString() ?? fullName,
        phone: saved['phone']?.toString() ?? normalized,
        email: saved['email']?.toString() ?? authEmail,
        role: saved['role']?.toString() ?? role,
        isVerified: saved['is_verified'] == true,
        city: saved['city']?.toString() ?? city,
        address: saved['address']?.toString() ?? address,
        currentLocation:
            saved['current_location']?.toString() ?? currentLocation,
        passwordHash: saved['password_hash']?.toString(),
        profileImageData: saved['profile_image']?.toString(),
        shopCategory: saved['shop_category']?.toString() ?? shopCategory,
        shopName: saved['shop_name']?.toString() ?? shopName,
        shopLocation: saved['shop_location']?.toString() ?? shopLocation,
        shopBannerUrl: saved['shop_banner']?.toString() ?? shopBannerUrl,
        vehicleType: saved['vehicle_type']?.toString() ?? vehicleType,
        plateNumber: saved['plate_number']?.toString() ?? plateNumber,
        licensePhotoPath:
            saved['license_photo']?.toString() ?? licensePhotoPath,
        createdAt: DateTime.tryParse(saved['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );
      _verifiedSignupPhone = null;
      _verifiedSignupAt = null;
      if (authUser == null) {
        await _signInPhoneUserForMedia(normalized, safePassword);
      }
      return createdProfile;
    } catch (error) {
      lastError = error.toString();
      if (authUser != null) {
        try {
          await authUser.delete();
        } catch (_) {
          // Ignore cleanup errors in case Firebase Auth is unavailable.
        }
      }
      return null;
    }
  }

  Future<bool> _createProfileForTestableDatabase(
    String firebaseKey,
    Map<String, dynamic> profile,
  ) async {
    final path = 'profiles/$firebaseKey';
    if ((await _databaseService.read(path)).isNotEmpty) return false;
    await _databaseService.write(path, profile);
    return true;
  }
}
