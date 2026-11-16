import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:she_m_app/core/animations/route_transitions.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/data/services/media_upload_service.dart';
import 'package:she_m_app/data/services/notification_service.dart';
import 'package:she_m_app/data/services/order_service.dart';
import 'package:she_m_app/presentation/admin/merchant_management_screen.dart';
import 'package:she_m_app/presentation/common/custom_appbar.dart';
import 'package:she_m_app/presentation/orders/customer_order_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    this.initialNotificationId,
    this.onAdminOrderTap,
    this.authService,
    this.notificationService,
    this.databaseService,
    super.key,
  });

  final String? initialNotificationId;
  final Future<void> Function(String orderId)? onAdminOrderTap;
  final AuthService? authService;
  final NotificationService? notificationService;
  final DatabaseService? databaseService;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final AuthService _auth;
  late final NotificationService _service;
  late final DatabaseService _databaseService;
  final Map<String, Future<List<String>>> _orderImageFutures = {};
  List<CustomerNotification> _notifications = const [];
  bool _loading = true;
  bool _unreadOnly = false;
  bool _initialNotificationHandled = false;
  String? _errorMessage;
  String? _profileRole;
  String? _profileId;

  @override
  void initState() {
    super.initState();
    _auth = widget.authService ?? AuthService();
    _service = widget.notificationService ?? NotificationService();
    _databaseService =
        widget.databaseService ?? FirebaseDatabaseService.instance;
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    if (_notifications.isEmpty && mounted) {
      setState(() => _loading = true);
    }
    try {
      final profile =
          await _auth.loadSession() ?? await _auth.getCurrentProfile();
      final profileId = profile == null
          ? ''
          : (profile.id.trim().isNotEmpty
              ? profile.id.trim()
              : profile.phone.trim());
      if (profile == null || profileId.isEmpty) {
        throw StateError('تعذر تحديد الحساب الحالي');
      }
      final notifications = await _service.getForProfile(
        profileId,
        role: profile.role,
      );
      if (!mounted) return;
      setState(() {
        _notifications = notifications;
        _profileRole = profile.role;
        _profileId = profileId;
        _errorMessage = null;
        _loading = false;
      });
      final notificationId = widget.initialNotificationId;
      if (!_initialNotificationHandled && notificationId != null) {
        _initialNotificationHandled = true;
        final matchingNotification = notifications.where(
          (notification) => notification.id == notificationId,
        );
        if (matchingNotification.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _openNotification(matchingNotification.first);
          });
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'تعذر تحميل الإشعارات. تحقق من الاتصال وحاول مجددًا.';
        _loading = false;
      });
    }
  }

  Future<void> _openNotification(CustomerNotification notification) async {
    if (!notification.isRead) {
      final marked = await _service.markAsRead(notification.id);
      if (!mounted) return;
      if (!marked) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تحديث حالة الإشعار')),
        );
      } else {
        setState(() {
          _notifications = _notifications
              .map((item) => item.id == notification.id
                  ? item.copyWith(isRead: true)
                  : item)
              .toList();
        });
      }
    }

    if (_profileRole == 'merchant' && notification.type == 'product_rejected') {
      await _openRejectedProduct(notification);
      return;
    }

    if (!mounted) return;
    final orderId = notification.orderId?.trim() ?? '';
    if (_profileRole == 'admin') {
      if (orderId.isNotEmpty && widget.onAdminOrderTap != null) {
        await widget.onAdminOrderTap!(orderId);
      } else {
        await _showNotificationDetails(notification);
      }
      return;
    }

    if (orderId.isEmpty || !mounted) return;

    if (_profileRole == 'customer') {
      await Navigator.of(context).push(
        slideFadeRoute(page: CustomerOrderDetailScreen(orderId: orderId)),
      );
    } else if (_profileRole == 'merchant') {
      final order = await OrderService().getOrderById(orderId);
      if (!mounted) return;
      if (order == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تحميل تفاصيل الطلب')),
        );
        return;
      }
      await Navigator.of(context).push(
        slideFadeRoute(
          page: MerchantOrderDetailScreen(
            order: order.toJson(),
            currencySymbol: order.currencySymbol,
          ),
        ),
      );
    }
  }

  Future<void> _showNotificationDetails(
    CustomerNotification notification,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(notification.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(notification.body.isEmpty
                  ? 'لا توجد تفاصيل إضافية لهذا الإشعار.'
                  : notification.body),
              const SizedBox(height: 16),
              _NotificationDetailLine(
                label: 'النوع',
                value: notification.type,
              ),
              if (notification.status.isNotEmpty)
                _NotificationDetailLine(
                  label: 'الحالة',
                  value: notification.status,
                ),
              if (notification.orderId?.trim().isNotEmpty == true)
                _NotificationDetailLine(
                  label: 'رقم الطلب',
                  value: notification.orderId!.trim(),
                ),
              if (notification.productId?.trim().isNotEmpty == true)
                _NotificationDetailLine(
                  label: 'معرف المنتج',
                  value: notification.productId!.trim(),
                ),
              _NotificationDetailLine(
                label: 'التاريخ',
                value: _formatTime(notification.createdAt),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Future<void> _openRejectedProduct(
    CustomerNotification notification,
  ) async {
    final productId = notification.productId?.trim() ?? '';
    final profileId = _profileId?.trim() ?? '';
    if (productId.isEmpty || profileId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحديد المنتج المرتبط بالإشعار')),
      );
      return;
    }

    try {
      final product = await _databaseService.read('products/$productId');
      final merchantId =
          (product['merchant_id'] ?? product['merchantId'] ?? '').toString();
      if (!mounted) return;
      if (product.isEmpty || merchantId != profileId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تحميل بيانات المنتج')),
        );
        return;
      }

      final productWithId = <String, dynamic>{...product, 'id': productId};
      await Navigator.of(context).push(
        slideFadeRoute(
          page: MerchantProductRejectionDetailsScreen(
            product: productWithId,
            rejectionReason: (product['review_reason'] ??
                    product['reviewReason'] ??
                    notification.body)
                .toString(),
            onEdit: () {
              Navigator.of(context).push(
                slideFadeRoute(
                  page: MerchantProductManagementScreen(
                    preselectedProduct: productWithId,
                    currencySymbol: resolveProductCurrencyLabel(productWithId),
                    openPreselectedProductForEdit: true,
                  ),
                ),
              );
            },
          ),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to load rejected merchant product: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحميل بيانات المنتج')),
      );
    }
  }

  Future<void> _markAllAsRead() async {
    final marked = await _service.markAllAsRead(
      _notifications.where((item) => !item.isRead).map((item) => item.id),
    );
    if (!mounted) return;
    if (!marked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحديث كل الإشعارات')),
      );
      await _loadNotifications();
      return;
    }
    setState(() {
      _notifications =
          _notifications.map((item) => item.copyWith(isRead: true)).toList();
    });
  }

  IconData _iconFor(CustomerNotification notification) {
    if (_isRejected(notification)) return Icons.cancel_outlined;
    if (notification.status == 'delivered') return Icons.task_alt_rounded;
    if (notification.type == 'new_order') {
      return Icons.receipt_long_rounded;
    }
    if (notification.type == 'delivery_assignment') {
      return Icons.delivery_dining_rounded;
    }
    if (notification.type == 'order_status') {
      return Icons.local_shipping_outlined;
    }
    return Icons.campaign_outlined;
  }

  Color _colorFor(CustomerNotification notification) {
    if (_isRejected(notification)) return const Color(0xFFB91C1C);
    if (notification.status == 'delivered') return const Color(0xFF15803D);
    if (_isOverdue(notification)) return const Color(0xFFB45309);
    if (notification.type == 'new_order') return const Color(0xFF047857);
    if (notification.type == 'delivery_assignment') {
      return const Color(0xFF2563EB);
    }
    if (notification.type == 'order_status') return const Color(0xFF2563EB);
    return const Color(0xFFB45309);
  }

  bool get _isManagementRole =>
      {'admin', 'manager', 'central_dispatcher'}.contains(_profileRole);

  bool _isRejected(CustomerNotification notification) {
    return {'rejected', 'cancelled', 'item_rejected'}
            .contains(notification.status) ||
        {'product_rejected', 'order_item_rejected'}.contains(notification.type);
  }

  bool _isOverdue(CustomerNotification notification) {
    if (notification.isRead ||
        _isRejected(notification) ||
        notification.status == 'delivered') {
      return false;
    }
    return DateTime.now().difference(notification.createdAt.toLocal()) >=
        const Duration(hours: 24);
  }

  Color _backgroundFor(CustomerNotification notification) {
    if (!_isManagementRole) {
      return notification.isRead ? Colors.white : const Color(0xFFFFFBEB);
    }
    if (notification.isRead) return const Color(0xFFF3F4F6);
    if (_isRejected(notification)) return const Color(0xFFFEF2F2);
    if (_isOverdue(notification)) return const Color(0xFFFFF7ED);
    if (notification.status == 'delivered') return const Color(0xFFF0FDF4);
    if (notification.type == 'new_order') return const Color(0xFFECFDF5);
    if ({
      'pending_payment',
      'awaiting_confirmation',
    }.contains(notification.status)) {
      return const Color(0xFFFFFBEB);
    }
    return const Color(0xFFEFF6FF);
  }

  String _stateLabel(CustomerNotification notification) {
    if (notification.isRead) return 'مقروء';
    if (_isRejected(notification)) return 'مرفوض';
    if (notification.status == 'delivered') return 'مكتمل';
    if (_isOverdue(notification)) return 'متأخر';
    return 'جديد';
  }

  Future<List<String>> _loadOrderImages(String orderId) async {
    try {
      final order = await _databaseService.read('orders/$orderId');
      if (_profileRole == 'merchant') {
        final profileId = _profileId?.trim() ?? '';
        if (profileId.isEmpty) return const [];
        final products = await _databaseService.read('products');
        return merchantOrderProductImages(
          order: order,
          merchantId: profileId,
          productsSnapshot: products,
        );
      }

      final rawItems = order['items'];
      final items = rawItems is List
          ? rawItems
          : rawItems is Map
              ? rawItems.values.toList()
              : const <dynamic>[];
      for (final rawItem in items) {
        if (rawItem is! Map) continue;
        final item = Map<String, dynamic>.from(rawItem);
        final image = (item['image_url'] ??
                item['imageUrl'] ??
                item['cover_image_url'] ??
                item['coverImageUrl'] ??
                '')
            .toString()
            .trim();
        if (image.isNotEmpty) return [image];
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to load order image for notification: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    return const [];
  }

  Widget _notificationLeading(
    CustomerNotification notification,
    Color color,
  ) {
    Widget iconAvatar() => CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(_iconFor(notification), color: color),
        );

    final orderId = notification.orderId?.trim() ?? '';
    if ((!_isManagementRole && _profileRole != 'merchant') ||
        notification.type != 'new_order' ||
        orderId.isEmpty) {
      return iconAvatar();
    }

    final imageFuture = _orderImageFutures.putIfAbsent(
      orderId,
      () => _loadOrderImages(orderId),
    );
    return FutureBuilder<List<String>>(
      future: imageFuture,
      builder: (context, snapshot) {
        final images = snapshot.data ?? const <String>[];
        if (_profileRole != 'merchant') {
          final imageProvider = MediaUploadService.imageProvider(
            images.isEmpty ? null : images.first,
          );
          if (imageProvider == null) return iconAvatar();
          return Semantics(
            label: 'الصورة الرئيسية لمنتج الطلب $orderId',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Image(
                  key: ValueKey('notification-product-image-$orderId'),
                  image: imageProvider,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => iconAvatar(),
                ),
              ),
            ),
          );
        }
        return MerchantOrderProductThumbnails(
          orderId: orderId,
          imageUrls: images,
          size: 48,
          placeholderColor: color,
          placeholderIcon: _iconFor(notification),
        );
      },
    );
  }

  String _formatTime(DateTime value) {
    final difference = DateTime.now().difference(value.toLocal());
    if (difference.inSeconds < 60) return 'الآن';
    if (difference.inMinutes < 60) return 'منذ ${difference.inMinutes} د';
    if (difference.inHours < 24) return 'منذ ${difference.inHours} س';
    return '${value.day}/${value.month}/${value.year}';
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount =
        _notifications.where((notification) => !notification.isRead).length;
    final visibleNotifications = _notifications
        .where((notification) => !_unreadOnly || !notification.isRead)
        .toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: CustomAppBar(
          title: 'الإشعارات',
          icon: Icons.notifications_rounded,
          actions: [
            if (unreadCount > 0)
              IconButton(
                tooltip: 'قراءة الكل',
                onPressed: _markAllAsRead,
                icon: const Icon(Icons.done_all_rounded),
              ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      unreadCount == 0
                          ? 'كل الإشعارات مقروءة'
                          : '$unreadCount إشعار غير مقروء',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  ChoiceChip(
                    label: const Text('الكل'),
                    selected: !_unreadOnly,
                    onSelected: (_) => setState(() => _unreadOnly = false),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('غير مقروء'),
                    selected: _unreadOnly,
                    onSelected: (_) => setState(() => _unreadOnly = true),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.wifi_off_rounded, size: 36),
                              const SizedBox(height: 10),
                              Text(_errorMessage!),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: _loadNotifications,
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('إعادة المحاولة'),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadNotifications,
                          child: visibleNotifications.isEmpty
                              ? ListView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  children: [
                                    SizedBox(
                                      height: 280,
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            _notifications.isEmpty
                                                ? Icons
                                                    .notifications_off_outlined
                                                : Icons.done_all_rounded,
                                            size: 42,
                                            color: const Color(0xFF9CA3AF),
                                          ),
                                          const SizedBox(height: 12),
                                          Text(_notifications.isEmpty
                                              ? 'لا توجد إشعارات حتى الآن'
                                              : 'لا توجد إشعارات غير مقروءة'),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              : ListView.separated(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 8, 16, 24),
                                  itemCount: visibleNotifications.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 8),
                                  itemBuilder: (context, index) {
                                    final notification =
                                        visibleNotifications[index];
                                    final color = _colorFor(notification);
                                    return Card(
                                      margin: EdgeInsets.zero,
                                      color: _backgroundFor(notification),
                                      child: ListTile(
                                        onTap: () =>
                                            _openNotification(notification),
                                        leading: _notificationLeading(
                                          notification,
                                          color,
                                        ),
                                        title: Text(
                                          notification.title,
                                          style: TextStyle(
                                            fontWeight: notification.isRead
                                                ? FontWeight.w600
                                                : FontWeight.w800,
                                          ),
                                        ),
                                        subtitle: Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(notification.body),
                                              const SizedBox(height: 6),
                                              Text(
                                                notification.orderId == null
                                                    ? _formatTime(
                                                        notification.createdAt)
                                                    : '${_formatTime(notification.createdAt)} • طلب ${notification.orderId}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFF6B7280),
                                                ),
                                              ),
                                              if (_isManagementRole) ...[
                                                const SizedBox(height: 6),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 8,
                                                    vertical: 3,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: color.withValues(
                                                      alpha: 0.12,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      999,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    _stateLabel(notification),
                                                    style: TextStyle(
                                                      color: color,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        trailing: notification.isRead
                                            ? null
                                            : Container(
                                                width: 8,
                                                height: 8,
                                                decoration: BoxDecoration(
                                                  color: color,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                      ),
                                    );
                                  },
                                ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationDetailLine extends StatelessWidget {
  const _NotificationDetailLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class MerchantProductRejectionDetailsScreen extends StatelessWidget {
  const MerchantProductRejectionDetailsScreen({
    required this.product,
    required this.rejectionReason,
    required this.onEdit,
    super.key,
  });

  final Map<String, dynamic> product;
  final String rejectionReason;
  final VoidCallback onEdit;

  String _value(Iterable<String> keys, {String fallback = 'غير محدد'}) {
    for (final key in keys) {
      final value = product[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return fallback;
  }

  String _listValue(Iterable<String> keys) {
    for (final key in keys) {
      final value = product[key];
      if (value is List) {
        final items = value
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList();
        if (items.isNotEmpty) return items.join('، ');
      }
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return 'غير محدد';
  }

  @override
  Widget build(BuildContext context) {
    final image = resolveProductPrimaryImage(product);
    final currency = resolveProductCurrencyLabel(product);
    final rejection =
        rejectionReason.trim().isEmpty ? 'لم يُذكر سبب الرفض' : rejectionReason;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('تفاصيل رفض المنتج')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (image.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  child: MediaUploadService.isDataUri(image)
                      ? Image.memory(
                          MediaUploadService.decodeDataUriToBytes(image) ??
                              Uint8List(0),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.image_not_supported_rounded,
                          ),
                        )
                      : Image(
                          image: CachedNetworkImageProvider(image),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.image_not_supported_rounded,
                          ),
                        ),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              _value(['name'], fallback: 'منتج'),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 12),
            Card(
              color: const Color(0xFFFEF2F2),
              child: ListTile(
                leading: const Icon(
                  Icons.error_outline_rounded,
                  color: Color(0xFFB91C1C),
                ),
                title: const Text(
                  'سبب الرفض',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(rejection),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _ProductDetailRow(
              label: 'القسم',
              value: _value([
                'subcategory',
                'category',
                'main_category',
              ]),
            ),
            _ProductDetailRow(
              label: 'السعر',
              value: '${_value(['price'], fallback: '0')} $currency',
            ),
            _ProductDetailRow(
              label: 'السعر الأصلي',
              value: _value([
                'merchant_claimed_original_price',
                'original_price',
              ]),
            ),
            _ProductDetailRow(
              label: 'المخزون',
              value: _value(['stock', 'inventory'], fallback: '0'),
            ),
            _ProductDetailRow(
              label: 'الألوان',
              value: _listValue(['colors', 'available_colors']),
            ),
            _ProductDetailRow(
              label: 'المقاسات',
              value: _listValue(['sizes', 'available_sizes']),
            ),
            _ProductDetailRow(
              label: 'الوصف',
              value: _value(['description']),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_rounded),
              label: const Text('فتح شاشة تعديل المنتج'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductDetailRow extends StatelessWidget {
  const _ProductDetailRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(value),
          ],
        ),
      ),
    );
  }
}
