import 'package:flutter/material.dart';
import 'package:she_m_app/data/services/payment_service.dart';

class OrderApprovalScreen extends StatefulWidget {
  final String orderNumber;
  final String customerName;
  final String total;
  final String? proofId;

  const OrderApprovalScreen({
    super.key,
    required this.orderNumber,
    required this.customerName,
    required this.total,
    this.proofId,
  });

  @override
  State<OrderApprovalScreen> createState() => _OrderApprovalScreenState();
}

class _OrderApprovalScreenState extends State<OrderApprovalScreen> {
  final PaymentService _paymentService = PaymentService();
  bool _isProcessing = false;
  String? _proofId;

  @override
  void initState() {
    super.initState();
    _proofId = widget.proofId;
  }

  Future<void> _reviewPayment(String status) async {
    final proofId = _proofId;
    if (proofId == null || proofId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا يوجد إثبات دفع مرتبط بهذا الطلب')),
        );
      }
      return;
    }

    setState(() => _isProcessing = true);

    await _paymentService.reviewProof(
      proofId: proofId,
      status: status,
      note: status == 'approved'
          ? 'تمت الموافقة من الإدارة'
          : 'تم رفض الإثبات من الإدارة',
    );

    if (!mounted) return;
    setState(() => _isProcessing = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          status == 'approved' ? 'تم قبول الطلب بنجاح' : 'تم رفض الطلب بنجاح',
        ),
      ),
    );
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('مراجعة الطلب')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('طلب رقم: ${widget.orderNumber}'),
                      const SizedBox(height: 8),
                      Text('العميل: ${widget.customerName}'),
                      const SizedBox(height: 8),
                      Text('الإجمالي: ${widget.total}'),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'إثبات الدفع',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  height: 220,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.image_rounded,
                      size: 72,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _proofId == null || _proofId!.isEmpty
                      ? 'لا يوجد إثبات دفع مرتبط بهذا الطلب.'
                      : 'تم رفع صورة الإيداع من العميل ويحتاج تأكيد الإدارة.',
                  style: const TextStyle(color: Color(0xFF4B5563), height: 1.6),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: (_isProcessing ||
                                _proofId == null ||
                                _proofId!.isEmpty)
                            ? null
                            : () => _reviewPayment('approved'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _isProcessing ? 'جاري المعالجة...' : 'قبول الطلب',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: (_isProcessing ||
                                _proofId == null ||
                                _proofId!.isEmpty)
                            ? null
                            : () => _reviewPayment('rejected'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFDC2626),
                          side: const BorderSide(color: Color(0xFFDC2626)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _isProcessing ? '...' : 'رفض الطلب',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
