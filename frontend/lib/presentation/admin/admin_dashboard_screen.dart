import 'package:flutter/material.dart';
import 'package:she_m_app/core/animations/route_transitions.dart';
import 'package:she_m_app/core/errors/app_error.dart';
import 'package:she_m_app/core/responsive.dart';
import 'package:she_m_app/core/theme/design_tokens.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/data/services/admin_service.dart';
import 'package:she_m_app/presentation/admin/admin_management_detail_screens.dart';
import 'package:she_m_app/presentation/admin/app_update_management_screen.dart';
import 'package:she_m_app/presentation/admin/dispatcher_performance_report_screen.dart';
import 'package:she_m_app/presentation/admin/promotion_management_screen.dart';
import 'package:she_m_app/presentation/admin/receipt_management_screen.dart';
import 'package:she_m_app/presentation/admin/support_management_screen.dart';
import 'package:she_m_app/presentation/auth/phone_login_screen.dart';
import 'package:she_m_app/presentation/catalog/product_catalog.dart';
import 'package:she_m_app/presentation/common/app_version_list_tile.dart';
import 'package:she_m_app/presentation/common/account_switcher_button.dart';
import 'package:she_m_app/presentation/common/logout_confirmation_dialog.dart';
import 'package:she_m_app/presentation/common/notification_bell.dart';
import 'package:she_m_app/presentation/support/notifications_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late Future<_AdminDashboardData> _dashboardLoad;

  @override
  void initState() {
    super.initState();
    _dashboardLoad = _loadDashboard();
  }

  Future<_AdminDashboardData> _loadDashboard() async {
    final service = AdminService();
    final results = await Future.wait<Object>([
      service.getDashboardStats(),
      service.getManagementSummary(),
    ]);
    return _AdminDashboardData(
      stats: results[0] as AdminDashboardStats,
      summary: results[1] as AdminManagementSummary,
    );
  }

  Future<void> _refresh() async {
    final load = _loadDashboard();
    setState(() => _dashboardLoad = load);
    try {
      await load;
    } catch (error, stackTrace) {
      debugPrint('Failed to refresh admin dashboard: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _openOrderNotification(String orderId) async {
    await Navigator.of(context).push(
      slideFadeRoute(
        page: OrderManagementScreen(initialOrderId: orderId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AdminDashboardData>(
      future: _dashboardLoad,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('لوحة الإدارة'),
              actions: [
                const AccountSwitcherButton(),
                IconButton(
                  tooltip: 'إعادة المحاولة',
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cloud_off_rounded,
                      size: 48,
                      color: Color(0xFFB91C1C),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'تعذر تحميل بيانات لوحة الإدارة',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppErrorMessage.from(snapshot.error!),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('لوحة الإدارة')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final stats = snapshot.data!.stats;
        final summary = snapshot.data!.summary;

        final overviewCards = <Widget>[
          _OverviewCard(
            title: 'إجمالي الإيرادات',
            value: stats.revenueLabel,
            color: Theme.of(context).colorScheme.primary,
            icon: Icons.account_balance_wallet_rounded,
            note: stats.unconvertedOrderCount > 0
                ? 'تعذّر تحويل ${stats.unconvertedOrderCount} طلب'
                : null,
          ),
          _OverviewCard(
            title: 'الطلبات',
            value: stats.totalOrders.toString(),
            color: const Color(0xFF10B981),
            icon: Icons.receipt_long_rounded,
          ),
          _OverviewCard(
            title: 'التجار',
            value: stats.totalMerchants.toString(),
            color: const Color(0xFF3B82F6),
            icon: Icons.storefront_rounded,
          ),
          _OverviewCard(
            title: 'المراجعات',
            value: summary.pendingApprovals.toString(),
            color: const Color(0xFFF59E0B),
            icon: Icons.pending_actions_rounded,
          ),
        ];

        final managementItems = <Widget>[
          const _ManagementTile(
            title: 'إدارة العملة الافتراضية',
            subtitle: 'إدارة الرصيد، التحويلات، والعملة الرقمية',
            icon: Icons.currency_exchange_rounded,
            destination: VirtualCurrencyManagementScreen(),
          ),
          const _ManagementTile(
            title: 'إدارة العمولة والتوصيل',
            subtitle: 'تحديد العمولة الموحّدة وأجرة التوصيل وسياساتها',
            icon: Icons.price_change_rounded,
            destination: PricingManagementScreen(),
          ),
          const _ManagementTile(
            title: 'إدارة الطلبات',
            subtitle: 'متابعة الطلبات وتأكيدها ومعالجتها',
            icon: Icons.receipt_long_rounded,
            destination: OrderManagementScreen(),
          ),
          const _ManagementTile(
            title: 'طلبات الاسترداد',
            subtitle: 'مراجعة تفاصيل المنتج والعميل والتاجر واعتماد المبالغ',
            icon: Icons.assignment_return_rounded,
            destination: AdminRefundManagementScreen(),
          ),
          const _ManagementTile(
            title: 'بيانات التواصل مع الدعم',
            subtitle: 'تحديث الهاتف وواتساب والبريد وساعات العمل',
            icon: Icons.support_agent_rounded,
            destination: SupportSettingsAdminScreen(),
          ),
          const _ManagementTile(
            title: 'إدارة تحديث التطبيق',
            subtitle: 'ضبط الإصدار ورابط التحميل والأدوار وأهمية التنبيه',
            icon: Icons.system_update_alt_rounded,
            destination: AppUpdateManagementScreen(),
          ),
          const _ManagementTile(
            title: 'إدارة المستخدمين',
            subtitle: 'مراجعة الحسابات والأدوار والصلاحيات',
            icon: Icons.people_alt_rounded,
            destination: UserManagementScreen(),
          ),
          const _ManagementTile(
            title: 'إدارة التجار',
            subtitle: 'مراجعة بيانات المتاجر والبحث حسب النشاط والمنطقة',
            icon: Icons.storefront_rounded,
            destination: MerchantManagementAdminScreen(),
          ),
          const _ManagementTile(
            title: 'إدارة السائقين',
            subtitle: 'إدارة قائمة السائقين وحالة توفرهم ومناطق التوصيل',
            icon: Icons.delivery_dining_rounded,
            destination: DriverManagementScreen(),
          ),
          const _ManagementTile(
            title: 'تقارير مسؤولي التوصيل',
            subtitle: 'متابعة الأداء اليومي والشهري والسنوي وتفاصيل الإسناد',
            icon: Icons.analytics_rounded,
            destination: DispatcherPerformanceReportScreen(),
          ),
          const _ManagementTile(
            title: 'إدارة الارصدة والحسابات',
            subtitle: 'مراقبة الرصيد، الحركات، والعمليات المالية',
            icon: Icons.account_balance_wallet_rounded,
            destination: BalanceManagementScreen(),
          ),
          const _ManagementTile(
            title: 'محافظ التجار وطلبات السحب',
            subtitle: 'اعتماد السحب ومتابعة المستحقات بعد فترة الاسترداد',
            icon: Icons.payments_rounded,
            destination: MerchantWalletAdminScreen(),
          ),
          const _ManagementTile(
            title: 'إدارة المحافظ الالكترونية',
            subtitle: 'إدارة المحافظ الرقمية وتهيئتها',
            icon: Icons.wallet_rounded,
            destination: WalletManagementScreen(),
          ),
          const _ManagementTile(
            title: 'إدارة إيصالات الدفع',
            subtitle: 'معاينة الإيصالات ومراجعة واعتماد التحويلات',
            icon: Icons.receipt_long_rounded,
            destination: ReceiptManagementScreen(),
          ),
          const _ManagementTile(
            title: 'إدارة أقسام المنتجات',
            subtitle: 'إدارة الأقسام الرئيسية والفرعية التابعة لها',
            icon: Icons.category_rounded,
            destination: ProductCategoryManagementScreen(),
          ),
          const _ManagementTile(
            title: 'إدارة فئات المتاجر',
            subtitle: 'تحديد الفئات التي تظهر للتجار عند إنشاء الحساب',
            icon: Icons.store_mall_directory_rounded,
            destination: MerchantCategoryManagementScreen(),
          ),
          const _ManagementTile(
            title: 'إدارة المنتجات',
            subtitle: 'إدارة المتاح، الأسعار، والعروض',
            icon: Icons.inventory_2_rounded,
            destination: ProductManagementAdminScreen(),
          ),
          const _ManagementTile(
            title: 'إدارة العروض والإعلانات',
            subtitle: 'إنشاء الإعلانات وترتيب ظهورها للعملاء',
            icon: Icons.campaign_rounded,
            destination: PromotionManagementScreen(),
          ),
          _ManagementTile(
            title: 'الإشعارات',
            subtitle: 'عرض الإشعارات وفتح تفاصيل الطلبات المرتبطة',
            icon: Icons.notifications_active_rounded,
            destination: NotificationsScreen(
              onAdminOrderTap: _openOrderNotification,
            ),
          ),
        ];

        return Scaffold(
          appBar: AppBar(
            title: const Text('لوحة الإدارة'),
            leadingWidth: 68,
            leading: NotificationBell(
              prominent: true,
              onAdminOrderTap: _openOrderNotification,
            ),
            actions: [
              const AccountSwitcherButton(),
              IconButton(
                tooltip: 'بحث في المنتجات',
                onPressed: () => Navigator.of(context).push(
                  slideFadeRoute(page: ProductCatalogScreen()),
                ),
                icon: const Icon(Icons.search_rounded),
              ),
              IconButton(
                tooltip: 'تحديث البيانات',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
              Builder(
                builder: (context) => IconButton(
                  tooltip: 'القائمة الجانبية',
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                  icon: const Icon(Icons.menu_rounded),
                ),
              ),
            ],
          ),
          endDrawer: Drawer(
            width: 310,
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFD4AF37).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.admin_panel_settings_rounded,
                          color: Color(0xFF9A7B2F),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'لوحة الإدارة',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'إغلاق القائمة',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  ListTile(
                    leading: const Icon(Icons.dashboard_rounded),
                    title: const Text('الرئيسية'),
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  ListTile(
                    leading: const Icon(Icons.receipt_long_rounded),
                    title: const Text('إدارة الطلبات'),
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        slideFadeRoute(page: const OrderManagementScreen()),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.wallet_rounded),
                    title: const Text('إدارة المحافظ الإلكترونية'),
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        slideFadeRoute(page: const WalletManagementScreen()),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.receipt_long_rounded),
                    title: const Text('إدارة إيصالات الدفع'),
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        slideFadeRoute(
                          page: const ReceiptManagementScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 28),
                  ListTile(
                    leading:
                        const Icon(Icons.logout_rounded, color: Colors.red),
                    title: const Text(
                      'تسجيل الخروج',
                      style: TextStyle(color: Colors.red),
                    ),
                    onTap: () async {
                      Navigator.of(context).pop();
                      final shouldSignOut =
                          await showLogoutConfirmationDialog(context);
                      if (!shouldSignOut || !context.mounted) return;
                      await AuthService().clearSession();
                      if (!context.mounted) return;
                      Navigator.of(context).pushAndRemoveUntil(
                        slideFadeRoute(page: const PhoneLoginScreen()),
                        (route) => false,
                      );
                    },
                  ),
                  const Divider(height: 28),
                  const AppVersionListTile(),
                ],
              ),
            ),
          ),
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0F172A), Color(0xFF111827)],
                              begin: Alignment.centerRight,
                              end: Alignment.centerLeft,
                            ),
                            borderRadius: BorderRadius.circular(26),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 18,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'لوحة الإدارة',
                                      key: ValueKey('admin_dashboard_header'),
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 26,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'مراقبة الأداء، الطلبات، والمتاجر في الوقت الحقيقي.',
                                      style: TextStyle(
                                        color: Color(0xFFE5E7EB),
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _Pill(
                                            label:
                                                '${summary.pendingApprovals} مراجعات معلقة'),
                                        _Pill(
                                            label:
                                                '${summary.unreadNotifications} إشعارات جديدة'),
                                        _Pill(
                                            label:
                                                '${summary.activeDeliveries} طلبات قيد التنفيذ'),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD4AF37)
                                      .withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: const Icon(
                                  Icons.dashboard_customize_rounded,
                                  color: Color(0xFFD4AF37),
                                  size: 30,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: Responsive.columnsForWidth(
                            constraints.maxWidth,
                            mobile: 2,
                            tablet: 3,
                            desktop: 4,
                          ),
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.2,
                          children: overviewCards,
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            const Text(
                              'إدارة النظام',
                              key: ValueKey('admin_system_section'),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'نشط الآن',
                                style: TextStyle(
                                  color: Color(0xFF10B981),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _Pill(label: 'إدارة العملة الافتراضية'),
                            _Pill(label: 'إدارة الطلبات'),
                            _Pill(label: 'إدارة المستخدمين'),
                            _Pill(label: 'إدارة التجار'),
                            _Pill(label: 'إدارة السائقين'),
                            _Pill(label: 'إدارة الارصدة والحسابات'),
                            _Pill(label: 'إدارة المحافظ الالكترونية'),
                            _Pill(label: 'إدارة أقسام المنتجات'),
                            _Pill(label: 'إدارة المنتجات'),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...managementItems,
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF111827),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'النشاط الأخير',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '• ${summary.totalMerchants} متجر مسجل في المنصة',
                                style:
                                    const TextStyle(color: Color(0xFFE5E7EB)),
                              ),
                              Text(
                                '• ${summary.pendingApprovals} مراجعات تحتاج اعتماد الإدارة',
                                style:
                                    const TextStyle(color: Color(0xFFE5E7EB)),
                              ),
                              Text(
                                '• ${summary.activeDeliveries} طلبات قيد التنفيذ والتوصيل',
                                style:
                                    const TextStyle(color: Color(0xFFE5E7EB)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _AdminDashboardData {
  const _AdminDashboardData({required this.stats, required this.summary});

  final AdminDashboardStats stats;
  final AdminManagementSummary summary;
}

class _OverviewCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;
  final String? note;

  const _OverviewCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: DesignTokens.elevatedShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(
              note!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ManagementTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget destination;

  const _ManagementTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.destination,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          slideFadeRoute(page: destination),
        );
      },
      borderRadius: BorderRadius.circular(16),
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
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;

  const _Pill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F3FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE9D5FF)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF4C1D95),
        ),
      ),
    );
  }
}
