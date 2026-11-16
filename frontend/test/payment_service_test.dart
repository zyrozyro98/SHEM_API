import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/data/services/payment_service.dart';

class _FakePaymentDatabase implements DatabaseService {
  final Map<String, dynamic> data = {};

  @override
  Future<Map<String, dynamic>> read(String path) async {
    final directValue = data[path];
    if (directValue is Map) return Map<String, dynamic>.from(directValue);
    final prefix = '$path/';
    final nested = <String, dynamic>{};
    for (final entry in data.entries) {
      if (entry.key.startsWith(prefix)) {
        nested[entry.key.substring(prefix.length)] = entry.value;
      }
    }
    return nested;
  }

  @override
  Future<Map<String, dynamic>> write(
    String path,
    Map<String, dynamic> value,
  ) async {
    data[path] = value;
    return value;
  }

  @override
  Future<Map<String, dynamic>> update(
    String path,
    Map<String, dynamic> value,
  ) async {
    final current = await read(path);
    final updated = {...current, ...value};
    data[path] = updated;
    return updated;
  }

  @override
  Future<Map<String, dynamic>?> updateIf(
    String path, {
    required bool Function(Map<String, dynamic> current) condition,
    required Map<String, dynamic> updates,
  }) async {
    final current = await read(path);
    if (!condition(current)) return null;
    return update(path, updates);
  }

  @override
  Future<void> delete(String path) async {
    data.removeWhere((key, _) => key == path || key.startsWith('$path/'));
  }
}

void main() {
  test('payment wallets can be added, loaded, and removed', () async {
    final database = _FakePaymentDatabase();
    final service = PaymentService(databaseService: database);

    expect(
      await service.savePaymentWallet(
        id: 'wallet-mobile',
        provider: 'محفظة الهاتف',
        name: 'صاحب الحساب',
        accountNumber: '777000111',
        logoUrl: 'https://example.test/wallet-logo.png',
      ),
      isTrue,
    );
    expect(
      await service.savePaymentWallet(
        id: 'invalid/id',
        provider: 'محفظة غير صالحة',
        name: 'صاحب الحساب',
        accountNumber: '777000222',
      ),
      isFalse,
    );

    final wallets = await service.getPaymentWallets();
    expect(wallets, hasLength(1));
    expect(wallets.single['id'], 'wallet-mobile');
    expect(wallets.single['provider'], 'محفظة الهاتف');
    expect(wallets.single['account_number'], '777000111');
    expect(wallets.single['logo_url'], 'https://example.test/wallet-logo.png');

    await service.deletePaymentWallet('wallet-mobile');
    expect(await service.getPaymentWallets(), isEmpty);
  });

  test('payment proof stores the selected wallet on the order', () async {
    final database = _FakePaymentDatabase()
      ..data['orders/order-1'] = {
        'id': 'order-1',
        'customer_id': 'customer-1',
      };
    final service = PaymentService(databaseService: database);

    final result = await service.submitProofRecord(
      orderId: 'order-1',
      uploadedBy: 'customer-1',
      imageData: 'https://example.test/receipt.png',
      note: 'تحويل عبر المحفظة',
      paymentMethod: 'wallet',
      paymentWalletId: 'wallet-mobile',
      paymentWalletName: 'محفظة الهاتف',
    );

    expect(result['success'], isTrue);
    final savedOrder = database.data['orders/order-1'] as Map;
    expect(savedOrder['payment_method'], 'wallet');
    expect(savedOrder['payment_wallet_id'], 'wallet-mobile');
    expect(savedOrder['payment_wallet_name'], 'محفظة الهاتف');
    expect(savedOrder['status'], 'awaiting_confirmation');
  });

  test('approved payment proof leaves the order new for merchant approval',
      () async {
    final database = _FakePaymentDatabase()
      ..data['payment_proofs/proof-1'] = {
        'id': 'proof-1',
        'order_id': 'order-1',
        'status': 'pending',
      }
      ..data['orders/order-1'] = {
        'id': 'order-1',
        'customer_id': 'customer-1',
        'status': 'awaiting_confirmation',
      };
    final service = PaymentService(databaseService: database);

    final reviewed = await service.reviewProof(
      proofId: 'proof-1',
      status: 'approved',
    );

    expect(reviewed?.status, 'approved');
    expect((database.data['orders/order-1'] as Map)['status'], 'new');
    expect(
      (database.data['customers/customer-1/orders/order-1'] as Map)['status'],
      'new',
    );
  });
}
