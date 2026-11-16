import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/data/services/merchant_wallet_service.dart';

void main() {
  test(
      'merchant wallet uses stored base prices without double deducting commission',
      () async {
    final service = MerchantWalletService(
      database: _WalletDatabase({
        'orders': {
          'order-1': {
            'status': 'new',
            'commission': 20,
            'commission_included_in_subtotal': true,
            'items': [
              {
                'product_id': 'p1',
                'merchant_id': 'm1',
                'quantity': 1,
                'unit_price': 220,
                'base_unit_price': 200,
                'total_yer': 220,
                'base_unit_price_yer': 200,
                'vat_amount': 0,
                'total': 220,
              },
            ],
          },
        },
        'merchant_withdrawals': {'m1': <String, dynamic>{}},
        'products': {
          'p1': {'id': 'p1', 'merchant_id': 'm1'},
        },
      }),
    );

    final wallet = await service.load('m1');

    expect(wallet.pendingSales, 200);
    expect(wallet.totalSales, 200);
    expect(wallet.pendingOrders, 1);
  });

  test('wallet excludes cancelled and unpaid orders', () async {
    final service = MerchantWalletService(
      database: _WalletDatabase({
        'orders': {
          'delivered': {
            'status': 'delivered',
            'created_at': DateTime.now()
                .toUtc()
                .subtract(const Duration(days: 4))
                .toIso8601String(),
            'items': [
              {
                'product_id': 'p1',
                'merchant_id': 'm1',
                'quantity': 1,
                'base_unit_price_yer': 100,
                'total_yer': 120,
              },
            ],
          },
          'cancelled': {
            'status': 'cancelled',
            'items': [
              {
                'product_id': 'p1',
                'merchant_id': 'm1',
                'base_unit_price_yer': 500,
                'total_yer': 550,
              },
            ],
          },
          'unpaid': {
            'status': 'pending_payment',
            'items': [
              {
                'product_id': 'p1',
                'merchant_id': 'm1',
                'base_unit_price_yer': 300,
                'total_yer': 330,
              },
            ],
          },
        },
        'merchant_withdrawals': {'m1': <String, dynamic>{}},
        'products': {
          'p1': {'id': 'p1', 'merchant_id': 'm1'},
        },
      }),
    );

    final wallet = await service.load('m1');

    expect(wallet.totalSales, 100);
    expect(wallet.availableBalance, 100);
    expect(wallet.pendingSales, 0);
    expect(wallet.pendingOrders, 0);
  });

  test('legacy commission is deducted only when included in item prices',
      () async {
    final service = MerchantWalletService(
      database: _WalletDatabase({
        'orders': {
          'included': {
            'status': 'confirmed',
            'commission': 20,
            'commission_included_in_subtotal': true,
            'items': [
              {
                'product_id': 'p1',
                'merchant_id': 'm1',
                'quantity': 1,
                'total_yer': 120,
              },
            ],
          },
          'separate': {
            'status': 'confirmed',
            'commission': 20,
            'commission_included_in_subtotal': false,
            'items': [
              {
                'product_id': 'p1',
                'merchant_id': 'm1',
                'quantity': 1,
                'total_yer': 100,
              },
            ],
          },
        },
        'merchant_withdrawals': {'m1': <String, dynamic>{}},
        'products': {
          'p1': {'id': 'p1', 'merchant_id': 'm1'},
        },
      }),
    );

    final wallet = await service.load('m1');

    expect(wallet.pendingSales, 200);
    expect(wallet.totalSales, 200);
  });

  test('wallet load errors propagate instead of appearing as zero balance',
      () async {
    final service = MerchantWalletService(
      database: _WalletDatabase(
        {'orders': {}, 'merchant_withdrawals': {}, 'products': {}},
        failReads: true,
      ),
    );

    await expectLater(service.load('m1'), throwsStateError);
  });

  test(
      'wallet reports orders that cannot be converted to the accounting currency',
      () async {
    final service = MerchantWalletService(
      database: _WalletDatabase({
        'orders': {
          'unconverted': {
            'status': 'confirmed',
            'items': [
              {
                'product_id': 'p1',
                'merchant_id': 'm1',
                'quantity': 1,
                'currency_code': 'USD',
                'total': 100,
              },
            ],
          },
        },
        'merchant_withdrawals': {'m1': <String, dynamic>{}},
        'products': {
          'p1': {'id': 'p1', 'merchant_id': 'm1'},
        },
      }),
    );

    final wallet = await service.load('m1');

    expect(wallet.unconvertedOrderCount, 1);
    expect(wallet.totalSales, 0);
  });
}

class _WalletDatabase implements DatabaseService {
  _WalletDatabase(this.data, {this.failReads = false});

  final Map<String, dynamic> data;
  final bool failReads;

  @override
  Future<Map<String, dynamic>> read(String path) async {
    if (failReads) throw StateError('database unavailable');
    dynamic value = data;
    for (final part in path.split('/')) {
      if (value is! Map) return <String, dynamic>{};
      value = value[part];
    }
    if (value is! Map) return <String, dynamic>{};
    return Map<String, dynamic>.from(value);
  }

  @override
  Future<Map<String, dynamic>> write(
    String path,
    Map<String, dynamic> data,
  ) async =>
      data;

  @override
  Future<Map<String, dynamic>> update(
    String path,
    Map<String, dynamic> data,
  ) async =>
      data;

  @override
  Future<Map<String, dynamic>?> updateIf(
    String path, {
    required bool Function(Map<String, dynamic> current) condition,
    required Map<String, dynamic> updates,
  }) async =>
      updates;

  @override
  Future<void> delete(String path) async {}
}
