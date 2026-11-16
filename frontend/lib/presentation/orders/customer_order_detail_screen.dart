import 'dart:async';

import 'package:flutter/material.dart';
import 'package:she_m_app/data/models/order_model.dart';
import 'package:she_m_app/data/models/payment_proof_model.dart';
import 'package:she_m_app/data/models/user_model.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/data/services/media_upload_service.dart';
import 'package:she_m_app/data/services/order_service.dart';
import 'package:she_m_app/data/services/payment_service.dart';
import 'package:she_m_app/presentation/common/custom_appbar.dart';
import 'package:she_m_app/presentation/common/order_number_copy_button.dart';

class CustomerOrderDetailScreen extends StatefulWidget {
  final OrderModel? order;
  final String? orderId;
  final OrderService? orderService;
  final AuthService? authService;

  const CustomerOrderDetailScreen({
    super.key,
    this.order,
    this.orderId,
    this.orderService,
    this.authService,
  }) : assert(order != null || orderId != null,
            'Either order or orderId is required');

  @override
  State<CustomerOrderDetailScreen> createState() =>
      _CustomerOrderDetailScreenState();
}

class _CustomerOrderDetailScreenState extends State<CustomerOrderDetailScreen> {
  late Future<OrderModel?> _orderFuture;
  late final Future<UserModel?> _profileFuture;
  Timer? _cancellationTimer;

  @override
  void initState() {
    super.initState();
    _orderFuture = _loadOrder();
    _profileFuture = _loadProfile();
    _cancellationTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _cancellationTimer?.cancel();
    super.dispose();
  }

  Future<OrderModel?> _loadOrder() async {
    if (widget.order != null) {
      return widget.order!;
    }

    final targetId = widget.orderId;
    if (targetId == null || targetId.isEmpty) {
      return null;
    }

    final service = widget.orderService ?? OrderService();
    return service.getOrderById(targetId);
  }

  Future<UserModel?> _loadProfile() async {
    final auth = widget.authService ?? AuthService();
    if (widget.authService != null) {
      return auth.getCurrentProfile();
    }
    return await auth.loadSession() ?? await auth.getCurrentProfile();
  }

  Future<List<PaymentProofModel>> _loadProofs(String orderId) {
    return PaymentService().getProofsForOrder(orderId);
  }

  bool _canCustomerCancel(OrderModel order) {
    const lockedStatuses = {'shipped', 'picked_up', 'delivered', 'cancelled'};
    if (lockedStatuses.contains(order.status)) return false;
    return DateTime.now().toUtc().difference(order.createdAt.toUtc()) <=
        const Duration(minutes: 15);
  }

  Future<void> _cancelOrder(OrderModel order, UserModel? profile) async {
    final customerId = profile?.id.trim().isNotEmpty == true
        ? profile!.id.trim()
        : profile?.phone.trim() ?? '';
    if (customerId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إلغاء الطلب'),
        content: const Text(
          'يمكن إلغاء الطلب خلال أول 15 دقيقة فقط وقبل تسليمه للتوصيل. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('الاحتفاظ بالطلب'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('إلغاء الطلب'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final service = widget.orderService ?? OrderService();
    final updated = await service.cancelOrderByCustomer(
      orderId: order.id,
      customerId: customerId,
    );
    if (!mounted) return;

    if (updated != null) {
      setState(() => _orderFuture = Future.value(updated));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إلغاء الطلب بنجاح')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر الإلغاء: انتهت المهلة أو بدأ تسليم الطلب'),
        ),
      );
    }
  }

  String _statusLabel(String status) {
    return switch (status) {
      'new' => 'طلب جديد',
      'pending_payment' => 'انتظار تأكيد الدفع',
      'awaiting_confirmation' => 'بانتظار الموافقة',
      'confirmed' => 'تمت الموافقة',
      'preparing' => 'قيد التجهيز',
      'shipped' => 'جاهز للاستلام من المتجر',
      'picked_up' => 'تم تسليم الطلب للسائق',
      'delivered' => 'تم توصيل المنتج للعميل',
      'cancelled' => 'ملغي',
      _ => 'قيد المراجعة',
    };
  }

  String _paymentLabel(String paymentMethod) {
    return switch (paymentMethod) {
      'cash_on_delivery' => 'الدفع عند الاستلام',
      'jib_wallet' => 'محفظة جيب',
      'wallet' => 'المحفظة',
      'card' => 'بطاقة ائتمانية',
      'bank_transfer' => 'تحويل بنكي',
      _ => 'الدفع عند الاستلام',
    };
  }

  String _paymentStatus(OrderModel order) {
    if (order.paymentMethod == 'jib_wallet' ||
        order.paymentMethod == 'wallet') {
      return switch (order.status) {
        'new' ||
        'confirmed' ||
        'preparing' ||
        'shipped' ||
        'delivered' =>
          'تم تأكيد الدفع',
        'cancelled' => 'تم رفض الدفع',
        _ => 'بانتظار مراجعة الإيصال',
      };
    }
    return order.status == 'paid' ? 'مدفوع' : 'قيد المعالجة';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OrderModel?>(
      future: _orderFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final order = snapshot.data;
        if (order == null) {
          return const Scaffold(
            body: Center(
              child: Text('تعذر العثور على بيانات الطلب'),
            ),
          );
        }

        final formattedDate =
            '${order.createdAt.day}/${order.createdAt.month}/${order.createdAt.year} - '
            '${order.createdAt.hour.toString().padLeft(2, '0')}:${order.createdAt.minute.toString().padLeft(2, '0')}';
        final orderIdShort = order.displayOrderNumber;
        final currencySymbol = order.currencySymbol;

        return FutureBuilder<UserModel?>(
          future: _profileFuture,
          builder: (context, profileSnapshot) {
            final profile = profileSnapshot.data;
            final customerName = profile?.fullName ?? 'عميل التطبيق';
            final city = profile?.city?.trim() ?? '';
            final address = profile?.address?.trim() ?? '';
            final deliveryAddress = [
              if (city.isNotEmpty) city,
              if (address.isNotEmpty) address,
            ].join('، ');
            final canCancel = _canCustomerCancel(order);
            final cancellationLocked = order.status == 'shipped' ||
                order.status == 'picked_up' ||
                order.status == 'delivered';

            return Scaffold(
              appBar: CustomAppBar(
                title: 'تفاصيل الطلب',
                icon: Icons.receipt_long_rounded,
                actions: [
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _orderFuture = _loadOrder();
                      });
                    },
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              body: Directionality(
                textDirection: TextDirection.rtl,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'طلب',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '#$orderIdShort',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF111827),
                                      ),
                                    ),
                                    OrderNumberCopyButton(
                                      orderNumber: orderIdShort,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _statusLabel(order.status),
                              style: const TextStyle(
                                color: Color(0xFF10B981),
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'تاريخ الطلب',
                              style: TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.access_time_rounded,
                                    size: 16, color: Color(0xFF6B7280)),
                                const SizedBox(width: 6),
                                Text(
                                  formattedDate,
                                  style:
                                      const TextStyle(color: Color(0xFF6B7280)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (order.status != 'cancelled') ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: canCancel
                                ? const Color(0xFFFFF7ED)
                                : const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: canCancel
                                  ? const Color(0xFFFDBA74)
                                  : const Color(0xFFD1D5DB),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                canCancel
                                    ? 'الإلغاء متاح الآن'
                                    : 'الإلغاء غير متاح',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                cancellationLocked
                                    ? 'تم تسليم الطلب للتوصيل، لذلك لا يمكن إلغاؤه.'
                                    : 'يمكن الإلغاء خلال أول 15 دقيقة من إنشاء الطلب وقبل تسليمه للتوصيل.',
                                style: const TextStyle(
                                  color: Color(0xFF4B5563),
                                  height: 1.4,
                                ),
                              ),
                              if (canCancel) ...[
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        _cancelOrder(order, profile),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFFB91C1C),
                                      side: const BorderSide(
                                        color: Color(0xFFB91C1C),
                                      ),
                                    ),
                                    icon: const Icon(Icons.close_rounded),
                                    label: const Text('إلغاء الطلب'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _InfoCard(
                        title: 'معلومات التوصيل',
                        child: Column(
                          children: [
                            _InfoRow(label: 'الاسم', value: customerName),
                            _InfoRow(
                              label: 'العنوان',
                              value: deliveryAddress.isEmpty
                                  ? 'العنوان غير مسجل'
                                  : deliveryAddress,
                            ),
                            const _InfoRow(
                              label: 'طريقة التوصيل',
                              value: 'توصيل إلى العنوان المحفوظ',
                            ),
                            _InfoRow(
                              label: 'حالة الطلب',
                              value: _statusLabel(order.status),
                            ),
                          ],
                        ),
                      ),
                      if (order.status == 'cancelled' &&
                          order.cancellationReason?.isNotEmpty == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: _InfoCard(
                            title: 'تفاصيل الإلغاء',
                            child: _InfoRow(
                              label: 'السبب',
                              value: order.cancellationReason!,
                            ),
                          ),
                        ),
                      const Text(
                        'منتجات الطلب',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      ...order.items.map((item) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 54,
                                height: 54,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD4AF37)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.shopping_bag_rounded,
                                  color: Color(0xFFD4AF37),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.productName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    if (item.selectedColor != null &&
                                        item.selectedColor!.isNotEmpty)
                                      Text(
                                        'اللون: ${item.selectedColor}',
                                        style: const TextStyle(
                                          color: Color(0xFF6B7280),
                                          fontSize: 12,
                                        ),
                                      ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'الكمية: ${item.quantity}  •  السعر: ${item.unitPrice.toStringAsFixed(0)} ${item.currencySymbol}',
                                      style: const TextStyle(
                                          color: Color(0xFF6B7280)),
                                    ),
                                    if (item.status == 'rejected')
                                      Padding(
                                        padding: const EdgeInsets.only(top: 5),
                                        child: Text(
                                          'غير متوفر — ${item.rejectionReason ?? 'نفدت الكمية'}، '
                                          'وتم استبعاده من إجمالي الطلب',
                                          style: const TextStyle(
                                            color: Color(0xFFB91C1C),
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Text(
                                item.status == 'rejected'
                                    ? 'غير محسوب'
                                    : '${item.total.toStringAsFixed(0)} ${item.currencySymbol}',
                                style: const TextStyle(
                                  color: Color(0xFF111827),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 20),
                      _InfoCard(
                        title: 'طريقة الدفع',
                        child: Column(
                          children: [
                            _InfoRow(
                              label: 'الخيار',
                              value: order.paymentWalletName?.isNotEmpty == true
                                  ? order.paymentWalletName!
                                  : _paymentLabel(order.paymentMethod),
                            ),
                            _InfoRow(
                              label: 'حالة الدفع',
                              value: _paymentStatus(order),
                            ),
                            if (order.paymentProofId != null &&
                                order.paymentProofId!.isNotEmpty)
                              FutureBuilder<List<PaymentProofModel>>(
                                future: _loadProofs(order.id),
                                builder: (context, proofSnapshot) {
                                  final proof = proofSnapshot.data
                                      ?.where((item) =>
                                          item.id == order.paymentProofId)
                                      .firstOrNull;
                                  if (proof == null) {
                                    return const _InfoRow(
                                      label: 'إيصال التحويل',
                                      value: 'قيد التحميل',
                                    );
                                  }
                                  final bytes =
                                      MediaUploadService.decodeDataUriToBytes(
                                          proof.imageUrl);
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const _InfoRow(
                                        label: 'إيصال التحويل',
                                        value: 'تم إرفاقه للمراجعة',
                                      ),
                                      if (bytes != null)
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          child: Image.memory(
                                            bytes,
                                            height: 180,
                                            width: double.infinity,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF111827),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ملخص الدفع',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'المجموع الفرعي',
                                  style: TextStyle(color: Colors.white70),
                                ),
                                Text(
                                  '${order.subtotal.toStringAsFixed(0)} $currencySymbol',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'التوصيل',
                                  style: TextStyle(color: Colors.white70),
                                ),
                                Text(
                                  '${order.shippingFee.toStringAsFixed(0)} $currencySymbol',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                            const Divider(color: Colors.white24, height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'الإجمالي',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${order.total.toStringAsFixed(0)} $currencySymbol',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _InfoCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.left,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
