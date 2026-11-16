import 'package:flutter/material.dart';
import 'package:she_m_app/core/errors/app_error.dart';
import 'package:she_m_app/data/models/order_number.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/data/services/support_service.dart';

class AdminRefundManagementScreen extends StatefulWidget {
  const AdminRefundManagementScreen({super.key, this.supportService});

  final SupportService? supportService;

  @override
  State<AdminRefundManagementScreen> createState() =>
      _AdminRefundManagementScreenState();
}

class _AdminRefundManagementScreenState
    extends State<AdminRefundManagementScreen> {
  late final SupportService _supportService =
      widget.supportService ?? SupportService();
  late Future<List<Map<String, dynamic>>> _requestsFuture;
  String _statusFilter = 'all';
  String _adminId = 'admin';

  @override
  void initState() {
    super.initState();
    _refresh();
    _loadAdminId();
  }

  void _refresh() {
    _requestsFuture = _supportService.getRefundRequests();
  }

  Future<void> _loadAdminId() async {
    final profile = await AuthService().loadSession();
    if (!mounted || profile == null) return;
    setState(() =>
        _adminId = profile.id.trim().isEmpty ? profile.phone : profile.id);
  }

  String _statusLabel(String status) => switch (status) {
        'under_review' => 'قيد المراجعة',
        'approved' => 'تمت الموافقة',
        'rejected' => 'مرفوض',
        _ => 'بانتظار المراجعة',
      };

  Color _statusColor(String status) => switch (status) {
        'under_review' => const Color(0xFF2563EB),
        'approved' => const Color(0xFF15803D),
        'rejected' => const Color(0xFFB91C1C),
        _ => const Color(0xFFB45309),
      };

  List<Map<String, dynamic>> _mapSnapshot(
    Map<String, dynamic> request,
    String key,
  ) {
    final value = request[key];
    return value is Map
        ? [Map<String, dynamic>.from(value)]
        : const <Map<String, dynamic>>[];
  }

  Map<String, dynamic> _snapshot(Map<String, dynamic> request, String key) {
    final values = _mapSnapshot(request, key);
    return values.isEmpty ? const {} : values.first;
  }

  String _date(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return 'غير متوفر';
    final local = parsed.toLocal();
    final date = local.toString();
    return date.length >= 16 ? date.substring(0, 16) : date;
  }

  Future<void> _openRequest(Map<String, dynamic> request) async {
    final requestedAmount = _asDouble(request['customer_claimed_amount']);
    final approvedAmountController = TextEditingController(
      text: _asDouble(request['approved_amount'] ?? requestedAmount)
          .toStringAsFixed(2),
    );
    final adminNoteController = TextEditingController(
      text: request['admin_note']?.toString() ?? '',
    );
    var isSaving = false;
    String? errorMessage;

    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            final customer = _snapshot(request, 'customer_snapshot');
            final order = _snapshot(request, 'order_snapshot');
            final product = _snapshot(request, 'product_snapshot');
            final merchant = _snapshot(request, 'merchant_snapshot');
            final orderItem = _snapshot(request, 'order_item_snapshot');
            final status = request['status']?.toString() ?? 'pending';
            final currency = request['currency_symbol']?.toString() ?? 'ر.س';

            Future<void> decide(String nextStatus) async {
              final amount = double.tryParse(
                    approvedAmountController.text.trim(),
                  ) ??
                  0;
              if (nextStatus == 'approved' && amount <= 0) {
                setDialogState(
                    () => errorMessage = 'أدخل المبلغ النهائي المستحق للعميل');
                return;
              }
              setDialogState(() {
                isSaving = true;
                errorMessage = null;
              });
              final result = await _supportService.reviewRefundRequest(
                requestId: request['id']?.toString() ?? '',
                status: nextStatus,
                approvedAmount: amount,
                adminNote: adminNoteController.text,
                reviewedBy: _adminId,
              );
              if (!dialogContext.mounted) return;
              if (result == null) {
                setDialogState(() {
                  isSaving = false;
                  errorMessage =
                      'تعذر حفظ القرار. تحقق من المبلغ وحاول مرة أخرى.';
                });
                return;
              }
              Navigator.of(dialogContext).pop(true);
            }

            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: Text('تفاصيل الاسترداد · ${request['id'] ?? ''}'),
                content: SizedBox(
                  width: 620,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _StatusBadge(
                              label: _statusLabel(status),
                              color: _statusColor(status),
                            ),
                            Chip(
                                label: Text(
                                    'أُرسل ${_date(request['created_at'])}')),
                            Chip(
                                label:
                                    Text('الطلب ${request['order_id'] ?? ''}')),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _detailSection('العميل', [
                          _detailRow('الاسم', customer['full_name']),
                          _detailRow('رقم الهاتف', customer['phone']),
                          _detailRow('البريد الإلكتروني', customer['email']),
                          _detailRow('المدينة', customer['city']),
                          _detailRow('عنوان التوصيل', customer['address']),
                          _detailRow('معرّف العميل', request['customer_id']),
                        ]),
                        _detailSection('الطلب', [
                          _detailRow(
                            'رقم الطلب',
                            OrderNumber.fromOrder(order),
                          ),
                          _detailRow('تاريخ الطلب', _date(order['created_at'])),
                          _detailRow('حالة الطلب', order['status']),
                          _detailRow('طريقة الدفع', order['payment_method']),
                          _detailRow('إجمالي الطلب',
                              '${order['total'] ?? 0} $currency'),
                          _detailRow(
                              'عنوان التسليم', order['delivery_address']),
                        ]),
                        _detailSection('المنتج ومصدره', [
                          _detailRow('اسم المنتج', product['name']),
                          _detailRow('معرّف المنتج', request['product_id']),
                          _detailRow('الفئة', product['category']),
                          _detailRow('الوصف', product['description']),
                          _detailRow('رابط الصورة', product['image_url']),
                          _detailRow(
                              'اللون المختار', orderItem['selected_color']),
                          _detailRow(
                              'المقاس المختار', orderItem['selected_size']),
                        ]),
                        _detailSection('بيانات التاجر', [
                          _detailRow('المتجر', merchant['shop_name']),
                          _detailRow('اسم التاجر', merchant['full_name']),
                          _detailRow('رقم الهاتف', merchant['phone']),
                          _detailRow('البريد الإلكتروني', merchant['email']),
                          _detailRow('معرّف التاجر', request['merchant_id']),
                        ]),
                        _detailSection('مطالبة الاسترداد', [
                          _detailRow('سبب العميل', request['reason']),
                          _detailRow(
                              'تفاصيل العميل', request['customer_message']),
                          _detailRow('الكمية', request['quantity']),
                          _detailRow('سعر البيع للوحدة',
                              '${request['unit_price'] ?? 0} $currency'),
                          _detailRow('المبلغ المطالب به للعميل',
                              '${request['customer_claimed_amount'] ?? 0} $currency'),
                          _detailRow(
                            'السعر الأصلي للوحدة المطالب به من التاجر',
                            request['merchant_claimed_original_price'] == null
                                ? 'لم يحدده التاجر'
                                : '${request['merchant_claimed_original_price']} $currency',
                          ),
                          _detailRow(
                            'إجمالي تكلفة التاجر للكمية',
                            request['merchant_claimed_total'] == null
                                ? 'غير متوفر'
                                : '${request['merchant_claimed_total']} $currency',
                          ),
                          _detailRow(
                              'آخر مراجعة', _date(request['reviewed_at'])),
                        ]),
                        const SizedBox(height: 12),
                        TextField(
                          controller: approvedAmountController,
                          enabled: !isSaving && status != 'rejected',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText:
                                'المبلغ النهائي المستحق للعميل ($currency)',
                            prefixIcon: const Icon(Icons.payments_outlined),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: adminNoteController,
                          enabled: !isSaving,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'ملاحظة المسؤول',
                            alignLabelWithHint: true,
                          ),
                        ),
                        if (errorMessage != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            errorMessage!,
                            style: const TextStyle(color: Color(0xFFB91C1C)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed:
                        isSaving ? null : () => Navigator.pop(dialogContext),
                    child: const Text('إغلاق'),
                  ),
                  if (status == 'pending')
                    OutlinedButton(
                      onPressed: isSaving ? null : () => decide('under_review'),
                      child: const Text('بدء المراجعة'),
                    ),
                  TextButton(
                    onPressed: isSaving ? null : () => decide('rejected'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFB91C1C),
                    ),
                    child: const Text('رفض الاسترداد'),
                  ),
                  FilledButton(
                    onPressed: isSaving ? null : () => decide('approved'),
                    child: isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('اعتماد الاسترداد'),
                  ),
                ],
              ),
            );
          },
        ),
      );
      if (saved == true && mounted) {
        setState(_refresh);
      }
    } finally {
      approvedAmountController.dispose();
      adminNoteController.dispose();
    }
  }

  Widget _detailSection(String title, List<Widget> rows) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const Divider(height: 16),
          ...rows,
        ],
      ),
    );
  }

  Widget _detailRow(String label, Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text == 'null') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filterOptions = <String, String>{
      'all': 'الكل',
      'pending': 'بانتظار المراجعة',
      'under_review': 'قيد المراجعة',
      'approved': 'المعتمدة',
      'rejected': 'المرفوضة',
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('طلبات الاسترداد'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: () => setState(_refresh),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  for (final entry in filterOptions.entries)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: ChoiceChip(
                        label: Text(entry.value),
                        selected: _statusFilter == entry.key,
                        onSelected: (_) =>
                            setState(() => _statusFilter = entry.key),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _requestsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final allRequests = snapshot.data ?? const [];
                  final requests = _statusFilter == 'all'
                      ? allRequests
                      : allRequests
                          .where((request) =>
                              request['status']?.toString() == _statusFilter)
                          .toList();
                  if (requests.isEmpty) {
                    return const Center(child: Text('لا توجد طلبات استرداد'));
                  }
                  return RefreshIndicator(
                    onRefresh: () async => setState(_refresh),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: requests.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final request = requests[index];
                        final product = _snapshot(request, 'product_snapshot');
                        final customer =
                            _snapshot(request, 'customer_snapshot');
                        final status =
                            request['status']?.toString() ?? 'pending';
                        return Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            key: ValueKey('refund_request_${request['id']}'),
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => _openRequest(request),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border:
                                    Border.all(color: const Color(0xFFE5E7EB)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: _statusColor(status)
                                          .withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      Icons.assignment_return_rounded,
                                      color: _statusColor(status),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          product['name']?.toString() ??
                                              'منتج غير معروف',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${customer['full_name'] ?? 'عميل'} · ${request['order_id'] ?? ''}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFF6B7280),
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${_statusLabel(status)} · ${_date(request['created_at'])}',
                                          style: TextStyle(
                                            color: _statusColor(status),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    '${request['customer_claimed_amount'] ?? 0} ${request['currency_symbol'] ?? 'ر.س'}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
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
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class SupportSettingsAdminScreen extends StatefulWidget {
  const SupportSettingsAdminScreen({super.key});

  @override
  State<SupportSettingsAdminScreen> createState() =>
      _SupportSettingsAdminScreenState();
}

class _SupportSettingsAdminScreenState
    extends State<SupportSettingsAdminScreen> {
  final SupportService _supportService = SupportService();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _whatsAppController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _hoursController = TextEditingController();
  final TextEditingController _responseTimeController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _supportService.getSupportContact();
    if (!mounted) return;
    setState(() {
      _phoneController.text = settings['phone']?.toString() ?? '';
      _whatsAppController.text = settings['whatsapp_phone']?.toString() ?? '';
      _emailController.text = settings['email']?.toString() ?? '';
      _hoursController.text = settings['working_hours']?.toString() ?? '';
      _responseTimeController.text =
          settings['response_time']?.toString() ?? '';
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _whatsAppController.dispose();
    _emailController.dispose();
    _hoursController.dispose();
    _responseTimeController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await _supportService.saveSupportContact(
        phone: _phoneController.text,
        whatsappPhone: _whatsAppController.text,
        email: _emailController.text,
        workingHours: _hoursController.text,
        responseTime: _responseTimeController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث بيانات التواصل')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                AppErrorMessage.from(error))),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة بيانات الدعم')),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    'قنوات التواصل التي تظهر للعملاء',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _phoneController,
                    enabled: !_isSaving,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'رقم الاتصال',
                      prefixIcon: Icon(Icons.call_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _whatsAppController,
                    enabled: !_isSaving,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'رقم واتساب مع مفتاح الدولة',
                      prefixIcon: Icon(Icons.chat_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _emailController,
                    enabled: !_isSaving,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'البريد الإلكتروني للدعم',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _hoursController,
                    enabled: !_isSaving,
                    decoration: const InputDecoration(
                      labelText: 'ساعات العمل',
                      prefixIcon: Icon(Icons.schedule_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _responseTimeController,
                    enabled: !_isSaving,
                    decoration: const InputDecoration(
                      labelText: 'متوسط وقت الرد',
                      prefixIcon: Icon(Icons.timer_outlined),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: const Text('حفظ بيانات الدعم'),
                  ),
                ],
              ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11),
      ),
    );
  }
}
