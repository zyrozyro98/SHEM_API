import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/services/notification_service.dart';
import 'package:she_m_app/presentation/common/notification_bell.dart';

void main() {
  final notification = CustomerNotification(
    id: 'notice-1',
    title: 'طلب جديد',
    body: 'لديك طلب جديد من أحد العملاء',
    type: 'new_order',
    recipientRole: 'merchant',
    orderId: 'order-1',
    status: '',
    isRead: false,
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  testWidgets('notification toast shows its content and handles tap',
      (tester) async {
    var tapped = false;
    var dismissed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MerchantNotificationToast(
            notification: notification,
            onTap: () => tapped = true,
            onDismissed: () => dismissed = true,
          ),
        ),
      ),
    );

    expect(find.text('طلب جديد'), findsOneWidget);
    expect(find.text('لديك طلب جديد من أحد العملاء'), findsOneWidget);
    await tester.tap(find.text('طلب جديد'));
    expect(tapped, isTrue);
    expect(dismissed, isFalse);
  });

  testWidgets('notification toast can be swiped away in either direction',
      (tester) async {
    var dismissed = 0;

    await _pumpDismissibleToast(tester, () => dismissed++);

    await tester.drag(find.byType(Dismissible), const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(dismissed, 1);
  });

  testWidgets('notification toast can be swiped away in the opposite direction',
      (tester) async {
    var dismissed = false;
    await _pumpDismissibleToast(tester, () => dismissed = true);

    await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(dismissed, isTrue);
  });
}

Future<void> _pumpDismissibleToast(
  WidgetTester tester,
  VoidCallback onDismissed,
) async {
  var visible = true;
  await tester.pumpWidget(
    MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: visible
              ? MerchantNotificationToast(
                  notification: CustomerNotification(
                    id: 'notice-1',
                    title: 'طلب جديد',
                    body: 'لديك طلب جديد من أحد العملاء',
                    type: 'new_order',
                    recipientRole: 'merchant',
                    orderId: 'order-1',
                    status: '',
                    isRead: false,
                    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
                  ),
                  onTap: () {},
                  onDismissed: () {
                    onDismissed();
                    setState(() => visible = false);
                  },
                )
              : const SizedBox.shrink(),
        ),
      ),
    ),
  );
}
