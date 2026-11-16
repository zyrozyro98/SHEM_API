import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:she_m_app/core/errors/app_error.dart';
import 'package:she_m_app/data/models/product_model.dart';
import 'package:she_m_app/data/models/promotion_model.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/data/services/catalog_service.dart';
import 'package:she_m_app/data/services/media_upload_service.dart';
import 'package:she_m_app/data/services/promotion_service.dart';

class PromotionManagementScreen extends StatefulWidget {
  const PromotionManagementScreen({super.key});

  @override
  State<PromotionManagementScreen> createState() =>
      _PromotionManagementScreenState();
}

class _PromotionManagementScreenState extends State<PromotionManagementScreen> {
  final PromotionService _service = PromotionService();
  late Future<List<PromotionModel>> _promotionsFuture;
  late Future<List<ProductModel>> _productsFuture;
  String _ownerId = '';
  bool _isAdmin = false;
  bool _isEditingPromotion = false;

  @override
  void initState() {
    super.initState();
    _productsFuture = _loadProducts();
    _reload();
  }

  Future<List<ProductModel>> _loadProducts() async {
    final profile = await AuthService().loadSession();
    if (!mounted) {
      return const [];
    }
    _ownerId = profile?.id.trim() ?? '';
    _isAdmin = profile?.role == 'admin';
    final products = await CatalogService().getProducts(forceRefresh: true);
    if (_isAdmin) return products;
    return products.where((product) => product.merchantId == _ownerId).toList();
  }

  void _reload() {
    _service.clearCache();
    setState(() => _promotionsFuture = _loadPromotions());
  }

  Future<List<PromotionModel>> _loadPromotions() async {
    final profile = await AuthService().loadSession();
    _ownerId = profile?.id.trim() ?? _ownerId;
    _isAdmin = profile?.role == 'admin' || _isAdmin;
    final promotions = await _service.getAllPromotions();
    if (_isAdmin) return promotions;
    return promotions
        .where((promotion) => promotion.merchantId == _ownerId)
        .toList();
  }

  String _approvalLabel(PromotionModel promotion) {
    switch (promotion.approvalStatus) {
      case 'approved':
        return 'معتمد ومنشور';
      case 'rejected':
        return 'مرفوض';
      case 'ignored':
        return 'متجاهل';
      default:
        return 'قيد مراجعة المسؤول';
    }
  }

  Future<void> _editPromotion([PromotionModel? promotion]) async {
    if (_isEditingPromotion) return;
    setState(() => _isEditingPromotion = true);
    try {
      final products = await _productsFuture;
      if (!mounted) return;
      final result = await showDialog<PromotionModel>(
        context: context,
        builder: (_) => _PromotionFormDialog(
          promotion: promotion,
          products: products,
          ownerId: _ownerId,
          isAdmin: _isAdmin,
        ),
      );
      if (result == null) return;
      try {
        if (promotion == null) {
          await _service.createPromotion(result);
        } else {
          await _service.updatePromotion(result);
        }
        if (!mounted) return;
        _reload();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ العرض بنجاح')),
        );
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر الحفظ: ${AppErrorMessage.from(error)}'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isEditingPromotion = false);
      }
    }
  }

  Future<void> _deletePromotion(PromotionModel promotion) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف العرض؟'),
        content: Text('سيتم حذف «${promotion.title}» نهائيًا.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service.deletePromotion(promotion.id);
    if (mounted) _reload();
  }

  Future<void> _reviewPromotion(
    PromotionModel promotion,
    String status,
  ) async {
    final reasonController = TextEditingController();
    final isApproval = status == 'approved';
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isApproval ? 'الموافقة على الإعلان' : 'مراجعة الإعلان'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isApproval
                  ? 'سيظهر الإعلان للعملاء بعد الموافقة.'
                  : 'لن يظهر الإعلان للعملاء. اكتب السبب ليعرفه التاجر.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonController,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText:
                    isApproval ? 'ملاحظة المسؤول (اختياري)' : 'سبب القرار',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final reason = reasonController.text.trim();
              if (!isApproval && reason.isEmpty) return;
              Navigator.pop(dialogContext, reason);
            },
            child: Text(isApproval ? 'موافقة ونشر' : 'حفظ القرار'),
          ),
        ],
      ),
    );
    reasonController.dispose();
    if (reason == null) return;
    try {
      await _service.updatePromotion(
        PromotionModel(
          id: promotion.id,
          title: promotion.title,
          subtitle: promotion.subtitle,
          imageUrl: promotion.imageUrl,
          productId: promotion.productId,
          merchantId: promotion.merchantId,
          isActive: isApproval,
          sortOrder: promotion.sortOrder,
          startsAt: promotion.startsAt,
          endsAt: promotion.endsAt,
          approvalStatus: status,
          reviewReason: reason,
          reviewedAt: DateTime.now(),
        ),
      );
      if (mounted) {
        _reload();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(isApproval ? 'تم نشر الإعلان' : 'تم حفظ قرار المراجعة')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر حفظ القرار: ${AppErrorMessage.from(error)}'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة العروض والإعلانات'),
        actions: [
          IconButton(
              onPressed: _reload, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isEditingPromotion ? null : () => _editPromotion(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('إضافة عرض'),
      ),
      body: FutureBuilder<List<PromotionModel>>(
        future: _promotionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'تعذر تحميل العروض: '
                '${AppErrorMessage.from(snapshot.error!)}',
              ),
            );
          }
          final promotions = snapshot.data ?? const <PromotionModel>[];
          if (promotions.isEmpty) {
            return const Center(child: Text('لا توجد عروض محفوظة بعد'));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: promotions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final promotion = promotions[index];
              return Card(
                child: ListTile(
                  leading: SizedBox(
                    width: 72,
                    height: 56,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image(
                        image: MediaUploadService.imageProvider(
                              promotion.imageUrl,
                            ) ??
                            NetworkImage(promotion.imageUrl),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.image_not_supported_rounded,
                        ),
                      ),
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(child: Text(promotion.title)),
                      if (promotion.approvalStatus == 'rejected' ||
                          promotion.approvalStatus == 'ignored')
                        const Tooltip(
                          message: 'يحتاج الإعلان إلى تعديل أو إعادة مراجعة',
                          child: Icon(Icons.warning_amber_rounded,
                              color: Colors.orange),
                        ),
                    ],
                  ),
                  subtitle: Text(
                    '${promotion.subtitle}\n${_approvalLabel(promotion)}${promotion.reviewReason.isEmpty ? '' : '\nالسبب: ${promotion.reviewReason}'}',
                  ),
                  isThreeLine: true,
                  trailing: Wrap(
                    spacing: 0,
                    children: [
                      if (_isAdmin && promotion.approvalStatus != 'approved')
                        IconButton(
                          tooltip: 'موافقة ونشر',
                          onPressed: () =>
                              _reviewPromotion(promotion, 'approved'),
                          icon: const Icon(Icons.check_circle_outline_rounded),
                        ),
                      if (_isAdmin && promotion.approvalStatus == 'pending')
                        IconButton(
                          tooltip: 'تجاهل',
                          onPressed: () =>
                              _reviewPromotion(promotion, 'ignored'),
                          icon: const Icon(Icons.pause_circle_outline_rounded),
                        ),
                      if (_isAdmin && promotion.approvalStatus != 'approved')
                        IconButton(
                          tooltip: 'رفض',
                          onPressed: () =>
                              _reviewPromotion(promotion, 'rejected'),
                          icon: const Icon(Icons.cancel_outlined),
                        ),
                      IconButton(
                        tooltip: 'تعديل',
                        onPressed: () => _editPromotion(promotion),
                        icon: const Icon(Icons.edit_rounded),
                      ),
                      IconButton(
                        tooltip: 'حذف',
                        onPressed: () => _deletePromotion(promotion),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _PromotionFormDialog extends StatefulWidget {
  const _PromotionFormDialog({
    this.promotion,
    required this.products,
    required this.ownerId,
    required this.isAdmin,
  });

  final PromotionModel? promotion;
  final List<ProductModel> products;
  final String ownerId;
  final bool isAdmin;

  @override
  State<_PromotionFormDialog> createState() => _PromotionFormDialogState();
}

class _PromotionFormDialogState extends State<_PromotionFormDialog> {
  late final TextEditingController _title;
  late final TextEditingController _subtitle;
  late final TextEditingController _sortOrder;
  late bool _isActive;
  late String _productId;
  String _imageUrl = '';
  bool _uploading = false;
  String _validationMessage = '';

  @override
  void initState() {
    super.initState();
    final promotion = widget.promotion;
    _title = TextEditingController(text: promotion?.title ?? '');
    _subtitle = TextEditingController(text: promotion?.subtitle ?? '');
    _sortOrder = TextEditingController(
      text: (promotion?.sortOrder ?? 0).toString(),
    );
    _isActive = widget.isAdmin && (promotion?.isActive ?? true);
    _productId = promotion?.productId ??
        (widget.products.length == 1 ? widget.products.first.id : '');
    _imageUrl = promotion?.imageUrl ?? '';
    _imageUrlController.text = _imageUrl;
  }

  @override
  void dispose() {
    _title.dispose();
    _subtitle.dispose();
    _imageUrlController.dispose();
    _sortOrder.dispose();
    super.dispose();
  }

  final TextEditingController _imageUrlController = TextEditingController();

  Future<void> _pickAndUploadImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _uploading = true);
    final bytes = await MediaUploadService.compactImageBytes(
      await picked.readAsBytes(),
    );
    final uploaded = bytes == null
        ? null
        : await MediaUploadService.uploadImage(
            bytes,
            fileName: 'promotion-${DateTime.now().millisecondsSinceEpoch}.jpg',
            contentType: 'image/jpeg',
            mediaType: 'promotions',
          );
    if (!mounted) return;
    setState(() {
      _uploading = false;
      if (uploaded != null) {
        _imageUrl = uploaded;
        _imageUrlController.text = uploaded;
      }
    });
    if (uploaded == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('فشل رفع صورة الإعلان إلى GitHub، حاول مرة أخرى'),
        ),
      );
    }
  }

  void _submit() {
    if (_uploading) return;
    final product = widget.products.firstWhere(
      (item) => item.id == _productId,
      orElse: () => const ProductModel(
        id: '',
        name: '',
        price: 0,
        category: '',
        description: '',
        imageUrl: '',
        available: false,
        merchantId: '',
      ),
    );
    if (_title.text.trim().isEmpty) {
      setState(() => _validationMessage = 'يرجى كتابة عنوان الإعلان');
      return;
    }
    if (_imageUrl.trim().isEmpty) {
      setState(() => _validationMessage = 'ارفع صورة الإعلان أولًا');
      return;
    }
    if (_productId.trim().isEmpty || product.id.isEmpty) {
      setState(() => _validationMessage = 'اختر المنتج المرتبط بالإعلان');
      return;
    }
    final old = widget.promotion;
    final approvalStatus =
        widget.isAdmin ? (old?.approvalStatus ?? 'approved') : 'pending';
    Navigator.pop(
      context,
      PromotionModel(
        id: old?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        title: _title.text.trim(),
        subtitle: _subtitle.text.trim(),
        imageUrl: _imageUrl.trim(),
        productId: product.id,
        merchantId: old?.merchantId.isNotEmpty == true
            ? old!.merchantId
            : widget.ownerId,
        isActive: widget.isAdmin && _isActive,
        sortOrder: widget.isAdmin
            ? int.tryParse(_sortOrder.text.trim()) ?? 0
            : (old?.sortOrder ?? 0),
        startsAt: old?.startsAt,
        endsAt: old?.endsAt,
        approvalStatus: approvalStatus,
        reviewReason: widget.isAdmin ? (old?.reviewReason ?? '') : '',
        reviewedAt: widget.isAdmin ? old?.reviewedAt : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.campaign_rounded),
          const SizedBox(width: 10),
          Text(widget.promotion == null ? 'إضافة إعلان' : 'تعديل الإعلان'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.isAdmin
                    ? 'أكمل بيانات الإعلان ثم قرر نشره للعملاء.'
                    : 'سيُرسل الإعلان للمراجعة ولن يظهر للعملاء قبل الموافقة.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
              const SizedBox(height: 18),
              TextField(
                  controller: _title,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(
                    labelText: 'عنوان الإعلان',
                    prefixIcon: Icon(Icons.title_rounded),
                    border: OutlineInputBorder(),
                  )),
              const SizedBox(height: 12),
              TextField(
                  controller: _subtitle,
                  textDirection: TextDirection.rtl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'وصف مختصر',
                    prefixIcon: Icon(Icons.notes_rounded),
                    border: OutlineInputBorder(),
                  )),
              const SizedBox(height: 14),
              TextField(
                controller: _imageUrlController,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: _imageUrl.isEmpty
                      ? 'صورة الإعلان'
                      : 'تم رفع صورة الإعلان إلى GitHub',
                  prefixIcon: const Icon(Icons.image_rounded),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: _uploading ? null : _pickAndUploadImage,
                    icon: _uploading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_rounded),
                  ),
                ),
              ),
              if (_imageUrl.isNotEmpty) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image(
                    image: MediaUploadService.imageProvider(_imageUrl)!,
                    height: 120,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: _productId.isEmpty ? null : _productId,
                decoration: const InputDecoration(
                  labelText: 'المنتج المرتبط بالإعلان',
                  helperText:
                      'عند نقر العميل على الإعلان ستفتح تفاصيل هذا المنتج',
                  prefixIcon: Icon(Icons.inventory_2_rounded),
                  border: OutlineInputBorder(),
                ),
                items: widget.products
                    .map((product) => DropdownMenuItem(
                          value: product.id,
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 15,
                                backgroundImage:
                                    MediaUploadService.imageProvider(
                                  product.imageUrl,
                                ),
                                child: product.imageUrl.isEmpty
                                    ? const Icon(Icons.image_outlined, size: 16)
                                    : null,
                              ),
                              const SizedBox(width: 10),
                              Flexible(child: Text(product.name)),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _productId = value ?? ''),
              ),
              if (_validationMessage.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  _validationMessage,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
              if (widget.isAdmin) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _sortOrder,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'ترتيب الظهور للعملاء',
                    prefixIcon: Icon(Icons.sort_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                  title: const Text('نشر الإعلان للعملاء'),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(onPressed: _submit, child: const Text('حفظ')),
      ],
    );
  }
}
