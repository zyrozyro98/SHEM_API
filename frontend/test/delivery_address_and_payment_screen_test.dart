import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/data/services/payment_service.dart';
import 'package:she_m_app/presentation/checkout/delivery_address_screen.dart';
import 'package:she_m_app/presentation/payment/wallet_payment_screen.dart';

void main() {
  test('delivery address formatting does not duplicate saved descriptions', () {
    const storedAddress =
        'شارع التحرير - الوصف: بجانب المدرسة - الوصف: بجانب المدرسة';
    const expectedAddress = 'شارع التحرير - الوصف: بجانب المدرسة';

    final address = deliveryAddressWithoutDescription(storedAddress);
    final description = deliveryLocationDescription(storedAddress);

    expect(address, 'شارع التحرير');
    expect(description, 'بجانب المدرسة');
    expect(formatDeliveryAddress(address, description), expectedAddress);
    expect(
      formatDeliveryAddress(expectedAddress, description),
      expectedAddress,
    );
    expect(
      formatDeliveryAddress(storedAddress, 'قرب المستشفى'),
      'شارع التحرير - الوصف: قرب المستشفى',
    );
    expect(
        deliveryLocationDescription(
            'شارع التحرير - الوصف: الموقع الحالي للجهاز'),
        '');
    expect(deliveryAddressCoordinates('15.369400, 44.191000'),
        '15.369400, 44.191000');
    expect(
      deliveryAddressCoordinates('شارع التحرير'),
      isNull,
    );
  });

  testWidgets(
      'selecting a wallet scrolls its details and receipt control into view',
      (tester) async {
    tester.view.physicalSize = const Size(390, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final paymentService = PaymentService(
      databaseService: _PaymentWalletDatabase({
        'jib': {
          'provider': 'jib',
          'name': 'صاحب الحساب',
          'account_number': '123456',
          'enabled': true,
        },
        'wallet2': {
          'provider': 'محفظة ثانية',
          'name': 'صاحب الحساب الثاني',
          'account_number': '654321',
          'enabled': true,
        },
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WalletPaymentScreen(paymentService: paymentService),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('محفظة جيب').first);
    await tester.pumpAndSettle();

    final receiptButton = tester.getRect(
      find.text('إرفاق صورة إيصال التحويل *'),
    );
    final submitButton = tester.getRect(
      find.text('إرسال الإيصال للمراجعة'),
    );

    expect(find.text('اسم صاحب الحساب: صاحب الحساب'), findsOneWidget);
    expect(receiptButton.bottom, lessThanOrEqualTo(submitButton.top));
    expect(tester.takeException(), isNull);
  });
}

class _PaymentWalletDatabase implements DatabaseService {
  _PaymentWalletDatabase(this.wallets);

  final Map<String, dynamic> wallets;

  @override
  Future<Map<String, dynamic>> read(String path) async {
    return path == 'settings/payment_wallets' ? wallets : const {};
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
      null;

  @override
  Future<void> delete(String path) async {}
}
