import 'package:flutter/material.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/presentation/auth/phone_login_screen.dart';
import 'package:she_m_app/presentation/common/role_dashboard_router.dart';

class AccountSwitcherButton extends StatefulWidget {
  const AccountSwitcherButton({super.key, this.authService});

  final AuthService? authService;

  @override
  State<AccountSwitcherButton> createState() => _AccountSwitcherButtonState();
}

class _AccountSwitcherButtonState extends State<AccountSwitcherButton> {
  late final AuthService _authService = widget.authService ?? AuthService();

  String _roleLabel(String role) => switch (role.trim().toLowerCase()) {
        'admin' => 'مدير',
        'manager' => 'مدير',
        'merchant' => 'تاجر',
        'driver' => 'سائق',
        'central_dispatcher' => 'مسؤول توصيل',
        _ => 'عميل',
      };

  Future<void> _openAccountSwitcher() async {
    _authService.lastError = null;
    final activeProfile = await _authService.loadSession();
    List<SavedAccountSession> accounts;
    try {
      accounts = await _authService.getSavedAccountSessions();
      if (activeProfile != null &&
          accounts.every(
            (account) => account.profileId != activeProfile.id.trim(),
          )) {
        await _authService.rememberCurrentAccount(activeProfile);
        accounts = await _authService.getSavedAccountSessions();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _authService.lastError ?? 'تعذر تحميل الحسابات المحفوظة',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final height = MediaQuery.sizeOf(sheetContext).height * 0.72;
          return SizedBox(
            height: height,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'تبديل الحساب',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                Expanded(
                  child: accounts.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.switch_account_outlined,
                                  size: 42,
                                  color: Color(0xFF9A7B2F),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'لا توجد حسابات محفوظة على هذا الجهاز',
                                  textAlign: TextAlign.center,
                                ),
                                if (_authService.lastError != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    _authService.lastError!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Theme.of(sheetContext)
                                          .colorScheme
                                          .error,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: accounts.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, indent: 64),
                          itemBuilder: (context, index) {
                            final account = accounts[index];
                            final isActive =
                                account.profileId == activeProfile?.id;
                            final title =
                                account.shopName?.trim().isNotEmpty == true
                                    ? account.shopName!.trim()
                                    : account.fullName.isNotEmpty
                                        ? account.fullName
                                        : account.phone;
                            final subtitle = [
                              _roleLabel(account.role),
                              if (account.phone.isNotEmpty) account.phone,
                              if (isActive) 'الحساب الحالي',
                            ].join(' • ');

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: account.profileImageUrl == null
                                    ? null
                                    : NetworkImage(account.profileImageUrl!),
                                child: account.profileImageUrl == null
                                    ? const Icon(Icons.person_rounded)
                                    : null,
                              ),
                              title: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isActive)
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: Color(0xFF16A34A),
                                    ),
                                  IconButton(
                                    tooltip: 'إزالة الحساب المحفوظ',
                                    onPressed: () => _removeAccount(
                                      sheetContext,
                                      account.sessionId,
                                      accounts,
                                      setSheetState,
                                    ),
                                    icon: const Icon(
                                      Icons.remove_circle_outline_rounded,
                                      color: Color(0xFF6B7280),
                                    ),
                                  ),
                                ],
                              ),
                              onTap: isActive
                                  ? null
                                  : () => _switchAccount(
                                        sheetContext,
                                        account.sessionId,
                                      ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const PhoneLoginScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text('إضافة حساب'),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _switchAccount(
    BuildContext sheetContext,
    String sessionId,
  ) async {
    Navigator.of(sheetContext).pop();
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final profile = await _authService.switchToSavedAccount(sessionId);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _authService.lastError ?? 'تعذر التبديل إلى الحساب المحفوظ',
          ),
        ),
      );
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => dashboardForRole(profile.role),
      ),
      (_) => false,
    );
  }

  Future<void> _removeAccount(
    BuildContext sheetContext,
    String sessionId,
    List<SavedAccountSession> accounts,
    StateSetter setSheetState,
  ) async {
    final confirmed = await showDialog<bool>(
      context: sheetContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إزالة الحساب المحفوظ'),
        content: const Text(
          'ستتم إزالة الجلسة الآمنة لهذا الحساب من هذا الجهاز. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('إزالة'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final removed = await _authService.removeSavedAccountSession(sessionId);
    if (!mounted) return;
    if (!removed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _authService.lastError ?? 'تعذر إزالة الحساب المحفوظ',
          ),
        ),
      );
      return;
    }
    setSheetState(() {
      accounts.removeWhere((account) => account.sessionId == sessionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'تبديل الحساب',
      onPressed: _openAccountSwitcher,
      icon: const Icon(Icons.switch_account_rounded),
    );
  }
}
