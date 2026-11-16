class OrderNumber {
  const OrderNumber._();

  static String fromOrder(Map<String, dynamic> order) {
    final savedNumber = order['order_number'] ?? order['orderNumber'];
    if (savedNumber != null && savedNumber.toString().trim().isNotEmpty) {
      return fromId(savedNumber);
    }
    return fromId(order['id'] ?? order['order_id'] ?? order['orderId']);
  }

  static String fromId(Object? value) {
    var number = value?.toString().trim() ?? '';
    if (number.isEmpty) return 'غير متاح';

    number = number.replaceFirst(RegExp(r'^#'), '');
    number = number.replaceFirst(
      RegExp(r'^order[-_]', caseSensitive: false),
      '',
    );
    return number.isEmpty ? 'غير متاح' : number.toUpperCase();
  }
}
