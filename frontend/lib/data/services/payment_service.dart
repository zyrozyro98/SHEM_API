import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:she_m_app/core/constants/app_constants.dart';
import 'package:she_m_app/data/models/order_model.dart';
import 'package:she_m_app/data/models/payment_proof_model.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/data/services/notification_service.dart';

class PaymentService {
  PaymentService({DatabaseService? databaseService})
      : _databaseService = databaseService ?? FirebaseDatabaseService.instance;

  static const String _baseUrl = AppConstants.apiBaseUrl;
  static const String _jibWalletPath = 'settings/payment_wallets/jib';
  static const String _walletsPath = 'settings/payment_wallets';

  final DatabaseService _databaseService;

  Future<Map<String, dynamic>> getJibWallet() async {
    try {
      return await _databaseService.read(_jibWalletPath);
    } catch (_) {
      return const {};
    }
  }

  Future<List<Map<String, dynamic>>> getPaymentWallets() async {
    final wallets = await _databaseService.read(_walletsPath);
    return wallets.entries
        .where((entry) => entry.value is Map)
        .map((entry) => {
              ...Map<String, dynamic>.from(entry.value as Map),
              'id': entry.key,
            })
        .where((wallet) => wallet['enabled'] != false)
        .toList();
  }

  Future<bool> savePaymentWallet({
    required String id,
    required String provider,
    required String name,
    required String accountNumber,
    String? logoUrl,
  }) async {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty ||
        RegExp(r'[.#$\[\]/]').hasMatch(normalizedId) ||
        provider.trim().isEmpty ||
        name.trim().isEmpty ||
        accountNumber.trim().isEmpty) {
      return false;
    }

    try {
      final wallet = <String, dynamic>{
        'provider': provider.trim(),
        'name': name.trim(),
        'account_number': accountNumber.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'enabled': true,
      };
      if (logoUrl != null) wallet['logo_url'] = logoUrl.trim();
      await _databaseService.write('$_walletsPath/$normalizedId', wallet);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> deletePaymentWallet(String id) async {
    await _databaseService.delete('$_walletsPath/$id');
  }

  Future<bool> saveJibWallet({
    required String name,
    required String accountNumber,
  }) async {
    try {
      await _databaseService.write(_jibWalletPath, {
        'provider': 'jib',
        'name': name.trim(),
        'account_number': accountNumber.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'enabled': true,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> submitPaymentProof({
    required String orderId,
    required File file,
    String? note,
  }) async {
    final uri = Uri.parse('$_baseUrl${AppConstants.paymentsEndpoint}/proofs');
    final req = http.MultipartRequest('POST', uri);
    req.fields['order_id'] = orderId;
    if (note != null) req.fields['note'] = note;
    req.files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamed = await req.send();
    final response = await http.Response.fromStream(streamed);
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return {'error': 'Failed to decode response'};
    }
  }

  Future<Map<String, dynamic>> submitProofRecord({
    required String orderId,
    String? uploadedBy,
    String? imageData,
    String? note,
    String paymentMethod = 'jib_wallet',
    String? paymentWalletId,
    String? paymentWalletName,
  }) async {
    if (uploadedBy == null ||
        uploadedBy.trim().isEmpty ||
        imageData == null ||
        imageData.trim().isEmpty) {
      return {
        'success': false,
        'error': 'يجب إرفاق صورة إيصال وتسجيل الدخول أولاً',
      };
    }

    final proofId = 'proof-${DateTime.now().millisecondsSinceEpoch}';
    final proof = PaymentProofModel(
      id: proofId,
      orderId: orderId,
      uploadedBy: uploadedBy,
      imageUrl: imageData,
      note: note ?? 'تم إرسال إثبات الدفع',
      status: 'pending',
      createdAt: DateTime.now(),
    );

    try {
      await _databaseService.write(
        'payment_proofs/$proofId',
        proof.toJson(),
      );
      final order = await _databaseService.read('orders/$orderId');
      if (order.isNotEmpty) {
        final updatedOrder = Map<String, dynamic>.from(order)
          ..['status'] = 'awaiting_confirmation'
          ..['payment_method'] = paymentMethod
          ..['payment_proof_id'] = proofId;
        if (paymentWalletId != null) {
          updatedOrder['payment_wallet_id'] = paymentWalletId;
        }
        if (paymentWalletName != null) {
          updatedOrder['payment_wallet_name'] = paymentWalletName;
        }
        await _databaseService.write(
          'orders/$orderId',
          updatedOrder,
        );

        final customerId =
            (order['customer_id'] ?? order['customerId'] ?? '').toString();
        if (customerId.isNotEmpty) {
          await _databaseService.write(
            'customers/$customerId/orders/$orderId',
            sanitizeOrderForCustomer(updatedOrder),
          );
          await NotificationService(databaseService: _databaseService)
              .notifyOrderStatus(
            customerId: customerId,
            orderId: orderId,
            status: 'awaiting_confirmation',
          );
        }
      }
      return {'success': true, 'data': proof.toJson()};
    } catch (error) {
      return {'success': false, 'error': error.toString()};
    }
  }

  Future<List<PaymentProofModel>> getPendingProofApprovals() async {
    try {
      final snapshot =
          await FirebaseDatabaseService.instance.read('payment_proofs');
      return snapshot.values
          .whereType<Map>()
          .map((value) =>
              PaymentProofModel.fromJson(Map<String, dynamic>.from(value)))
          .where((proof) => proof.status == 'pending')
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<PaymentProofModel>> getAllPaymentProofs() async {
    try {
      final snapshot =
          await FirebaseDatabaseService.instance.read('payment_proofs');
      final proofs =
          snapshot.entries.where((entry) => entry.value is Map).map((entry) {
        final data = Map<String, dynamic>.from(entry.value as Map);
        data['id'] ??= entry.key;
        return PaymentProofModel.fromJson(data);
      }).toList();
      proofs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return proofs;
    } catch (_) {
      return const [];
    }
  }

  Future<List<PaymentProofModel>> getProofsForOrder(String orderId) async {
    try {
      final snapshot =
          await FirebaseDatabaseService.instance.read('payment_proofs');
      return snapshot.values
          .whereType<Map>()
          .map((value) =>
              PaymentProofModel.fromJson(Map<String, dynamic>.from(value)))
          .where((proof) => proof.orderId == orderId)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<PaymentProofModel?> reviewProof({
    required String proofId,
    required String status,
    String? note,
  }) async {
    try {
      final proof = await _databaseService.read('payment_proofs/$proofId');
      if (proof.isEmpty) return null;

      final updatedProof = Map<String, dynamic>.from(proof)
        ..['status'] = status
        ..['review_note'] = note
        ..['reviewed_at'] = DateTime.now().toUtc().toIso8601String();
      await _databaseService.write('payment_proofs/$proofId', updatedProof);

      final orderId = proof['order_id']?.toString() ?? '';
      if (orderId.isNotEmpty) {
        final order = await _databaseService.read('orders/$orderId');
        if (order.isNotEmpty) {
          final updatedOrder = Map<String, dynamic>.from(order)
            ..['status'] = status == 'approved' ? 'new' : 'cancelled';
          if (status != 'approved') {
            updatedOrder['cancelled_by'] = 'admin';
            updatedOrder['cancellation_reason'] =
                'تم رفض إثبات الدفع من المسؤول';
            updatedOrder['cancelled_at'] =
                DateTime.now().toUtc().toIso8601String();
          }
          await _databaseService.write('orders/$orderId', updatedOrder);
          final customerId =
              (order['customer_id'] ?? order['customerId'] ?? '').toString();
          if (customerId.isNotEmpty) {
            await _databaseService.write(
              'customers/$customerId/orders/$orderId',
              sanitizeOrderForCustomer(updatedOrder),
            );
            await NotificationService(databaseService: _databaseService)
                .notifyOrderStatus(
              customerId: customerId,
              orderId: orderId,
              status: status == 'approved' ? 'new' : 'cancelled',
              cancellationReason:
                  status == 'approved' ? null : 'تم رفض إثبات الدفع من المسؤول',
            );
          }
        }
      }
      return PaymentProofModel.fromJson(updatedProof);
    } catch (_) {
      return null;
    }
  }

  Future<List<PaymentProofModel>> getPaymentProofsForOrder(
      String orderId) async {
    final response = await http.get(
      Uri.parse(
          '$_baseUrl${AppConstants.paymentsEndpoint}/proofs?order_id=$orderId'),
    );

    if (response.statusCode != 200) return const [];

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return const [];
    }

    if (decoded['items'] is! List) {
      return const [];
    }

    return (decoded['items'] as List)
        .map((e) => PaymentProofModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PaymentProofModel?> updateProofStatus({
    required String proofId,
    required String status,
  }) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl${AppConstants.paymentsEndpoint}/proofs/$proofId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'status': status}),
    );

    if (response.statusCode != 200) return null;

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;
    return PaymentProofModel.fromJson(decoded);
  }
}
