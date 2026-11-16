import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/services/admin_service.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/data/services/merchant_wallet_service.dart';
import 'package:she_m_app/presentation/admin/admin_management_detail_screens.dart';

void main() {
  testWidgets('shows account totals and real withdrawal requests',
      (tester) async {
    final database = _BalanceDatabase(
      profiles: {
        'customer-1': {'role': 'customer'},
        'merchant-1': {'role': 'merchant'},
        'driver-1': {'role': 'driver'},
        'merchant-2': {'role': 'merchant'},
      },
      requests: {
        'withdrawal-1': {
          'id': 'withdrawal-1',
          'merchant_id': 'merchant-1',
          'amount': 125,
          'currency_symbol': 'ر.ي',
          'status': 'pending',
          'created_at': '2026-10-20T10:00:00.000Z',
        },
      },
    );

    await tester.pumpWidget(_screen(database));
    await tester.pumpAndSettle();

    expect(find.text('إجمالي الحسابات'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('حسابات التجار'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('125.00 ر.ي'), findsOneWidget);
    expect(find.text('التاجر: merchant-1 · قيد المراجعة'), findsOneWidget);
    expect(find.text('845,200 ر.ي'), findsNothing);
  });

  testWidgets('reports a failed account or withdrawal load', (tester) async {
    final database = _BalanceDatabase(failReads: true);

    await tester.pumpWidget(_screen(database));
    await tester.pumpAndSettle();

    expect(find.text('تعذر تحميل الحسابات والعمليات المالية'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
  });
}

Widget _screen(_BalanceDatabase database) {
  return MaterialApp(
    home: BalanceManagementScreen(
      adminService: AdminService(databaseService: database),
      walletService: MerchantWalletService(database: database),
    ),
  );
}

class _BalanceDatabase implements DatabaseService {
  _BalanceDatabase({
    this.profiles = const {},
    this.requests = const {},
    this.failReads = false,
  });

  final Map<String, dynamic> profiles;
  final Map<String, dynamic> requests;
  final bool failReads;

  @override
  Future<Map<String, dynamic>> read(String path) async {
    if (failReads) throw StateError('database unavailable');
    if (path == 'profiles') return profiles;
    if (path == 'merchant_withdrawal_requests') return requests;
    return {};
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
