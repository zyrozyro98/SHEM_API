import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/presentation/checkout/order_confirmation_copy.dart';

void main() {
  test('new orders are labelled as awaiting merchant approval', () {
    expect(orderConfirmationTitleForStatus('new'), 'تم استلام طلبك');
    expect(orderConfirmationStatusLabel('new'), 'طلب جديد');
    expect(
      orderConfirmationMessageForStatus('new'),
      contains('بانتظار تأكيد التاجر'),
    );
  });

  test('awaiting receipt review is not presented as an approved order', () {
    expect(
      orderConfirmationTitleForStatus('awaiting_confirmation'),
      'تم استلام طلبك وإيصال الدفع',
    );
    expect(
      orderConfirmationStatusLabel('awaiting_confirmation'),
      'بانتظار مراجعة الإيصال',
    );
    expect(
      orderConfirmationMessageForStatus('awaiting_confirmation'),
      contains('قيد المراجعة'),
    );
  });

  test('preparing status is only shown for an order that is preparing', () {
    expect(
      orderConfirmationStatusLabel('preparing'),
      'قيد التجهيز',
    );
    expect(
      orderConfirmationTitleForStatus('preparing'),
      'طلبك قيد التجهيز',
    );
  });
}
