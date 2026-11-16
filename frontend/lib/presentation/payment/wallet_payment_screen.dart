import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:she_m_app/core/animations/route_transitions.dart';
import 'package:she_m_app/data/models/order_model.dart';
import 'package:she_m_app/data/models/order_number.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/data/services/cart_service.dart';
import 'package:she_m_app/data/services/media_upload_service.dart';
import 'package:she_m_app/data/services/payment_service.dart';
import 'package:she_m_app/data/services/order_service.dart';
import 'package:she_m_app/presentation/checkout/delivery_address_screen.dart';

class WalletPaymentScreen extends StatefulWidget {
  final String? orderId;
  final String? customerId;
  final List<OrderItem> items;
  final List<String> productIds;
  final double? subtotal;
  final double? shippingFee;
  final double commission;
  final PaymentService? paymentService;

  const WalletPaymentScreen({
    super.key,
    this.orderId,
    this.customerId,
    this.items = const [],
    this.productIds = const [],
    this.subtotal,
    this.shippingFee,
    this.commission = 0,
    this.paymentService,
  });

  @override
  State<WalletPaymentScreen> createState() => _WalletPaymentScreenState();
}

class _WalletPaymentScreenState extends State<WalletPaymentScreen> {
  late final PaymentService _paymentService;
  final ImagePicker _imagePicker = ImagePicker();
  final ScrollController _paymentContentController = ScrollController();
  final GlobalKey _walletDetailsKey = GlobalKey();
  List<Map<String, dynamic>> _wallets = const [];
  String? _receiptData;
  Uint8List? _receiptPreviewBytes;
  bool _isUploadingReceipt = false;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _selectedMethod;
  Object? _walletLoadError;
  String? _createdOrderId;

  String? get _activeOrderId => widget.orderId ?? _createdOrderId;
  bool get _isWalletSelected =>
      _selectedMethod != null && _selectedMethod != 'cash_on_delivery';
  Map<String, dynamic>? get _selectedWallet {
    for (final wallet in _wallets) {
      if (wallet['id']?.toString() == _selectedMethod) return wallet;
    }
    return null;
  }

  bool get _hasCheckoutDraft =>
      widget.customerId?.trim().isNotEmpty == true &&
      widget.items.isNotEmpty &&
      widget.subtotal != null &&
      widget.shippingFee != null;

  @override
  void initState() {
    super.initState();
    _paymentService = widget.paymentService ?? PaymentService();
    _loadWallets();
  }

  Future<void> _loadWallets() async {
    try {
      final wallets = (await _paymentService.getPaymentWallets())
          .where(_hasWalletDetails)
          .toList();
      if (!mounted) return;
      setState(() {
        _wallets = wallets;
        _walletLoadError = null;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _walletLoadError = error;
        _isLoading = false;
      });
    }
  }

  void _selectWallet(String id) {
    setState(() {
      _selectedMethod = id;
      _receiptData = null;
      _receiptPreviewBytes = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final detailsContext = _walletDetailsKey.currentContext;
      if (!mounted || detailsContext == null) return;
      Scrollable.ensureVisible(
        detailsContext,
        alignment: 0.1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    });
  }

  String _walletLabel(Map<String, dynamic> wallet) {
    final provider = wallet['provider']?.toString().trim() ?? '';
    if (provider == 'jib') return 'محفظة جيب';
    return provider.isNotEmpty ? provider : 'محفظة إلكترونية';
  }

  bool _hasWalletDetails(Map<String, dynamic>? wallet) {
    return wallet?['name']?.toString().trim().isNotEmpty == true &&
        wallet?['account_number']?.toString().trim().isNotEmpty == true;
  }

  String _paymentMethodFor(Map<String, dynamic> wallet) =>
      wallet['id'] == 'jib' ? 'jib_wallet' : 'wallet';

  Future<void> _pickReceipt() async {
    try {
      final file = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      final compacted = await MediaUploadService.compactImageBytes(
        bytes,
        maxWidth: 1200,
        maxHeight: 1200,
        targetSizeBytes: 240000,
        quality: 70,
      );
      if (!mounted) return;
      if (compacted == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تجهيز صورة الإيصال')),
        );
        return;
      }
      setState(() {
        _receiptPreviewBytes = compacted;
        _receiptData = null;
        _isUploadingReceipt = true;
      });
      final imageUrl = await MediaUploadService.uploadImage(
        compacted,
        fileName: file.name,
        mediaType: 'receipts',
      );
      if (!mounted) return;
      if (imageUrl == null) {
        setState(() => _isUploadingReceipt = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر رفع صورة الإيصال')),
        );
        return;
      }
      setState(() {
        _receiptData = imageUrl;
        _receiptPreviewBytes = null;
        _isUploadingReceipt = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isUploadingReceipt = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر اختيار صورة الإيصال')),
      );
    }
  }

  void _handlePickReceipt() {
    if (_isUploadingReceipt) return;
    if (!_hasWalletDetails(_selectedWallet)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('بيانات المحفظة غير مكتملة')),
      );
      return;
    }
    _pickReceipt();
  }

  void _handlePrimaryAction() {
    if (_selectedMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار طريقة الدفع أولاً')),
      );
      return;
    }

    if (_selectedMethod == 'cash_on_delivery') {
      _continueWithCashOnDelivery();
      return;
    }
    if (!_hasWalletDetails(_selectedWallet)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('بيانات المحفظة غير مكتملة')),
      );
      return;
    }
    _submitPayment();
  }

  Future<void> _submitPayment() async {
    if (_receiptData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('إرفاق صورة إيصال التحويل إلزامي')),
      );
      return;
    }

    final wallet = _selectedWallet!;
    final walletId = wallet['id'].toString();
    final walletName = _walletLabel(wallet);
    final paymentMethod = _paymentMethodFor(wallet);
    final profile = await AuthService().loadSession() ??
        await AuthService().getCurrentProfile();
    final customerId =
        widget.customerId ?? DeliveryAddressScreen.resolveCustomerId(profile);
    if (customerId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يجب تسجيل الدخول لإرسال إثبات الدفع')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final orderId = await _ensureOrderCreated(
      customerId: customerId,
      paymentMethod: paymentMethod,
      paymentWalletId: walletId,
      paymentWalletName: walletName,
      status: 'pending_payment',
    );
    if (orderId == null) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر إنشاء الطلب، حاول مرة أخرى')),
      );
      return;
    }

    final response = await _paymentService.submitProofRecord(
      orderId: orderId,
      uploadedBy: customerId,
      imageData: _receiptData!,
      note: 'تحويل عبر $walletName',
      paymentMethod: paymentMethod,
      paymentWalletId: walletId,
      paymentWalletName: walletName,
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (response['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response['error']?.toString() ?? 'تعذر إرسال الإيصال'),
        ),
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      slideFadeRoute(
        page: OrderConfirmationScreen(orderId: orderId),
      ),
    );
  }

  Future<void> _continueWithCashOnDelivery() async {
    setState(() => _isSubmitting = true);
    final hadExistingOrder = _activeOrderId != null;
    final orderId = _activeOrderId ??
        await _ensureOrderCreated(
          customerId: widget.customerId ?? '',
          paymentMethod: 'cash_on_delivery',
          status: 'new',
        );
    final updated = orderId == null
        ? null
        : hadExistingOrder
            ? (await OrderService().updatePaymentMethod(
                orderId: orderId,
                paymentMethod: 'cash_on_delivery',
                status: 'new',
                paymentWalletId: '',
                paymentWalletName: '',
              ))
                ?.id
            : orderId;
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (updated == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر اختيار الدفع عند الاستلام')),
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      slideFadeRoute(page: OrderConfirmationScreen(orderId: updated)),
    );
  }

  Future<String?> _ensureOrderCreated({
    required String customerId,
    required String paymentMethod,
    required String status,
    String? paymentWalletId,
    String? paymentWalletName,
  }) async {
    final existingOrderId = _activeOrderId;
    if (existingOrderId != null && existingOrderId.isNotEmpty) {
      return existingOrderId;
    }
    if (!_hasCheckoutDraft) return null;

    final order = await OrderService().createOrder(
      customerId: customerId,
      items: widget.items,
      paymentMethod: paymentMethod,
      subtotal: widget.subtotal!,
      shippingFee: widget.shippingFee!,
      commission: widget.commission,
      status: status,
      notifyCustomer:
          paymentMethod != 'jib_wallet' && paymentMethod != 'wallet',
      paymentWalletId: paymentWalletId,
      paymentWalletName: paymentWalletName,
    );
    if (order == null) return null;

    _createdOrderId = order.id;
    CartService.instance.removeProducts(widget.productIds);
    return order.id;
  }

  @override
  void dispose() {
    _paymentContentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedWallet = _selectedWallet;
    final walletName = selectedWallet?['name']?.toString().trim() ?? '';
    final accountNumber =
        selectedWallet?['account_number']?.toString().trim() ?? '';
    final hasWallet = _hasWalletDetails(selectedWallet);
    return Scaffold(
      appBar: AppBar(title: const Text('طرق الدفع')),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _paymentContentController,
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    'اختر طريقة الدفع',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'لن يتم إنشاء الطلب حتى تختار طريقة الدفع وتؤكدها.',
                    style: TextStyle(color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(height: 18),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const spacing = 10.0;
                      final columnCount = constraints.maxWidth >= 520
                          ? 3
                          : constraints.maxWidth < 300
                              ? 1
                              : 2;
                      final optionWidth =
                          (constraints.maxWidth - spacing * (columnCount - 1)) /
                              columnCount;
                      final options = <Widget>[
                        SizedBox(
                          width: optionWidth,
                          height: 148,
                          child: _PaymentMethodOption(
                            title: 'الدفع عند الاستلام',
                            subtitle: 'ادفع عند وصول الطلب',
                            icon: Icons.payments_outlined,
                            selected: _selectedMethod == 'cash_on_delivery',
                            onTap: () => setState(
                              () => _selectedMethod = 'cash_on_delivery',
                            ),
                          ),
                        ),
                        ..._wallets.map((wallet) {
                          final id = wallet['id']?.toString() ?? '';
                          return SizedBox(
                            width: optionWidth,
                            height: 148,
                            child: _PaymentMethodOption(
                              title: _walletLabel(wallet),
                              subtitle: 'تحويل مع إيصال',
                              icon: Icons.account_balance_wallet_outlined,
                              leading: _walletLogo(
                                wallet,
                                size: 42,
                                fallbackIcon:
                                    Icons.account_balance_wallet_outlined,
                                fallbackColor: _selectedMethod == id
                                    ? const Color(0xFF9A7B2F)
                                    : const Color(0xFF6B7280),
                              ),
                              selected: _selectedMethod == id,
                              onTap:
                                  id.isEmpty ? () {} : () => _selectWallet(id),
                            ),
                          );
                        }),
                      ];

                      return Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: options,
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  if (_activeOrderId != null && _activeOrderId!.isNotEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        'رقم الطلب: #${OrderNumber.fromId(_activeOrderId)}',
                        style: const TextStyle(
                          color: Color(0xFF166534),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  if (_selectedMethod == 'cash_on_delivery')
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle_outline_rounded,
                              color: Color(0xFF047857)),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'سيتم دفع قيمة الطلب عند استلامه.',
                              style: TextStyle(color: Color(0xFF065F46)),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_isLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (_walletLoadError != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'تعذر تحميل المحافظ. يرجى إعادة المحاولة.',
                          style: TextStyle(color: Color(0xFFB91C1C)),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _isLoading = true;
                              _walletLoadError = null;
                            });
                            _loadWallets();
                          },
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ],
                    )
                  else if (_isWalletSelected && selectedWallet == null)
                    const Text(
                      'المحفظة المحددة غير متاحة. اختر محفظة أخرى.',
                      style: TextStyle(color: Color(0xFFB91C1C)),
                    )
                  else if (_isWalletSelected && !hasWallet)
                    const Text(
                      'لم يضف المسؤول بيانات هذه المحفظة بعد. حاول لاحقًا.',
                      style: TextStyle(color: Color(0xFFB91C1C)),
                    ),
                  if (_isWalletSelected && hasWallet) ...[
                    Container(
                      key: _walletDetailsKey,
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE7DCC3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _walletLogo(
                                selectedWallet!,
                                size: 32,
                                fallbackIcon:
                                    Icons.account_balance_wallet_rounded,
                                fallbackColor: const Color(0xFF6B7280),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'بيانات ${_walletLabel(selectedWallet)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text('اسم صاحب الحساب: $walletName'),
                          const SizedBox(height: 6),
                          Text('رقم الحساب: $accountNumber'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed:
                          _isUploadingReceipt ? null : _handlePickReceipt,
                      icon: _isUploadingReceipt
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file_rounded),
                      label: Text(
                        _isUploadingReceipt
                            ? 'جار رفع الإيصال...'
                            : _receiptData == null
                                ? 'إرفاق صورة إيصال التحويل *'
                                : 'تغيير صورة الإيصال',
                      ),
                    ),
                    if (_receiptData != null ||
                        _receiptPreviewBytes != null) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image(
                          image: _receiptPreviewBytes != null
                              ? MemoryImage(_receiptPreviewBytes!)
                              : MediaUploadService.imageProvider(_receiptData)!,
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSubmitting || _isUploadingReceipt
                        ? null
                        : _handlePrimaryAction,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: const Color(0xFFD4AF37),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      _isSubmitting
                          ? 'جاري المعالجة...'
                          : switch (_selectedMethod) {
                              'cash_on_delivery' =>
                                'متابعة بالدفع عند الاستلام',
                              null => 'اختر طريقة الدفع',
                              _ => 'إرسال الإيصال للمراجعة',
                            },
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentMethodOption extends StatelessWidget {
  const _PaymentMethodOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.leading,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? leading;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFFBEB) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFFD4AF37) : const Color(0xFFE5E7EB),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 42,
              child: Center(
                child: leading ??
                    Icon(
                      icon,
                      color: selected
                          ? const Color(0xFF9A7B2F)
                          : const Color(0xFF6B7280),
                    ),
              ),
            ),
            const SizedBox(height: 6),
            Text(title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

Widget _walletLogo(
  Map<String, dynamic> wallet, {
  required double size,
  required IconData fallbackIcon,
  required Color fallbackColor,
}) {
  final logoUrl = wallet['logo_url']?.toString().trim() ?? '';
  final logoProvider = MediaUploadService.imageProvider(logoUrl);
  if (logoProvider != null) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image(
        image: logoProvider,
        key: ValueKey('wallet-logo-${wallet['id']}'),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(
          fallbackIcon,
          size: size,
          color: fallbackColor,
        ),
      ),
    );
  }
  if (wallet['id'] == 'jib') return _JibWalletLogo(size: size);
  return Icon(fallbackIcon, size: size, color: fallbackColor);
}

class _JibWalletLogo extends StatelessWidget {
  const _JibWalletLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        'assets/icon/jeep.webp',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}
