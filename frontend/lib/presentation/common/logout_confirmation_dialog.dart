import 'package:flutter/material.dart';

Future<bool> showLogoutConfirmationDialog(
  BuildContext context, {
  String message = 'هل تريد تسجيل الخروج من حسابك؟',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('تسجيل الخروج'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('تسجيل الخروج'),
        ),
      ],
    ),
  );
  return confirmed == true;
}
