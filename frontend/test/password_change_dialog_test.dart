import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/presentation/common/password_change_dialog.dart';

class _PasswordChangeAuthService extends AuthService {
  String? currentPassword;
  String? newPassword;

  @override
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    this.currentPassword = currentPassword;
    this.newPassword = newPassword;
    return true;
  }
}

void main() {
  test('password change requires a current password and six new characters',
      () async {
    final authService = AuthService();

    expect(
      await authService.changePassword(
        currentPassword: '',
        newPassword: 'new-pass',
      ),
      isFalse,
    );
    expect(authService.lastError, 'أدخل كلمة المرور الحالية');

    expect(
      await authService.changePassword(
        currentPassword: 'old-pass',
        newPassword: 'short',
      ),
      isFalse,
    );
    expect(
      authService.lastError,
      'كلمة المرور الجديدة يجب ألا تقل عن 6 أحرف',
    );
  });

  testWidgets('password change submits current and confirmed new passwords',
      (tester) async {
    final authService = _PasswordChangeAuthService();
    var changed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                changed = await showPasswordChangeDialog(
                  context,
                  authService: authService,
                );
              },
              child: const Text('Open password dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open password dialog'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('password-change-current')),
      'old-pass',
    );
    await tester.enterText(
      find.byKey(const ValueKey('password-change-new')),
      'new-pass',
    );
    await tester.enterText(
      find.byKey(const ValueKey('password-change-confirm')),
      'new-pass',
    );
    await tester.tap(find.byKey(const ValueKey('password-change-submit')));
    await tester.pumpAndSettle();

    expect(changed, isTrue);
    expect(authService.currentPassword, 'old-pass');
    expect(authService.newPassword, 'new-pass');
  });

  testWidgets('password change rejects a mismatched confirmation',
      (tester) async {
    final authService = _PasswordChangeAuthService();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showPasswordChangeDialog(
                context,
                authService: authService,
              ),
              child: const Text('Open password dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open password dialog'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('password-change-current')),
      'old-pass',
    );
    await tester.enterText(
      find.byKey(const ValueKey('password-change-new')),
      'new-pass',
    );
    await tester.enterText(
      find.byKey(const ValueKey('password-change-confirm')),
      'different',
    );
    await tester.tap(find.byKey(const ValueKey('password-change-submit')));
    await tester.pumpAndSettle();

    expect(find.text('تأكيد كلمة المرور غير متطابق'), findsOneWidget);
    expect(authService.newPassword, isNull);
  });
}
