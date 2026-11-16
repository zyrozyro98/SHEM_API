import 'package:flutter/material.dart';
import 'package:she_m_app/data/models/order_number.dart';
import 'package:she_m_app/data/services/payment_service.dart';

class PaymentProofScreen extends StatefulWidget {
  final String orderNumber;
  final String total;

  const PaymentProofScreen({
    super.key,
    required this.orderNumber,
    required this.total,
  });

  @override
  State<PaymentProofScreen> createState() => _PaymentProofScreenState();
}

class _PaymentProofScreenState extends State<PaymentProofScreen> {
  bool _isUploading = false;
  final PaymentService _paymentService = PaymentService();

  String? get _currentUserId => null;
  String get _displayOrderNumber => OrderNumber.fromId(widget.orderNumber);

  Future<void> _submitProof() async {
    final userId = _currentUserId;
    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('يجب تسجيل الدخول أولاً لإرسال إثبات الدفع')),
        );
      }
      return;
    }

    setState(() => _isUploading = true);

    final response = await _paymentService.submitProofRecord(
      orderId: widget.orderNumber,
      note: 'إثبات دفع للطلب ${widget.orderNumber}',
    );

    setState(() => _isUploading = false);

    if (!mounted) return;

    if (response['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('تم تسجيل إثبات الدفع للطلب $_displayOrderNumber بنجاح'),
        ),
      );
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          response['error']?.toString() ??
              'تعذر إرسال إثبات الدفع في الوقت الحالي',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('إثبات الدفع')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'معلومات الدفع',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Text('رقم الطلب: $_displayOrderNumber'),
                      const SizedBox(height: 8),
                      Text('المبلغ: ${widget.total}'),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'رقم الحساب',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('اسم البنك: البنك اليمني'),
                      SizedBox(height: 8),
                      Text('اسم الحساب: She M Store'),
                      SizedBox(height: 8),
                      Text('رقم الحساب: 1234567890'),
                      SizedBox(height: 8),
                      Text('IBAN: YE12 0000 0000 1234 5678'),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'رفع صورة الإثبات',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'قم بتحميل صورة الإيداع أو صورة الحوالة لتأكيد الطلب.',
                        style: TextStyle(color: Color(0xFF6B7280)),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('تجهيز رفع الملف ...')),
                              );
                            }
                          },
                          icon: const Icon(Icons.upload_file_rounded),
                          label: const Text('اختر صورة'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            foregroundColor:
                                Theme.of(context).colorScheme.primary,
                            side: BorderSide(
                                color: Theme.of(context).colorScheme.primary),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isUploading ? null : _submitProof,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            _isUploading ? 'جاري الإرسال...' : 'تأكيد الدفع',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
