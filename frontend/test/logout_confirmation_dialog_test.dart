import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/presentation/common/logout_confirmation_dialog.dart';

void main() {
  testWidgets('logout proceeds only after confirmation', (tester) async {
    bool? shouldSignOut;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              shouldSignOut = await showLogoutConfirmationDialog(context);
            },
            child: const Text('فتح التأكيد'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('فتح التأكيد'));
    await tester.pumpAndSettle();
    expect(find.text('هل تريد تسجيل الخروج من حسابك؟'), findsOneWidget);

    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(shouldSignOut, isFalse);
  });

  testWidgets('confirmation returns true when logout is confirmed',
      (tester) async {
    bool? shouldSignOut;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              shouldSignOut = await showLogoutConfirmationDialog(context);
            },
            child: const Text('فتح التأكيد'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('فتح التأكيد'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تسجيل الخروج').last);
    await tester.pumpAndSettle();
    expect(shouldSignOut, isTrue);
  });
}
