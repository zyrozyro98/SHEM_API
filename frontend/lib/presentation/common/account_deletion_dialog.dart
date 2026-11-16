import 'package:flutter/material.dart';

Future<String?> showAccountDeletionDialog(
  BuildContext context, {
  required String accountName,
  required String accountDescription,
}) async {
  final passwordController = TextEditingController();
  final password = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('حذف الحساب نهائياً'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('سيتم حذف $accountDescription «$accountName».'),
          const SizedBox(height: 10),
          const Text('أدخل كلمة مرورك لتأكيد العملية.'),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('account_deletion_password'),
            controller: passwordController,
            obscureText: true,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                Navigator.pop(dialogContext, value.trim());
              }
            },
            decoration: const InputDecoration(
              labelText: 'كلمة المرور',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: () {
            final value = passwordController.text.trim();
            if (value.isNotEmpty) Navigator.pop(dialogContext, value);
          },
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFB91C1C),
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.delete_forever_rounded),
          label: const Text('حذف نهائي'),
        ),
      ],
    ),
  );
  passwordController.dispose();
  return password;
}
