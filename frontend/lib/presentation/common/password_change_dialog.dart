import 'package:flutter/material.dart';
import 'package:she_m_app/core/constants/app_constants.dart';
import 'package:she_m_app/core/errors/app_error.dart';
import 'package:she_m_app/data/services/auth_service.dart';

Future<bool> showPasswordChangeDialog(
  BuildContext context, {
  AuthService? authService,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (_) => _PasswordChangeDialog(
          authService: authService ?? AuthService(),
        ),
      ) ??
      false;
}

class _PasswordChangeDialog extends StatefulWidget {
  const _PasswordChangeDialog({required this.authService});

  final AuthService authService;

  @override
  State<_PasswordChangeDialog> createState() => _PasswordChangeDialogState();
}

class _PasswordChangeDialogState extends State<_PasswordChangeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isSaving = false;
  String _errorMessage = '';

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSaving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isSaving = true;
      _errorMessage = '';
    });

    try {
      final changed = await widget.authService.changePassword(
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
      );
      if (!mounted) return;
      if (changed) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isSaving = false;
          _errorMessage = widget.authService.lastError ??
              'تعذر تغيير كلمة المرور، حاول مرة أخرى';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = AppErrorMessage.from(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تغيير كلمة المرور'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey('password-change-current'),
                controller: _currentPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور الحالية',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'أدخل كلمة المرور الحالية'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('password-change-new'),
                controller: _newPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور الجديدة',
                  helperText: '6 أحرف على الأقل',
                ),
                validator: (value) => AppConstants.isStrongPassword(value ?? '')
                    ? null
                    : 'كلمة المرور يجب ألا تقل عن 6 أحرف',
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('password-change-confirm'),
                controller: _confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'تأكيد كلمة المرور الجديدة',
                ),
                validator: (value) => value != _newPasswordController.text
                    ? 'تأكيد كلمة المرور غير متطابق'
                    : null,
              ),
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const ValueKey('password-change-submit'),
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('تغيير كلمة المرور'),
        ),
      ],
    );
  }
}
