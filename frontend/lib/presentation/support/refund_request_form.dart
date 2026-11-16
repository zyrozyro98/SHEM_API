import 'package:flutter/material.dart';
import 'package:she_m_app/core/errors/app_error.dart';
import 'package:she_m_app/data/models/order_model.dart';
import 'package:she_m_app/data/models/user_model.dart';
import 'package:she_m_app/data/services/support_service.dart';

class RefundRequestForm extends StatefulWidget {
  const RefundRequestForm({
    super.key,
    required this.customer,
    required this.orders,
    required this.supportService,
  });

  final UserModel customer;
  final List<OrderModel> orders;
  final SupportService supportService;

  @override
  State<RefundRequestForm> createState() => _RefundRequestFormState();
}

class _RefundRequestFormState extends State<RefundRequestForm> {
  static const List<String> _reasons = [
    'المنتج تالف أو معيب',
    'المنتج لا يطابق الوصف',
    'استلمت منتجًا مختلفًا',
    'مشكلة في الكمية أو المحتويات',
    'سبب آخر',
  ];

  final TextEditingController _messageController = TextEditingController();
  String? _selectedOrderId;
  int _selectedItemIndex = 0;
  String? _selectedReason;
  String? _errorMessage;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedOrderId = widget.orders.isEmpty ? null : widget.orders.first.id;
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  OrderModel? get _selectedOrder {
    for (final order in widget.orders) {
      if (order.id == _selectedOrderId) return order;
    }
    return null;
  }

  OrderItem? get _selectedItem {
    final order = _selectedOrder;
    if (order == null ||
        _selectedItemIndex < 0 ||
        _selectedItemIndex >= order.items.length) {
      return null;
    }
    return order.items[_selectedItemIndex];
  }

  Future<void> _submit() async {
    final order = _selectedOrder;
    final item = _selectedItem;
    final reason = _selectedReason;
    if (order == null || item == null) {
      setState(() => _errorMessage = 'اختر الطلب والمنتج المراد استرداده');
      return;
    }
    if (reason == null || _messageController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'حدد السبب واكتب تفاصيل المشكلة');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await widget.supportService.createRefundRequest(
        customerId: widget.customer.id.trim().isEmpty
            ? widget.customer.phone
            : widget.customer.id,
        orderId: order.id,
        itemIndex: _selectedItemIndex,
        reason: reason,
        customerMessage: _messageController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = AppErrorMessage.from(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _selectedOrder;
    final item = _selectedItem;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('طلب استرداد'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.orders.isEmpty)
                  const Text('لا توجد طلبات مسجلة لهذا الحساب.')
                else ...[
                  DropdownButtonFormField<String>(
                    key: const ValueKey('refund_order_selector'),
                    initialValue: _selectedOrderId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'الطلب',
                      prefixIcon: Icon(Icons.receipt_long_rounded),
                    ),
                    items: widget.orders
                        .map(
                          (order) => DropdownMenuItem(
                            value: order.id,
                            child: Text(
                              '${order.displayOrderNumber} · '
                              '${order.total.toStringAsFixed(2)} '
                              '${order.currencySymbol}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _isSubmitting
                        ? null
                        : (value) => setState(() {
                              _selectedOrderId = value;
                              _selectedItemIndex = 0;
                            }),
                  ),
                  const SizedBox(height: 12),
                  if (order != null)
                    DropdownButtonFormField<int>(
                      key: ValueKey('refund_item_selector_${order.id}'),
                      initialValue:
                          order.items.isEmpty ? null : _selectedItemIndex,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'المنتج',
                        prefixIcon: Icon(Icons.inventory_2_rounded),
                      ),
                      items: [
                        for (var index = 0; index < order.items.length; index++)
                          DropdownMenuItem(
                            value: index,
                            child: Text(
                              '${order.items[index].productName} × ${order.items[index].quantity}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _isSubmitting || order.items.isEmpty
                          ? null
                          : (value) => setState(() {
                                _selectedItemIndex = value ?? 0;
                              }),
                    ),
                  if (item != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F3E8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE8DDD0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'المبلغ المطالب به للعميل: ${item.total.toStringAsFixed(2)} ${item.currencySymbol}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'تكلفة التاجر المسجلة: ${item.merchantClaimedOriginalPrice?.toStringAsFixed(2) ?? 'غير مسجلة'} ${item.currencySymbol}',
                            style: const TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedReason,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'سبب الاسترداد',
                      prefixIcon: Icon(Icons.report_problem_outlined),
                    ),
                    items: _reasons
                        .map((reason) => DropdownMenuItem(
                              value: reason,
                              child: Text(reason),
                            ))
                        .toList(),
                    onChanged: _isSubmitting
                        ? null
                        : (value) => setState(() => _selectedReason = value),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('refund_customer_message'),
                    controller: _messageController,
                    minLines: 3,
                    maxLines: 5,
                    enabled: !_isSubmitting,
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      labelText: 'تفاصيل الطلب',
                      hintText: 'اشرح المشكلة وأرفق ما يلزم من معلومات...',
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Color(0xFFB91C1C)),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSubmitting ? null : () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: _isSubmitting || widget.orders.isEmpty ? null : _submit,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
            label: const Text('إرسال الطلب'),
          ),
        ],
      ),
    );
  }
}
