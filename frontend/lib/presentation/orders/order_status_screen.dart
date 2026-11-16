import 'package:flutter/material.dart';
import 'package:she_m_app/data/models/order_number.dart';
import 'package:she_m_app/presentation/common/custom_appbar.dart';

class OrderStatusScreen extends StatelessWidget {
  final String orderNumber;
  final String currentStatus;

  const OrderStatusScreen({
    super.key,
    required this.orderNumber,
    required this.currentStatus,
  });

  String _statusLabel(String status) {
    switch (status) {
      case 'تم الطلب':
        return 'تم الطلب';
      case 'انتظار تأكيد الدفع':
        return 'انتظار تأكيد الدفع';
      case 'تمت الموافقة':
        return 'تمت الموافقة';
      case 'قيد التجهيز':
        return 'قيد التجهيز';
      case 'تم قبول الطلب':
        return 'تم قبول الطلب';
      case 'تم استلام الطلب':
        return 'تم استلام الطلب';
      case 'في الطريق':
        return 'في الطريق';
      case 'تم التوصيل':
        return 'تم التسليم';
      case 'cancelled':
      case 'ملغي':
        return 'ملغي';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusText = _statusLabel(currentStatus);
    final statuses = statusText == 'ملغي'
        ? ['تم الطلب', 'ملغي']
        : [
            'تم الطلب',
            'انتظار تأكيد الدفع',
            'تمت الموافقة',
            'قيد التجهيز',
            'تم قبول الطلب',
            'تم استلام الطلب',
            'في الطريق',
            'تم التسليم',
          ];
    final currentIndex = statuses.indexOf(statusText);
    final safeIndex = currentIndex >= 0 ? currentIndex : 0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: const CustomAppBar(
          title: 'حالة الطلب',
          icon: Icons.local_shipping_rounded,
        ),
        body: SafeArea(
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
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'معلومات الطلب',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'رقم الطلب: '
                              '${OrderNumber.fromId(orderNumber)}',
                            ),
                            const SizedBox(height: 6),
                            Text('الحالة الحالية: $statusText'),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFD4AF37).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.local_shipping_rounded,
                          color: Color(0xFFD4AF37),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'رحلة الطلب',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 18),
                ...List.generate(statuses.length, (index) {
                  final isDone = index <= safeIndex;
                  final isCurrent = index == safeIndex;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: [
                            Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: isDone
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFE5E7EB),
                                shape: BoxShape.circle,
                              ),
                            ),
                            if (index < statuses.length - 1)
                              Container(
                                width: 2,
                                height: 34,
                                color: isDone
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFE5E7EB),
                              ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? const Color(0xFFEFF6FF)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              statuses[index],
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: isCurrent
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: isCurrent
                                    ? const Color(0xFF1F2937)
                                    : const Color(0xFF6B7280),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
