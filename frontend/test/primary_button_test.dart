import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/presentation/common/primary_button.dart';

void main() {
  testWidgets('ignores repeated taps while the action is running',
      (tester) async {
    final actionCompleter = Completer<void>();
    var actionCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrimaryButton(
            label: 'حفظ',
            onPressed: () {
              actionCount++;
              return actionCompleter.future;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.tap(find.text('حفظ'));
    await tester.pump();

    expect(actionCount, 1);

    actionCompleter.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
