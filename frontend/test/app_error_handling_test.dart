import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:she_m_app/core/errors/app_error.dart';
import 'package:she_m_app/data/services/cart_service.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/data/services/storage_service.dart';
import 'package:she_m_app/presentation/common/keyboard_dismissal_handler.dart';

void main() {
  test('database network failures become a safe retry message', () async {
    final service = FirebaseDatabaseService.forTesting(
      client: MockClient((_) async => throw const SocketException('offline')),
      databaseUrl: 'https://example.test',
    );
    addTearDown(service.close);

    await expectLater(
      service.read('products'),
      throwsA(
        isA<AppException>()
            .having((error) => error.kind, 'kind', AppErrorKind.network)
            .having(
              (error) => error.message,
              'message',
              AppErrorMessage.network,
            ),
      ),
    );
  });

  test('database write errors are not returned as a successful save', () async {
    final service = FirebaseDatabaseService.forTesting(
      client: MockClient(
        (_) async => http.Response('permission denied', 403),
      ),
      databaseUrl: 'https://example.test',
    );
    addTearDown(service.close);

    await expectLater(
      service.write('orders/order-1', {'status': 'pending'}),
      throwsA(
        isA<AppException>()
            .having((error) => error.kind, 'kind', AppErrorKind.access)
            .having((error) => error.statusCode, 'statusCode', 403)
            .having(
              (error) => error.toString().contains('permission denied'),
              'does not expose server response',
              isFalse,
            ),
      ),
    );
  });

  test('database requests authenticate with Firebase ID tokens', () async {
    final requests = <http.Request>[];
    final service = FirebaseDatabaseService.forTesting(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('{}', 200);
      }),
      databaseUrl: 'https://example.test',
      idTokenProvider: () async => 'test-id-token',
    );
    addTearDown(service.close);

    await service.readWithQuery(
      'profiles/967771234567',
      query: {'orderBy': '"\$key"'},
    );

    expect(requests, hasLength(1));
    expect(
      requests.single.url.queryParameters['auth'],
      'test-id-token',
    );
    expect(
      requests.single.url.queryParameters['orderBy'],
      '"\$key"',
    );
    expect(requests.single.headers.containsKey('authorization'), isFalse);
  });

  test('conditional database create does not overwrite existing data',
      () async {
    final requests = <http.Request>[];
    final service = FirebaseDatabaseService.forTesting(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('null', 412);
      }),
      databaseUrl: 'https://example.test',
    );
    addTearDown(service.close);

    final created = await service.createIfAbsent(
      'profiles/967771234567',
      {'phone': '+967771234567'},
    );

    expect(created, isFalse);
    expect(requests, hasLength(1));
    expect(requests.single.headers['if-match'], 'null_etag');
    expect(requests.single.method, 'PUT');
  });

  test('conditional database create saves a new profile', () async {
    final service = FirebaseDatabaseService.forTesting(
      client: MockClient((request) async {
        expect(request.headers['if-match'], 'null_etag');
        return http.Response('{"name":"new user"}', 200);
      }),
      databaseUrl: 'https://example.test',
    );
    addTearDown(service.close);

    expect(
      await service.createIfAbsent(
        'profiles/967771234567',
        {'name': 'new user'},
      ),
      isTrue,
    );
  });

  test('malformed successful responses do not become empty data', () async {
    final service = FirebaseDatabaseService.forTesting(
      client: MockClient((_) async => http.Response('<html>error</html>', 200)),
      databaseUrl: 'https://example.test',
    );
    addTearDown(service.close);

    await expectLater(
      service.read('products'),
      throwsA(
        isA<AppException>().having(
          (error) => error.kind,
          'kind',
          AppErrorKind.invalidData,
        ),
      ),
    );
  });

  test('unconfigured payment proof storage does not return a fake URL',
      () async {
    await expectLater(
      StorageService().uploadPaymentProof(
        file: File('receipt.png'),
        orderId: 'order-1',
      ),
      throwsA(isA<AppException>()),
    );
  });

  testWidgets('application errors appear as a safe global message',
      (tester) async {
    AppErrorReporter.takePendingNotice();
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: AppErrorReporter.scaffoldMessengerKey,
        builder: (context, child) => AppErrorListener(
          child: child ?? const SizedBox.shrink(),
        ),
        home: const Scaffold(body: Text('صفحة التطبيق')),
      ),
    );
    expect(AppErrorReporter.scaffoldMessengerKey.currentState, isNotNull);
    AppErrorReporter.report(
      const AppException(
        'تعذر حفظ العملية.',
        kind: AppErrorKind.server,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('تعذر حفظ العملية.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('transient network errors do not show global alerts',
      (tester) async {
    AppErrorReporter.takePendingNotice();
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: AppErrorReporter.scaffoldMessengerKey,
        builder: (context, child) => AppErrorListener(
          child: child ?? const SizedBox.shrink(),
        ),
        home: const Scaffold(body: Text('صفحة التطبيق')),
      ),
    );

    AppErrorReporter.report(
      const AppException(
        AppErrorMessage.network,
        kind: AppErrorKind.network,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text(AppErrorMessage.network), findsNothing);
    expect(AppErrorReporter.takePendingNotice(), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signed-out access errors do not show a global alert',
      (tester) async {
    AppErrorReporter.takePendingNotice();
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: AppErrorReporter.scaffoldMessengerKey,
        builder: (context, child) => AppErrorListener(
          child: child ?? const SizedBox.shrink(),
        ),
        home: const Scaffold(body: Text('صفحة التطبيق')),
      ),
    );

    AppErrorReporter.report(
      const AppException(
        AppErrorMessage.access,
        kind: AppErrorKind.access,
        statusCode: 403,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text(AppErrorMessage.access), findsNothing);
    expect(AppErrorReporter.takePendingNotice(), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping another text field transfers focus without dismissing',
      (tester) async {
    final firstFocus = FocusNode();
    final secondFocus = FocusNode();
    addTearDown(firstFocus.dispose);
    addTearDown(secondFocus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => KeyboardDismissalHandler(
          child: child ?? const SizedBox.shrink(),
        ),
        home: Scaffold(
          body: Column(
            children: [
              TextField(focusNode: firstFocus),
              TextField(focusNode: secondFocus),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    expect(firstFocus.hasFocus, isTrue);

    await tester.tap(find.byType(TextField).last);
    await tester.pump();
    expect(secondFocus.hasFocus, isTrue);
    expect(firstFocus.hasFocus, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard type switch does not unfocus the next field',
      (tester) async {
    final phoneFocus = FocusNode();
    final passwordFocus = FocusNode();
    addTearDown(phoneFocus.dispose);
    addTearDown(passwordFocus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => KeyboardDismissalHandler(
          child: child ?? const SizedBox.shrink(),
        ),
        home: Scaffold(
          body: Column(
            children: [
              TextField(
                focusNode: phoneFocus,
                keyboardType: TextInputType.phone,
              ),
              TextField(
                focusNode: passwordFocus,
                keyboardType: TextInputType.text,
              ),
            ],
          ),
        ),
      ),
    );

    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pump();
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    expect(phoneFocus.hasFocus, isTrue);

    await tester.tap(find.byType(TextField).last);
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(passwordFocus.hasFocus, isTrue);
    expect(phoneFocus.hasFocus, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('text selection toolbar actions preserve field focus',
      (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => KeyboardDismissalHandler(
          child: child ?? const SizedBox.shrink(),
        ),
        home: Scaffold(
          body: Stack(
            children: [
              TextField(focusNode: focusNode),
              TextSelectionToolbar(
                anchorAbove: const Offset(200, 100),
                anchorBelow: const Offset(200, 140),
                children: [
                  TextSelectionToolbarTextButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {},
                    child: const Text('Copy'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping outside text fields dismisses focus', (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => KeyboardDismissalHandler(
          child: child ?? const SizedBox.shrink(),
        ),
        home: Scaffold(
          body: Column(
            children: [
              TextField(focusNode: focusNode),
              const SizedBox(height: 80, child: Text('Outside')),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.tap(find.text('Outside'));
    await tester.pump();
    expect(focusNode.hasFocus, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cart storage failures are reported without crashing',
      (tester) async {
    const channel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'storage-unavailable'),
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    AppErrorReporter.takePendingNotice();
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: AppErrorReporter.scaffoldMessengerKey,
        builder: (context, child) => AppErrorListener(
          child: child ?? const SizedBox.shrink(),
        ),
        home: const Scaffold(body: Text('صفحة التطبيق')),
      ),
    );

    CartService.instance.clear();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(CartService.instance.persistenceError, AppErrorMessage.storage);
    expect(tester.takeException(), isNull);
  });
}
