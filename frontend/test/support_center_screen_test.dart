import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/models/user_model.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/data/services/support_service.dart';
import 'package:she_m_app/presentation/support/support_center_screen.dart';

class _UnusedSupportDatabase implements DatabaseService {
  @override
  Future<Map<String, dynamic>> read(String path) async => const {};

  @override
  Future<Map<String, dynamic>> write(
    String path,
    Map<String, dynamic> data,
  ) async =>
      Map<String, dynamic>.from(data);

  @override
  Future<Map<String, dynamic>> update(
    String path,
    Map<String, dynamic> data,
  ) async =>
      Map<String, dynamic>.from(data);

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

class _StubSupportService extends SupportService {
  _StubSupportService() : super(databaseService: _UnusedSupportDatabase());

  @override
  Future<Map<String, dynamic>> getSupportContact() async => const {};

  @override
  Future<List<Map<String, dynamic>>> getRefundRequestsForCustomer(
    String customerId,
  ) async =>
      const [];
}

UserModel _profile(String role) => UserModel(
      id: '$role-1',
      fullName: 'مستخدم الاختبار',
      phone: '+967700000000',
      role: role,
      isVerified: true,
      createdAt: DateTime(2026),
    );

Widget _screenFor(String role) => MaterialApp(
      home: SupportCenterScreen(
        supportService: _StubSupportService(),
        loadProfile: () async => _profile(role),
        loadOrders: (_) async => const [],
      ),
    );

void main() {
  testWidgets('merchant help can be searched and expanded', (tester) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_screenFor('merchant'));
    await tester.pumpAndSettle();

    expect(find.textContaining('دعم مخصص لدور التاجر'), findsOneWidget);
    expect(find.byKey(const ValueKey('create_refund_request')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('support_search')),
      'مستحقاتي',
    );
    await tester.pumpAndSettle();
    expect(find.text('كيف أتابع مستحقاتي؟'), findsOneWidget);
    expect(find.text('كيف أتابع الطلبات الجديدة؟'), findsNothing);

    await tester.tap(find.text('كيف أتابع مستحقاتي؟'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('قسم المحفظة أو التقارير المالية'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('driver receives delivery guidance, not customer refunds',
      (tester) async {
    await tester.pumpWidget(_screenFor('driver'));
    await tester.pumpAndSettle();

    expect(find.textContaining('دعم مخصص لدور السائق'), findsOneWidget);
    expect(find.byKey(const ValueKey('create_refund_request')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('support_search')),
      'مهمة توصيل',
    );
    await tester.pumpAndSettle();
    expect(find.text('كيف أستلم مهمة توصيل؟'), findsOneWidget);
    expect(find.text('كيف أطلب استرداد منتج؟'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('customer retains refund request access', (tester) async {
    await tester.pumpWidget(_screenFor('customer'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('create_refund_request')), findsOneWidget);
    expect(find.textContaining('دعم مخصص لدور العميل'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
