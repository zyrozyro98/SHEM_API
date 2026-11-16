import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:she_m_app/data/models/user_model.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/data/services/app_update_service.dart';
import 'package:she_m_app/presentation/common/app_update_gate.dart';

void main() {
  test('compares numeric version components rather than text', () {
    expect(AppUpdateNotice.compareVersions('1.10.0', '1.9.9'), greaterThan(0));
    expect(AppUpdateNotice.compareVersions('2.1', '2.1.0'), 0);
    expect(AppUpdateNotice.compareVersions('2.0.0', '2.0.1'), lessThan(0));
  });

  test('valid update targets selected roles and requires a secure URL', () {
    const notice = AppUpdateNotice(
      active: true,
      latestVersion: '1.2.0',
      title: 'تحديث جديد',
      message: 'يرجى تحديث التطبيق',
      downloadUrl: 'https://downloads.example.com/app.apk',
      targetRoles: ['customer', 'merchant'],
      importance: AppUpdateImportance.optional,
    );

    notice.validate();
    expect(notice.targetsRole('customer'), isTrue);
    expect(notice.targetsRole('admin'), isFalse);
  });

  test('rejects insecure links and unsupported roles', () {
    final insecureLink = _notice(downloadUrl: 'http://example.com/app.apk');
    final unsupportedRole = _notice(targetRoles: ['unknown']);

    expect(insecureLink.validate, throwsArgumentError);
    expect(unsupportedRole.validate, throwsArgumentError);
  });

  test('disabled settings retain values for later editing', () {
    final notice = AppUpdateNotice.fromJson({
      'active': false,
      'latest_version': '2.0.0',
      'title': 'تحديث جديد',
      'message': 'نص التنبيه',
      'download_url': 'https://downloads.example.com/app.apk',
      'target_roles': ['driver'],
      'importance': 'repeat',
    });

    expect(notice.active, isFalse);
    expect(notice.latestVersion, '2.0.0');
    expect(notice.targetRoles, ['driver']);
    expect(notice.importance, AppUpdateImportance.repeat);
  });

  test('active settings ignore invalid role entries from stored data', () {
    final notice = AppUpdateNotice.fromJson({
      'active': true,
      'latest_version': '1.0.6',
      'title': 'تحديث جديد',
      'message': 'يرجى تحديث التطبيق',
      'download_url': 'https://downloads.example.com/app.apk',
      'target_roles': ['customer', null, 'unknown'],
      'importance': 'mandatory',
    });

    expect(notice.targetRoles, ['customer']);
  });

  testWidgets('signed-out startup does not fetch private update settings',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final updateService = _PendingAppUpdateService();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('Login screen')),
        builder: (context, child) => AppUpdateGate(
          navigatorKey: navigatorKey,
          updateService: updateService,
          authService: _SessionlessAuthService(),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Login screen'), findsOneWidget);
    expect(find.text('تعذر التحقق من تحديث التطبيق'), findsNothing);
    expect(updateService.pendingChecks, isEmpty);
  });

  testWidgets('resuming keeps a pushed form mounted during update checks',
      (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'She M',
      packageName: 'com.shem',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
      installerStore: null,
    );
    final navigatorKey = GlobalKey<NavigatorState>();
    final updateService = _PendingAppUpdateService();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('Merchant dashboard')),
        builder: (context, child) => AppUpdateGate(
          navigatorKey: navigatorKey,
          updateService: updateService,
          authService: _AuthenticatedAuthService(),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(updateService.pendingChecks, hasLength(1));
    updateService.completeNextCheck();
    await tester.pumpAndSettle();

    unawaited(
      navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Product editor')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Product editor'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(updateService.pendingChecks, hasLength(1));
    expect(find.text('Product editor'), findsOneWidget);
    expect(find.text('جارٍ تجهيز التطبيق...'), findsNothing);
    updateService.completeNextCheck();
    await tester.pumpAndSettle();
    expect(find.text('Product editor'), findsOneWidget);
  });
}

class _PendingAppUpdateService extends AppUpdateService {
  final List<Completer<AppUpdateNotice>> pendingChecks = [];

  @override
  Future<AppUpdateNotice> getNotice() {
    final pendingCheck = Completer<AppUpdateNotice>();
    pendingChecks.add(pendingCheck);
    return pendingCheck.future;
  }

  void completeNextCheck() {
    pendingChecks.removeAt(0).complete(const AppUpdateNotice.disabled());
  }
}

class _SessionlessAuthService extends AuthService {
  @override
  Future<UserModel?> loadSession() async => null;
}

class _AuthenticatedAuthService extends AuthService {
  @override
  Future<UserModel?> loadSession() async => UserModel(
        id: 'test-user',
        fullName: 'Test User',
        phone: '+967770000000',
        role: 'customer',
        isVerified: true,
        createdAt: DateTime.utc(2025),
      );
}

AppUpdateNotice _notice({
  String downloadUrl = 'https://downloads.example.com/app.apk',
  List<String> targetRoles = const ['customer'],
}) {
  return AppUpdateNotice(
    active: true,
    latestVersion: '1.2.0',
    title: 'تحديث جديد',
    message: 'يرجى تحديث التطبيق',
    downloadUrl: downloadUrl,
    targetRoles: targetRoles,
    importance: AppUpdateImportance.optional,
  );
}
