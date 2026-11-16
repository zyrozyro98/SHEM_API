import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OrderNumberCopyButton extends StatelessWidget {
  const OrderNumberCopyButton({
    required this.orderNumber,
    super.key,
  });

  final String orderNumber;

  Future<void> _copyOrderNumber(BuildContext context) async {
    try {
      await Clipboard.setData(ClipboardData(text: orderNumber));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم نسخ رقم الطلب')),
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to copy order number: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر نسخ رقم الطلب')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: ValueKey('copy-order-number-$orderNumber'),
      tooltip: 'نسخ رقم الطلب',
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: EdgeInsets.zero,
      onPressed: () => _copyOrderNumber(context),
      icon: const Icon(Icons.copy_rounded, size: 18),
    );
  }
}
