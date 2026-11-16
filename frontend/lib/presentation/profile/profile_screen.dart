import 'package:flutter/material.dart';
import 'package:she_m_app/data/models/user_model.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/data/services/account_deletion_service.dart';
import 'package:she_m_app/data/services/cart_service.dart';
import 'package:she_m_app/data/services/media_upload_service.dart';
import 'package:she_m_app/data/services/order_service.dart';
import 'package:she_m_app/presentation/cart/cart_screen.dart';
import 'package:she_m_app/presentation/auth/phone_login_screen.dart';
import 'package:she_m_app/presentation/auth/profile_setup_screen.dart';
import 'package:she_m_app/presentation/profile/profile_edit_screen.dart';
import 'package:she_m_app/presentation/support/support_center_screen.dart';
import 'package:she_m_app/presentation/common/logout_confirmation_dialog.dart';
import 'package:she_m_app/presentation/common/custom_appbar.dart';
import 'package:she_m_app/presentation/common/account_switcher_button.dart';
import 'package:she_m_app/presentation/common/account_deletion_dialog.dart';
import 'package:she_m_app/core/animations/route_transitions.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  final OrderService _orderService = OrderService();
  UserModel? _profile;
  int _orderCount = 0;
  bool _isLoading = true;
  bool _deletingAccount = false;

  @override
  void initState() {
    super.initState();
    AuthService.profileUpdated.addListener(_handleProfileUpdated);
    _loadProfile();
  }

  @override
  void dispose() {
    AuthService.profileUpdated.removeListener(_handleProfileUpdated);
    super.dispose();
  }

  void _handleProfileUpdated() {
    if (mounted) {
      _loadProfile();
    }
  }

  Future<void> _loadProfile() async {
    final profile = await _authService.loadSession();
    if (!mounted) return;

    final customerId = profile?.id.trim().isNotEmpty == true
        ? profile!.id
        : (profile?.phone.trim().isNotEmpty == true ? profile!.phone : null);

    final orders = customerId == null
        ? const <dynamic>[]
        : await _orderService.getOrdersByCustomer(customerId);

    if (!mounted) return;

    setState(() {
      _profile = profile;
      _orderCount = orders.length;
      _isLoading = false;
    });
  }

  Future<void> _refreshProfile() async {
    await _loadProfile();
  }

  Future<void> _deleteCustomerAccount() async {
    final profile = _profile;
    if (profile == null || profile.role != 'customer' || _deletingAccount) {
      return;
    }
    final password = await showAccountDeletionDialog(
      context,
      accountName:
          profile.fullName.trim().isEmpty ? profile.phone : profile.fullName,
      accountDescription: 'حساب العميل',
    );
    if (password == null || !mounted) return;

    setState(() => _deletingAccount = true);
    try {
      await AccountDeletionService().deleteAccount(
        profileId: profile.id,
        requesterPhone: profile.phone,
        password: password,
      );
      await _authService.clearSession();
      await CartService.instance.loadForUser(null);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        slideFadeRoute(page: const PhoneLoginScreen()),
        (route) => false,
      );
    } on AccountDeletionException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر حذف الحساب. حاول مرة أخرى.')),
        );
      }
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
  }

  Future<void> _openEditProfileScreen() async {
    final navigator = Navigator.of(context);
    await navigator.push(
      slideFadeRoute(page: const ProfileEditScreen()),
    );
    await _refreshProfile();
  }

  String _roleLabel(String? role) {
    switch (role) {
      case 'merchant':
        return 'تاجر';
      case 'driver':
        return 'سائق';
      case 'central_dispatcher':
        return 'مسؤول توصيل مركزي';
      case 'admin':
        return 'مدير';
      case 'customer':
      default:
        return 'عميل';
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'غير محدد';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final profileName = _profile?.fullName.trim().isNotEmpty == true
        ? _profile!.fullName
        : 'لا يوجد اسم';
    final phone = _profile?.phone.trim().isNotEmpty == true
        ? _profile!.phone
        : 'لا يوجد رقم';
    final city = _profile?.city?.trim().isNotEmpty == true
        ? _profile!.city!
        : 'غير محدد';
    final address = _profile?.address?.trim().isNotEmpty == true
        ? _profile!.address!
        : 'لا يوجد عنوان مسجل';
    final role = _roleLabel(_profile?.role);
    final isVerified = _profile?.isVerified == true;
    final joinedAt = _formatDate(_profile?.createdAt);
    final profileImageData = _profile?.profileImageData;
    final profileImageBytes = profileImageData == null
        ? null
        : MediaUploadService.decodeDataUriToBytes(profileImageData);

    return Scaffold(
      appBar: CustomAppBar(
        title: 'حسابي',
        icon: Icons.person_rounded,
        actions: [
          const AccountSwitcherButton(),
          IconButton(
            onPressed: _refreshProfile,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshProfile,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF8F3DF), Color(0xFFFFFFFF)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE7DCC3)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.25),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: profileImageBytes != null
                          ? Image.memory(
                              profileImageBytes,
                              width: 92,
                              height: 92,
                              fit: BoxFit.cover,
                            )
                          : Center(
                              child: Text(
                                profileName.trim().isNotEmpty
                                    ? profileName.trim()[0].toUpperCase()
                                    : 'S',
                                style: const TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),
                    _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            profileName,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            role,
                            style: const TextStyle(
                              color: Color(0xFF111827),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isVerified
                                ? const Color(0xFFE7F9EE)
                                : const Color(0xFFFFF3E8),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            isVerified ? 'حساب موثق' : 'تفعيل الحساب',
                            style: TextStyle(
                              color: isVerified
                                  ? const Color(0xFF166534)
                                  : const Color(0xFF9A5B00),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _StatsCard(
                      label: 'الطلبات',
                      value: '$_orderCount',
                      icon: Icons.receipt_long_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: CartService.instance,
                      builder: (context, _) => _StatsCard(
                        label: 'السلة',
                        value: '${CartService.instance.itemCount}',
                        icon: Icons.shopping_cart_rounded,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_profile == null) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      slideFadeRoute(page: const PhoneLoginScreen()),
                    ),
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('تسجيل الدخول'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      slideFadeRoute(page: const ProfileSetupScreen()),
                    ),
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('إنشاء حساب جديد'),
                  ),
                ),
                const SizedBox(height: 18),
              ],
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'معلومات الحساب',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _DetailRow(label: 'رقم الهاتف', value: phone),
                    _DetailRow(label: 'المدينة', value: city),
                    _DetailRow(label: 'العنوان', value: address),
                    _DetailRow(label: 'تاريخ الانضمام', value: joinedAt),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              AnimatedBuilder(
                animation: CartService.instance,
                builder: (context, _) => _ProfileTile(
                  title: CartService.instance.itemCount == 0
                      ? 'السلة فارغة'
                      : 'السلة: ${CartService.instance.itemCount} عناصر',
                  icon: Icons.shopping_cart_rounded,
                  onTap: () => Navigator.of(context).push(
                    slideFadeRoute(page: const CartScreen()),
                  ),
                ),
              ),
              if (_profile != null)
                _ProfileTile(
                  title: 'تحديث البيانات',
                  icon: Icons.sync_rounded,
                  onTap: _openEditProfileScreen,
                ),
              if (_profile?.role == 'customer')
                _ProfileTile(
                  title: _deletingAccount ? 'جارٍ حذف الحساب...' : 'حذف الحساب',
                  icon: Icons.person_remove_alt_1_rounded,
                  onTap: _deleteCustomerAccount,
                ),
              _ProfileTile(
                title: 'مركز المساعدة',
                icon: Icons.support_agent_rounded,
                onTap: () {
                  Navigator.of(context).push(
                    slideFadeRoute(page: const SupportCenterScreen()),
                  );
                },
              ),
              if (_profile != null)
                _ProfileTile(
                  title: 'تسجيل الخروج',
                  icon: Icons.logout_rounded,
                  onTap: () async {
                    final shouldSignOut =
                        await showLogoutConfirmationDialog(context);
                    if (!shouldSignOut || !mounted) return;
                    await _authService.clearSession();
                    await CartService.instance.loadForUser(null);
                    if (!mounted) return;
                    await _refreshProfile();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatsCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback? onTap;

  const _ProfileTile({required this.title, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
          ],
        ),
      ),
    );
  }
}
