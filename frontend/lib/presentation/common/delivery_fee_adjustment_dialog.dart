import 'package:flutter/material.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/data/services/currency_service.dart';
import 'package:she_m_app/data/services/order_service.dart';

Future<void> showDeliveryFeeAdjustmentDialog(
  BuildContext context, {
  required Map<String, dynamic> order,
  VoidCallback? onUpdated,
}) async {
  final orderId = (order['id'] ?? '').toString().trim();
  if (orderId.isEmpty) return;

  final controller = TextEditingController(
    text: (order['shipping_fee'] ?? order['shippingFee'] ?? 0).toString(),
  );
  final rawItems = order['items'];
  final firstItem = rawItems is List && rawItems.isNotEmpty && rawItems.first is Map
      ? rawItems.first as Map
      : const <String, dynamic>{};
  final currencySymbol = (order['currency_symbol'] ??
          order['currencySymbol'] ??
          firstItem['currency_symbol'] ??
          CurrencyService.yerCurrency.symbol)
      .toString();
  final updatedFee = await showDialog<double>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('تعديل أجرة توصيل الطلب $orderId'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: 'أجرة التوصيل الجديدة',
          suffixText: currencySymbol,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () {
            final value = double.tryParse(controller.text.trim());
            if (value == null || !value.isFinite || value < 0) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(
                  content: Text('أدخل أجرة توصيل صحيحة وغير سالبة'),
                ),
              );
              return;
            }
            Navigator.of(dialogContext).pop(value);
          },
          child: const Text('حفظ التعديل'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (updatedFee == null || !context.mounted) return;
  final previousFee = double.tryParse(
        (order['shipping_fee'] ?? order['shippingFee'] ?? 0).toString(),
      ) ??
      0;
  if (updatedFee == previousFee) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('لم تتغير أجرة التوصيل')),
    );
    return;
  }

  final profile = await AuthService().loadSession() ??
      await AuthService().getCurrentProfile();
  if (!context.mounted) return;
  if (profile == null ||
      !{'admin', 'central_dispatcher'}.contains(profile.role)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('غير مصرح بتعديل أجرة التوصيل')),
    );
    return;
  }

  final result = await OrderService().updateDeliveryFee(
    orderId: orderId,
    shippingFee: updatedFee,
    actorId: profile.id,
    actorRole: profile.role,
  );
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        result == null
            ? 'تعذر تعديل أجرة التوصيل، قد يكون الطلب أُغلق أو تغير بالتزامن'
            : result.notificationSent
                ? 'تم تحديث أجرة التوصيل وإبلاغ العميل'
                : 'تم تحديث أجرة التوصيل، لكن تعذر إرسال إشعار للعميل',
      ),
    ),
  );
  if (result != null) onUpdated?.call();
}
