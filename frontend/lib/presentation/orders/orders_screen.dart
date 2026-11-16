import 'package:flutter/material.dart';
import 'package:she_m_app/core/animations/route_transitions.dart';
import 'package:she_m_app/presentation/common/custom_appbar.dart';
import 'package:she_m_app/data/models/order_model.dart';
import 'package:she_m_app/data/models/user_model.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/data/services/order_service.dart';
import 'package:she_m_app/presentation/orders/customer_order_detail_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({
    super.key,
    this.bottomNavigationBar,
  });

  final Widget? bottomNavigationBar;

  static String? resolveCustomerId(UserModel? profile) {
    if (profile == null) {
      return null;
    }

    final id = profile.id.trim();
    if (id.isNotEmpty) {
      return id;
    }

    final phone = profile.phone.trim();
    return phone.isNotEmpty ? phone : null;
  }

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  static const int _pageSize = 8;

  final OrderService _orderService = OrderService();
  final ScrollController _scrollController = ScrollController();
  final List<OrderModel> _loadedOrders = <OrderModel>[];
  late Future<List<OrderModel>> _ordersFuture;
  int _visibleCount = _pageSize;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _ordersFuture = _loadOrders();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<List<OrderModel>> _loadOrders() async {
    final authService = AuthService();
    final profile = await authService.loadSession() ??
        await authService.getCurrentProfile();
    final customerId = OrdersScreen.resolveCustomerId(profile);
    if (customerId == null || customerId.isEmpty) {
      return const [];
    }

    final orders = await _orderService.getOrdersByCustomer(customerId)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (!mounted) return orders;
    setState(() {
      _loadedOrders.clear();
      _loadedOrders.addAll(orders);
      _visibleCount = _pageSize;
    });
    return orders;
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _visibleCount >= _loadedOrders.length) {
      return;
    }

    final position = _scrollController.position;
    if (position.extentAfter < 300) {
      setState(() {
        _visibleCount =
            (_visibleCount + _pageSize).clamp(0, _loadedOrders.length);
      });
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'new':
        return 'طلب جديد';
      case 'pending_payment':
        return 'انتظار تأكيد الدفع';
      case 'awaiting_confirmation':
        return 'بانتظار الموافقة';
      case 'confirmed':
        return 'تمت الموافقة';
      case 'preparing':
        return 'قيد التجهيز';
      case 'shipped':
        return 'جاهز للاستلام من المتجر';
      case 'picked_up':
        return 'في الطريق';
      case 'delivered':
        return 'تم التوصيل';
      case 'cancelled':
        return 'ملغي';
      default:
        return 'قيد المعالجة';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'delivered':
        return const Color(0xFF15803D);
      case 'cancelled':
        return const Color(0xFFB91C1C);
      case 'shipped':
        return const Color(0xFF2563EB);
      case 'preparing':
        return const Color(0xFFD97706);
      default:
        return const Color(0xFF7C3AED);
    }
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year} - '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'الطلبات',
        icon: Icons.receipt_long_rounded,
      ),
      bottomNavigationBar: widget.bottomNavigationBar,
      body: FutureBuilder<List<OrderModel>>(
        future: _ordersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final orders = (snapshot.data ?? _loadedOrders).toList();
          if (orders.isEmpty) {
            return const Center(
              child: Text('لا توجد طلبات في حسابك الحالي'),
            );
          }

          final visibleOrders = orders.take(_visibleCount).toList();
          final hasMore = _visibleCount < orders.length;

          return Directionality(
            textDirection: TextDirection.rtl,
            child: RefreshIndicator(
              onRefresh: () async {
                setState(() => _ordersFuture = _loadOrders());
                await _ordersFuture;
              },
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification.metrics.extentAfter < 300 &&
                      !notification.metrics.outOfRange) {
                    _handleScroll();
                  }
                  return false;
                },
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFF8F3DF), Color(0xFFFFFFFF)],
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                        ),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: const Color(0xFFE7DCC3)),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'طلباتي',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'تابع حالة كل طلبية في مكان واحد',
                                  style: TextStyle(color: Color(0xFF6B7280)),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD4AF37)
                                  .withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.receipt_long_rounded,
                              color: Color(0xFFD4AF37),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...visibleOrders.asMap().entries.map((entry) {
                      final index = entry.key;
                      final order = entry.value;
                      final orderNumber = order.displayOrderNumber;
                      final status = _statusLabel(order.status);
                      final statusColor = _statusColor(order.status);
                      final itemCount = order.items.fold<int>(
                        0,
                        (sum, item) => sum + item.quantity,
                      );
                      final rejectedItemCount = order.items
                          .where((item) => item.status == 'rejected')
                          .length;
                      final currency = order.currencySymbol;

                      return Padding(
                        padding: EdgeInsets.only(
                            bottom: index == visibleOrders.length - 1 ? 0 : 12),
                        child: InkWell(
                          onTap: () {
                            Navigator.of(context).push(
                              slideFadeRoute(
                                page: CustomerOrderDetailScreen(
                                  orderId: order.id,
                                  orderService: _orderService,
                                ),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
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
                                  child: Icon(
                                    Icons.shopping_bag_rounded,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'طلب #$orderNumber',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        rejectedItemCount == 0
                                            ? status
                                            : '$status • $rejectedItemCount منتج غير متوفر',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: statusColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        '${_formatDate(order.createdAt)}  •  $itemCount ${itemCount == 1 ? 'قطعة' : 'قطع'}',
                                        style: const TextStyle(
                                          color: Color(0xFF6B7280),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${order.total.toStringAsFixed(0)} $currency',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    const Icon(
                                      Icons.arrow_back_ios_new_rounded,
                                      size: 16,
                                      color: Color(0xFF6B7280),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    if (hasMore)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Text(
                            'جاري تحميل المزيد...',
                            style: TextStyle(
                              color: Color(0xFF6B7280),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
