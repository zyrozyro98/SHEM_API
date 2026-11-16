import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:she_m_app/main.dart';
import 'package:she_m_app/presentation/auth/login_screen.dart';
import 'package:she_m_app/presentation/auth/phone_login_screen.dart';
import 'package:she_m_app/presentation/auth/profile_setup_screen.dart';
import 'package:she_m_app/presentation/common/app_version_list_tile.dart';
import 'package:she_m_app/presentation/dashboard/customer_dashboard_screen.dart';

void main() {
  test('app defaults to customer browsing', () {
    expect(const SheMApp().initialScreen, isA<CustomerDashboardScreen>());
  });

  testWidgets('create account button opens signup', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PhoneLoginScreen()),
    );

    final createAccountButton = find.text('إنشاء حساب جديد');
    await tester.ensureVisible(createAccountButton);
    await tester.tap(createAccountButton);
    await tester.pumpAndSettle();

    expect(find.byType(ProfileSetupScreen), findsOneWidget);
  });

  testWidgets('login caret moves to end only when its field regains focus',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PhoneLoginScreen()),
    );
    await tester.pumpAndSettle();

    final phoneField = find.byType(TextFormField).first;
    final passwordField = find.byType(TextFormField).last;
    await tester.ensureVisible(phoneField);
    await tester.enterText(phoneField, '700000123');
    await tester.pump();

    final phoneController =
        tester.widget<TextFormField>(phoneField).controller!;
    expect(
      phoneController.selection,
      const TextSelection.collapsed(offset: 9),
    );

    phoneController.selection = const TextSelection.collapsed(offset: 3);
    final editableFinder = find.descendant(
      of: phoneField,
      matching: find.byType(EditableText),
    );
    final renderEditable =
        tester.state<EditableTextState>(editableFinder).renderEditable;
    final cursorPoint = renderEditable.localToGlobal(
      renderEditable.getLocalRectForCaret(const TextPosition(offset: 3)).center,
    );
    await tester.tapAt(cursorPoint);
    await tester.pump();
    expect(
      phoneController.selection,
      const TextSelection.collapsed(offset: 3),
    );

    await tester.ensureVisible(passwordField);
    await tester.tap(passwordField);
    await tester.pump();
    await tester.tap(phoneField);
    await tester.pump();

    expect(
      phoneController.selection,
      const TextSelection.collapsed(offset: 9),
    );
  });

  testWidgets('login screen shows the installed app version at the top left',
      (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'She M',
      packageName: 'com.shem',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
      installerStore: null,
    );

    await tester.pumpWidget(
      const MaterialApp(home: LoginScreen()),
    );
    await tester.pumpAndSettle();

    final versionLabel = find.text('الإصدار 1.0.0');
    expect(versionLabel, findsOneWidget);
    expect(
      tester.getCenter(versionLabel).dx,
      lessThan(tester.getCenter(find.text('تسجيل الدخول')).dx),
    );
  });

  testWidgets('sidebar version tile shows the installed app version',
      (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'She M',
      packageName: 'com.shem',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
      installerStore: null,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppVersionListTile(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('إصدار التطبيق'), findsOneWidget);
    expect(find.text('الإصدار 1.0.0'), findsOneWidget);
  });
}
