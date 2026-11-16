import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:she_m_app/core/constants/app_constants.dart';
import 'package:she_m_app/data/models/user_model.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';

void main() {
  test('password accepts any character mix with a six-character minimum', () {
    expect(AppConstants.isStrongPassword('123456'), isTrue);
    expect(AppConstants.isStrongPassword('abcdef'), isTrue);
    expect(AppConstants.isStrongPassword('!@#\$%^'), isTrue);
    expect(AppConstants.isStrongPassword('A1!xyz'), isTrue);
    expect(AppConstants.isStrongPassword('12345'), isFalse);
    expect(AppConstants.isStrongPassword('     '), isFalse);
  });

  test('password reset requires a verified WhatsApp OTP before saving',
      () async {
    final database = _PasswordResetDatabase({
      'id': '967771234567',
      'phone': '+967771234567',
      'password_hash': 'old-hash',
    });
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/auth/request-otp') {
        return http.Response(
          jsonEncode({'success': true, 'message': 'OTP sent'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/auth/verify-otp') {
        return http.Response(
          jsonEncode({'success': true, 'phone': '+967771234567'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('', 404);
    });
    final authService = AuthService(
      databaseService: database,
      httpClient: client,
      authApiBaseUrl: 'https://test.example',
    );

    final requestResult = await authService.requestPasswordResetOtp(
      phone: '0771234567',
    );
    final resetBeforeVerification = await authService.resetPasswordWithOtp(
      phone: '0771234567',
      newPassword: 'NewPass123',
    );
    expect(resetBeforeVerification['success'], isFalse);
    expect(database.profile['password_hash'], 'old-hash');

    final verificationResult = await authService.verifyPasswordResetOtp(
      phone: '0771234567',
      otp: '123456',
    );
    final resetResult = await authService.resetPasswordWithOtp(
      phone: '0771234567',
      newPassword: 'NewPass123',
    );

    expect(requestResult['success'], isTrue);
    expect(requestResult['provider'], 'backend');
    expect(jsonDecode(requests.first.body)['for_password_reset'], isTrue);
    expect(verificationResult['success'], isTrue);
    expect(resetResult['success'], isTrue);
    expect(requests.map((request) => request.url.path), [
      '/auth/request-otp',
      '/auth/verify-otp',
    ]);
    expect(jsonDecode(requests.last.body)['otp'], '123456');
    expect(
      database.profile['password_hash'],
      authService.hashPassword('NewPass123'),
    );

    client.close();
  });

  test('phone change accepts a verified WhatsApp OTP', () async {
    final database = _PasswordResetDatabase({
      'id': '967771234567',
      'phone': '+967771234567',
      'full_name': 'Test user',
      'role': 'customer',
      'is_verified': true,
    });
    final client = MockClient((request) async {
      if (request.url.path == '/auth/request-otp' ||
          request.url.path == '/auth/verify-otp') {
        return http.Response(
          jsonEncode({'success': true, 'phone': '+967771234568'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('', 404);
    });
    final authService = AuthService(
      databaseService: database,
      httpClient: client,
      authApiBaseUrl: 'https://test.example',
    );
    final profile = UserModel.fromJson(database.profile);

    final requestResult = await authService.requestOtp(
      phone: '+967771234568',
      updatePhoneOnCurrentUser: true,
    );
    final verification = await authService.verifyOtp(
      phone: '+967771234568',
      otp: '123456',
    );
    final updated = await authService.updateProfileDetails(
      profile: profile,
      email: '',
      phone: '+967771234568',
      city: 'Sanaa',
      address: 'Test address',
      profileImageData: null,
    );

    expect(requestResult['success'], isTrue);
    expect(requestResult['provider'], 'backend');
    expect(verification['success'], isTrue);
    expect(updated?.phone, '+967771234568');

    client.close();
  });

  test('OTP delivery failure does not fall back to Firebase SMS', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode({'success': false, 'error': 'WhatsApp delivery failed'}),
        502,
        headers: {'content-type': 'application/json'},
      );
    });
    final authService = AuthService(
      databaseService: _PasswordResetDatabase({}),
      httpClient: client,
      authApiBaseUrl: 'https://test.example',
    );

    final result = await authService.requestOtp(
      phone: '0771234567',
      forSignup: true,
    );

    expect(result['success'], isFalse);
    expect(result['provider'], 'backend');
    expect(requests.map((request) => request.url.path), ['/auth/request-otp']);

    client.close();
  });

  test('Google profile is not created before phone verification', () async {
    final database = _GoogleProfileDatabase();
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({'success': true, 'phone': '+967771234567'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final authService = AuthService(
      databaseService: database,
      httpClient: client,
      authApiBaseUrl: 'https://test.example',
    );
    final profile = UserModel(
      id: 'google-user-id',
      fullName: 'Google User',
      phone: '',
      email: 'user@example.com',
      role: 'customer',
      isVerified: false,
      createdAt: DateTime.now(),
    );

    final beforeVerification = await authService.completeGoogleProfile(
      profile: profile,
      phone: '+967771234567',
      city: 'Sanaa',
      address: 'Test address',
    );
    expect(beforeVerification, isNull);
    expect(database.profile, isEmpty);

    await authService.requestOtp(phone: '+967771234567', forSignup: true);
    final verification = await authService.verifyOtp(
      phone: '+967771234567',
      otp: '123456',
    );
    final completed = await authService.completeGoogleProfile(
      profile: profile,
      phone: '+967771234567',
      city: 'Sanaa',
      address: 'Test address',
    );

    expect(verification['success'], isTrue);
    expect(completed?.phone, '+967771234567');
    expect(database.profile['phone'], '+967771234567');
    expect(database.profile['auth_provider'], 'google');

    client.close();
  });

  test('Google signup rejects a phone number linked to another profile',
      () async {
    final database = _GoogleProfileDatabase();
    final authService = AuthService(
      databaseService: database,
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({'success': true, 'phone': '+967771234567'}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
      authApiBaseUrl: 'https://test.example',
    );
    final profile = UserModel(
      id: 'google-user-id',
      fullName: 'Google User',
      phone: '',
      email: 'user@example.com',
      role: 'customer',
      isVerified: false,
      createdAt: DateTime.now(),
    );
    await authService.requestOtp(phone: '+967771234567', forSignup: true);
    await authService.verifyOtp(phone: '+967771234567', otp: '123456');
    database.phoneProfile.addAll({
      'id': 'existing-user-id',
      'phone': '+967771234567',
    });

    final completed = await authService.completeGoogleProfile(
      profile: profile,
      phone: '+967771234567',
      city: 'Sanaa',
    );

    expect(completed, isNull);
    expect(authService.lastError, 'رقم الهاتف مرتبط بحساب آخر');
    expect(database.profile, isEmpty);
  });

  test('signup does not send OTP to an already registered phone', () async {
    final database = _GoogleProfileDatabase();
    var requestCount = 0;
    final authService = AuthService(
      databaseService: database,
      httpClient: MockClient((request) async {
        requestCount++;
        if (request.url.path == '/auth/request-otp') {
          expect(jsonDecode(request.body)['for_signup'], isTrue);
          return http.Response(
            jsonEncode({
              'success': false,
              'error': 'رقم الهاتف مسجل مسبقاً. سجّل الدخول إلى حسابك.',
            }),
            409,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'success': true}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      authApiBaseUrl: 'https://test.example',
    );

    final result = await authService.requestOtp(
      phone: '0771234567',
      forSignup: true,
    );
    final verification = await authService.verifyOtp(
      phone: '0771234567',
      otp: '123456',
    );

    expect(result['success'], isFalse);
    expect(result['error'], 'رقم الهاتف مسجل مسبقاً. سجّل الدخول إلى حسابك.');
    expect(verification['success'], isFalse);
    expect(requestCount, 1);
    expect(database.phoneProfile, isEmpty);
  });

  test('registration does not overwrite a profile created after OTP request',
      () async {
    final database = _GoogleProfileDatabase();
    final authService = AuthService(
      databaseService: database,
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({'success': true, 'phone': '+967771234567'}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
      authApiBaseUrl: 'https://test.example',
    );
    await authService.requestOtp(phone: '+967771234567', forSignup: true);
    await authService.verifyOtp(phone: '+967771234567', otp: '123456');
    database.phoneProfile.addAll({
      'id': 'existing-user-id',
      'phone': '+967771234567',
      'full_name': 'Existing user',
    });

    final registered = await authService.registerUser(
      fullName: 'New user',
      phone: '+967771234567',
      role: 'customer',
      password: 'StrongPass123',
    );

    expect(registered, isNull);
    expect(authService.lastError,
        'رقم الهاتف مسجل مسبقاً. سجّل الدخول إلى حسابك.');
    expect(database.phoneProfile['id'], 'existing-user-id');
    expect(database.phoneProfile['full_name'], 'Existing user');
  });
}

class _GoogleProfileDatabase implements DatabaseService {
  final Map<String, dynamic> profile = {};
  final Map<String, dynamic> phoneProfile = {};

  @override
  Future<Map<String, dynamic>> read(String path) async =>
      Map<String, dynamic>.from(
        path == 'profiles/967771234567' ? phoneProfile : profile,
      );

  @override
  Future<Map<String, dynamic>> write(
    String path,
    Map<String, dynamic> data,
  ) async {
    final destination =
        path == 'profiles/967771234567' ? phoneProfile : profile;
    destination
      ..clear()
      ..addAll(data);
    return Map<String, dynamic>.from(destination);
  }

  @override
  Future<Map<String, dynamic>> update(
    String path,
    Map<String, dynamic> data,
  ) async {
    final destination =
        path == 'profiles/967771234567' ? phoneProfile : profile;
    destination.addAll(data);
    return Map<String, dynamic>.from(destination);
  }

  @override
  Future<Map<String, dynamic>?> updateIf(
    String path, {
    required bool Function(Map<String, dynamic> current) condition,
    required Map<String, dynamic> updates,
  }) async {
    if (!condition(profile)) return null;
    profile.addAll(updates);
    return Map<String, dynamic>.from(profile);
  }

  @override
  Future<void> delete(String path) async {
    profile.clear();
  }
}

class _PasswordResetDatabase implements DatabaseService {
  _PasswordResetDatabase(Map<String, dynamic> profile)
      : profile = Map<String, dynamic>.from(profile);

  final Map<String, dynamic> profile;

  @override
  Future<Map<String, dynamic>> read(String path) async =>
      path == 'profiles/967771234567' ? Map<String, dynamic>.from(profile) : {};

  @override
  Future<Map<String, dynamic>> write(
    String path,
    Map<String, dynamic> data,
  ) async {
    profile
      ..clear()
      ..addAll(data);
    return Map<String, dynamic>.from(profile);
  }

  @override
  Future<Map<String, dynamic>> update(
    String path,
    Map<String, dynamic> data,
  ) async {
    profile.addAll(data);
    return Map<String, dynamic>.from(profile);
  }

  @override
  Future<Map<String, dynamic>?> updateIf(
    String path, {
    required bool Function(Map<String, dynamic> current) condition,
    required Map<String, dynamic> updates,
  }) async {
    if (!condition(profile)) return null;
    profile.addAll(updates);
    return Map<String, dynamic>.from(profile);
  }

  @override
  Future<void> delete(String path) async {
    profile.clear();
  }
}
