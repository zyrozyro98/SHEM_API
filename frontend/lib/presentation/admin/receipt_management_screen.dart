import 'package:flutter/material.dart';
import 'package:she_m_app/core/errors/app_error.dart';
import 'package:she_m_app/data/models/order_number.dart';
import 'package:she_m_app/data/models/payment_proof_model.dart';
import 'package:she_m_app/data/services/media_upload_service.dart';
import 'package:she_m_app/data/services/payment_service.dart';

class ReceiptManagementScreen extends StatefulWidget {
  const ReceiptManagementScreen({super.key});

  @override
  State<ReceiptManagementScreen> createState() =>
      _ReceiptManagementScreenState();
}

class _ReceiptManagementScreenState extends State<ReceiptManagementScreen> {
  final PaymentService _paymentService = PaymentService();
  late Future<List<PaymentProofModel>> _proofsFuture;
  final TextEditingController _searchController = TextEditingController();
  String _statusFilter = 'pending';
  String _query = '';

  @override
  void initState() {
    super.initState();
    _proofsFuture = _loadProofs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<PaymentProofModel>> _loadProofs() async {
    final snapshot = await _paymentService.getAllPaymentProofs();
    return snapshot;
  }

  void _refresh() {
    setState(() => _proofsFuture = _loadProofs());
  }

  Future<void> _review(PaymentProofModel proof, String status) async {
    final controller = TextEditingController();
    final isApproval = status == 'approved';
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isApproval ? 'اعتماد الإيصال' : 'رفض الإيصال'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: isApproval ? 'ملاحظة (اختياري)' : 'سبب الرفض',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (!isApproval && value.isEmpty) return;
              Navigator.pop(dialogContext, value);
            },
            child: Text(isApproval ? 'اعتماد' : 'رفض'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note == null) return;

    final result = await _paymentService.reviewProof(
      proofId: proof.id,
      status: status,
      note: note.isEmpty ? 'تمت المراجعة من الإدارة' : note,
    );
    if (!mounted) return;
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحديث حالة الإيصال')),
      );
      return;
    }
    _refresh();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(isApproval ? 'تم اعتماد الإيصال' : 'تم رفض الإيصال')),
    );
  }

  void _showReceipt(PaymentProofModel proof) {
    final provider = MediaUploadService.imageProvider(proof.imageUrl);
    if (provider == null) return;
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: Image(image: provider, fit: BoxFit.contain),
        ),
      ),
    );
  }

  List<PaymentProofModel> _filter(List<PaymentProofModel> proofs) {
    final query = _query.trim().toLowerCase();
    return proofs.where((proof) {
      final matchesStatus = _statusFilter == 'all' ||
          proof.status.trim().toLowerCase() == _statusFilter;
      final matchesQuery = query.isEmpty ||
          proof.orderId.toLowerCase().contains(query) ||
          proof.uploadedBy.toLowerCase().contains(query);
      return matchesStatus && matchesQuery;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة إيصالات الدفع'),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: FutureBuilder<List<PaymentProofModel>>(
          future: _proofsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'تعذر تحميل الإيصالات: '
                  '${AppErrorMessage.from(snapshot.error!)}',
                ),
              );
            }
            final proofs = _filter(snapshot.data ?? const []);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    labelText: 'بحث برقم الطلب أو معرف العميل',
                    prefixIcon: Icon(Icons.search_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'pending', label: Text('قيد المراجعة')),
                    ButtonSegment(value: 'approved', label: Text('معتمد')),
                    ButtonSegment(value: 'rejected', label: Text('مرفوض')),
                    ButtonSegment(value: 'all', label: Text('الكل')),
                  ],
                  selected: {_statusFilter},
                  onSelectionChanged: (value) =>
                      setState(() => _statusFilter = value.first),
                ),
                const SizedBox(height: 16),
                if (proofs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child:
                        Center(child: Text('لا توجد إيصالات في هذا التصنيف')),
                  )
                else
                  ...proofs.map(_buildProofCard),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildProofCard(PaymentProofModel proof) {
    final provider = MediaUploadService.imageProvider(proof.imageUrl);
    final isPending = proof.status == 'pending';
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long_rounded),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'الطلب ${OrderNumber.fromId(proof.orderId)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Chip(label: Text(_statusLabel(proof.status))),
              ],
            ),
            const SizedBox(height: 10),
            if (provider != null)
              InkWell(
                onTap: () => _showReceipt(proof),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: Image(image: provider, fit: BoxFit.contain),
                ),
              )
            else
              const SizedBox(
                height: 180,
                child: Center(child: Text('تعذر قراءة صورة الإيصال')),
              ),
            if (proof.note?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Text('ملاحظة العميل: ${proof.note}'),
            ],
            if (proof.reviewNote?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(
                'ملاحظة الإدارة: ${proof.reviewNote}',
                style: const TextStyle(color: Color(0xFF6B7280)),
              ),
            ],
            const SizedBox(height: 12),
            if (isPending)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _review(proof, 'approved'),
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      label: const Text('اعتماد'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _review(proof, 'rejected'),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('رفض'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'approved':
        return 'معتمد';
      case 'rejected':
        return 'مرفوض';
      default:
        return 'قيد المراجعة';
    }
  }
}
