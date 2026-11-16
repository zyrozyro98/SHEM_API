import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/data/services/payment_service.dart';
import 'package:she_m_app/presentation/admin/admin_management_detail_screens.dart';

void main() {
  testWidgets('admin can choose a logo while adding a payment wallet',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WalletManagementScreen(
          paymentService: PaymentService(
            databaseService: _WalletDatabase(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('إضافة شعار المحفظة'), findsOneWidget);
  });
}

class _WalletDatabase implements DatabaseService {
  @override
  Future<Map<String, dynamic>> read(String path) async => {};

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
