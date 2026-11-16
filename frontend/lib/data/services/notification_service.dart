import 'package:flutter/foundation.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';

class CustomerNotification {
  const CustomerNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.recipientRole,
    required this.orderId,
    this.productId,
    required this.status,
    required this.isRead,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String body;
  final String type;
  final String recipientRole;
  final String? orderId;
  final String? productId;
  final String status;
  final bool isRead;
  final DateTime createdAt;

  factory CustomerNotification.fromJson(String id, Map<String, dynamic> json) {
    return CustomerNotification(
      id: id,
      title: json['title']?.toString() ?? 'تحديث جديد',
      body: json['body']?.toString() ?? '',
      type: (json['type'] ?? json['kind'] ?? 'general').toString(),
      recipientRole:
          (json['recipient_role'] ?? json['recipientRole'] ?? '').toString(),
      orderId: (json['order_id'] ?? json['orderId'])?.toString(),
      productId: (json['product_id'] ?? json['productId'])?.toString(),
      status: (json['status'] ?? '').toString(),
      isRead: json['is_read'] == true ||
          json['isRead'] == true ||
          json['is_read']?.toString().toLowerCase() == 'true' ||
          json['isRead']?.toString().toLowerCase() == 'true',
      createdAt: DateTime.tryParse(
            (json['created_at'] ?? json['createdAt'] ?? '').toString(),
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  CustomerNotification copyWith({bool? isRead}) {
    return CustomerNotification(
      id: id,
      title: title,
      body: body,
      type: type,
      recipientRole: recipientRole,
      orderId: orderId,
      productId: productId,
      status: status,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }
}

class NotificationService {
  NotificationService({DatabaseService? databaseService})
      : _databaseService = databaseService ?? FirebaseDatabaseService.instance;

  final DatabaseService _databaseService;

  Future<List<CustomerNotification>> getForProfile(
    String profileId, {
    String? role,
  }) async {
    final normalizedId = profileId.trim();
    if (normalizedId.isEmpty) return const [];
    final snapshot = await _databaseService.read('notifications');
    return snapshot.entries
        .where((entry) => entry.value is Map)
        .map((entry) =>
            MapEntry(entry.key, Map<String, dynamic>.from(entry.value as Map)))
        .where((entry) {
          final recipientId = (entry.value['profile_id'] ??
                  entry.value['profileId'] ??
                  entry.value['user_id'] ??
                  entry.value['userId'])
              ?.toString();
          if (recipientId != normalizedId) return false;
          final recipientRole =
              (entry.value['recipient_role'] ?? entry.value['recipientRole'])
                  ?.toString();
          return role == null ||
              role.trim().isEmpty ||
              recipientRole == null ||
              recipientRole.isEmpty ||
              recipientRole == role;
        })
        .map((entry) => CustomerNotification.fromJson(entry.key, entry.value))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<List<CustomerNotification>> getForCustomer(String customerId) =>
      getForProfile(customerId, role: 'customer');

  Future<bool> markAsRead(String notificationId) async {
    if (notificationId.trim().isEmpty) return false;
    try {
      await _databaseService.update(
        'notifications/$notificationId',
        {'is_read': true},
      );
      return true;
    } catch (error, stackTrace) {
      debugPrint('Failed to mark notification as read: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  Future<bool> markAllAsRead(Iterable<String> notificationIds) async {
    final ids = notificationIds.where((id) => id.trim().isNotEmpty);
    final results = await Future.wait(ids.map(markAsRead));
    return results.every((result) => result);
  }

  Future<bool> notifyProfile({
    required String profileId,
    required String role,
    required String title,
    required String body,
    required String type,
    String? orderId,
    String? productId,
    String? status,
    String? eventId,
  }) async {
    final normalizedProfileId = profileId.trim();
    if (normalizedProfileId.isEmpty) return false;

    final keyPart = normalizedProfileId.replaceAll(
      RegExp(r'[^a-zA-Z0-9_-]'),
      '_',
    );
    final safeEventId = (eventId?.trim().isNotEmpty == true
            ? eventId!.trim()
            : DateTime.now().microsecondsSinceEpoch.toString())
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return _writeNotification(
      'notifications/profile-$keyPart-$safeEventId',
      {
        'profile_id': normalizedProfileId,
        'recipient_role': role.trim(),
        'title': title,
        'body': body,
        'type': type,
        if (orderId?.trim().isNotEmpty == true) 'order_id': orderId!.trim(),
        if (productId?.trim().isNotEmpty == true)
          'product_id': productId!.trim(),
        if (status?.trim().isNotEmpty == true) 'status': status!.trim(),
        'is_read': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  Future<bool> notifyOrderCreated({
    required String orderId,
    required Iterable<String> merchantIds,
  }) async {
    final normalizedOrderId = orderId.trim();
    if (normalizedOrderId.isEmpty) return false;

    final merchants =
        merchantIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet();
    final recipients = <String, String>{
      for (final merchantId in merchants) merchantId: 'merchant',
    };

    try {
      final profiles = await _databaseService.read('profiles');
      for (final entry in profiles.entries) {
        if (entry.value is! Map) continue;
        final profile = Map<String, dynamic>.from(entry.value as Map);
        final profileId = (profile['id'] ?? entry.key).toString().trim();
        final role = (profile['role'] ?? '').toString().trim();
        if (profileId.isEmpty) continue;
        if (role == 'admin' ||
            role == 'manager' ||
            role == 'central_dispatcher') {
          recipients[profileId] = role;
        }
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to load notification recipients: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }

    final safeOrderId = normalizedOrderId.replaceAll(
      RegExp(r'[^a-zA-Z0-9_-]'),
      '_',
    );
    final results = await Future.wait(
      recipients.entries.map((recipient) {
        final isMerchant = recipient.value == 'merchant';
        return notifyProfile(
          profileId: recipient.key,
          role: recipient.value,
          title: isMerchant ? 'طلب جديد لمتجرك' : 'طلب جديد يحتاج للمتابعة',
          body: isMerchant
              ? 'تم استلام طلب رقم $normalizedOrderId يحتوي على منتجات متجرك.'
              : 'تم استلام طلب رقم $normalizedOrderId ويحتاج إلى المتابعة.',
          type: 'new_order',
          orderId: normalizedOrderId,
          status: 'new',
          eventId: 'order-$safeOrderId-created',
        );
      }),
    );
    return results.every((result) => result);
  }

  Future<bool> _writeNotification(
    String path,
    Map<String, dynamic> data,
  ) async {
    try {
      await _databaseService.write(path, data);
      return true;
    } catch (error, stackTrace) {
      debugPrint('Failed to save notification: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  Future<bool> notifyOrderStatus({
    required String customerId,
    required String orderId,
    required String status,
    String? cancellationReason,
  }) async {
    final normalizedCustomerId = customerId.trim();
    final normalizedOrderId = orderId.trim();
    if (normalizedCustomerId.isEmpty || normalizedOrderId.isEmpty) {
      return false;
    }

    final title = switch (status) {
      'new' => 'تم استلام طلبك',
      'pending_payment' => 'تم استلام طلبك',
      'awaiting_confirmation' => 'إثبات الدفع قيد المراجعة',
      'confirmed' => 'تم تأكيد طلبك',
      'preparing' => 'طلبك قيد التجهيز',
      'shipped' => 'طلبك جاهز للاستلام من المتجر',
      'picked_up' => 'تم تسليم طلبك للسائق',
      'delivered' => 'تم توصيل طلبك',
      'cancelled' => 'تم إلغاء طلبك',
      'rejected' => 'تم رفض طلبك',
      _ => 'تحديث على طلبك',
    };
    final reason = cancellationReason?.trim() ?? '';
    final body = switch (status) {
      'new' => 'طلبك رقم $normalizedOrderId جديد وبانتظار تأكيد التاجر.',
      'pending_payment' => 'طلبك رقم $normalizedOrderId بانتظار تأكيد الدفع.',
      'awaiting_confirmation' =>
        'استلمنا إثبات الدفع للطلب رقم $normalizedOrderId، وسيتم مراجعته.',
      'confirmed' => 'تم تأكيد الطلب رقم $normalizedOrderId وبدء تجهيزه.',
      'preparing' => 'يجري تجهيز الطلب رقم $normalizedOrderId.',
      'shipped' => 'الطلب رقم $normalizedOrderId جاهز للاستلام من المتجر.',
      'picked_up' => 'تم تأكيد استلام السائق للطلب رقم $normalizedOrderId.',
      'delivered' =>
        'اكتمل توصيل الطلب رقم $normalizedOrderId. نتمنى لك تجربة سعيدة.',
      'cancelled' => reason.isEmpty
          ? 'تم إلغاء الطلب رقم $normalizedOrderId.'
          : 'تم إلغاء الطلب رقم $normalizedOrderId. السبب: $reason',
      'rejected' => reason.isEmpty
          ? 'تم رفض الطلب رقم $normalizedOrderId.'
          : 'تم رفض الطلب رقم $normalizedOrderId. السبب: $reason',
      _ => 'تغيرت حالة الطلب رقم $normalizedOrderId.',
    };
    final safeOrderId = normalizedOrderId.replaceAll(
      RegExp(r'[^a-zA-Z0-9_-]'),
      '_',
    );

    return _writeNotification(
      'notifications/order-$safeOrderId-$status',
      {
        'profile_id': normalizedCustomerId,
        'recipient_role': 'customer',
        'title': title,
        'body': body,
        'type': 'order_status',
        'order_id': normalizedOrderId,
        'status': status,
        'is_read': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  Future<bool> notifyOrderItemRejected({
    required String customerId,
    required String orderId,
    required String productId,
    required String productName,
    required String reason,
    required double updatedTotal,
    required String currencySymbol,
    required bool orderCancelled,
  }) async {
    final normalizedCustomerId = customerId.trim();
    final normalizedOrderId = orderId.trim();
    final normalizedProductId = productId.trim();
    if (normalizedCustomerId.isEmpty ||
        normalizedOrderId.isEmpty ||
        normalizedProductId.isEmpty) {
      return false;
    }

    final safeOrderId =
        normalizedOrderId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final safeProductId =
        normalizedProductId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final title =
        orderCancelled ? 'تعذر إتمام الطلب' : 'تم تحديث أحد منتجات طلبك';
    final body = orderCancelled
        ? 'تعذر إتمام الطلب رقم $normalizedOrderId؛ المنتج "$productName" غير متوفر ($reason).'
        : 'المنتج "$productName" غير متوفر ($reason) في الطلب رقم $normalizedOrderId. '
            'سيتم إتمام بقية المنتجات، والإجمالي الجديد '
            '${updatedTotal.toStringAsFixed(0)} $currencySymbol.';

    return _writeNotification(
      'notifications/order-$safeOrderId-item-$safeProductId-${DateTime.now().millisecondsSinceEpoch}',
      {
        'profile_id': normalizedCustomerId,
        'recipient_role': 'customer',
        'title': title,
        'body': body,
        'type': 'order_item_rejected',
        'order_id': normalizedOrderId,
        'status': 'item_rejected',
        'is_read': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  Future<bool> notifyDeliveryFeeChanged({
    required String customerId,
    required String orderId,
    required double previousFee,
    required double updatedFee,
    required String currencySymbol,
  }) async {
    final normalizedCustomerId = customerId.trim();
    final normalizedOrderId = orderId.trim();
    if (normalizedCustomerId.isEmpty || normalizedOrderId.isEmpty) {
      return false;
    }
    final safeOrderId =
        normalizedOrderId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final change = updatedFee - previousFee;
    final changeLabel = change > 0 ? 'زادت' : 'انخفضت';
    final body =
        'تم تعديل أجرة التوصيل للطلب رقم $normalizedOrderId. $changeLabel من '
        '${previousFee.toStringAsFixed(0)} إلى '
        '${updatedFee.toStringAsFixed(0)} $currencySymbol.';

    return _writeNotification(
      'notifications/order-$safeOrderId-delivery-fee-${DateTime.now().millisecondsSinceEpoch}',
      {
        'profile_id': normalizedCustomerId,
        'recipient_role': 'customer',
        'title': 'تعديل أجرة التوصيل',
        'body': body,
        'type': 'delivery_fee_changed',
        'order_id': normalizedOrderId,
        'status': 'delivery_fee_changed',
        'is_read': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }
}
