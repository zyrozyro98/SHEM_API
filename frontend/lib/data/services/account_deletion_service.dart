import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:she_m_app/core/constants/app_constants.dart';

class AccountDeletionException implements Exception {
  const AccountDeletionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AccountDeletionService {
  AccountDeletionService({
    http.Client? client,
    String? baseUrl,
  })  : _client = client,
        _baseUrl = baseUrl ?? AppConstants.mediaApiBaseUrl;

  final http.Client? _client;
  final String _baseUrl;

  Future<void> deleteAccount({
    required String profileId,
    required String requesterPhone,
    required String password,
  }) async {
    final normalizedId = profileId.trim();
    final normalizedPhone = requesterPhone.trim();
    if (normalizedId.isEmpty ||
        normalizedPhone.isEmpty ||
        password.trim().isEmpty) {
      throw const AccountDeletionException('بيانات تأكيد الحذف غير مكتملة.');
    }

    final baseUrl = _baseUrl.trim().replaceAll(
          RegExp(r'/+$'),
          '',
        );
    if (baseUrl.isEmpty) {
      throw const AccountDeletionException('خدمة إدارة الحسابات غير مهيأة.');
    }

    try {
      final uri =
          Uri.parse('$baseUrl/accounts/${Uri.encodeComponent(normalizedId)}');
      const headers = {'Content-Type': 'application/json'};
      final body = jsonEncode({
        'requester_phone': normalizedPhone,
        'requester_password': password,
      });
      final response = await (_client?.delete(
                uri,
                headers: headers,
                body: body,
              ) ??
              http.delete(uri, headers: headers, body: body))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode >= 200 && response.statusCode < 300) return;

      Map? decoded;
      try {
        final value = jsonDecode(response.body);
        if (value is Map) decoded = value;
      } on FormatException {
        decoded = null;
      }

      final code = decoded?['error_code']?.toString();
      if (code != null && code.isNotEmpty) {
        throw AccountDeletionException(_messageForCode(code));
      }
      throw AccountDeletionException(_messageForStatus(response.statusCode));
    } on AccountDeletionException {
      rethrow;
    } on TimeoutException {
      throw const AccountDeletionException(
        'انتهت مهلة الاتصال بخدمة حذف الحساب. حاول مرة أخرى.',
      );
    } on http.ClientException {
      throw const AccountDeletionException(
        'تعذر الوصول إلى خدمة حذف الحساب. تحقق من الاتصال وحاول مجددًا.',
      );
    } catch (_) {
      throw const AccountDeletionException(
        'تعذر الاتصال بخدمة حذف الحساب. حاول مرة أخرى.',
      );
    }
  }

  String _messageForStatus(int statusCode) => switch (statusCode) {
        404 =>
          'مسار حذف الحساب غير موجود على الخادم (404). يجب تحديث خدمة API على Render.',
        502 ||
        503 =>
          'خدمة حذف الحساب غير متاحة حاليًا. تحقق من إعدادات الخادم وحاول لاحقًا.',
        _ =>
          'تعذر حذف الحساب (HTTP $statusCode). حاول مرة أخرى أو تواصل مع الدعم.',
      };

  String _messageForCode(String? code) => switch (code) {
        'invalid_credentials' => 'كلمة المرور غير صحيحة.',
        'account_not_found' => 'الحساب المطلوب غير موجود.',
        'customer_active_orders' =>
          'لا يمكن حذف الحساب لوجود طلبات لم تُسلّم أو تُلغَ.',
        'merchant_active_orders' =>
          'لا يمكن حذف الحساب لوجود طلبات جديدة أو مقبولة لم تُسلّم أو تُرفض.',
        'admin_account_protected' => 'لا يمكن حذف حساب المدير.',
        'forbidden' => 'لا تملك صلاحية حذف هذا الحساب.',
        'too_many_attempts' =>
          'محاولات كثيرة لكلمة المرور. انتظر 15 دقيقة ثم أعد المحاولة.',
        'account_deletion_not_configured' =>
          'خدمة إدارة الحسابات غير مهيأة على الخادم.',
        _ => 'تعذر حذف الحساب. حاول مرة أخرى أو تواصل مع الدعم.',
      };
}
