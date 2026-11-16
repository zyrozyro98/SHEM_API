import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/models/user_model.dart';

void main() {
  test('merchant contact and wallet details survive profile serialization', () {
    final profile = UserModel.fromJson({
      'id': 'merchant-1',
      'full_name': 'Merchant',
      'phone': '771234567',
      'role': 'merchant',
      'is_verified': true,
      'shop_contact_phones': ['711111111', '733333333'],
      'shop_wallets': [
        {'provider': 'محفظة أ', 'account_number': '711111111'},
        {'provider': 'محفظة ب', 'account_number': '733333333'},
      ],
      'created_at': DateTime(2026).toIso8601String(),
    });

    final restored = UserModel.fromJson(profile.toJson());
    expect(restored.shopContactPhones, ['711111111', '733333333']);
    expect(restored.shopWallets, [
      {'provider': 'محفظة أ', 'account_number': '711111111'},
      {'provider': 'محفظة ب', 'account_number': '733333333'},
    ]);
  });
}
