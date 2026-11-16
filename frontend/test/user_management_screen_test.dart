import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/services/admin_service.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/presentation/admin/admin_management_detail_screens.dart';

void main() {
  testWidgets('shows all users and filters them by search text',
      (tester) async {
    final profiles = <String, dynamic>{
      for (var index = 1; index <= 7; index++)
        'user-$index': {
          'full_name': 'User $index',
          'phone': '70000000$index',
          'role': index == 7 ? 'merchant' : 'customer',
          'is_verified': false,
        },
    };
    await tester.pumpWidget(_screenApp(profiles));
    await tester.pumpAndSettle();

    expect(find.text('7'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '700000007');
    await tester.pumpAndSettle();

    expect(find.text('User 7'), findsOneWidget);
    expect(find.text('User 1'), findsNothing);
    expect(find.text('1 نتيجة'), findsOneWidget);
  });

  testWidgets('verification action persists and refreshes the user',
      (tester) async {
    final database = _UserProfilesDatabase({
      'user-1': {
        'full_name': 'Test User',
        'phone': '700000001',
        'role': 'customer',
        'is_verified': false,
      },
    });
    await tester.pumpWidget(_screenApp(database.profiles, database: database));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Test User'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('إجراءات المستخدم'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('توثيق الحساب'));
    await tester.pumpAndSettle();

    expect(database.profiles['user-1']['is_verified'], isTrue);
    await tester.ensureVisible(find.text('Test User'));
    await tester.pumpAndSettle();
    expect(find.text('موثق'), findsOneWidget);
  });

  testWidgets('tapping a user card opens details without exposing secrets',
      (tester) async {
    final profiles = <String, dynamic>{
      'customer-1': {
        'id': 'customer-1',
        'full_name': 'Test User',
        'phone': '700000001',
        'email': 'test@example.com',
        'role': 'customer',
        'is_verified': true,
        'password_hash': 'must-not-be-shown',
      },
    };
    await tester.pumpWidget(_screenApp(profiles));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Test User'));
    await tester.pumpAndSettle();

    expect(find.text('تفاصيل المستخدم'), findsOneWidget);
    expect(find.text('معرّف الحساب'), findsOneWidget);
    expect(find.text('البريد الإلكتروني'), findsOneWidget);
    expect(find.text('test@example.com'), findsOneWidget);
    expect(find.text('must-not-be-shown'), findsNothing);
  });

  testWidgets('admin can archive and restore a customer profile',
      (tester) async {
    final database = _UserProfilesDatabase({
      'customer-1': {
        'full_name': 'Customer One',
        'phone': '700000001',
        'role': 'customer',
        'is_verified': false,
      },
    });
    await tester.pumpWidget(_screenApp(database.profiles, database: database));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('إجراءات المستخدم'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('أرشفة الحساب'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'أرشفة'));
    await tester.pumpAndSettle();

    expect(database.profiles['customer-1']['is_archived'], isTrue);
    expect(find.text('Customer One'), findsNothing);

    await tester.tap(find.text('عرض الحسابات المؤرشفة'));
    await tester.pumpAndSettle();
    expect(find.text('Customer One'), findsOneWidget);
    await tester.tap(find.byTooltip('إجراءات المستخدم'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('استعادة الحساب'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'استعادة'));
    await tester.pumpAndSettle();

    expect(database.profiles['customer-1']['is_archived'], isFalse);
  });
}

Widget _screenApp(
  Map<String, dynamic> profiles, {
  _UserProfilesDatabase? database,
}) {
  return MaterialApp(
    home: UserManagementScreen(
      service: AdminService(
        databaseService: database ?? _UserProfilesDatabase(profiles),
      ),
    ),
  );
}

class _UserProfilesDatabase implements DatabaseService {
  _UserProfilesDatabase(this.profiles);

  final Map<String, dynamic> profiles;

  @override
  Future<Map<String, dynamic>> read(String path) async {
    if (path == 'profiles') return profiles;
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
  ) async {
    final profileId = path.substring('profiles/'.length);
    profiles[profileId] = {
      ...Map<String, dynamic>.from(profiles[profileId] as Map),
      ...data,
    };
    return data;
  }

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
