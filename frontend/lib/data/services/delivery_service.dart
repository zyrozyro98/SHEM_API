import 'package:she_m_app/data/services/firebase_database_service.dart';

class DeliveryService {
  DeliveryService({DatabaseService? databaseService})
      : _databaseService = databaseService ?? FirebaseDatabaseService.instance;

  final DatabaseService _databaseService;

  static String statusLabel(String status) {
    switch (status) {
      case 'new':
        return 'طلب جديد';
      case 'pending':
      case 'pending_payment':
        return 'انتظار تأكيد الدفع';
      case 'awaiting_confirmation':
        return 'بانتظار الموافقة';
      case 'confirmed':
        return 'تمت الموافقة';
      case 'preparing':
        return 'قيد التجهيز';
      case 'accepted':
        return 'تم قبول الطلب';
      case 'picked_up':
        return 'تم تسليم الطلب للسائق';
      case 'shipped':
        return 'جاهز للاستلام من المتجر';
      case 'delivered':
        return 'تم توصيل المنتج للعميل';
      case 'cancelled':
        return 'ملغي';
      case 'rejected':
        return 'مرفوض';
      default:
        return 'قيد المعالجة';
    }
  }

  DateTime _parseTimestamp(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  Future<List<Map<String, dynamic>>> getCustomerDeliveries(
      String customerId) async {
    final normalizedId = customerId.trim();
    if (normalizedId.isEmpty) return const [];

    try {
      final snapshot =
          await _databaseService.read('customers/$normalizedId/orders');
      final updatesSnapshot = await _databaseService.read('delivery_updates');

      final latestUpdatesByOrder = <String, Map<String, dynamic>>{};
      for (final entry in updatesSnapshot.entries) {
        if (entry.value is! Map) continue;
        final update = Map<String, dynamic>.from(entry.value as Map);
        final orderId = update['order_id']?.toString() ?? '';
        if (orderId.isEmpty) continue;

        final current = latestUpdatesByOrder[orderId];
        final currentStamp = _parseTimestamp(current?['created_at']);
        final nextStamp = _parseTimestamp(update['created_at']);

        if (current == null || nextStamp.isAfter(currentStamp)) {
          latestUpdatesByOrder[orderId] = update;
        }
      }

      final deliveries =
          snapshot.entries.where((entry) => entry.value is Map).map((entry) {
        final order = Map<String, dynamic>.from(entry.value as Map);
        final orderId = order['id']?.toString() ?? entry.key;
        final update =
            latestUpdatesByOrder[orderId] ?? const <String, dynamic>{};
        final status = update['status']?.toString() ??
            order['status']?.toString() ??
            'pending_payment';
        final courier = update['courier_name']?.toString() ??
            order['courier_name']?.toString() ??
            order['courier']?.toString() ??
            'غير مخصص بعد';
        final eta = update['eta']?.toString() ??
            order['eta']?.toString() ??
            (status == 'delivered' ? 'مكتمل' : 'قريباً');
        final sortTime = _parseTimestamp(
          update['created_at'] ??
              order['created_at'] ??
              DateTime.now().toIso8601String(),
        );

        return {
          'order_id': orderId,
          'status': status,
          'eta': eta,
          'courier': courier,
          'sort_time': sortTime.millisecondsSinceEpoch,
        };
      }).toList();

      deliveries.sort((a, b) {
        final aTime = (a['sort_time'] as int?) ?? 0;
        final bTime = (b['sort_time'] as int?) ?? 0;
        return bTime.compareTo(aTime);
      });

      return deliveries;
    } catch (_) {
      return const [];
    }
  }
}
