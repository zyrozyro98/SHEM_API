import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/models/order_model.dart';
import 'package:she_m_app/data/models/order_number.dart';

void main() {
  test('formats new and legacy order ids consistently', () {
    expect(OrderNumber.fromId('order-1761150000123'), '1761150000123');
    expect(OrderNumber.fromId('#1042'), '1042');
    expect(OrderNumber.fromId('legacy-order'), 'LEGACY-ORDER');
    expect(OrderNumber.fromId(null), 'غير متاح');
  });

  test('prefers the persisted display number for order records', () {
    expect(
      OrderNumber.fromOrder({
        'id': 'order-1761150000123',
        'order_number': '1761150000123',
      }),
      '1761150000123',
    );
    expect(
      OrderNumber.fromOrder({'order_id': 'order-1761150000123'}),
      '1761150000123',
    );
  });

  test('order model keeps internal id separate from display number', () {
    final order = OrderModel.fromJson({
      'id': 'order-1761150000123',
      'order_number': '1761150000123',
      'customer_id': 'customer-1',
      'items': <dynamic>[],
      'status': 'pending_payment',
      'payment_method': 'cash_on_delivery',
      'subtotal': 100,
      'shipping_fee': 10,
      'total': 110,
      'pickup_otp': '123456',
      'created_at': '2026-10-22T20:00:00.000Z',
    });

    expect(order.id, 'order-1761150000123');
    expect(order.displayOrderNumber, '1761150000123');
    expect(order.toJson()['id'], 'order-1761150000123');
    expect(order.toJson()['order_number'], '1761150000123');
    expect(order.toJson()['pickup_otp'], '123456');
  });
}
