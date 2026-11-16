import 'dart:async';

import 'package:flutter/material.dart';
import 'package:she_m_app/core/errors/app_error.dart';
import 'package:she_m_app/data/models/order_number.dart';
import 'package:she_m_app/core/animations/route_transitions.dart';
import 'package:she_m_app/data/models/user_model.dart';
import 'package:she_m_app/data/services/admin_service.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/data/services/currency_service.dart';
import 'package:she_m_app/presentation/common/delivery_fee_adjustment_dialog.dart';
import 'package:she_m_app/presentation/common/app_version_list_tile.dart';
import 'package:she_m_app/presentation/common/account_switcher_button.dart';
import 'package:she_m_app/presentation/common/logout_confirmation_dialog.dart';
import 'package:she_m_app/presentation/common/notification_bell.dart';
import 'package:she_m_app/presentation/auth/phone_login_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class CentralDispatcherDashboardScreen extends StatefulWidget {
  const CentralDispatcherDashboardScreen({super.key});

  @override
  State<CentralDispatcherDashboardScreen> createState() =>
      _CentralDispatcherDashboardScreenState();
}

class _CentralDispatcherDashboardScreenState
    extends State<CentralDispatcherDashboardScreen> {
  final AdminService _service = AdminService();
  final TextEditingController _orderSearchController = TextEditingController();
  late Future<_DispatcherData> _dashboardFuture;
  late Future<DispatcherPerformanceReport> _reportFuture;
  DispatcherReportPeriod _period = DispatcherReportPeriod.daily;
  UserModel? _profile;
  String _currencySymbol = CurrencyService.yerCurrency.symbol;
  String _orderQuery = '';
  String _orderStatusFilter = 'all';
  bool _starredOrdersOnly = false;
  int _dashboardRequestId = 0;
  final Set<String> _assigningOrderIds = {};
  final Set<String> _updatingStarredOrderIds = {};
  Timer? _trackingRefreshTimer;

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _loadDashboard();
    _trackingRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (mounted) _refresh();
      },
    );
  }

  Future<_DispatcherData> _loadDashboard() async {
    final requestId = ++_dashboardRequestId;
    final auth = AuthService();
    final profile = await auth.loadSession() ?? await auth.getCurrentProfile();
    if (profile == null ||
        (profile.role != 'central_dispatcher' && profile.role != 'manager')) {
      throw StateError('تعذر التحقق من حساب مسؤول التوصيل المركزي');
    }
    final results = await Future.wait([
      _service.getOrdersAwaitingDispatch(dispatcherId: profile.id),
      _service.getProfilesForAdmin(role: 'driver', limit: 100),
      _service.getActiveDispatcherOrders(dispatcherId: profile.id),
    ]);
    final currencies = await CurrencyService().getCurrencies();
    final dispatchOrders = results[0].map((order) {
      final totalInYER = CurrencyService.orderTotalInYER(order, currencies);
      return {
        ...order,
        if (totalInYER != null) 'report_total_yer': totalInYER,
      };
    }).toList();
    if (requestId == _dashboardRequestId && mounted) {
      _profile = profile;
      _currencySymbol = CurrencyService.yerCurrency.symbol;
      _reportFuture = _service.getDispatcherPerformanceReport(
        dispatcherId: profile.id,
        period: _period,
      );
    }
    return _DispatcherData(
      orders: dispatchOrders,
      drivers: results[1],
      assignedOrders: results[2],
    );
  }

  Future<void> _refresh() {
    final refreshFuture = _loadDashboard();
    setState(() => _dashboardFuture = refreshFuture);
    return refreshFuture.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        // FutureBuilder presents the error while the refresh indicator stops.
      },
    );
  }

  @override
  void dispose() {
    _trackingRefreshTimer?.cancel();
    _orderSearchController.dispose();
    super.dispose();
  }

  Future<void> _assignOrder(
    Map<String, dynamic> order,
    List<Map<String, dynamic>> drivers,
  ) async {
    final orderId = (order['id'] ?? '').toString();
    final driver = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.65,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'اختر سائقًا للطلب ${OrderNumber.fromOrder(order)}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Expanded(
                  child: drivers.isEmpty
                      ? const Center(child: Text('لا يوجد سائقون مسجلون'))
                      : ListView.builder(
                          itemCount: drivers.length,
                          itemBuilder: (context, index) {
                            final driver = drivers[index];
                            final available = _isAvailable(driver);
                            final name =
                                driver['full_name']?.toString().trim() ??
                                    'سائق';
                            return ListTile(
                              enabled: available,
                              leading:
                                  const Icon(Icons.delivery_dining_rounded),
                              title: Text(name),
                              subtitle: Text([
                                driver['phone']?.toString() ?? '',
                                available ? 'متاح' : 'غير متاح',
                              ].where((part) => part.isNotEmpty).join(' • ')),
                              trailing: available
                                  ? const Icon(Icons.chevron_left_rounded)
                                  : null,
                              onTap: available
                                  ? () => Navigator.of(context).pop(driver)
                                  : null,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (driver == null || !mounted) return;

    if (_assigningOrderIds.contains(orderId)) return;
    setState(() => _assigningOrderIds.add(orderId));
    try {
      final success = await _service.assignOrderToDriver(
        orderId: orderId,
        driverName: driver['full_name']?.toString() ?? 'سائق',
        driverId: driver['id']?.toString(),
        driverPhone: driver['phone']?.toString(),
        eta: 'قريبًا',
        dispatcherId: _profile?.id,
        dispatcherName: _profile?.fullName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'تم إسناد الطلب $orderId إلى ${driver['full_name'] ?? 'السائق'}'
                : 'تعذر إسناد الطلب، حدّث القائمة وحاول مجددًا',
          ),
        ),
      );
      if (success) _refresh();
    } catch (error, stackTrace) {
      debugPrint('Failed to assign order $orderId: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر إسناد الطلب، حاول مجددًا')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _assigningOrderIds.remove(orderId));
      }
    }
  }

  bool _isAvailable(Map<String, dynamic> driver) {
    final raw = driver['is_available'];
    return raw == true || raw?.toString().toLowerCase() == 'true';
  }

  String _periodLabel(DispatcherReportPeriod period) => switch (period) {
        DispatcherReportPeriod.daily => 'يومي',
        DispatcherReportPeriod.monthly => 'شهري',
        DispatcherReportPeriod.yearly => 'سنوي',
      };

  Future<void> _signOut() async {
    final shouldSignOut = await showLogoutConfirmationDialog(context);
    if (!shouldSignOut || !mounted) return;

    await AuthService().clearSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      slideFadeRoute(page: const PhoneLoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة مسؤول التوصيل'),
        actions: [
          const AccountSwitcherButton(),
          IconButton(
            tooltip: 'تحديث',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const NotificationBell(),
          Builder(
            builder: (context) => IconButton(
              tooltip: 'القائمة الجانبية',
              onPressed: () => Scaffold.of(context).openEndDrawer(),
              icon: const Icon(Icons.menu_rounded),
            ),
          ),
          IconButton(
            tooltip: 'تسجيل الخروج',
            onPressed: _signOut,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      endDrawer: Drawer(
        width: 310,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
              children: [
                Row(
                  children: [
                    const Icon(Icons.local_shipping_rounded),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _profile?.role == 'manager'
                            ? 'لوحة المدير'
                            : 'لوحة مسؤول التوصيل',
                        style: const TextStyle(
                          fontSize: 18,
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
                const AppVersionListTile(),
              ],
            ),
          ),
        ),
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: FutureBuilder<_DispatcherData>(
          future: _dashboardFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _LoadError(
                  message: AppErrorMessage.from(snapshot.error!),
                  onRetry: _refresh);
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data!;
            final visibleOrders = data.orders
                .where(
                  (order) =>
                      _matchesOrder(order, _orderQuery) &&
                      (_orderStatusFilter == 'all' ||
                          order['status']?.toString() == _orderStatusFilter) &&
                      (!_starredOrdersOnly || _isStarred(order)),
                )
                .toList();
            final hasAvailableDrivers = data.drivers.any(_isAvailable);
            return RefreshIndicator(
              onRefresh: _refresh,
              child: LayoutBuilder(
                builder: (context, constraints) => ListView(
                  padding: EdgeInsets.symmetric(
                    horizontal: constraints.maxWidth >= 800 ? 32 : 16,
                    vertical: 16,
                  ),
                  children: [
                    _DispatcherHeader(
                      name: _profile?.fullName ?? 'مسؤول التوصيل',
                    ),
                    const SizedBox(height: 16),
                    _DispatcherSummary(
                      pendingOrders: data.orders.length,
                      availableDrivers: data.drivers.where(_isAvailable).length,
                      totalDrivers: data.drivers.length,
                    ),
                    const SizedBox(height: 24),
                    _sectionTitle('طلبات بانتظار إسناد سائق'),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _orderSearchController,
                      textInputAction: TextInputAction.search,
                      onChanged: (value) =>
                          setState(() => _orderQuery = value.trim()),
                      decoration: InputDecoration(
                        hintText: 'ابحث برقم الطلب أو اسم العميل أو هاتفه',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _orderQuery.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'مسح البحث',
                                onPressed: () {
                                  _orderSearchController.clear();
                                  setState(() => _orderQuery = '');
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 185,
                          child: DropdownButtonFormField<String>(
                            initialValue: _orderStatusFilter,
                            decoration: const InputDecoration(
                              labelText: 'تصفية حسب الحالة',
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'all',
                                child: Text('كل الحالات'),
                              ),
                              DropdownMenuItem(
                                value: 'accepted',
                                child: Text('مقبول'),
                              ),
                              DropdownMenuItem(
                                value: 'confirmed',
                                child: Text('مؤكد'),
                              ),
                              DropdownMenuItem(
                                value: 'preparing',
                                child: Text('قيد التجهيز'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _orderStatusFilter = value);
                              }
                            },
                          ),
                        ),
                        FilterChip(
                          avatar: Icon(
                            _starredOrdersOnly
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                          ),
                          label: const Text('المميزة بنجمة'),
                          selected: _starredOrdersOnly,
                          onSelected: (selected) =>
                              setState(() => _starredOrdersOnly = selected),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (data.orders.isEmpty)
                      const _EmptyPanel(
                        message: 'لا توجد طلبات تحتاج إلى إسناد حاليًا',
                      )
                    else if (visibleOrders.isEmpty)
                      const _EmptyPanel(
                        message: 'لا توجد طلبات تطابق عوامل التصفية',
                      )
                    else
                      ...visibleOrders.map(
                        (order) => _DispatchOrderCard(
                          order: order,
                          currencySymbol: _currencySymbol,
                          isStarred: _isStarred(order),
                          isUpdatingStar: _updatingStarredOrderIds
                              .contains((order['id'] ?? '').toString()),
                          onToggleStar: () => _toggleOrderStar(order),
                          isAssigning: _assigningOrderIds
                              .contains((order['id'] ?? '').toString()),
                          onAssign: hasAvailableDrivers
                              ? () => _assignOrder(order, data.drivers)
                              : null,
                          onShowDetails: () => _showOrderDetails(order),
                          onDeliveryFeeUpdated: _refresh,
                        ),
                      ),
                    const SizedBox(height: 18),
                    _sectionTitle(
                      'طلباتك المسندة قيد التوصيل (${data.assignedOrders.length})',
                    ),
                    const SizedBox(height: 10),
                    if (data.assignedOrders.isEmpty)
                      const _EmptyPanel(
                        message: 'لا توجد طلبات مسندة قيد التوصيل حاليًا',
                      )
                    else
                      ...data.assignedOrders.map(
                        (order) => _AssignedDispatchOrderCard(
                          order: order,
                          currencySymbol: _currencySymbol,
                          onShowDetails: () => _showOrderDetails(order),
                        ),
                      ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(child: _sectionTitle('أداؤك')),
                        DropdownButton<DispatcherReportPeriod>(
                          value: _period,
                          items: DispatcherReportPeriod.values
                              .map(
                                (period) => DropdownMenuItem(
                                  value: period,
                                  child: Text(_periodLabel(period)),
                                ),
                              )
                              .toList(),
                          onChanged: (period) {
                            if (period == null || _profile == null) return;
                            setState(() {
                              _period = period;
                              _reportFuture =
                                  _service.getDispatcherPerformanceReport(
                                dispatcherId: _profile!.id,
                                period: _period,
                              );
                            });
                          },
                        ),
                      ],
                    ),
                    FutureBuilder<DispatcherPerformanceReport>(
                      future: _reportFuture,
                      builder: (context, reportSnapshot) {
                        if (reportSnapshot.hasError) {
                          return _LoadError(
                            message:
                                AppErrorMessage.from(reportSnapshot.error!),
                            onRetry: _refresh,
                          );
                        }
                        if (!reportSnapshot.hasData) {
                          return const Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }
                        return _DispatcherReportCards(
                          report: reportSnapshot.data!,
                          period: _periodLabel(_period),
                          currencySymbol: _currencySymbol,
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) => Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      );

  bool _matchesOrder(Map<String, dynamic> order, String query) {
    if (query.isEmpty) return true;
    final normalizedQuery = query.toLowerCase();
    return [
      order['id'],
      OrderNumber.fromOrder(order),
      order['customer_name'],
      order['customer_phone'],
      order['delivery_address'],
    ].any(
      (value) =>
          value?.toString().toLowerCase().contains(normalizedQuery) ?? false,
    );
  }

  bool _isStarred(Map<String, dynamic> order) {
    final value = order['is_starred'];
    return value == true || value?.toString().toLowerCase() == 'true';
  }

  Future<void> _toggleOrderStar(Map<String, dynamic> order) async {
    final orderId = (order['id'] ?? '').toString();
    final dispatcherId = _profile?.id ?? '';
    if (orderId.isEmpty ||
        dispatcherId.isEmpty ||
        _updatingStarredOrderIds.contains(orderId)) {
      return;
    }
    final wasStarred = _isStarred(order);
    final starred = !wasStarred;
    setState(() {
      _updatingStarredOrderIds.add(orderId);
      order['is_starred'] = starred;
    });
    try {
      final updated = await _service.setDispatcherOrderStarred(
        dispatcherId: dispatcherId,
        orderId: orderId,
        starred: starred,
      );
      if (!updated) throw StateError('تعذر حفظ تمييز الطلب');
    } catch (error, stackTrace) {
      debugPrint('Failed to update starred state for order $orderId: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => order['is_starred'] = wasStarred);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر حفظ تمييز الطلب، حاول مجددًا')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _updatingStarredOrderIds.remove(orderId));
      }
    }
  }

  void _showOrderDetails(Map<String, dynamic> order) {
    final orderId = (order['id'] ?? '').toString();
    if (orderId.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.92,
        child: _DispatcherOrderDetailsSheet(
          order: order,
          loadLatest: () => _service.getOrderTrackingSnapshot(orderId),
          openMap: _openGoogleMaps,
        ),
      ),
    );
  }

  Future<void> _openGoogleMaps(
    String label,
    String address,
    String? coordinates,
  ) async {
    final query = coordinates?.trim().isNotEmpty == true
        ? coordinates!.trim()
        : address.trim();
    if (query.isEmpty || _isCoordinateOnlyAddress(query)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('لا يتوفر عنوان أو موقع $label لفتحه')),
      );
      return;
    }
    final uri = Uri.https(
      'www.google.com',
      '/maps/search/',
      {'api': '1', 'query': query},
    );
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح خرائط Google')),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to open Google Maps for $label: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح خرائط Google')),
        );
      }
    }
  }
}

class _DispatcherData {
  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> drivers;
  final List<Map<String, dynamic>> assignedOrders;

  const _DispatcherData({
    required this.orders,
    required this.drivers,
    required this.assignedOrders,
  });
}

class _DispatcherHeader extends StatelessWidget {
  final String name;

  const _DispatcherHeader({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF134E4A)],
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.hub_rounded, color: Colors.white, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'مرحبًا، $name',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'استقبل الطلبات وأسندها للسائق المناسب',
                  style: TextStyle(color: Color(0xFFD1FAE5)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DispatcherSummary extends StatelessWidget {
  final int pendingOrders;
  final int availableDrivers;
  final int totalDrivers;

  const _DispatcherSummary({
    required this.pendingOrders,
    required this.availableDrivers,
    required this.totalDrivers,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        'طلبات تنتظر الإسناد',
        pendingOrders.toString(),
        Icons.assignment_outlined,
        const Color(0xFFB45309),
        const Color(0xFFFFF7ED),
      ),
      (
        'سائقون متاحون',
        availableDrivers.toString(),
        Icons.delivery_dining_rounded,
        const Color(0xFF047857),
        const Color(0xFFECFDF5),
      ),
      (
        'إجمالي السائقين',
        totalDrivers.toString(),
        Icons.groups_rounded,
        const Color(0xFF1D4ED8),
        const Color(0xFFEFF6FF),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 3 : 2;
        final cardWidth = (constraints.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: items
              .map(
                (item) => SizedBox(
                  width: cardWidth,
                  child: Card(
                    margin: EdgeInsets.zero,
                    elevation: 0,
                    color: item.$5,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.white,
                            foregroundColor: item.$4,
                            child: Icon(item.$3),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.$2,
                                  style: TextStyle(
                                    color: item.$4,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  item.$1,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _DispatchOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final String currencySymbol;
  final bool isStarred;
  final bool isUpdatingStar;
  final VoidCallback onToggleStar;
  final VoidCallback? onAssign;
  final VoidCallback onShowDetails;
  final bool isAssigning;
  final VoidCallback onDeliveryFeeUpdated;

  const _DispatchOrderCard({
    required this.order,
    required this.currencySymbol,
    required this.isStarred,
    required this.isUpdatingStar,
    required this.onToggleStar,
    required this.onAssign,
    required this.onShowDetails,
    required this.isAssigning,
    required this.onDeliveryFeeUpdated,
  });

  @override
  Widget build(BuildContext context) {
    final totalInYER = order['report_total_yer'];
    final amount = totalInYER is num
        ? '${totalInYER.toStringAsFixed(0)} $currencySymbol'
        : 'غير متاح بالريال اليمني';
    final status = switch (order['status']?.toString()) {
      'accepted' => 'مقبول',
      'confirmed' => 'مؤكد',
      'preparing' => 'قيد التجهيز',
      _ => 'بانتظار الإسناد',
    };
    return Card(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      shadowColor: const Color(0x14000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF8F6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    color: Color(0xFF0F766E),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'طلب #${OrderNumber.fromOrder(order)}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Container(
                  constraints: const BoxConstraints(maxWidth: 145),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    amount,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF0F766E),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: isStarred ? 'إزالة من المميزة' : 'تمييز الطلب بنجمة',
                  onPressed: isUpdatingStar ? null : onToggleStar,
                  icon: isUpdatingStar
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          isStarred ? Icons.star_rounded : Icons.star_border,
                          color: isStarred
                              ? const Color(0xFFEAB308)
                              : const Color(0xFF64748B),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                status,
                style: const TextStyle(
                  color: Color(0xFFB45309),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _OrderInfoRow(
              icon: Icons.person_outline_rounded,
              text: order['customer_name']?.toString() ?? 'عميل',
            ),
            if ((order['customer_phone']?.toString() ?? '').isNotEmpty)
              _OrderInfoRow(
                icon: Icons.phone_outlined,
                text: order['customer_phone'].toString(),
              ),
            _OrderInfoRow(
              icon: Icons.location_on_outlined,
              text: _deliveryAddress(order),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: isAssigning ? null : onAssign,
                    icon: isAssigning
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_add_alt_1_rounded),
                    label: Text(
                      isAssigning
                          ? 'جارٍ إسناد الطلب'
                          : onAssign == null
                              ? 'لا يوجد سائق متاح'
                              : 'اختيار السائق وإسناد الطلب',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => showDeliveryFeeAdjustmentDialog(
                      context,
                      order: order,
                      onUpdated: onDeliveryFeeUpdated,
                    ),
                    icon: const Icon(Icons.price_change_rounded),
                    label: const Text('تعديل أجرة التوصيل'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onShowDetails,
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('تفاصيل الطلب والمواقع'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssignedDispatchOrderCard extends StatelessWidget {
  const _AssignedDispatchOrderCard({
    required this.order,
    required this.currencySymbol,
    required this.onShowDetails,
  });

  final Map<String, dynamic> order;
  final String currencySymbol;
  final VoidCallback onShowDetails;

  @override
  Widget build(BuildContext context) {
    final total = _formatAmount(
      order['total'],
      currencySymbol: _orderCurrency(order, currencySymbol),
    );
    return Card(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      shadowColor: const Color(0x14000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFEFF8F6),
          foregroundColor: Color(0xFF0F766E),
          child: Icon(Icons.delivery_dining_rounded),
        ),
        title: Text(
          'طلب #${OrderNumber.fromOrder(order)} • ${order['customer_name'] ?? 'عميل'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'السائق: ${order['driver_name'] ?? 'غير محدد'}\n'
            'الحالة: ${_statusLabel(order['status'])}\n'
            'الإجمالي: $total',
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: IconButton(
          tooltip: 'تفاصيل الطلب',
          onPressed: onShowDetails,
          icon: const Icon(Icons.open_in_new_rounded),
        ),
        onTap: onShowDetails,
      ),
    );
  }
}

class _DispatcherOrderDetailsSheet extends StatefulWidget {
  const _DispatcherOrderDetailsSheet({
    required this.order,
    required this.loadLatest,
    required this.openMap,
  });

  final Map<String, dynamic> order;
  final Future<Map<String, dynamic>?> Function() loadLatest;
  final Future<void> Function(String label, String address, String? coordinates)
      openMap;

  @override
  State<_DispatcherOrderDetailsSheet> createState() =>
      _DispatcherOrderDetailsSheetState();
}

class _DispatcherOrderDetailsSheetState
    extends State<_DispatcherOrderDetailsSheet> {
  late Map<String, dynamic> _order;
  late Future<Map<String, dynamic>?> _orderFuture;
  Timer? _refreshTimer;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    _orderFuture = widget.loadLatest();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refresh(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (!mounted || _refreshing) return;
    _refreshing = true;
    final future = widget.loadLatest();
    setState(() => _orderFuture = future);
    future.then(
      (latest) {
        if (mounted && latest != null) setState(() => _order = latest);
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Failed to refresh dispatcher order details: $error');
        debugPrintStack(stackTrace: stackTrace);
      },
    ).whenComplete(() {
      _refreshing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'تفاصيل الطلب #${OrderNumber.fromOrder(_order)}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'تحديث الموقع والبيانات',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                tooltip: 'إغلاق',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<Map<String, dynamic>?>(
            future: _orderFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('تعذر تحديث تفاصيل الطلب'),
                        const SizedBox(height: 8),
                        Text(AppErrorMessage.from(snapshot.error!)),
                        TextButton.icon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final latest = snapshot.data;
              if (latest == null) {
                return const Center(child: Text('لم يعد الطلب متاحًا'));
              }
              _order = latest;
              return _detailsContent(context, _order);
            },
          ),
        ),
      ],
    );
  }

  Widget _detailsContent(
    BuildContext context,
    Map<String, dynamic> order,
  ) {
    final customer = _mapValue(order['customer_snapshot'] ?? order['customer']);
    final driver = _mapValue(order['driver_snapshot'] ?? order['driver']);
    final update = _mapValue(order['latest_delivery_update']);
    final items = _orderItems(order);
    final merchantProfiles = _mapValue(order['merchant_snapshots']);
    final currency = _orderCurrency(order, 'ر.ي');
    final address = _firstNonEmpty([
      order['delivery_address'],
      order['shipping_address'],
      order['address'],
      customer['address'],
      customer['shipping_address'],
      'تفاصيل عنوان التوصيل غير متوفرة',
    ]);
    final merchantEntries = <(String, Map<String, dynamic>)>[];
    for (final item in items) {
      final merchantId =
          (item['merchant_id'] ?? item['merchantId'] ?? '').toString();
      final merchant = _mapValue(
        item['merchant_snapshot'] ??
            item['merchant'] ??
            merchantProfiles[merchantId] ??
            order['merchant_snapshot'],
      );
      final name = _firstNonEmpty([
        item['merchant_name'],
        item['merchantName'],
        merchant['shop_name'],
        merchant['full_name'],
        order['merchant_name'],
        'التاجر',
      ]);
      if (!merchantEntries.any((entry) => entry.$1 == name)) {
        merchantEntries.add((name, merchant));
      }
    }
    if (merchantEntries.isEmpty) {
      merchantEntries.add((
        _firstNonEmpty([
          order['merchant_name'],
          _mapValue(order['merchant_snapshot'])['shop_name'],
          'التاجر',
        ]),
        _mapValue(order['merchant_snapshot']),
      ));
    }

    final customerCoordinates = _coordinateFor(
          order,
          latitudeKeys: const [
            'customer_latitude',
            'delivery_latitude',
            'latitude',
          ],
          longitudeKeys: const [
            'customer_longitude',
            'delivery_longitude',
            'longitude',
          ],
          locationKeys: const ['delivery_address', 'shipping_address'],
        ) ??
        _coordinateFor(
          customer,
          latitudeKeys: const ['latitude', 'customer_latitude'],
          longitudeKeys: const ['longitude', 'customer_longitude'],
          locationKeys: const ['address', 'current_location', 'location'],
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      children: [
        _detailsSection(
          context,
          title: 'العميل وعنوان التوصيل',
          icon: Icons.person_pin_circle_rounded,
          children: [
            _detailLine(
                'اسم العميل',
                _firstNonEmpty([
                  order['customer_name'],
                  customer['full_name'],
                  'عميل',
                ])),
            _detailLine(
              'هاتف العميل',
              _firstNonEmpty(
                  [order['customer_phone'], customer['phone'], 'غير متوفر']),
            ),
            _detailLine('عنوان التوصيل', address),
            _mapButton(
              label: 'فتح موقع العميل على خرائط Google',
              address: address,
              coordinates: customerCoordinates,
            ),
          ],
        ),
        _detailsSection(
          context,
          title: 'السائق والوقت المتوقع',
          icon: Icons.delivery_dining_rounded,
          children: [
            _detailLine(
                'السائق',
                _firstNonEmpty([
                  order['driver_name'],
                  order['courier_name'],
                  driver['full_name'],
                  'غير محدد',
                ])),
            _detailLine(
              'حالة الطلب',
              _statusLabel(order['status']),
            ),
            _detailLine(
              'الوقت المتوقع',
              _firstNonEmpty([update['eta'], order['eta'], 'غير محدد']),
            ),
          ],
        ),
        _detailsSection(
          context,
          title: merchantEntries.length == 1 ? 'التاجر' : 'التجار',
          icon: Icons.store_mall_directory_rounded,
          children: [
            for (final entry in merchantEntries) ...[
              _detailLine('اسم التاجر', entry.$1),
              _detailLine(
                'عنوان التاجر',
                _merchantAddress(entry.$2),
              ),
              _mapButton(
                label: 'فتح موقع ${entry.$1} على خرائط Google',
                address: _merchantAddress(entry.$2),
                coordinates: _coordinateFor(
                  entry.$2,
                  latitudeKeys: const ['shop_latitude', 'latitude'],
                  longitudeKeys: const ['shop_longitude', 'longitude'],
                  locationKeys: const [
                    'shop_location',
                    'shop_address',
                    'address',
                  ],
                ),
              ),
              if (entry != merchantEntries.last) const Divider(),
            ],
          ],
        ),
        _detailsSection(
          context,
          title: 'المنتجات (${items.length})',
          icon: Icons.inventory_2_rounded,
          children: items.isEmpty
              ? [_detailLine('المنتجات', 'لا توجد تفاصيل منتجات محفوظة')]
              : [
                  for (final item in items) _productDetail(item, currency),
                ],
        ),
        _detailsSection(
          context,
          title: 'ملخص المبالغ',
          icon: Icons.payments_outlined,
          children: [
            _detailLine('المجموع الفرعي',
                _formatAmount(order['subtotal'], currencySymbol: currency)),
            _detailLine(
              'سعر التوصيل',
              _formatAmount(
                order['shipping_fee'] ??
                    order['shippingFee'] ??
                    order['delivery_fee'],
                currencySymbol: currency,
              ),
            ),
            if (order['commission'] != null)
              _detailLine(
                'العمولة',
                _formatAmount(order['commission'], currencySymbol: currency),
              ),
            _detailLine(
              'الإجمالي',
              _formatAmount(order['total'], currencySymbol: currency),
              emphasis: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _mapButton({
    required String label,
    required String address,
    required String? coordinates,
  }) {
    final hasCoordinates = coordinates?.isNotEmpty == true;
    final hasAddress = address.isNotEmpty &&
        !_isCoordinateOnlyAddress(address) &&
        address != 'تفاصيل عنوان التوصيل غير متوفرة' &&
        address != 'لم يُسجل موقع حالي للسائق' &&
        !address.contains('غير متوفر') &&
        !address.contains('لم يُسجل');
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        onPressed: hasCoordinates || hasAddress
            ? () => widget.openMap(label, address, coordinates)
            : null,
        icon: const Icon(Icons.map_outlined),
        label: Text(label),
      ),
    );
  }
}

Widget _detailsSection(
  BuildContext context, {
  required String title,
  required IconData icon,
  required List<Widget> children,
}) {
  return Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const Divider(),
          ...children,
        ],
      ),
    ),
  );
}

Widget _detailLine(String label, String value, {bool emphasis = false}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 125,
          child: Text(label, style: const TextStyle(color: Color(0xFF6B7280))),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontWeight: emphasis ? FontWeight.bold : FontWeight.normal,
              fontSize: emphasis ? 16 : null,
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _productDetail(Map<String, dynamic> item, String currency) {
  final status = (item['status'] ?? 'available').toString().toLowerCase();
  final excluded = const {
    'rejected',
    'excluded',
    'unavailable',
    'cancelled',
  }.contains(status);
  final name = _firstNonEmpty([
    item['product_name'],
    item['productName'],
    item['name'],
    'منتج',
  ]);
  final quantity = item['quantity']?.toString() ?? '1';
  final unitPrice = item['unit_price'] ?? item['unitPrice'];
  final total = item['total'];
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: excluded ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          excluded ? '$name • مستبعد من التاجر' : name,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: excluded ? const Color(0xFFB91C1C) : null,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'الكمية: $quantity • سعر الوحدة: ${_formatAmount(unitPrice, currencySymbol: currency)}'
          '${total == null ? '' : ' • الإجمالي: ${_formatAmount(total, currencySymbol: currency)}'}',
        ),
        if ((item['rejection_reason'] ?? item['rejectionReason'])
                ?.toString()
                .trim()
                .isNotEmpty ==
            true)
          Text(
            'سبب الاستبعاد: ${item['rejection_reason'] ?? item['rejectionReason']}',
            style: const TextStyle(color: Color(0xFFB91C1C)),
          ),
      ],
    ),
  );
}

List<Map<String, dynamic>> _orderItems(Map<String, dynamic> order) {
  final rawItems = order['items'] ?? order['order_items'];
  if (rawItems is! List) return const [];
  return rawItems
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

Map<String, dynamic> _mapValue(Object? value) {
  return value is Map ? Map<String, dynamic>.from(value) : const {};
}

String _deliveryAddress(Map<String, dynamic> order) {
  final customer = _mapValue(order['customer_snapshot'] ?? order['customer']);
  final address = _firstNonEmpty([
    order['delivery_address'],
    order['shipping_address'],
    order['address'],
    customer['address'],
    customer['shipping_address'],
  ]);
  if (address.isEmpty || _isCoordinateOnlyAddress(address)) {
    return 'تفاصيل عنوان التوصيل غير متوفرة';
  }
  return address;
}

String _merchantAddress(Map<String, dynamic> merchant) {
  final address = _firstNonEmpty([
    merchant['shop_location'],
    merchant['shop_address'],
    merchant['address'],
    merchant['current_location'],
  ]);
  if (address.isEmpty || _isCoordinateOnlyAddress(address)) {
    return 'عنوان التاجر غير متوفر';
  }
  return address;
}

String _firstNonEmpty(Iterable<Object?> values) {
  for (final value in values) {
    final text = _addressText(value).trim();
    if (text.isNotEmpty &&
        text.toLowerCase() != 'null' &&
        !_isCoordinateOnlyAddress(text)) {
      return text;
    }
  }
  return '';
}

String _addressText(Object? value) {
  if (value is Map) {
    final address = _firstNonEmpty([
      value['formatted_address'],
      value['full_address'],
      value['address'],
      value['street'],
      value['district'],
      value['city'],
      value['region'],
      value['details'],
      value['landmark'],
    ]);
    return address;
  }
  return value?.toString() ?? '';
}

String? _coordinateFor(
  Map<String, dynamic> source, {
  required List<String> latitudeKeys,
  required List<String> longitudeKeys,
  required List<String> locationKeys,
}) {
  final latitude = _firstNonEmpty(latitudeKeys.map((key) => source[key]));
  final longitude = _firstNonEmpty(longitudeKeys.map((key) => source[key]));
  final direct = _validCoordinates(latitude, longitude);
  if (direct != null) return direct;
  for (final key in locationKeys) {
    final location = source[key];
    if (location is Map) {
      final nested = Map<String, dynamic>.from(location);
      final nestedCoordinates = _validCoordinates(
        _firstNonEmpty([nested['latitude'], nested['lat']]),
        _firstNonEmpty([nested['longitude'], nested['lng'], nested['lon']]),
      );
      if (nestedCoordinates != null) return nestedCoordinates;
    }
    final coordinates = _extractCoordinatePair(location?.toString() ?? '');
    if (coordinates != null) return coordinates;
  }
  return null;
}

String? _extractCoordinatePair(String value) {
  final match = RegExp(
    r'(-?\d+(?:\.\d+)?)\s*[,،]\s*(-?\d+(?:\.\d+)?)',
  ).firstMatch(value);
  if (match == null) return null;
  return _validCoordinates(match.group(1)!, match.group(2)!);
}

String? _validCoordinates(String latitude, String longitude) {
  final lat = double.tryParse(latitude);
  final lon = double.tryParse(longitude);
  if (lat == null ||
      lon == null ||
      lat < -90 ||
      lat > 90 ||
      lon < -180 ||
      lon > 180) {
    return null;
  }
  return '$lat,$lon';
}

bool _isCoordinateOnlyAddress(String value) =>
    _extractCoordinatePair(value) != null &&
    value.trim().replaceAll(RegExp(r'\s+'), '').length <= 25;

String _formatAmount(Object? value, {required String currencySymbol}) {
  final amount = value is num ? value.toDouble() : double.tryParse('$value');
  if (amount == null) return 'غير متوفر';
  final formatted =
      amount.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  return '$formatted $currencySymbol';
}

String _orderCurrency(Map<String, dynamic> order, String fallback) {
  final items = _orderItems(order);
  return _firstNonEmpty([
    order['currency_symbol'],
    order['currencySymbol'],
    if (items.isNotEmpty)
      items.first['currency_symbol'] ?? items.first['currencySymbol'],
    fallback,
  ]);
}

String _statusLabel(Object? value) {
  switch (value?.toString()) {
    case 'accepted':
      return 'مقبول';
    case 'confirmed':
      return 'مؤكد';
    case 'preparing':
      return 'قيد التجهيز';
    case 'picked_up':
      return 'تم تسليم الطلب للسائق';
    case 'shipped':
      return 'جاهز للاستلام من المتجر';
    case 'delivered':
      return 'تم التوصيل';
    case 'cancelled':
      return 'ملغي';
    case 'rejected':
      return 'مرفوض';
    default:
      return 'قيد المعالجة';
  }
}

class _OrderInfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _OrderInfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
}

class _DispatcherReportCards extends StatelessWidget {
  final DispatcherPerformanceReport report;
  final String period;
  final String currencySymbol;

  const _DispatcherReportCards({
    required this.report,
    required this.period,
    required this.currencySymbol,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = [
      ('الطلبات المسندة', report.totalAssigned, const Color(0xFF0F766E)),
      ('تم توصيلها', report.delivered, const Color(0xFF16A34A)),
      ('قيد التنفيذ', report.inProgress, const Color(0xFF2563EB)),
      ('ملغاة', report.cancelled, const Color(0xFFDC2626)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ملخص $period'),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 720 ? 4 : 2;
            final cardWidth =
                (constraints.maxWidth - (columns - 1) * 8) / columns;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: metrics
                  .map(
                    (metric) => SizedBox(
                      width: cardWidth,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                metric.$2.toString(),
                                style: TextStyle(
                                  fontSize: 23,
                                  fontWeight: FontWeight.bold,
                                  color: metric.$3,
                                ),
                              ),
                              Text(metric.$1),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: const Text('إجمالي قيمة الطلبات المسندة'),
            trailing: Text(
              '${report.totalOrderValue.toStringAsFixed(0)} $currencySymbol',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        if (report.unconvertedOrderCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'تعذّر تحويل قيمة ${report.unconvertedOrderCount} طلب إلى الريال اليمني.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  final String message;

  const _EmptyPanel({required this.message});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: Text(message)),
        ),
      );
}

class _LoadError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _LoadError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('تعذر تحميل البيانات'),
              const SizedBox(height: 6),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
}
