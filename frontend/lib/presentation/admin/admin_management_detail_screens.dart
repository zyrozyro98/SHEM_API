import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:she_m_app/core/constants/app_constants.dart';
import 'package:she_m_app/core/constants/yemeni_cities.dart';
import 'package:she_m_app/core/errors/app_error.dart';
import 'package:she_m_app/core/animations/route_transitions.dart';
import 'package:she_m_app/data/models/product_model.dart';
import 'package:she_m_app/data/models/payment_proof_model.dart';
import 'package:she_m_app/data/models/order_number.dart';
import 'package:she_m_app/data/services/admin_service.dart';
import 'package:she_m_app/data/services/account_deletion_service.dart';
import 'package:she_m_app/data/services/delivery_service.dart';
import 'package:she_m_app/data/services/media_upload_service.dart';
import 'package:she_m_app/data/services/merchant_category_service.dart';
import 'package:she_m_app/data/services/currency_service.dart';
import 'package:she_m_app/data/services/payment_service.dart';
import 'package:she_m_app/data/services/pricing_service.dart';
import 'package:she_m_app/data/services/order_service.dart';
import 'package:she_m_app/data/services/merchant_wallet_service.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/data/services/notification_service.dart';
import 'package:she_m_app/presentation/auth/phone_login_screen.dart';
import 'package:she_m_app/presentation/admin/receipt_management_screen.dart';
import 'package:she_m_app/presentation/admin/merchant_management_screen.dart';
import 'package:she_m_app/presentation/admin/admin_profile_details_screen.dart';
import 'package:she_m_app/presentation/common/app_version_list_tile.dart';
import 'package:she_m_app/presentation/common/account_switcher_button.dart';
import 'package:she_m_app/presentation/common/account_deletion_dialog.dart';
import 'package:she_m_app/presentation/common/delivery_fee_adjustment_dialog.dart';
import 'package:she_m_app/presentation/common/logout_confirmation_dialog.dart';
import 'package:she_m_app/presentation/common/notification_bell.dart';
import 'package:she_m_app/presentation/common/password_change_dialog.dart';
import 'package:she_m_app/presentation/common/product_media_fullscreen.dart';
import 'package:she_m_app/presentation/support/support_center_screen.dart';
import 'package:url_launcher/url_launcher.dart';

Map<String, dynamic> _lastMerchantCategoryMap = const {};
AdminDriverDispatchSummary? _lastDriverDispatchSummary;

List<String> resolveAdminProductImageUrls(Map<String, dynamic> product) {
  final images = <String>[];
  final seen = <String>{};

  void addImage(Object? value, {bool splitText = false}) {
    if (value is List) {
      for (final item in value) {
        addImage(item);
      }
      return;
    }
    if (value == null) return;

    final text = value.toString().trim();
    if (text.isEmpty) return;
    final values = splitText && !text.startsWith('data:')
        ? text.split(RegExp(r'[,\r\n]+'))
        : [text];
    for (final item in values) {
      final normalized = item.trim();
      if (normalized.isNotEmpty && seen.add(normalized)) {
        images.add(normalized);
      }
    }
  }

  for (final key in ['image_url', 'imageUrl', 'image']) {
    addImage(product[key], splitText: true);
  }
  for (final key in [
    'image_urls',
    'imageUrls',
    'images',
    'cover_images',
    'coverImageUrls',
    'cover_image_url',
    'coverImageUrl',
  ]) {
    addImage(product[key], splitText: true);
  }

  return images;
}

List<String> _productReviewValues(Object? value) {
  if (value is List) {
    return value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList();
  }
  return (value?.toString() ?? '')
      .split(RegExp(r'[,/|\n]+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

class AdminDetailScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<MetricCardData> metrics;
  final List<ActionRowData> rows;

  const AdminDetailScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.metrics,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF111827), Color(0xFF1F2937)],
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFFE5E7EB),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.45,
              children:
                  metrics.map((metric) => _MetricCard(metric: metric)).toList(),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'العمليات الحالية',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ...rows.map(
                    (row) => InkWell(
                      onTap: row.onTap,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: row.color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(row.icon, color: row.color),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    row.label,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    row.value,
                                    style: const TextStyle(
                                      color: Color(0xFF6B7280),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 16,
                              color: Color(0xFF9CA3AF),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PricingManagementScreen extends StatefulWidget {
  const PricingManagementScreen({super.key, this.database});

  final DatabaseService? database;

  @override
  State<PricingManagementScreen> createState() =>
      _PricingManagementScreenState();
}

class _CategoryRateRule {
  _CategoryRateRule({required this.category, String value = ''})
      : value = TextEditingController(text: value);

  String? category;
  final TextEditingController value;

  void dispose() => value.dispose();
}

class _MerchantRateRule {
  _MerchantRateRule({required this.merchantId, String value = ''})
      : value = TextEditingController(text: value);

  String? merchantId;
  final TextEditingController value;

  void dispose() => value.dispose();
}

class _ProductCommissionConflict {
  const _ProductCommissionConflict({
    required this.id,
    required this.name,
    required this.category,
    required this.merchantName,
    required this.merchantId,
    required this.price,
    required this.currencySymbol,
    required this.description,
    required this.stock,
    required this.currentMode,
    required this.currentValue,
    required this.newMode,
    required this.newValue,
  });

  final String id;
  final String name;
  final String category;
  final String merchantName;
  final String merchantId;
  final double price;
  final String currencySymbol;
  final String description;
  final String stock;
  final String currentMode;
  final double currentValue;
  final String newMode;
  final double newValue;
}

class _PricingSelectionOption {
  const _PricingSelectionOption({
    required this.id,
    required this.name,
    this.subtitle = '',
  });

  final String id;
  final String name;
  final String subtitle;

  String get searchText => '$name $id $subtitle'.toLowerCase();
}

class _PricingManagementScreenState extends State<PricingManagementScreen> {
  late final DatabaseService _database;
  late final PricingService _service;
  final _commissionValue = TextEditingController();
  final _deliveryValue = TextEditingController();
  final _baseFee = TextEditingController();
  final _perKm = TextEditingController();
  final _deliveryByRegion = TextEditingController();
  final _deliveryByMerchantRegion = TextEditingController();
  final _deliveryExemptProducts = TextEditingController();
  final _deliveryExemptMerchants = TextEditingController();
  final _freeDeliveryCommissionThreshold = TextEditingController();
  final _freeDeliveryMultiMerchantCommissionThreshold = TextEditingController();
  final _freeDeliverySingleMerchantThreshold = TextEditingController();
  final _commissionCategoryRules = <_CategoryRateRule>[];
  final _commissionMerchantRules = <_MerchantRateRule>[];
  List<String> _productCategories = const [];
  List<_PricingSelectionOption> _products = const [];
  List<_PricingSelectionOption> _merchants = const [];
  List<Map<String, dynamic>> _productRecords = const [];
  PricingConfig _loadedPricingConfig = const PricingConfig();
  String _commissionMode = 'percent';
  String _deliveryMode = 'distance';
  bool _loading = true;
  bool _saving = false;
  bool _loadFailed = false;
  final Set<String> _selectedCommissionProducts = {};

  @override
  void initState() {
    super.initState();
    _database = widget.database ?? FirebaseDatabaseService.instance;
    _service = PricingService(database: _database);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final results = await Future.wait<Object>([
        _service.load(),
        _database.read('product_categories'),
        _database.read('products'),
        _database.read('profiles'),
      ]);
      final config = results[0] as PricingConfig;
      final categoryData = results[1] as Map<String, dynamic>;
      final productData = results[2] as Map<String, dynamic>;
      final profileData = results[3] as Map<String, dynamic>;
      final productRecords = <Map<String, dynamic>>[];
      for (final entry in productData.entries) {
        if (entry.value is! Map) continue;
        productRecords.add({
          ...Map<String, dynamic>.from(entry.value as Map),
          'id': (entry.value as Map)['id']?.toString() ?? entry.key,
        });
      }
      if (!mounted) return;
      _loadedPricingConfig = config;
      _commissionMode = config.commissionMode;
      _deliveryMode = config.deliveryMode;
      _deliveryByRegion.text = config.deliveryByRegion.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join(', ');
      _deliveryByMerchantRegion.text = config.deliveryByMerchantRegion.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join(', ');
      _deliveryExemptProducts.text = config.deliveryExemptProductIds.join(', ');
      _deliveryExemptMerchants.text =
          config.deliveryExemptMerchantIds.join(', ');
      for (final rule in config.freeDeliveryRules) {
        switch (rule.type) {
          case 'vat_any':
          case 'commission_any':
            _freeDeliveryCommissionThreshold.text = rule.threshold.toString();
            break;
          case 'subtotal_single_merchant':
            _freeDeliverySingleMerchantThreshold.text =
                rule.threshold.toString();
            break;
          case 'vat_multi_merchant':
          case 'commission_multi_merchant':
            _freeDeliveryMultiMerchantCommissionThreshold.text =
                rule.threshold.toString();
            break;
        }
      }
      _commissionValue.text = config.commissionValue.toString();
      _deliveryValue.text = config.deliveryValue.toString();
      _baseFee.text = config.deliveryBaseFee.toString();
      _perKm.text = config.deliveryPerKm.toString();
      _productCategories = _productCategoryNames(categoryData);
      _products = _selectionOptions(productData);
      _merchants = _selectionOptions(
        profileData,
        isMerchant: true,
      );
      _productRecords = productRecords;
      _replaceCategoryRules(
        _commissionCategoryRules,
        config.commissionByCategory,
      );
      _replaceMerchantRules(
        _commissionMerchantRules,
        config.commissionByMerchant,
      );
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  List<_PricingSelectionOption> _selectionOptions(
    Map<String, dynamic> data, {
    bool isMerchant = false,
  }) {
    final optionsById = <String, _PricingSelectionOption>{};
    for (final entry in data.entries) {
      if (entry.value is! Map) continue;
      final value = Map<String, dynamic>.from(entry.value as Map);
      if (isMerchant &&
          (value['role'] ?? '').toString().trim().toLowerCase() != 'merchant') {
        continue;
      }
      final id = (value['id'] ?? entry.key).toString().trim();
      if (id.isEmpty) continue;
      final name = (isMerchant
              ? value['shop_name'] ?? value['shopName'] ?? value['full_name']
              : value['name'] ?? value['product_name'] ?? value['title'])
          ?.toString()
          .trim();
      final subtitle = isMerchant
          ? (value['phone'] ?? '').toString().trim()
          : (value['category'] ?? '').toString().trim();
      optionsById[id] = _PricingSelectionOption(
        id: id,
        name: name == null || name.isEmpty
            ? (isMerchant ? 'تاجر بدون اسم' : 'منتج بدون اسم')
            : name,
        subtitle: subtitle,
      );
    }
    return optionsById.values.toList()
      ..sort((first, second) {
        final byName = first.name.compareTo(second.name);
        return byName != 0 ? byName : first.id.compareTo(second.id);
      });
  }

  Future<void> _selectPricingItems({
    required String title,
    required String itemLabel,
    required List<_PricingSelectionOption> options,
    required TextEditingController controller,
  }) async {
    final selected = _parseIds(controller.text);
    final knownIds = options.map((option) => option.id).toSet();
    final availableOptions = [
      ...options,
      for (final id in selected.difference(knownIds))
        _PricingSelectionOption(
          id: id,
          name: '$itemLabel غير معروف',
        ),
    ];
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final normalizedQuery = query.trim().toLowerCase();
            final filteredOptions = availableOptions
                .where(
                  (option) =>
                      normalizedQuery.isEmpty ||
                      option.searchText.contains(normalizedQuery),
                )
                .toList();
            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 440,
                height: 440,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      onChanged: (value) => setDialogState(() => query = value),
                      decoration: InputDecoration(
                        hintText: 'ابحث بالاسم أو المعرف',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'مسح البحث',
                                onPressed: () =>
                                    setDialogState(() => query = ''),
                                icon: const Icon(Icons.close_rounded),
                              ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('المحدد: ${selected.length}'),
                        const Spacer(),
                        TextButton(
                          onPressed: selected.isEmpty
                              ? null
                              : () => setDialogState(selected.clear),
                          child: const Text('مسح التحديد'),
                        ),
                        TextButton(
                          onPressed: filteredOptions.isEmpty
                              ? null
                              : () => setDialogState(() {
                                    selected.addAll(
                                      filteredOptions
                                          .map((option) => option.id),
                                    );
                                  }),
                          child: const Text('تحديد النتائج'),
                        ),
                      ],
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: filteredOptions.isEmpty
                          ? Center(
                              child: Text(
                                availableOptions.isEmpty
                                    ? 'لا توجد $itemLabel متاحة'
                                    : 'لا توجد نتائج مطابقة للبحث',
                                textAlign: TextAlign.center,
                              ),
                            )
                          : ListView.builder(
                              itemCount: filteredOptions.length,
                              itemBuilder: (context, index) {
                                final option = filteredOptions[index];
                                final isSelected = selected.contains(option.id);
                                return CheckboxListTile(
                                  key: ValueKey('${title}_${option.id}'),
                                  value: isSelected,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  title: Text(option.name),
                                  subtitle: Text(
                                    option.subtitle.isEmpty
                                        ? 'المعرف: ${option.id}'
                                        : '${option.subtitle} • ${option.id}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onChanged: (value) {
                                    setDialogState(() {
                                      if (value == true) {
                                        selected.add(option.id);
                                      } else {
                                        selected.remove(option.id);
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    Set<String>.from(selected),
                  ),
                  child: const Text('اعتماد الاختيار'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == null || !mounted) return;
    setState(() {
      controller.text = (result.toList()..sort()).join(', ');
    });
  }

  Widget _pricingSelectionField({
    required String title,
    required String itemLabel,
    required List<_PricingSelectionOption> options,
    required TextEditingController controller,
    required IconData icon,
  }) {
    final selectedIds = _parseIds(controller.text);
    final optionsById = {for (final option in options) option.id: option};
    final visibleSelection = selectedIds
        .map(
          (id) =>
              optionsById[id] ??
              _PricingSelectionOption(
                id: id,
                name: '$itemLabel غير معروف',
              ),
        )
        .toList()
      ..sort((first, second) => first.name.compareTo(second.name));
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        selectedIds.isEmpty
                            ? 'لم يتم اختيار $itemLabel'
                            : 'تم اختيار ${selectedIds.length} $itemLabel',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _loading || _saving
                      ? null
                      : () => _selectPricingItems(
                            title: title,
                            itemLabel: itemLabel,
                            options: options,
                            controller: controller,
                          ),
                  icon: const Icon(Icons.search_rounded),
                  label: Text(selectedIds.isEmpty ? 'اختيار' : 'تعديل'),
                ),
              ],
            ),
            if (visibleSelection.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final option in visibleSelection)
                    InputChip(
                      key: ValueKey('${title}_selected_${option.id}'),
                      label: Text(option.name),
                      onDeleted: _saving
                          ? null
                          : () => setState(() {
                                selectedIds.remove(option.id);
                                controller.text =
                                    (selectedIds.toList()..sort()).join(', ');
                              }),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<String> _productCategoryNames(Map<String, dynamic> data) {
    final categories = <String>{};
    for (final value in data.values) {
      if (value is String && value.trim().isNotEmpty) {
        categories.add(value.trim());
      } else if (value is Map && value['active'] != false) {
        final rawSubcategories = value['subcategories'];
        if (rawSubcategories is Map) {
          for (final subcategory in rawSubcategories.values) {
            if (subcategory is String && subcategory.trim().isNotEmpty) {
              categories.add(subcategory.trim());
            } else if (subcategory is Map && subcategory['active'] != false) {
              final name = subcategory['name']?.toString().trim() ?? '';
              if (name.isNotEmpty) categories.add(name);
            }
          }
          continue;
        }
        final name = value['name']?.toString().trim() ?? '';
        if (name.isNotEmpty) categories.add(name);
      }
    }
    return categories.toList()..sort();
  }

  void _replaceCategoryRules(
    List<_CategoryRateRule> rules,
    Map<String, double> values,
  ) {
    for (final rule in rules) {
      rule.dispose();
    }
    rules
      ..clear()
      ..addAll(values.entries.map(
        (entry) => _CategoryRateRule(
          category: entry.key,
          value: entry.value.toString(),
        ),
      ));
  }

  void _addCategoryRule(List<_CategoryRateRule> rules) {
    final selected = rules.map((rule) => rule.category).toSet();
    final available =
        _productCategories.where((item) => !selected.contains(item));
    final category = available.isEmpty ? null : available.first;
    if (category == null) return;
    setState(() => rules.add(_CategoryRateRule(category: category)));
  }

  void _replaceMerchantRules(
    List<_MerchantRateRule> rules,
    Map<String, double> values,
  ) {
    for (final rule in rules) {
      rule.dispose();
    }
    rules
      ..clear()
      ..addAll(values.entries.map(
        (entry) => _MerchantRateRule(
          merchantId: entry.key,
          value: entry.value.toString(),
        ),
      ));
  }

  void _addMerchantRule() {
    final selected = _commissionMerchantRules
        .map((rule) => rule.merchantId)
        .whereType<String>()
        .toSet();
    final available =
        _merchants.where((option) => !selected.contains(option.id)).toList();
    if (available.isEmpty) return;
    setState(() => _commissionMerchantRules.add(
          _MerchantRateRule(merchantId: available.first.id),
        ));
  }

  List<Widget> _merchantCommissionFields() {
    return [
      for (var index = 0; index < _commissionMerchantRules.length; index++)
        Row(
          key: ObjectKey(_commissionMerchantRules[index]),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                key: ValueKey('merchant-commission-merchant-$index'),
                initialValue: _commissionMerchantRules[index].merchantId,
                decoration: const InputDecoration(labelText: 'التاجر'),
                items: {
                  ..._merchants.map((merchant) => merchant.id),
                  if (_commissionMerchantRules[index].merchantId != null)
                    _commissionMerchantRules[index].merchantId!,
                }.map((merchantId) {
                  final options = _merchants
                      .where((merchant) => merchant.id == merchantId)
                      .toList();
                  final option = options.isEmpty ? null : options.first;
                  final usedElsewhere =
                      _commissionMerchantRules.asMap().entries.any(
                            (entry) =>
                                entry.key != index &&
                                entry.value.merchantId == merchantId,
                          );
                  return DropdownMenuItem<String>(
                    value: merchantId,
                    enabled: !usedElsewhere,
                    child: Text(
                      option?.name ?? 'تاجر غير معروف ($merchantId)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (merchantId) {
                  if (merchantId == null) return;
                  setState(() =>
                      _commissionMerchantRules[index].merchantId = merchantId);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(
                key: ValueKey('merchant-commission-value-$index'),
                controller: _commissionMerchantRules[index].value,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: _commissionMode == 'percent'
                      ? 'النسبة (%)'
                      : 'المبلغ (ر.ي)',
                ),
              ),
            ),
            IconButton(
              tooltip: 'حذف عمولة التاجر',
              onPressed: () => setState(() {
                _commissionMerchantRules.removeAt(index).dispose();
              }),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      if (_commissionMerchantRules.length < _merchants.length)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: _addMerchantRule,
            icon: const Icon(Icons.add),
            label: const Text('إضافة تاجر'),
          ),
        ),
      if (_merchants.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('لا يوجد تجار لاختيارهم'),
        ),
    ];
  }

  Map<String, double>? _merchantRuleValues() {
    final values = <String, double>{};
    for (final rule in _commissionMerchantRules) {
      final merchantId = rule.merchantId;
      final raw = rule.value.text.trim();
      if (raw.isEmpty) continue;
      final amount = double.tryParse(raw);
      if (merchantId == null ||
          amount == null ||
          !amount.isFinite ||
          amount < 0 ||
          values.containsKey(merchantId)) {
        return null;
      }
      values[merchantId] = amount;
    }
    return values;
  }

  List<Widget> _categoryRuleFields(
    List<_CategoryRateRule> rules,
  ) {
    return [
      for (var index = 0; index < rules.length; index++)
        Row(
          key: ObjectKey(rules[index]),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                initialValue: rules[index].category,
                decoration: const InputDecoration(labelText: 'الفئة'),
                items: {
                  ..._productCategories,
                  if (rules[index].category != null) rules[index].category!,
                }.map((category) {
                  final usedElsewhere = rules.asMap().entries.any(
                        (entry) =>
                            entry.key != index &&
                            entry.value.category == category,
                      );
                  return DropdownMenuItem<String>(
                    value: category,
                    enabled: !usedElsewhere,
                    child: Text(category),
                  );
                }).toList(),
                onChanged: (category) {
                  if (category == null) return;
                  setState(() => rules[index].category = category);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(
                key: ValueKey('category-commission-value-$index'),
                controller: rules[index].value,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: _commissionMode == 'percent'
                      ? 'النسبة (%)'
                      : 'المبلغ (ر.ي)',
                ),
              ),
            ),
            IconButton(
              tooltip: 'حذف قاعدة الفئة',
              onPressed: () => setState(() {
                rules.removeAt(index).dispose();
              }),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      if (_productCategories
          .any((category) => !rules.any((rule) => rule.category == category)))
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => _addCategoryRule(rules),
            icon: const Icon(Icons.add),
            label: const Text('إضافة فئة'),
          ),
        ),
      if (_productCategories.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('لا توجد فئات منتجات نشطة للاختيار منها'),
        ),
    ];
  }

  Map<String, double>? _categoryRuleValues(
    List<_CategoryRateRule> rules,
  ) {
    final values = <String, double>{};
    for (final rule in rules) {
      final category = rule.category;
      final raw = rule.value.text.trim();
      if (raw.isEmpty) continue;
      final amount = double.tryParse(raw);
      if (category == null ||
          amount == null ||
          !amount.isFinite ||
          amount < 0 ||
          values.containsKey(category)) {
        return null;
      }
      values[category] = amount;
    }
    return values;
  }

  @override
  void dispose() {
    _commissionValue.dispose();
    _deliveryValue.dispose();
    _baseFee.dispose();
    _perKm.dispose();
    _deliveryByRegion.dispose();
    _deliveryByMerchantRegion.dispose();
    _deliveryExemptProducts.dispose();
    _deliveryExemptMerchants.dispose();
    _freeDeliveryCommissionThreshold.dispose();
    _freeDeliverySingleMerchantThreshold.dispose();
    _freeDeliveryMultiMerchantCommissionThreshold.dispose();
    for (final rule in _commissionCategoryRules) {
      rule.dispose();
    }
    for (final rule in _commissionMerchantRules) {
      rule.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final commissionCategoryRules = _categoryRuleValues(
      _commissionCategoryRules,
    );
    if (commissionCategoryRules == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تحقق من قيمة العمولة لكل فئة'),
        ),
      );
      return;
    }
    final commissionMerchantRules = _merchantRuleValues();
    if (commissionMerchantRules == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تحقق من قيمة العمولة لكل تاجر')),
      );
      return;
    }
    final commissionValue = double.tryParse(_commissionValue.text.trim());
    if (commissionValue == null ||
        !commissionValue.isFinite ||
        commissionValue < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل قيمة عمولة عامة صحيحة وغير سالبة')),
      );
      return;
    }
    final deliveryByRegion = _parseDeliveryFees(_deliveryByRegion.text);
    final deliveryByMerchantRegion =
        _parseDeliveryFees(_deliveryByMerchantRegion.text);
    if (deliveryByRegion == null || deliveryByMerchantRegion == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تحقق من أسعار المناطق: اسم المنطقة=سعر التوصيل'),
        ),
      );
      return;
    }
    final freeDeliveryRules = <FreeDeliveryRule>[];
    final freeDeliveryThresholds = <(String, TextEditingController)>[
      ('commission_any', _freeDeliveryCommissionThreshold),
      ('subtotal_single_merchant', _freeDeliverySingleMerchantThreshold),
      (
        'commission_multi_merchant',
        _freeDeliveryMultiMerchantCommissionThreshold
      ),
    ];
    for (final (type, controller) in freeDeliveryThresholds) {
      final raw = controller.text.trim();
      if (raw.isEmpty) continue;
      final threshold = double.tryParse(raw);
      if (threshold == null || !threshold.isFinite || threshold < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('أدخل حدود التوصيل المجاني بشكل صحيح')),
        );
        return;
      }
      freeDeliveryRules.add(FreeDeliveryRule(type: type, threshold: threshold));
    }
    double? parseNonNegative(TextEditingController controller) {
      final raw = controller.text.trim();
      if (raw.isEmpty) return 0;
      final value = double.tryParse(raw);
      return value != null && value.isFinite && value >= 0 ? value : null;
    }

    final deliveryValue = parseNonNegative(_deliveryValue);
    final baseFee = parseNonNegative(_baseFee);
    final deliveryPerKm = parseNonNegative(_perKm);
    if (deliveryValue == null || baseFee == null || deliveryPerKm == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('أدخل قيم توصيل رقمية صحيحة وغير سالبة'),
        ),
      );
      return;
    }
    final config = PricingConfig(
      commissionMode: _commissionMode,
      commissionValue: commissionValue,
      deliveryMode: _deliveryMode,
      deliveryValue: deliveryValue,
      deliveryBaseFee: baseFee,
      deliveryPerKm: deliveryPerKm,
      merchantDisplayDeliveryFee:
          _loadedPricingConfig.merchantDisplayDeliveryFee,
      commissionByCategory: commissionCategoryRules,
      commissionByMerchant: commissionMerchantRules,
      deliveryByRegion: deliveryByRegion,
      deliveryByMerchantRegion: deliveryByMerchantRegion,
      deliveryExemptProductIds: _parseIds(_deliveryExemptProducts.text),
      deliveryExemptMerchantIds: _parseIds(_deliveryExemptMerchants.text),
      freeDeliveryRules: freeDeliveryRules,
    );
    final conflicts = _commissionConflicts(config);
    final productsToUseNewCommission = conflicts.isEmpty
        ? <String>{}
        : await _confirmCommissionConflicts(conflicts);
    if (productsToUseNewCommission == null) return;
    if (mounted) setState(() => _saving = true);
    final saved = await _service.save(config);
    if (!mounted) return;
    if (!saved) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حفظ سياسة الأسعار')),
      );
      return;
    }

    final failedProducts = <String>[];
    for (final productId in productsToUseNewCommission) {
      try {
        await _database.update('products/$productId', {
          'commission_mode_override': null,
          'commission_value_override': null,
        });
        for (final product in _productRecords) {
          if (product['id']?.toString() != productId) continue;
          product
            ..remove('commission_mode_override')
            ..remove('commission_value_override');
          break;
        }
      } catch (_) {
        failedProducts.add(productId);
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (failedProducts.isEmpty) {
      _loadedPricingConfig = config;
      await _load();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failedProducts.isEmpty
              ? productsToUseNewCommission.isEmpty
                  ? 'تم حفظ سياسة الأسعار'
                  : 'تم حفظ السياسة وتطبيق العمولة الجديدة على المنتجات المحددة'
              : 'تم حفظ السياسة، لكن تعذر تطبيق العمولة الجديدة على المنتجات: '
                  '${failedProducts.join('، ')}. بقيت عمولاتها الخاصة محفوظة.',
        ),
      ),
    );
  }

  Map<String, double>? _parseDeliveryFees(String value) {
    final result = <String, double>{};
    if (value.trim().isEmpty) return result;
    for (final rule in value.split(',')) {
      final parts = rule.split('=').map((part) => part.trim()).toList();
      if (parts.length != 2 ||
          parts.first.isEmpty ||
          result.containsKey(parts.first)) {
        return null;
      }
      final fee = double.tryParse(parts.last);
      if (fee == null || !fee.isFinite || fee < 0) return null;
      result[parts.first] = fee;
    }
    return result;
  }

  Set<String> _parseIds(String value) => value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet();

  ({String mode, double value}) _rateWithoutProductOverride(
    PricingConfig config,
    String category,
    String merchantId,
  ) {
    final merchantRate = config.commissionByMerchant[merchantId];
    if (merchantRate != null) {
      return (mode: config.commissionMode, value: merchantRate);
    }
    final categoryRate = config.commissionByCategory[category];
    if (categoryRate != null) {
      return (mode: config.commissionMode, value: categoryRate);
    }
    return (mode: config.commissionMode, value: config.commissionValue);
  }

  List<_ProductCommissionConflict> _commissionConflicts(
    PricingConfig config,
  ) {
    final merchantsById = {
      for (final merchant in _merchants) merchant.id: merchant.name,
    };
    final conflicts = <_ProductCommissionConflict>[];
    for (final product in _productRecords) {
      final currentValue = double.tryParse(
        product['commission_value_override']?.toString() ?? '',
      );
      final currentMode = product['commission_mode_override']?.toString() ?? '';
      if (currentValue == null ||
          !currentValue.isFinite ||
          !{'percent', 'fixed'}.contains(currentMode)) {
        continue;
      }
      final id = (product['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      final category = (product['category'] ?? '').toString().trim();
      final merchantId = (product['merchant_id'] ?? '').toString().trim();
      final previousRate = _rateWithoutProductOverride(
        _loadedPricingConfig,
        category,
        merchantId,
      );
      final nextRate =
          _rateWithoutProductOverride(config, category, merchantId);
      if (previousRate.mode == nextRate.mode &&
          previousRate.value == nextRate.value) {
        continue;
      }
      conflicts.add(_ProductCommissionConflict(
        id: id,
        name: (product['name'] ?? 'منتج بدون اسم').toString(),
        category: category.isEmpty ? 'غير محددة' : category,
        merchantName: merchantsById[merchantId] ?? 'غير معروف',
        merchantId: merchantId,
        price: double.tryParse(product['price']?.toString() ?? '') ?? 0,
        currencySymbol: (product['currency_symbol'] ?? 'ر.س').toString(),
        description: (product['description'] ?? 'لا يوجد وصف').toString(),
        stock:
            (product['stock'] ?? product['inventory'] ?? 'غير محدد').toString(),
        currentMode: currentMode,
        currentValue: currentValue,
        newMode: nextRate.mode,
        newValue: nextRate.value,
      ));
    }
    return conflicts;
  }

  String _commissionDescription(String mode, double value) => mode == 'fixed'
      ? '${value.toStringAsFixed(2)} ر.ي لكل قطعة'
      : '${value.toStringAsFixed(2)}%';

  Future<Set<String>?> _confirmCommissionConflicts(
    List<_ProductCommissionConflict> conflicts,
  ) async {
    _selectedCommissionProducts.clear();
    final selectedProductIds = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('مراجعة المنتجات ذات العمولة الخاصة'),
          content: SizedBox(
            width: 520,
            height: 480,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'تغييرات العمولة الجديدة تتداخل مع عمولة مستقلة محفوظة '
                  'لبعض المنتجات. اختر المنتجات التي تريد نقلها إلى '
                  'العمولة الجديدة. المنتجات غير المحددة ستحتفظ بعمولتها '
                  'الخاصة دون تغيير.',
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    itemCount: conflicts.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final product = conflicts[index];
                      final currentSalePrice = product.price +
                          ProductModel.commissionAmountForPrice(
                            price: product.price,
                            mode: product.currentMode,
                            value: product.currentValue,
                          );
                      final newSalePrice = product.price +
                          ProductModel.commissionAmountForPrice(
                            price: product.price,
                            mode: product.newMode,
                            value: product.newValue,
                          );
                      return CheckboxListTile(
                        key: ValueKey(
                          'commission-conflict-${product.id}',
                        ),
                        value: _selectedCommissionProducts.contains(
                          product.id,
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(product.name),
                        subtitle: Text(
                          'معرف المنتج: ${product.id}\n'
                          'الفئة: ${product.category}\n'
                          'التاجر: ${product.merchantName} '
                          '(${product.merchantId})\n'
                          'السعر الأساسي: ${product.price.toStringAsFixed(2)} ${product.currencySymbol}\n'
                          'الوصف: ${product.description}\n'
                          'المخزون: ${product.stock}\n'
                          'عمولته الخاصة الحالية: '
                          '${_commissionDescription(product.currentMode, product.currentValue)} '
                          '(سعره الحالي ${currentSalePrice.toStringAsFixed(2)} ${product.currencySymbol})\n'
                          'العمولة الجديدة التي ستطبق عليه: '
                          '${_commissionDescription(product.newMode, product.newValue)} '
                          '(السعر الجديد ${newSalePrice.toStringAsFixed(2)} ${product.currencySymbol})\n'
                          'تحديده يلغي عمولته الخاصة ويستخدم العمولة الجديدة.',
                        ),
                        onChanged: (selected) {
                          setDialogState(() {
                            if (selected == true) {
                              _selectedCommissionProducts.add(product.id);
                            } else {
                              _selectedCommissionProducts.remove(product.id);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء حفظ العمولة'),
            ),
            FilledButton(
              onPressed: () {
                final selected = _selectedCommissionProducts.toList();
                Navigator.pop(dialogContext, selected);
              },
              child: Text(
                'تأكيد وحفظ (${_selectedCommissionProducts.length})',
              ),
            ),
          ],
        ),
      ),
    );
    return selectedProductIds?.toSet();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadFailed) {
      return Scaffold(
        appBar: AppBar(title: const Text('إدارة الأسعار والعمولات')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('تعذر تحميل الفئات والتجار'),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _load,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الأسعار والعمولات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: _commissionMode,
            decoration: const InputDecoration(labelText: 'نوع العمولة'),
            items: const [
              DropdownMenuItem(
                  value: 'percent', child: Text('نسبة من سعر المنتج')),
              DropdownMenuItem(
                  value: 'fixed', child: Text('مبلغ ثابت لكل قطعة')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _commissionMode = value);
            },
          ),
          TextField(
              controller: _commissionValue,
              decoration: InputDecoration(
                labelText: _commissionMode == 'percent'
                    ? 'نسبة العمولة (%)'
                    : 'العمولة لكل قطعة (ر.ي)',
              )),
          const SizedBox(height: 12),
          const Text(
            'عمولة حسب الفئة',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          ..._categoryRuleFields(_commissionCategoryRules),
          const SizedBox(height: 12),
          const Text(
            'عمولة مخصصة حسب التاجر',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const Text(
            'عمولة التاجر تتقدم على عمولة الفئة، والعمولة الخاصة بالمنتج '
            'تبقى الأعلى أولوية ما لم تختر نقل المنتج إليها عند الحفظ.',
          ),
          ..._merchantCommissionFields(),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _deliveryMode,
            decoration: const InputDecoration(labelText: 'طريقة أجرة التوصيل'),
            items: const [
              DropdownMenuItem(value: 'fixed', child: Text('مبلغ ثابت')),
              DropdownMenuItem(
                  value: 'percent', child: Text('نسبة من قيمة الطلب')),
              DropdownMenuItem(value: 'distance', child: Text('حسب المسافة')),
              DropdownMenuItem(
                  value: 'region', child: Text('حسب منطقة العميل')),
              DropdownMenuItem(
                value: 'merchant_region',
                child: Text('حسب منطقة التاجر'),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _deliveryMode = value);
            },
          ),
          TextField(
              controller: _deliveryValue,
              decoration: InputDecoration(
                labelText: _deliveryMode == 'percent'
                    ? 'نسبة التوصيل (%)'
                    : 'قيمة التوصيل (ر.ي)',
              )),
          TextField(
              controller: _baseFee,
              decoration: const InputDecoration(
                  labelText: 'الرسم الأساسي للمسافة (ر.ي)')),
          TextField(
              controller: _perKm,
              decoration:
                  const InputDecoration(labelText: 'الرسم لكل كيلومتر (ر.ي)')),
          TextField(
            controller: _deliveryByRegion,
            decoration: const InputDecoration(
              labelText: 'سعر التوصيل حسب منطقة العميل (ر.ي)',
              hintText: 'صنعاء=25, إب=30',
              helperText: 'يُستخدم عند اختيار طريقة التسعير حسب منطقة العميل.',
            ),
          ),
          TextField(
            controller: _deliveryByMerchantRegion,
            decoration: const InputDecoration(
              labelText: 'سعر التوصيل حسب منطقة التاجر (ر.ي)',
              hintText: 'صنعاء=20, إب=25',
              helperText: 'يُستخدم عند اختيار طريقة التسعير حسب منطقة التاجر.',
            ),
          ),
          _pricingSelectionField(
            title: 'منتجات مستثناة من تسعير منطقة التاجر والتوصيل المجاني',
            itemLabel: 'منتج',
            options: _products,
            controller: _deliveryExemptProducts,
            icon: Icons.inventory_2_outlined,
          ),
          _pricingSelectionField(
            title: 'تجار مستثنون من تسعير منطقة التاجر والتوصيل المجاني',
            itemLabel: 'تاجر',
            options: _merchants,
            controller: _deliveryExemptMerchants,
            icon: Icons.storefront_outlined,
          ),
          const SizedBox(height: 18),
          const Text(
            'شروط التوصيل المجاني',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          TextField(
            controller: _freeDeliveryCommissionThreshold,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'مجاني إذا تجاوزت عمولة الطلب هذا الحد',
              helperText: 'اتركه فارغًا لتعطيل الشرط.',
            ),
          ),
          TextField(
            controller: _freeDeliverySingleMerchantThreshold,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText:
                  'مجاني لطلب تاجر واحد إذا تجاوز إجماليه هذا الحد (ر.ي)',
              helperText: 'اتركه فارغًا لتعطيل الشرط.',
            ),
          ),
          TextField(
            controller: _freeDeliveryMultiMerchantCommissionThreshold,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'مجاني لعدة تجار إذا تجاوزت العمولة هذا الحد',
              helperText: 'اتركه فارغًا لتعطيل الشرط.',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'جار الحفظ...' : 'حفظ الإعدادات')),
        ],
      ),
    );
  }
}

class MetricCardData {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const MetricCardData({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });
}

class ActionRowData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const ActionRowData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });
}

class _MetricCard extends StatelessWidget {
  final MetricCardData metric;

  const _MetricCard({required this.metric});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: metric.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(metric.icon, color: metric.color),
          ),
          Text(
            metric.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            metric.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class VirtualCurrencyManagementScreen extends StatefulWidget {
  const VirtualCurrencyManagementScreen({super.key});

  @override
  State<VirtualCurrencyManagementScreen> createState() =>
      _VirtualCurrencyManagementScreenState();
}

class _VirtualCurrencyManagementScreenState
    extends State<VirtualCurrencyManagementScreen> {
  final CurrencyService _currencyService = CurrencyService();
  bool _currenciesLoaded = false;
  final List<_CurrencyItem> _currencies = [
    _CurrencyItem(
      title: 'ريال سعودي',
      code: 'SAR',
      symbol: 'ر.س',
      isDefault: true,
      rateToYER: null,
    ),
    _CurrencyItem(
      title: 'دولار أمريكي',
      code: 'USD',
      symbol: '\$',
      rateToYER: null,
    ),
    _CurrencyItem(
      title: 'درهم إماراتي',
      code: 'AED',
      symbol: 'د.إ',
      rateToYER: null,
    ),
    _CurrencyItem(
      title: CurrencyService.yerCurrency.title,
      code: CurrencyService.yerCurrency.code,
      symbol: CurrencyService.yerCurrency.symbol,
      rateToYER: 1,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadCurrencies();
  }

  Future<void> _loadCurrencies() async {
    final currencies = await _currencyService.getCurrencies(
      includeDisabled: true,
    );
    if (!mounted) return;
    setState(() {
      _currencies
        ..clear()
        ..addAll(currencies.map((currency) => _CurrencyItem(
              title: currency.title,
              code: currency.code,
              symbol: currency.symbol,
              isDefault: currency.isDefault,
              rateToYER: currency.rateToYER,
              enabled: currency.enabled,
            )));
      _currenciesLoaded = true;
    });
  }

  Future<bool> _persistCurrencies() {
    return _currencyService.saveCurrencies(
      _currencies
          .map((currency) => CurrencyOption(
                title: currency.title,
                code: currency.code,
                symbol: currency.symbol,
                isDefault: currency.isDefault,
                rateToYER: currency.rateToYER,
                enabled: currency.enabled,
              ))
          .toList(),
    );
  }

  Future<void> _editCurrencyRate(_CurrencyItem currency) async {
    if (currency.code == CurrencyService.yerCode) return;
    final controller = TextEditingController(
      text: currency.rateToYER?.toString() ?? '',
    );
    final formKey = GlobalKey<FormState>();
    final rate = await showDialog<double>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('سعر صرف ${currency.title}'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'كم ريالًا يمنيًا تساوي وحدة واحدة؟',
                suffixText: 'ر.ي',
              ),
              validator: (value) {
                final parsed = double.tryParse((value ?? '').trim());
                if (parsed == null || !parsed.isFinite || parsed <= 0) {
                  return 'أدخل سعر صرف أكبر من صفر';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.of(dialogContext)
                    .pop(double.parse(controller.text.trim()));
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (rate == null || !mounted) return;

    final previousRate = currency.rateToYER;
    setState(() => currency.rateToYER = rate);
    final saved = await _persistCurrencies();
    if (!mounted) return;
    if (!saved) setState(() => currency.rateToYER = previousRate);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved ? 'تم حفظ سعر الصرف' : 'تعذر حفظ سعر الصرف في قاعدة البيانات',
        ),
      ),
    );
  }

  Future<void> _setDefaultCurrency(_CurrencyItem selected) async {
    if (!selected.enabled) return;
    final previousDefaults =
        _currencies.map((currency) => currency.isDefault).toList();
    setState(() {
      for (final currency in _currencies) {
        currency.isDefault = currency == selected;
      }
    });
    final saved = await _persistCurrencies();
    if (!mounted) return;
    if (!saved) {
      setState(() {
        for (var index = 0; index < _currencies.length; index++) {
          _currencies[index].isDefault = previousDefaults[index];
        }
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? 'تم تحديث العملة الافتراضية'
              : 'تعذر حفظ العملة الافتراضية في قاعدة البيانات',
        ),
      ),
    );
  }

  Future<void> _toggleCurrencyArchived(_CurrencyItem currency) async {
    if (currency.code == CurrencyService.yerCode) return;
    final archive = currency.enabled;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(archive ? 'أرشفة العملة' : 'استعادة العملة'),
        content: Text(
          archive
              ? 'ستبقى الأسعار والطلبات القديمة كما هي، ولن تظهر العملة ضمن خيارات الاستخدام الجديدة. هل تريد المتابعة؟'
              : 'هل تريد إعادة إتاحة ${currency.title}؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(archive ? 'أرشفة' : 'استعادة'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final previousDefaults = _currencies.map((item) => item.isDefault).toList();
    final wasEnabled = currency.enabled;
    setState(() {
      currency.enabled = !archive;
      if (archive && currency.isDefault) {
        for (final item in _currencies) {
          item.isDefault = item.enabled && item.code == CurrencyService.yerCode;
        }
      }
    });
    final saved = await _persistCurrencies();
    if (!mounted) return;
    if (!saved) {
      setState(() {
        currency.enabled = wasEnabled;
        for (var index = 0; index < _currencies.length; index++) {
          _currencies[index].isDefault = previousDefaults[index];
        }
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? archive
                  ? 'تمت أرشفة العملة'
                  : 'تمت استعادة العملة'
              : 'تعذر تحديث العملة في قاعدة البيانات',
        ),
      ),
    );
  }

  Future<void> _showAddCurrencyDialog() async {
    final formKey = GlobalKey<FormState>();
    final titleController = TextEditingController();
    final codeController = TextEditingController();
    final symbolController = TextEditingController();
    final rateController = TextEditingController();
    var setAsDefault = _currencies.isEmpty;

    final result = await showDialog<_CurrencyItem>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: const Text('إضافة عملة جديدة'),
                content: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: titleController,
                          textDirection: TextDirection.rtl,
                          decoration: const InputDecoration(
                            labelText: 'اسم العملة',
                            prefixIcon: Icon(Icons.monetization_on_rounded),
                          ),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'أدخل اسم العملة';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: codeController,
                          textDirection: TextDirection.rtl,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'رمز العملة',
                            prefixIcon: Icon(Icons.code_rounded),
                            hintText: 'SAR',
                          ),
                          validator: (value) {
                            final cleaned = (value ?? '').trim();
                            if (cleaned.isEmpty) {
                              return 'أدخل رمز العملة';
                            }
                            if (cleaned.length < 2 || cleaned.length > 5) {
                              return 'رمز العملة يجب أن يكون من 2 إلى 5 أحرف';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: symbolController,
                          textDirection: TextDirection.rtl,
                          decoration: const InputDecoration(
                            labelText: 'رمز العملة الحالي',
                            prefixIcon: Icon(Icons.currency_exchange_rounded),
                            hintText: 'ر.س / \$ / €',
                          ),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'أدخل رمز العملة الحالي';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: rateController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'سعر الصرف بالريال اليمني',
                            helperText:
                                'قيمة وحدة واحدة من العملة بالريال اليمني',
                            prefixIcon: Icon(Icons.currency_exchange_rounded),
                          ),
                          validator: (value) {
                            final rate = double.tryParse((value ?? '').trim());
                            if (rate == null || !rate.isFinite || rate <= 0) {
                              return 'أدخل سعر صرف أكبر من صفر';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: setAsDefault,
                          title: const Text('تعيين كعملة افتراضية'),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => setAsDefault = value);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('إلغاء'),
                  ),
                  FilledButton(
                    onPressed: () {
                      if (!formKey.currentState!.validate()) return;

                      final newCurrency = _CurrencyItem(
                        title: titleController.text.trim(),
                        code: codeController.text.trim().toUpperCase(),
                        symbol: symbolController.text.trim(),
                        isDefault: setAsDefault,
                        rateToYER: double.parse(rateController.text.trim()),
                      );
                      Navigator.of(dialogContext).pop(newCurrency);
                    },
                    child: const Text('حفظ'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    titleController.dispose();
    codeController.dispose();
    symbolController.dispose();
    rateController.dispose();
    if (result == null) return;

    final duplicate = _currencies.any(
      (currency) => currency.code.toUpperCase() == result.code.toUpperCase(),
    );
    if (duplicate || RegExp(r'[.#$\[\]/]').hasMatch(result.code)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رمز العملة غير صالح أو مستخدم مسبقاً')),
      );
      return;
    }

    final previousDefaults =
        _currencies.map((currency) => currency.isDefault).toList();
    setState(() {
      if (result.isDefault) {
        for (final currency in _currencies) {
          currency.isDefault = false;
        }
      }
      _currencies.add(result);
    });
    final saved = await _persistCurrencies();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? 'تم حفظ العملة وإتاحتها للتاجر'
              : 'تعذر حفظ العملة في قاعدة البيانات',
        ),
      ),
    );
    if (!saved) {
      setState(() {
        _currencies.remove(result);
        for (var index = 0; index < _currencies.length; index++) {
          _currencies[index].isDefault = previousDefaults[index];
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultCurrency = _currencies.firstWhere(
      (currency) => currency.isDefault,
      orElse: () => _currencies.first,
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة العملة الافتراضية'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF111827), Color(0xFF1F2937)],
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'إدارة العملة الافتراضية',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'إدارة العملات المتاحة، الرموز، وتحديد العملة الإفتراضية داخل المنصة.',
                    style: const TextStyle(
                      color: Color(0xFFE5E7EB),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 2,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.45,
              children: [
                _VirtualCurrencyMetricCard(
                  label: 'العملة الافتراضية',
                  value: '${defaultCurrency.code} / ${defaultCurrency.symbol}',
                  color: const Color(0xFF8B5CF6),
                  icon: Icons.currency_exchange_rounded,
                ),
                _VirtualCurrencyMetricCard(
                  label: 'عدد العملات',
                  value: _currencies.length.toString(),
                  color: const Color(0xFF10B981),
                  icon: Icons.account_balance_wallet_rounded,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _showAddCurrencyDialog,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('إضافة عملة'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'قائمة العملات',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ..._currencies.map(
                    (currency) => Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: currency.isDefault
                                  ? const Color(0xFF8B5CF6)
                                      .withValues(alpha: 0.12)
                                  : const Color(0xFFE5E7EB),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              currency.symbol,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currency.enabled
                                      ? currency.title
                                      : '${currency.title} • مؤرشفة',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  currency.code,
                                  style: const TextStyle(
                                    color: Color(0xFF6B7280),
                                    fontSize: 12,
                                  ),
                                ),
                                if (_currenciesLoaded) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    currency.rateToYER == null
                                        ? 'سعر الصرف غير محدد'
                                        : '1 ${currency.code} = ${currency.rateToYER} ر.ي',
                                    style: TextStyle(
                                      color: currency.rateToYER == null
                                          ? const Color(0xFFB45309)
                                          : const Color(0xFF6B7280),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              if (currency.code != CurrencyService.yerCode)
                                IconButton(
                                  tooltip: 'تعديل سعر الصرف',
                                  onPressed: () => _editCurrencyRate(currency),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                              if (currency.isDefault)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981)
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: const Text(
                                    'افتراضية',
                                    style: TextStyle(
                                      color: Color(0xFF10B981),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                    ),
                                  ),
                                )
                              else
                                TextButton(
                                  onPressed: currency.enabled
                                      ? () => _setDefaultCurrency(currency)
                                      : null,
                                  child: const Text('تحديد افتراضي'),
                                ),
                              if (currency.code != CurrencyService.yerCode)
                                IconButton(
                                  tooltip: currency.enabled
                                      ? 'أرشفة العملة'
                                      : 'استعادة العملة',
                                  onPressed: () =>
                                      _toggleCurrencyArchived(currency),
                                  icon: Icon(
                                    currency.enabled
                                        ? Icons.archive_outlined
                                        : Icons.unarchive_outlined,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrencyItem {
  final String title;
  final String code;
  final String symbol;
  bool isDefault;
  double? rateToYER;
  bool enabled;

  _CurrencyItem({
    required this.title,
    required this.code,
    required this.symbol,
    this.isDefault = false,
    this.rateToYER,
    this.enabled = true,
  });
}

class _VirtualCurrencyMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _VirtualCurrencyMetricCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class OrderManagementScreen extends StatefulWidget {
  const OrderManagementScreen({
    this.initialOrderId,
    this.service,
    super.key,
  });

  final String? initialOrderId;
  final AdminService? service;

  @override
  State<OrderManagementScreen> createState() => _OrderManagementScreenState();
}

class _OrderManagementScreenState extends State<OrderManagementScreen> {
  final _searchController = TextEditingController();
  late final AdminService _service;
  late Future<_AdminOrderDashboardData> _dashboardFuture;
  String _query = '';
  String _statusFilter = 'all';
  bool _initialOrderHandled = false;
  final Set<String> _updatingOrderIds = {};

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? AdminService();
    _dashboardFuture = _loadDashboard();
  }

  Future<_AdminOrderDashboardData> _loadDashboard() async {
    final summaryFuture = _service.getManagementSummary().then(
      (summary) => _OrderSummaryLoad(summary: summary),
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Failed to load order management summary: $error');
        debugPrintStack(stackTrace: stackTrace);
        return _OrderSummaryLoad(error: error);
      },
    );
    final results = await Future.wait<Object>([
      summaryFuture,
      _service.getOrdersForAdmin(
        limit: null,
        propagateErrors: true,
        includeArchived: true,
      ),
    ]);
    final summaryLoad = results[0] as _OrderSummaryLoad;
    final dashboard = _AdminOrderDashboardData(
      summary: summaryLoad.summary,
      summaryError: summaryLoad.error,
      orders: results[1] as List<Map<String, dynamic>>,
    );
    final initialOrderId = widget.initialOrderId?.trim();
    if (!_initialOrderHandled && initialOrderId?.isNotEmpty == true) {
      _initialOrderHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Map<String, dynamic>? order;
        for (final candidate in dashboard.orders) {
          if ((candidate['id'] ?? '').toString() == initialOrderId) {
            order = candidate;
            break;
          }
        }
        if (order == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذر العثور على الطلب المرتبط')),
          );
          return;
        }
        _showOrderDetails(order);
      });
    }
    return dashboard;
  }

  Future<void> _refresh() async {
    final future = _loadDashboard();
    setState(() {
      _dashboardFuture = future;
    });
    try {
      await future;
    } catch (error, stackTrace) {
      debugPrint('Failed to refresh admin orders: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<_AdminOrderDetailData> _loadOrderDetails(
    Map<String, dynamic> order,
  ) async {
    final orderId = (order['id'] ?? '').toString();
    final profiles = <String, Map<String, dynamic>>{};
    final items = (order['items'] ?? order['order_items']) is List
        ? ((order['items'] ?? order['order_items']) as List)
            .whereType<Map>()
            .toList()
        : const <Map>[];
    final profileIds = <String>{
      (order['customer_id'] ?? order['customerId'] ?? '').toString(),
      (order['driver_id'] ?? order['driverId'] ?? '').toString(),
      (order['merchant_id'] ?? order['merchantId'] ?? '').toString(),
      ...items.map((item) =>
          (item['merchant_id'] ?? item['merchantId'] ?? '').toString()),
    }..removeWhere((id) => id.trim().isEmpty);
    final proofIds = <String>{
      (order['payment_proof_id'] ?? order['paymentProofId'] ?? '').toString(),
      if (order['payment_proof_ids'] is List)
        ...(order['payment_proof_ids'] as List).map((id) => id.toString()),
      if (order['paymentProofIds'] is List)
        ...(order['paymentProofIds'] as List).map((id) => id.toString()),
    }..removeWhere((id) => id.trim().isEmpty);
    final profileResults = await Future.wait(
      profileIds.map(
        (id) => FirebaseDatabaseService.instance.read('profiles/$id'),
      ),
    );
    var profileIndex = 0;
    for (final id in profileIds) {
      final profile = profileResults[profileIndex++];
      if (profile.isEmpty) continue;
      profile.putIfAbsent('id', () => id);
      profiles[id] = profile;
    }

    final proofs = <_AdminOrderProof>[];
    final proofResults = await Future.wait(
      proofIds.map(
        (id) => FirebaseDatabaseService.instance.read('payment_proofs/$id'),
      ),
    );
    var proofIndex = 0;
    for (final id in proofIds) {
      final proofData = proofResults[proofIndex++];
      if (proofData.isEmpty) continue;
      final raw = Map<String, dynamic>.from(proofData)
        ..putIfAbsent('id', () => id);
      final proof = PaymentProofModel.fromJson(raw);
      if (proof.orderId == orderId || proof.orderId.isEmpty) {
        proofs.add(_AdminOrderProof(proof: proof, raw: raw));
      }
    }
    if (proofIds.isEmpty) {
      final legacyProofs = await PaymentService().getProofsForOrder(orderId);
      proofs.addAll(
        legacyProofs.map(
          (proof) => _AdminOrderProof(proof: proof, raw: proof.toJson()),
        ),
      );
    }
    proofs.sort((first, second) =>
        second.proof.createdAt.compareTo(first.proof.createdAt));

    final deliveryUpdatesSnapshot =
        await FirebaseDatabaseService.instance.read('delivery_updates');
    final updates = <Map<String, dynamic>>[];
    for (final entry in deliveryUpdatesSnapshot.entries) {
      if (entry.value is! Map) continue;
      final update = Map<String, dynamic>.from(entry.value as Map)
        ..putIfAbsent('id', () => entry.key);
      if ((update['order_id'] ?? update['orderId'])?.toString() == orderId) {
        updates.add(update);
      }
    }
    updates.sort((first, second) {
      final firstDate = DateTime.tryParse(
            (first['created_at'] ?? first['createdAt'] ?? '').toString(),
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final secondDate = DateTime.tryParse(
            (second['created_at'] ?? second['createdAt'] ?? '').toString(),
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return firstDate.compareTo(secondDate);
    });
    return _AdminOrderDetailData(
      order: order,
      profiles: profiles,
      proofs: proofs,
      deliveryUpdates: updates,
    );
  }

  void _showOrderDetails(Map<String, dynamic> order) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.94,
        child: _AdminOrderDetailsSheet(
          loadDetails: () => _loadOrderDetails(order),
          isUpdating: _updatingOrderIds.contains(
            (order['id'] ?? '').toString(),
          ),
          onManage: () {
            Navigator.of(context).pop();
            _showOrderActionDialog(order);
          },
          onOpenMap: _openOrderMap,
          onShowReceipt: _showPaymentReceipt,
          onReviewProof: _reviewOrderProof,
          onRefresh: () => _refreshAndShowOrderDetails(
            (order['id'] ?? '').toString(),
          ),
        ),
      ),
    );
  }

  Future<void> _refreshAndShowOrderDetails(String orderId) async {
    Navigator.of(context).pop();
    await _refresh();
    if (!mounted) return;
    try {
      final dashboard = await _dashboardFuture;
      final order = dashboard.orders.firstWhere(
        (item) => item['id']?.toString() == orderId,
        orElse: () => <String, dynamic>{},
      );
      if (order.isNotEmpty) _showOrderDetails(order);
    } catch (error, stackTrace) {
      debugPrint('Failed to refresh order details: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _openOrderMap(
      String label, String address, String? coordinates) async {
    final query = coordinates?.trim().isNotEmpty == true
        ? coordinates!.trim()
        : address.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('لا يتوفر موقع $label لهذا الطلب')),
      );
      return;
    }
    final uri = Uri.https(
      'www.google.com',
      '/maps/search/',
      {'api': '1', 'query': query},
    );
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر فتح موقع $label')),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to open $label location: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر فتح موقع $label')),
        );
      }
    }
  }

  void _showPaymentReceipt(PaymentProofModel proof) {
    final provider = MediaUploadService.imageProvider(proof.imageUrl);
    if (provider == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر قراءة صورة الإيصال')),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 5,
          child: Image(image: provider, fit: BoxFit.contain),
        ),
      ),
    );
  }

  Future<void> _reviewOrderProof(
    PaymentProofModel proof,
    String status,
  ) async {
    final controller = TextEditingController();
    final isApproval = status == 'approved';
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isApproval ? 'اعتماد إيصال الدفع' : 'رفض إيصال الدفع'),
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
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (!isApproval && value.isEmpty) return;
              Navigator.of(dialogContext).pop(value);
            },
            child: Text(isApproval ? 'اعتماد الإيصال' : 'رفض الإيصال'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note == null || !mounted) return;

    final result = await PaymentService().reviewProof(
      proofId: proof.id,
      status: status,
      note: note.isEmpty ? 'تمت المراجعة من مدير النظام' : note,
    );
    if (!mounted) return;
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحديث إيصال الدفع')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isApproval
              ? 'تم اعتماد الإيصال وتحديث حالة الطلب'
              : 'تم رفض الإيصال وتحديث حالة الطلب',
        ),
      ),
    );
    await _refreshAndShowOrderDetails(proof.orderId);
  }

  Future<void> _showOrderActionDialog(Map<String, dynamic> order) async {
    final id = (order['id'] ?? '').toString();
    if (id.isEmpty) return;
    final status = (order['status'] ?? 'pending_payment').toString();

    final assignedDriver =
        (order['driver_name'] ?? order['courier_name'] ?? 'غير مخصص')
            .toString()
            .trim();
    final hasDriverReference = [
      order['driver_id'],
      order['driverId'],
      order['driver_phone'],
      order['driverPhone'],
    ].any((value) => value?.toString().trim().isNotEmpty ?? false);
    final alreadyAssigned = hasDriverReference ||
        (assignedDriver.isNotEmpty &&
            !{'غير مخصص', 'غير مخصص بعد', 'غير معين', 'unassigned'}
                .contains(assignedDriver.toLowerCase()));
    final canAssignDriver =
        {'preparing', 'shipped'}.contains(status) && !alreadyAssigned;
    final driverStatus = (order['driver_status'] ?? '').toString();
    final canReassignDriver = {'preparing', 'shipped'}.contains(status) &&
        alreadyAssigned &&
        order['pickup_otp_verified'] != true &&
        !{'picked_up', 'delivered'}.contains(driverStatus);
    final currentDriverId =
        (order['driver_id'] ?? order['driverId'] ?? '').toString().trim();
    final currentDriverPhone =
        (order['driver_phone'] ?? order['driverPhone'] ?? '').toString().trim();
    List<Map<String, dynamic>> driverOptions = [];
    try {
      if (canAssignDriver || canReassignDriver) {
        final drivers = await _service.getProfilesForAdmin(
          role: 'driver',
          limit: 100,
        );
        driverOptions = drivers.where((driver) {
          if (!_isDriverAvailable(driver)) return false;
          final candidateId = (driver['id'] ?? '').toString().trim();
          if (currentDriverId.isNotEmpty) {
            return candidateId != currentDriverId;
          }
          final candidatePhone = (driver['phone'] ?? '').toString().trim();
          if (currentDriverPhone.isNotEmpty) {
            return candidatePhone != currentDriverPhone;
          }
          final candidateName = (driver['full_name'] ?? '').toString().trim();
          return candidateName != assignedDriver;
        }).toList();
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to load drivers for order $id: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحميل السائقين، حاول مرة أخرى')),
      );
      return;
    }

    if (!mounted) return;

    final selectedDriver = await showDialog<Object>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('تخصيص طلب $id'),
          content: SizedBox(
            width: 320,
            child: alreadyAssigned
                ? Text(
                    'تم تخصيص الطلب إلى '
                    '${hasDriverReference && assignedDriver == 'غير مخصص' ? 'سائق' : assignedDriver}',
                  )
                : !canAssignDriver
                    ? const Text('ابدأ تجهيز الطلب قبل تخصيص سائق.')
                    : driverOptions.isEmpty
                        ? const Text('لا يوجد سائقون متاحون لتخصيص الطلب')
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: driverOptions.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final driver = driverOptions[index];
                              final driverName =
                                  driver['full_name']?.toString().trim() ??
                                      'سائق';
                              return ListTile(
                                title: Text(driverName),
                                subtitle: Text(
                                  [
                                    driver['phone']?.toString() ?? '',
                                    'متاح',
                                  ]
                                      .where((value) => value.isNotEmpty)
                                      .join(' • '),
                                ),
                                leading:
                                    const Icon(Icons.delivery_dining_rounded),
                                onTap: () => Navigator.of(context).pop(driver),
                              );
                            },
                          ),
          ),
          actions: [
            if ({'new', 'pending_payment', 'awaiting_confirmation'}
                .contains(status))
              TextButton(
                onPressed: () => Navigator.of(context).pop('__approve__'),
                child: const Text('تأكيد الطلب'),
              ),
            if ({'confirmed', 'accepted'}.contains(status))
              TextButton(
                onPressed: () => Navigator.of(context).pop('__prepare__'),
                child: const Text('بدء التجهيز'),
              ),
            if ({'preparing', 'shipped'}.contains(status) && alreadyAssigned)
              TextButton(
                onPressed: () => Navigator.of(context).pop('__handoff__'),
                child: Text(
                  status == 'shipped'
                      ? 'عرض رمز استلام السائق'
                      : 'تسليم للسائق وإنشاء الرمز',
                ),
              ),
            if ({'preparing', 'shipped'}.contains(status) && alreadyAssigned)
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop('__handoff_without_code__'),
                child: const Text('تسليم للسائق بدون رمز الاستلام'),
              ),
            if (canReassignDriver)
              TextButton(
                onPressed: () => Navigator.of(context).pop('__reassign__'),
                child: const Text('تغيير السائق'),
              ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop('__adjust_delivery_fee__'),
              child: const Text('تعديل أجرة التوصيل'),
            ),
            if (!{'cancelled', 'rejected', 'delivered', 'picked_up', 'shipped'}
                .contains(status))
              TextButton(
                onPressed: () => Navigator.of(context).pop('__reject__'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFB91C1C),
                ),
                child: const Text('رفض الطلب'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    if (selectedDriver == '__reassign__') {
      if (driverOptions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا يوجد سائقون متاحون لتغيير الإسناد')),
        );
        return;
      }

      final replacementDriver = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('اختيار سائق بديل للطلب $id'),
          content: SizedBox(
            width: 320,
            height: 320,
            child: ListView.separated(
              itemCount: driverOptions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final driver = driverOptions[index];
                final driverName =
                    driver['full_name']?.toString().trim() ?? 'سائق';
                return ListTile(
                  title: Text(driverName),
                  subtitle: Text(
                    (driver['phone'] ?? '').toString(),
                    textDirection: TextDirection.ltr,
                  ),
                  leading: const Icon(Icons.delivery_dining_rounded),
                  onTap: () => Navigator.of(dialogContext)
                      .pop(Map<String, dynamic>.from(driver)),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('إلغاء'),
            ),
          ],
        ),
      );
      if (!mounted || replacementDriver == null) return;

      final replacementName =
          replacementDriver['full_name']?.toString().trim() ?? 'سائق';
      var reassigned = false;
      await _runOrderUpdate(
        id,
        () async {
          reassigned = await _service.reassignOrderToDriver(
            orderId: id,
            currentDriverId: currentDriverId,
            currentDriverName: assignedDriver,
            currentDriverPhone: currentDriverPhone,
            driverName: replacementName,
            driverId: replacementDriver['id']?.toString() ?? '',
            driverPhone: replacementDriver['phone']?.toString() ?? '',
            eta: order['eta']?.toString(),
          );
          return reassigned;
        },
        successMessage: 'تم تغيير سائق الطلب $id إلى $replacementName',
      );
      if (reassigned && status == 'shipped' && mounted) {
        await _prepareAndShowPickupCode(id, order);
      }
      return;
    }

    if (selectedDriver == '__adjust_delivery_fee__') {
      await showDeliveryFeeAdjustmentDialog(
        context,
        order: order,
        onUpdated: () {
          if (mounted) setState(_refresh);
        },
      );
      return;
    }

    if (selectedDriver == '__approve__') {
      await _runOrderUpdate(
        id,
        () => _service.updateOrderStatusForAdmin(
          orderId: id,
          status: 'confirmed',
        ),
        successMessage: 'تم تأكيد الطلب $id وإبلاغ العميل',
      );
      return;
    }

    if (selectedDriver == '__prepare__') {
      await _runOrderUpdate(
        id,
        () => _service.updateOrderStatusForAdmin(
          orderId: id,
          status: 'preparing',
        ),
        successMessage: 'بدأ تجهيز الطلب $id',
      );
      return;
    }

    if (selectedDriver == '__handoff__') {
      await _prepareAndShowPickupCode(id, order);
      return;
    }

    if (selectedDriver == '__handoff_without_code__') {
      await _handoffWithoutPickupCode(id);
      return;
    }

    if (selectedDriver == '__reject__') {
      final shouldReject = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('رفض الطلب'),
          content: Text('سيتم رفض الطلب $id وإبلاغ العميل. هل تريد المتابعة؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB91C1C),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('تأكيد الرفض'),
            ),
          ],
        ),
      );

      if (shouldReject != true) return;

      await _runOrderUpdate(
        id,
        () => _service.updateOrderStatusForAdmin(
          orderId: id,
          status: 'rejected',
        ),
        successMessage: 'تم رفض الطلب $id وإبلاغ العميل',
      );
      return;
    }

    if (!mounted || selectedDriver is! Map<String, dynamic>) {
      return;
    }

    final driverName =
        selectedDriver['full_name']?.toString().trim().isNotEmpty == true
            ? selectedDriver['full_name'].toString().trim()
            : 'سائق';
    final service = _service;
    String? pickupOtp;
    await _runOrderUpdate(
      id,
      () async {
        final assigned = await service.assignOrderToDriver(
          orderId: id,
          driverName: driverName,
          driverId: selectedDriver['id']?.toString(),
          driverPhone: selectedDriver['phone']?.toString(),
          eta: '30 دقيقة',
        );
        if (!assigned) return false;
        pickupOtp = await service.prepareOrderHandoffForAdmin(orderId: id);
        return pickupOtp?.isNotEmpty == true;
      },
      successMessage: 'تم إسناد الطلب $id إلى $driverName وإنشاء رمز الاستلام',
    );
    if (pickupOtp != null && mounted) {
      await _showPickupHandoffCode(
        orderNumber: OrderNumber.fromOrder(order),
        pickupOtp: pickupOtp!,
      );
    }
  }

  Future<void> _prepareAndShowPickupCode(
    String orderId,
    Map<String, dynamic> order,
  ) async {
    String? pickupOtp;
    await _runOrderUpdate(
      orderId,
      () async {
        pickupOtp =
            await _service.prepareOrderHandoffForAdmin(orderId: orderId);
        return pickupOtp?.isNotEmpty == true;
      },
      successMessage: 'تم تجهيز رمز استلام الطلب',
    );
    if (pickupOtp != null && mounted) {
      await _showPickupHandoffCode(
        orderNumber: OrderNumber.fromOrder(order),
        pickupOtp: pickupOtp!,
      );
    }
  }

  Future<void> _handoffWithoutPickupCode(String orderId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تسليم الطلب دون رمز الاستلام'),
        content: const Text(
          'سيتم اعتبار الطلب مستلمًا من السائق مباشرةً. '
          'يمكن للسائق تأكيد التسليم مباشرةً عند وصوله للعميل.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('تأكيد التسليم'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _runOrderUpdate(
      orderId,
      () async {
        final handedOffOrder =
            await _service.handoffOrderToDriverWithoutPickupOtpForAdmin(
          orderId: orderId,
        );
        return handedOffOrder != null;
      },
      successMessage: 'تم تسليم الطلب للسائق دون رمز الاستلام',
    );
  }

  Future<void> _showPickupHandoffCode({
    required String orderNumber,
    required String pickupOtp,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('رمز استلام الطلب #$orderNumber'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'أعطِ الرمز للسائق ليدخله عند استلام الطلب من المتجر. '
              'الرمز صالح لمدة 30 دقيقة.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            SelectableText(
              pickupOtp,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: 8,
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('تم تسليم الرمز للسائق'),
          ),
        ],
      ),
    );
  }

  Future<void> _runOrderUpdate(
    String orderId,
    Future<bool> Function() update, {
    required String successMessage,
  }) async {
    if (_updatingOrderIds.contains(orderId)) return;
    setState(() => _updatingOrderIds.add(orderId));
    try {
      final success = await update();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? successMessage : 'تعذر تحديث الطلب، حدّث القائمة وحاول',
          ),
        ),
      );
      if (success) await _refresh();
    } catch (error, stackTrace) {
      debugPrint('Failed to update order $orderId: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تحديث الطلب، حاول مرة أخرى')),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingOrderIds.remove(orderId));
    }
  }

  bool _isDriverAvailable(Map<String, dynamic> driver) {
    final available =
        driver['is_available'] ?? driver['isAvailable'] ?? driver['available'];
    return available == true || available?.toString().toLowerCase() == 'true';
  }

  Future<void> _toggleOrderArchived(Map<String, dynamic> order) async {
    final id = (order['id'] ?? '').toString();
    if (id.isEmpty) return;
    final archived = order['is_archived'] == true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(archived ? 'استعادة الطلب' : 'أرشفة الطلب'),
        content: Text(
          archived
              ? 'هل تريد إعادة الطلب $id إلى قائمة الطلبات النشطة؟'
              : 'سيُخفى الطلب $id من القائمة النشطة مع الإبقاء على تفاصيله وسجلاته. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(archived ? 'استعادة' : 'أرشفة'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runOrderUpdate(
      id,
      () => _service.setOrderArchivedForAdmin(
        orderId: id,
        archived: !archived,
      ),
      successMessage:
          archived ? 'تمت استعادة الطلب $id' : 'تمت أرشفة الطلب $id',
    );
  }

  Future<void> _deleteOrderForAdmin(Map<String, dynamic> order) async {
    final id = (order['id'] ?? '').toString();
    if (id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف الطلب نهائيًا'),
        content: Text(
          'سيُحذف الطلب $id من النظام ومن سجل العميل ولا يمكن استعادته. '
          'ستبقى سجلات الدفع والتوصيل لأغراض المراجعة. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _runOrderUpdate(
      id,
      () => _service.deleteOrderForAdmin(
        orderId: id,
        customerId:
            (order['customer_id'] ?? order['customerId'] ?? '').toString(),
      ),
      successMessage: 'تم حذف الطلب نهائيًا',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة الطلبات'),
          actions: [
            IconButton(
              tooltip: 'تحديث الطلبات',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: FutureBuilder<_AdminOrderDashboardData>(
          future: _dashboardFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _OrderManagementMessage(
                icon: Icons.cloud_off_rounded,
                message: 'تعذر تحميل الطلبات',
                details: AppErrorMessage.from(snapshot.error!),
                actionLabel: 'إعادة المحاولة',
                onAction: _refresh,
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final dashboard = snapshot.data!;
            final orders = dashboard.orders.where((order) {
              final isArchived = order['is_archived'] == true;
              if (_statusFilter == 'archived') {
                if (!isArchived) return false;
              } else if (_statusFilter != 'all' && isArchived) {
                return false;
              }
              final status = (order['status'] ?? 'pending_payment').toString();
              if (_statusFilter != 'all' &&
                  _statusFilter != 'active' &&
                  _statusFilter != 'archived' &&
                  status != _statusFilter) {
                return false;
              }
              if (_query.isEmpty) return true;
              return [
                order['id'],
                OrderNumber.fromOrder(order),
                order['customer_name'],
                order['customer_phone'],
                order['phone'],
                order['customer_id'],
                order['merchant_name'],
                order['merchant_id'],
                order['driver_name'],
                order['driver_phone'],
                order['payment_proof_id'],
                order['delivery_address'],
              ].any((value) =>
                  value?.toString().toLowerCase().contains(_query) ?? false);
            }).toList();

            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (dashboard.summary != null)
                    _OrderManagementSummary(summary: dashboard.summary!)
                  else
                    _OrderManagementSummaryWarning(
                      details: AppErrorMessage.from(dashboard.summaryError!),
                      onRetry: _refresh,
                    ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onChanged: (value) =>
                        setState(() => _query = value.trim().toLowerCase()),
                    decoration: InputDecoration(
                      hintText: 'ابحث برقم الطلب أو اسم العميل أو هاتفه',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'مسح البحث',
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _statusFilter,
                    decoration: InputDecoration(
                      labelText: 'تصفية حسب الحالة',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'all',
                        child: Text('جميع الطلبات'),
                      ),
                      const DropdownMenuItem(
                        value: 'active',
                        child: Text('الطلبات النشطة'),
                      ),
                      const DropdownMenuItem(
                        value: 'archived',
                        child: Text('الطلبات المؤرشفة'),
                      ),
                      ..._adminOrderStatuses.map(
                        (status) => DropdownMenuItem(
                          value: status,
                          child: Text(DeliveryService.statusLabel(status)),
                        ),
                      ),
                    ],
                    onChanged: (status) {
                      if (status != null) {
                        setState(() => _statusFilter = status);
                      }
                    },
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'الطلبات',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        '${orders.length} طلب',
                        style: const TextStyle(color: Color(0xFF6B7280)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (orders.isEmpty)
                    const _OrderManagementMessage(
                      icon: Icons.receipt_long_rounded,
                      message: 'لا توجد طلبات مطابقة',
                      details: 'جرّب تغيير كلمات البحث أو حالة الطلب.',
                    )
                  else
                    ...orders.map(_buildOrderCard),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final id = (order['id'] ?? '').toString();
    final status = (order['status'] ?? 'pending_payment').toString();
    final total = order['total'];
    final rawItems = order['items'] ?? order['order_items'];
    final items = rawItems is List
        ? rawItems.whereType<Map>().toList()
        : rawItems is Map
            ? rawItems.values.whereType<Map>().toList()
            : <Map>[];
    final currencySymbol = (order['currency_symbol'] ??
            order['currencySymbol'] ??
            (items.isNotEmpty
                ? items.first['currency_symbol'] ??
                    items.first['currencySymbol']
                : null) ??
            CurrencyService.yerCurrency.symbol)
        .toString();
    final totalText = total is num
        ? '${total.toStringAsFixed(2)} $currencySymbol'
        : '${double.tryParse('$total')?.toStringAsFixed(2) ?? '0.00'} $currencySymbol';
    final customerName = (order['customer_name'] ??
            order['full_name'] ??
            order['customer_id'] ??
            'عميل')
        .toString();
    final customerPhone =
        (order['customer_phone'] ?? order['phone'] ?? '').toString();
    final date = DateTime.tryParse(
      (order['created_at'] ?? order['createdAt'] ?? '').toString(),
    );
    final statusColor = _adminOrderStatusColor(status);
    final isClosed = {'cancelled', 'rejected', 'delivered'}.contains(status);
    final isArchived = order['is_archived'] == true;
    final isUpdating = _updatingOrderIds.contains(id);
    final itemCount = items.length;
    final displayNumber = OrderNumber.fromOrder(order);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isArchived
                        ? 'طلب #$displayNumber • مؤرشف'
                        : 'طلب #$displayNumber',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    DeliveryService.statusLabel(status),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 68,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) => _AdminOrderProductThumbnail(
                    orderId: id,
                    index: index,
                    item: Map<String, dynamic>.from(items[index]),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(customerName,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if (customerPhone.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(customerPhone,
                  style: const TextStyle(color: Color(0xFF6B7280))),
            ],
            if (date != null) ...[
              const SizedBox(height: 4),
              Text(
                '${date.toLocal()}'.split('.').first,
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
              ),
            ],
            const Divider(height: 22),
            Row(
              children: [
                Expanded(child: Text('$itemCount منتجات')),
                Text(
                  totalText,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if ((status == 'cancelled' || status == 'rejected') &&
                ((order['cancellation_reason'] ?? order['rejection_reason'])
                        ?.toString()
                        .isNotEmpty ??
                    false))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  status == 'rejected'
                      ? 'سبب الرفض: ${order['rejection_reason']}'
                      : 'سبب الإلغاء: ${order['cancellation_reason']}',
                  style: const TextStyle(color: Color(0xFFB91C1C)),
                ),
              ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => _showOrderDetails(order),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('عرض جميع تفاصيل الطلب'),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _toggleOrderArchived(order),
                icon: Icon(isArchived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined),
                label: Text(isArchived ? 'استعادة الطلب' : 'أرشفة الطلب'),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed:
                    isUpdating ? null : () => _deleteOrderForAdmin(order),
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('حذف الطلب نهائيًا'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB91C1C),
                ),
              ),
            ),
            if (!isClosed && !isArchived) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed:
                      isUpdating ? null : () => _showOrderActionDialog(order),
                  icon: isUpdating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.settings_rounded),
                  label:
                      Text(isUpdating ? 'جارٍ تحديث الطلب' : 'إجراءات الطلب'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AdminOrderProductThumbnail extends StatelessWidget {
  const _AdminOrderProductThumbnail({
    required this.orderId,
    required this.index,
    required this.item,
  });

  final String orderId;
  final int index;
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final productName =
        (item['product_name'] ?? item['productName'] ?? 'منتج ${index + 1}')
            .toString();
    final imageUrls = resolveAdminProductImageUrls(item);
    final image = imageUrls.isEmpty
        ? null
        : MediaUploadService.imageProvider(imageUrls.first);

    return Tooltip(
      message: productName,
      child: Semantics(
        image: true,
        label: 'صورة المنتج $productName',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 60,
            height: 60,
            padding: const EdgeInsets.all(4),
            color: const Color(0xFFF3F4F6),
            alignment: Alignment.center,
            child: image == null
                ? const Icon(
                    Icons.shopping_bag_rounded,
                    color: Color(0xFF9CA3AF),
                  )
                : Image(
                    key: ValueKey(
                      'admin-order-product-image-$orderId-$index',
                    ),
                    image: image,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _AdminOrderDashboardData {
  const _AdminOrderDashboardData({
    required this.summary,
    required this.summaryError,
    required this.orders,
  });

  final AdminManagementSummary? summary;
  final Object? summaryError;
  final List<Map<String, dynamic>> orders;
}

class _OrderSummaryLoad {
  const _OrderSummaryLoad({this.summary, this.error});

  final AdminManagementSummary? summary;
  final Object? error;
}

class _AdminOrderProof {
  const _AdminOrderProof({required this.proof, required this.raw});

  final PaymentProofModel proof;
  final Map<String, dynamic> raw;
}

class _AdminOrderDetailData {
  const _AdminOrderDetailData({
    required this.order,
    required this.profiles,
    required this.proofs,
    required this.deliveryUpdates,
  });

  final Map<String, dynamic> order;
  final Map<String, Map<String, dynamic>> profiles;
  final List<_AdminOrderProof> proofs;
  final List<Map<String, dynamic>> deliveryUpdates;
}

class _AdminOrderDetailsSheet extends StatefulWidget {
  const _AdminOrderDetailsSheet({
    required this.loadDetails,
    required this.isUpdating,
    required this.onManage,
    required this.onOpenMap,
    required this.onShowReceipt,
    required this.onReviewProof,
    required this.onRefresh,
  });

  final Future<_AdminOrderDetailData> Function() loadDetails;
  final bool isUpdating;
  final VoidCallback onManage;
  final Future<void> Function(String label, String address, String? coordinates)
      onOpenMap;
  final ValueChanged<PaymentProofModel> onShowReceipt;
  final Future<void> Function(PaymentProofModel proof, String status)
      onReviewProof;
  final VoidCallback onRefresh;

  @override
  State<_AdminOrderDetailsSheet> createState() =>
      _AdminOrderDetailsSheetState();
}

class _AdminOrderDetailsSheetState extends State<_AdminOrderDetailsSheet> {
  late Future<_AdminOrderDetailData> _detailsFuture;
  Timer? _refreshTimer;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _detailsFuture = widget.loadDetails();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refresh(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (!mounted || _refreshing) return;
    _refreshing = true;
    final future = widget.loadDetails();
    setState(() {
      _detailsFuture = future;
    });
    future.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Failed to refresh live order tracking: $error');
        debugPrintStack(stackTrace: stackTrace);
      },
    ).whenComplete(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AdminOrderDetailData>(
      future: _detailsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _OrderManagementMessage(
            icon: Icons.cloud_off_rounded,
            message: 'تعذر تحميل تفاصيل الطلب',
            details: AppErrorMessage.from(snapshot.error!),
            actionLabel: 'إعادة المحاولة',
            onAction: _refresh,
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return _AdminOrderDetailsView(
          data: snapshot.data!,
          isUpdating: widget.isUpdating,
          onManage: widget.onManage,
          onOpenMap: widget.onOpenMap,
          onShowReceipt: widget.onShowReceipt,
          onReviewProof: widget.onReviewProof,
          onRefresh: widget.onRefresh,
        );
      },
    );
  }
}

class _AdminOrderDetailsView extends StatelessWidget {
  const _AdminOrderDetailsView({
    required this.data,
    required this.isUpdating,
    required this.onManage,
    required this.onOpenMap,
    required this.onShowReceipt,
    required this.onReviewProof,
    required this.onRefresh,
  });

  final _AdminOrderDetailData data;
  final bool isUpdating;
  final VoidCallback onManage;
  final Future<void> Function(String label, String address, String? coordinates)
      onOpenMap;
  final ValueChanged<PaymentProofModel> onShowReceipt;
  final Future<void> Function(PaymentProofModel proof, String status)
      onReviewProof;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final order = data.order;
    final status = (order['status'] ?? 'pending_payment').toString();
    final items = (order['items'] ?? order['order_items']) is List
        ? ((order['items'] ?? order['order_items']) as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
        : const <Map<String, dynamic>>[];
    final customerId =
        (order['customer_id'] ?? order['customerId'] ?? '').toString();
    final driverId = (order['driver_id'] ?? order['driverId'] ?? '').toString();
    final customer = data.profiles[customerId] ??
        _mapValue(order['customer_snapshot'] ?? order['customer']);
    final driver = data.profiles[driverId] ??
        _mapValue(order['driver_snapshot'] ?? order['driver']);
    final merchantIds = <String>{
      if ((order['merchant_id'] ?? order['merchantId'])
              ?.toString()
              .trim()
              .isNotEmpty ==
          true)
        (order['merchant_id'] ?? order['merchantId']).toString(),
      ...items
          .map((item) => (item['merchant_id'] ?? item['merchantId'] ?? '')
              .toString()
              .trim())
          .where((id) => id.isNotEmpty),
    };
    final merchants = merchantIds
        .map((id) => data.profiles[id])
        .whereType<Map<String, dynamic>>()
        .toList();
    for (final item in items) {
      final merchantSnapshot =
          _mapValue(item['merchant_snapshot'] ?? item['merchant']);
      if (merchantSnapshot.isNotEmpty &&
          !merchants.any(
            (merchant) =>
                merchant['id']?.toString() ==
                merchantSnapshot['id']?.toString(),
          )) {
        merchants.add(merchantSnapshot);
      }
    }
    final currency = (order['currency_symbol'] ??
            order['currencySymbol'] ??
            (items.isNotEmpty
                ? (items.first['currency_symbol'] ??
                    items.first['currencySymbol'] ??
                    'ر.ي')
                : 'ر.ي'))
        .toString();
    final latestUpdate =
        data.deliveryUpdates.isEmpty ? null : data.deliveryUpdates.last;

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFF8E8), Color(0xFFFFFFFF)],
              begin: AlignmentDirectional.centerStart,
              end: AlignmentDirectional.centerEnd,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE9D9B6)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x101B120C),
                blurRadius: 16,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AF37).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: Color(0xFF8A6D26),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تفاصيل الطلب',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '#${OrderNumber.fromOrder(order)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF6B7280),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  DeliveryService.statusLabel(status),
                  style: const TextStyle(
                    color: Color(0xFF1D4ED8),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'تحديث التفاصيل',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                tooltip: 'إغلاق التفاصيل',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            children: [
              _OrderDetailSection(
                title: 'الحالة والمتابعة',
                icon: Icons.track_changes_rounded,
                children: [
                  _OrderDetailLine(
                    label: 'الحالة الحالية',
                    value: DeliveryService.statusLabel(status),
                  ),
                  _OrderDetailLine(
                    label: 'حالة السائق',
                    value: (order['driver_status'] ?? 'غير محدد').toString(),
                  ),
                  _OrderDetailLine(
                    label: 'الوقت المتوقع',
                    value: (latestUpdate?['eta'] ?? order['eta'] ?? 'غير محدد')
                        .toString(),
                  ),
                  if (order['cancellation_reason'] != null)
                    _OrderDetailLine(
                      label: 'سبب الإلغاء',
                      value: order['cancellation_reason'].toString(),
                    ),
                  const Divider(),
                  _OrderTimeline(
                    order: order,
                    proofs: data.proofs,
                    deliveryUpdates: data.deliveryUpdates,
                  ),
                ],
              ),
              _OrderDetailSection(
                title: 'العميل',
                icon: Icons.person_pin_circle_rounded,
                children: [
                  _ProfileDetailLines(
                      profile: customer, fallback: order, prefix: 'customer'),
                  _LocationAction(
                    label: 'العميل',
                    address: _firstValue([
                      order['delivery_address'],
                      order['shipping_address'],
                      order['address'],
                      customer['address'],
                      customer['current_location'],
                    ]),
                    coordinates: _coordinateText(
                          order,
                          latitudeKeys: const [
                            'customer_latitude',
                            'delivery_latitude',
                            'latitude',
                          ],
                          longitudeKeys: const [
                            'customer_longitude',
                            'delivery_longitude',
                            'longitude',
                          ],
                          locationKeys: const [
                            'delivery_address',
                            'shipping_address',
                          ],
                        ) ??
                        _coordinateText(
                          customer,
                          latitudeKeys: const ['latitude', 'customer_latitude'],
                          longitudeKeys: const [
                            'longitude',
                            'customer_longitude',
                          ],
                          locationKeys: const [
                            'current_location',
                            'address',
                            'location',
                          ],
                        ),
                    onOpenMap: onOpenMap,
                  ),
                ],
              ),
              _OrderDetailSection(
                title: merchants.length == 1 ? 'التاجر' : 'التجار',
                icon: Icons.store_mall_directory_rounded,
                children: merchants.isEmpty
                    ? const [
                        _OrderDetailLine(
                          label: 'بيانات التاجر',
                          value: 'لا توجد بيانات تاجر مرتبطة بالطلب',
                        ),
                      ]
                    : merchants
                        .map(
                          (merchant) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _ProfileDetailLines(
                                profile: merchant,
                                fallback: const {},
                                prefix: 'merchant',
                              ),
                              _LocationAction(
                                label: 'التاجر',
                                address: _firstValue([
                                  merchant['shop_location'],
                                  merchant['shop_address'],
                                  merchant['address'],
                                  merchant['current_location'],
                                ]),
                                coordinates: _coordinateText(
                                  merchant,
                                  latitudeKeys: const [
                                    'shop_latitude',
                                    'latitude',
                                  ],
                                  longitudeKeys: const [
                                    'shop_longitude',
                                    'longitude',
                                  ],
                                  locationKeys: const [
                                    'shop_location',
                                    'shop_address',
                                    'address',
                                  ],
                                ),
                                onOpenMap: onOpenMap,
                              ),
                              const Divider(),
                            ],
                          ),
                        )
                        .toList(),
              ),
              _OrderDetailSection(
                title: 'السائق',
                icon: Icons.delivery_dining_rounded,
                children: [
                  _ProfileDetailLines(
                    profile: driver,
                    fallback: order,
                    prefix: 'driver',
                  ),
                ],
              ),
              _OrderDetailSection(
                title: 'المنتجات (${items.length})',
                icon: Icons.inventory_2_rounded,
                children: items.isEmpty
                    ? const [
                        _OrderDetailLine(
                          label: 'المنتجات',
                          value: 'لا توجد تفاصيل منتجات محفوظة',
                        ),
                      ]
                    : items
                        .asMap()
                        .entries
                        .map(
                          (entry) => _OrderItemDetailCard(
                            index: entry.key + 1,
                            item: entry.value,
                            currency: (entry.value['currency_symbol'] ??
                                    entry.value['currencySymbol'] ??
                                    'ر.س')
                                .toString(),
                          ),
                        )
                        .toList(),
              ),
              _OrderDetailSection(
                title: 'المبالغ والدفع',
                icon: Icons.payments_rounded,
                children: [
                  _OrderDetailLine(
                    label: 'طريقة الدفع',
                    value: (order['payment_wallet_name'] ??
                            order['paymentWalletName'] ??
                            order['payment_method'] ??
                            order['paymentMethod'] ??
                            'غير محددة')
                        .toString(),
                  ),
                  _OrderDetailLine(
                    label: 'المجموع الفرعي',
                    value: '${_displayAmount(order['subtotal'])} $currency',
                  ),
                  _OrderDetailLine(
                    label: 'أجرة التوصيل',
                    value:
                        '${_displayAmount(order['shipping_fee'] ?? order['shippingFee'])} $currency',
                  ),
                  _OrderDetailLine(
                    label: 'العمولة',
                    value: '${_displayAmount(order['commission'])} $currency',
                  ),
                  _OrderDetailLine(
                    label: 'الإجمالي',
                    value: '${_displayAmount(order['total'])} $currency',
                    emphasis: true,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'إيصالات الدفع (${data.proofs.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (data.proofs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text('لا يوجد إيصال دفع مرفق بهذا الطلب.'),
                    )
                  else
                    ...data.proofs.map(
                      (proof) => _OrderProofCard(
                        proof: proof,
                        onShowReceipt: onShowReceipt,
                        onReviewProof: onReviewProof,
                      ),
                    ),
                ],
              ),
              _OrderDetailSection(
                title: 'التواريخ والتوقيتات',
                icon: Icons.schedule_rounded,
                children: [
                  ..._orderTimestampFields(order).map(
                    (entry) => _OrderDetailLine(
                      label: _detailFieldLabel(entry.key),
                      value: _formatTimestamp(entry.value),
                    ),
                  ),
                  ...data.proofs.map(
                    (entry) => _OrderDetailLine(
                      label: 'رفع إيصال ${entry.proof.id}',
                      value: _formatTimestamp(entry.proof.createdAt),
                    ),
                  ),
                  ...data.deliveryUpdates.map(
                    (update) => _OrderDetailLine(
                      label:
                          'تحديث توصيل: ${DeliveryService.statusLabel((update['status'] ?? '').toString())}',
                      value: _formatTimestamp(
                        update['created_at'] ?? update['createdAt'],
                      ),
                    ),
                  ),
                ],
              ),
              _OrderDetailSection(
                title: 'بيانات الطلب المحفوظة',
                icon: Icons.data_object_rounded,
                children: order.entries
                    .where((entry) =>
                        entry.key != 'items' &&
                        entry.key != 'order_items' &&
                        !_isPrivateOrderField(entry.key))
                    .map(
                      (entry) => _OrderDetailLine(
                        label: _detailFieldLabel(entry.key),
                        value: _displayDetailValue(entry.value),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: isUpdating ? null : onManage,
                icon: isUpdating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.tune_rounded),
                label: Text(
                  isUpdating ? 'جارٍ تحديث الطلب' : 'إدارة هذا الطلب',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OrderDetailSection extends StatelessWidget {
  const _OrderDetailSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 1,
      shadowColor: const Color(0x14000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFECE7DF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: const Color(0xFF8A6D26),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 22),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _OrderDetailLine extends StatelessWidget {
  const _OrderDetailLine({
    required this.label,
    required this.value,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 6,
            child: SelectableText(
              value,
              textAlign: TextAlign.start,
              style: TextStyle(
                fontSize: 13,
                fontWeight: emphasis ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileDetailLines extends StatelessWidget {
  const _ProfileDetailLines({
    required this.profile,
    required this.fallback,
    required this.prefix,
  });

  final Map<String, dynamic> profile;
  final Map<String, dynamic> fallback;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    final name = _firstValue([
      profile['full_name'],
      profile['fullName'],
      fallback['${prefix}_name'],
      fallback['${prefix}Name'],
      fallback['courier_name'],
    ]);
    final phone = _firstValue([
      profile['phone'],
      fallback['${prefix}_phone'],
      fallback['${prefix}Phone'],
    ]);
    final id = _firstValue([
      profile['id'],
      fallback['${prefix}_id'],
      fallback['${prefix}Id'],
    ]);
    final role = _firstValue([profile['role']]);
    final details = <(String, String)>[
      if (name.isNotEmpty) ('الاسم', name),
      if (phone.isNotEmpty) ('الهاتف', phone),
      if (id.isNotEmpty) ('المعرف', id),
      if (role.isNotEmpty) ('الدور', role),
      for (final entry in profile.entries)
        if (!_isPrivateOrderField(entry.key) &&
            !{
              'id',
              'full_name',
              'fullName',
              'phone',
              'role',
              'password_hash',
              'latitude',
              'longitude',
              'lat',
              'lng',
              'lon',
              'customer_latitude',
              'customer_longitude',
              'driver_latitude',
              'driver_longitude',
              'shop_latitude',
              'shop_longitude',
              'address',
              'delivery_address',
              'shipping_address',
              'current_location',
              'location',
              'shop_location',
              'shop_address',
            }.contains(entry.key) &&
            entry.value != null &&
            entry.value.toString().trim().isNotEmpty)
          (_detailFieldLabel(entry.key), _displayDetailValue(entry.value)),
    ];
    if (details.isEmpty) {
      return const _OrderDetailLine(
        label: 'بيانات الطرف',
        value: 'لا توجد بيانات ملف شخصي مرتبطة',
      );
    }
    return Column(
      children: details
          .map((detail) => _OrderDetailLine(
                label: detail.$1,
                value: detail.$2,
              ))
          .toList(),
    );
  }
}

class _LocationAction extends StatelessWidget {
  const _LocationAction({
    required this.label,
    required this.address,
    required this.coordinates,
    required this.onOpenMap,
  });

  final String label;
  final String address;
  final String? coordinates;
  final Future<void> Function(String label, String address, String? coordinates)
      onOpenMap;

  @override
  Widget build(BuildContext context) {
    final displayAddress = _humanLocationAddress(address);
    if (displayAddress.isEmpty && coordinates == null) {
      return const _OrderDetailLine(
        label: 'الموقع',
        value: 'لا توجد بيانات موقع محفوظة',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (displayAddress.isNotEmpty)
          _OrderDetailLine(label: 'العنوان', value: displayAddress),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => onOpenMap(label, displayAddress, coordinates),
            icon: const Icon(Icons.map_outlined),
            label: Text('فتح موقع $label على الخريطة'),
          ),
        ),
      ],
    );
  }
}

class _OrderItemDetailCard extends StatelessWidget {
  const _OrderItemDetailCard({
    required this.index,
    required this.item,
    required this.currency,
  });

  final int index;
  final Map<String, dynamic> item;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final status = (item['status'] ?? 'available').toString();
    final name = (item['product_name'] ?? item['productName'] ?? 'منتج $index')
        .toString();
    final quantity = item['quantity'] ?? 0;
    final unitPrice = item['unit_price'] ?? item['unitPrice'];
    final total = item['total'];
    final merchantName =
        (item['merchant_name'] ?? item['merchantName'] ?? '').toString();
    final options = [
      if ((item['selected_color'] ?? item['selectedColor'])
              ?.toString()
              .isNotEmpty ==
          true)
        'اللون: ${item['selected_color'] ?? item['selectedColor']}',
      if ((item['selected_size'] ?? item['selectedSize'])
              ?.toString()
              .isNotEmpty ==
          true)
        'المقاس: ${item['selected_size'] ?? item['selectedSize']}',
    ].join(' • ');
    final image = MediaUploadService.imageProvider(
      (item['image_url'] ?? item['imageUrl'] ?? item['cover_image_url'])
          ?.toString(),
    );
    const displayedFields = {
      'product_id',
      'productId',
      'product_name',
      'productName',
      'product_category',
      'productCategory',
      'product_description',
      'productDescription',
      'quantity',
      'unit_price',
      'unitPrice',
      'total',
      'selected_color',
      'selectedColor',
      'selected_size',
      'selectedSize',
      'image_url',
      'imageUrl',
      'cover_image_url',
      'merchant_id',
      'merchantId',
      'merchant_name',
      'merchantName',
      'status',
      'rejection_reason',
      'rejectionReason',
    };
    final additionalDetails = item.entries
        .where((entry) =>
            !displayedFields.contains(entry.key) &&
            !_isPrivateOrderField(entry.key) &&
            entry.value != null)
        .map(
          (entry) => _OrderDetailLine(
            label: _detailFieldLabel(entry.key),
            value: _displayDetailValue(entry.value),
          ),
        )
        .toList();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (image != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image(
                      image: image,
                      width: 58,
                      height: 58,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(
                        width: 58,
                        height: 58,
                        child: Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Text(
                  '$index. $name',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          _OrderDetailLine(
              label: 'معرف المنتج',
              value: (item['product_id'] ?? item['productId'] ?? 'غير محدد')
                  .toString()),
          _OrderDetailLine(label: 'الكمية', value: quantity.toString()),
          _OrderDetailLine(
              label: 'سعر الوحدة',
              value: '${_displayAmount(unitPrice)} $currency'),
          _OrderDetailLine(
              label: 'الإجمالي', value: '${_displayAmount(total)} $currency'),
          if (merchantName.isNotEmpty)
            _OrderDetailLine(label: 'التاجر', value: merchantName),
          if (options.isNotEmpty)
            _OrderDetailLine(label: 'الخيارات', value: options),
          _OrderDetailLine(label: 'حالة المنتج', value: status),
          if ((item['rejection_reason'] ?? item['rejectionReason'])
                  ?.toString()
                  .isNotEmpty ==
              true)
            _OrderDetailLine(
              label: 'سبب الرفض',
              value: (item['rejection_reason'] ?? item['rejectionReason'])
                  .toString(),
            ),
          if ((item['product_description'] ?? item['productDescription'])
                  ?.toString()
                  .isNotEmpty ==
              true)
            _OrderDetailLine(
              label: 'الوصف',
              value: (item['product_description'] ?? item['productDescription'])
                  .toString(),
            ),
          ...additionalDetails,
        ],
      ),
    );
  }
}

class _OrderProofCard extends StatelessWidget {
  const _OrderProofCard({
    required this.proof,
    required this.onShowReceipt,
    required this.onReviewProof,
  });

  final _AdminOrderProof proof;
  final ValueChanged<PaymentProofModel> onShowReceipt;
  final Future<void> Function(PaymentProofModel proof, String status)
      onReviewProof;

  @override
  Widget build(BuildContext context) {
    final imageProvider =
        MediaUploadService.imageProvider(proof.proof.imageUrl);
    final status = switch (proof.proof.status) {
      'approved' => 'معتمد',
      'rejected' => 'مرفوض',
      'pending' => 'قيد المراجعة',
      _ => proof.proof.status,
    };
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long_rounded),
                const SizedBox(width: 8),
                Expanded(child: Text('إيصال ${proof.proof.id}')),
                Chip(label: Text(status)),
              ],
            ),
            _OrderDetailLine(
              label: 'رفع بواسطة',
              value: proof.proof.uploadedBy,
            ),
            _OrderDetailLine(
              label: 'تاريخ الرفع',
              value: _formatTimestamp(proof.proof.createdAt),
            ),
            if (proof.proof.note?.trim().isNotEmpty == true)
              _OrderDetailLine(
                  label: 'ملاحظة العميل', value: proof.proof.note!),
            if (proof.proof.reviewNote?.trim().isNotEmpty == true)
              _OrderDetailLine(
                label: 'ملاحظة المراجعة',
                value: proof.proof.reviewNote!,
              ),
            if (proof.raw['reviewed_at'] != null)
              _OrderDetailLine(
                label: 'تاريخ المراجعة',
                value: _formatTimestamp(proof.raw['reviewed_at']),
              ),
            if (imageProvider != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: InkWell(
                  onTap: () => onShowReceipt(proof.proof),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: Center(
                      child: Image(
                        image: imageProvider,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Text(
                          'تعذر تحميل صورة الإيصال',
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('لا تتوفر صورة قابلة للعرض لهذا الإيصال'),
              ),
            if (imageProvider != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => onShowReceipt(proof.proof),
                  icon: const Icon(Icons.zoom_in_rounded),
                  label: const Text('تكبير الإيصال'),
                ),
              ),
            if (proof.proof.status == 'pending')
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => onReviewProof(proof.proof, 'approved'),
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: const Text('اعتماد الإيصال'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => onReviewProof(proof.proof, 'rejected'),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('رفض الإيصال'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _OrderTimeline extends StatelessWidget {
  const _OrderTimeline({
    required this.order,
    required this.proofs,
    required this.deliveryUpdates,
  });

  final Map<String, dynamic> order;
  final List<_AdminOrderProof> proofs;
  final List<Map<String, dynamic>> deliveryUpdates;

  @override
  Widget build(BuildContext context) {
    final events = <(DateTime, String, String)>[];
    final rawHistory = order['status_history'] ?? order['statusHistory'];
    if (rawHistory is List) {
      for (final item in rawHistory.whereType<Map>()) {
        final history = Map<String, dynamic>.from(item);
        final date = DateTime.tryParse(
          (history['created_at'] ??
                  history['createdAt'] ??
                  history['timestamp'] ??
                  '')
              .toString(),
        );
        if (date == null) continue;
        final status = (history['status'] ?? '').toString();
        events.add((
          date,
          'تغيير حالة الطلب',
          [
            if (status.isNotEmpty) DeliveryService.statusLabel(status),
            history['note']?.toString() ?? '',
            history['changed_by']?.toString() ?? '',
          ].where((part) => part.isNotEmpty).join(' • '),
        ));
      }
    }
    for (final entry in _orderTimestampFields(order)) {
      final date = DateTime.tryParse(entry.value.toString());
      if (date == null) continue;
      events.add((
        date,
        _detailFieldLabel(entry.key),
        DeliveryService.statusLabel(
          (entry.key == 'created_at'
                  ? 'pending_payment'
                  : order['status'] ?? '')
              .toString(),
        ),
      ));
    }
    for (final proof in proofs) {
      events.add((
        proof.proof.createdAt,
        'إرفاق إيصال دفع',
        'حالة الإيصال: ${proof.proof.status}',
      ));
      final reviewedAt = DateTime.tryParse(
        proof.raw['reviewed_at']?.toString() ?? '',
      );
      if (reviewedAt != null) {
        events.add((reviewedAt, 'مراجعة إيصال الدفع', proof.proof.status));
      }
    }
    for (final update in deliveryUpdates) {
      final date = DateTime.tryParse(
        (update['created_at'] ?? update['createdAt'] ?? '').toString(),
      );
      if (date == null) continue;
      events.add((
        date,
        'تحديث حالة التوصيل',
        DeliveryService.statusLabel((update['status'] ?? '').toString()),
      ));
    }
    events.sort((first, second) => first.$1.compareTo(second.$1));

    if (events.isEmpty) {
      return const Text('لا يوجد سجل زمني محفوظ لهذا الطلب.');
    }
    return Column(
      children: events
          .map(
            (event) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.radio_button_checked_rounded, size: 18),
              title: Text(event.$2),
              subtitle: Text('${_formatTimestamp(event.$1)}\n${event.$3}'),
              isThreeLine: event.$3.isNotEmpty,
            ),
          )
          .toList(),
    );
  }
}

class _OrderManagementSummary extends StatelessWidget {
  const _OrderManagementSummary({required this.summary});

  final AdminManagementSummary summary;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      ('إجمالي الطلبات', summary.totalOrders, Icons.receipt_long_rounded),
      ('بانتظار المراجعة', summary.pendingApprovals, Icons.pending_actions),
      ('قيد التوصيل', summary.activeDeliveries, Icons.local_shipping_rounded),
      ('العملاء', summary.totalCustomers, Icons.people_alt_rounded),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: metrics.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 230,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.7,
      ),
      itemBuilder: (context, index) {
        final metric = metrics[index];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(metric.$3, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      metric.$2.toString(),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      metric.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OrderManagementSummaryWarning extends StatelessWidget {
  const _OrderManagementSummaryWarning({
    required this.details,
    required this.onRetry,
  });

  final String details;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFFFBEB),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 16, 8),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFB45309),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'تعذر تحميل مؤشرات الملخص؛ ما زال بإمكانك إدارة الطلبات.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      details,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'إعادة تحميل المؤشرات',
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderManagementMessage extends StatelessWidget {
  const _OrderManagementMessage({
    required this.icon,
    required this.message,
    required this.details,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String details;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: const Color(0xFF6B7280)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            const SizedBox(height: 8),
            Text(details, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

const _adminOrderStatuses = [
  'pending_payment',
  'awaiting_confirmation',
  'confirmed',
  'preparing',
  'accepted',
  'picked_up',
  'shipped',
  'delivered',
  'cancelled',
  'rejected',
];

Color _adminOrderStatusColor(String status) => switch (status) {
      'cancelled' || 'rejected' => const Color(0xFFB91C1C),
      'delivered' => const Color(0xFF047857),
      'shipped' || 'picked_up' => const Color(0xFF1D4ED8),
      'pending_payment' || 'awaiting_confirmation' => const Color(0xFFB45309),
      _ => const Color(0xFF6B7280),
    };

String _firstValue(Iterable<Object?> values) {
  for (final value in values) {
    final text = value is Map
        ? _firstValue([
            value['formatted_address'],
            value['full_address'],
            value['address_line'],
            value['street_address'],
            value['address'],
            value['street'],
            value['district'],
            value['city'],
            value['region'],
            value['landmark'],
            value['details'],
          ])
        : _humanLocationAddress(value?.toString().trim() ?? '');
    if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
  }
  return '';
}

String _humanLocationAddress(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty ||
      RegExp(r'^-?\d+(?:\.\d+)?\s*[,،]\s*-?\d+(?:\.\d+)?$')
          .hasMatch(normalized)) {
    return '';
  }
  return normalized;
}

Map<String, dynamic> _mapValue(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

String? _coordinateText(
  Map<String, dynamic> source, {
  required List<String> latitudeKeys,
  required List<String> longitudeKeys,
  required List<String> locationKeys,
}) {
  final latitude = _firstValue(latitudeKeys.map((key) => source[key]));
  final longitude = _firstValue(longitudeKeys.map((key) => source[key]));
  final parsedLatitude = double.tryParse(latitude);
  final parsedLongitude = double.tryParse(longitude);
  if (parsedLatitude != null &&
      parsedLongitude != null &&
      parsedLatitude >= -90 &&
      parsedLatitude <= 90 &&
      parsedLongitude >= -180 &&
      parsedLongitude <= 180) {
    return '$parsedLatitude,$parsedLongitude';
  }

  for (final key in locationKeys) {
    final location = source[key];
    if (location is Map) {
      final nested = Map<String, dynamic>.from(location);
      final nestedLatitude = double.tryParse(
        _firstValue([nested['latitude'], nested['lat']]),
      );
      final nestedLongitude = double.tryParse(
        _firstValue([nested['longitude'], nested['lng'], nested['lon']]),
      );
      if (nestedLatitude != null &&
          nestedLongitude != null &&
          nestedLatitude >= -90 &&
          nestedLatitude <= 90 &&
          nestedLongitude >= -180 &&
          nestedLongitude <= 180) {
        return '$nestedLatitude,$nestedLongitude';
      }
    }
    final match = RegExp(
      r'(-?\d+(?:\.\d+)?)\s*[,،]\s*(-?\d+(?:\.\d+)?)',
    ).firstMatch(location?.toString() ?? '');
    if (match == null) continue;
    final nestedLatitude = double.tryParse(match.group(1)!);
    final nestedLongitude = double.tryParse(match.group(2)!);
    if (nestedLatitude != null &&
        nestedLongitude != null &&
        nestedLatitude >= -90 &&
        nestedLatitude <= 90 &&
        nestedLongitude >= -180 &&
        nestedLongitude <= 180) {
      return '$nestedLatitude,$nestedLongitude';
    }
  }
  return null;
}

List<MapEntry<String, Object?>> _orderTimestampFields(
  Map<String, dynamic> order,
) {
  final entries = <MapEntry<String, Object?>>[];
  for (final entry in order.entries) {
    final key = entry.key.toLowerCase();
    if (!(key.endsWith('_at') ||
            key.endsWith('at') ||
            key.contains('timestamp')) ||
        _isPrivateOrderField(key) ||
        entry.value == null) {
      continue;
    }
    if (DateTime.tryParse(entry.value.toString()) != null) {
      entries.add(MapEntry(entry.key, entry.value as Object));
    }
  }
  entries.sort((first, second) {
    final firstDate = DateTime.tryParse(first.value.toString())!;
    final secondDate = DateTime.tryParse(second.value.toString())!;
    return firstDate.compareTo(secondDate);
  });
  return entries;
}

bool _isPrivateOrderField(String key) {
  final normalized = key.toLowerCase();
  if (normalized.contains('otp') &&
      (normalized.contains('verified') ||
          normalized.contains('attempt') ||
          normalized.contains('expires') ||
          normalized.contains('locked'))) {
    return false;
  }
  return RegExp(r'(otp|password|token|secret|pin|hash|authorization)')
      .hasMatch(normalized);
}

String _displayDetailValue(Object? value) {
  if (value == null) return 'غير محدد';
  if (value is bool || value is num || value is String) {
    return value.toString();
  }
  if (value is DateTime) return _formatTimestamp(value);
  try {
    return jsonEncode(_sanitizePrivateDetails(value));
  } on Object {
    return value.toString();
  }
}

Object? _sanitizePrivateDetails(Object? value) {
  if (value is Map) {
    return Map<String, Object?>.fromEntries(
      value.entries
          .where((entry) => !_isPrivateOrderField(entry.key.toString()))
          .map(
            (entry) => MapEntry(
              entry.key.toString(),
              _sanitizePrivateDetails(entry.value),
            ),
          ),
    );
  }
  if (value is Iterable) {
    return value.map(_sanitizePrivateDetails).toList();
  }
  return value;
}

String _displayAmount(Object? value) {
  final amount = value is num ? value.toDouble() : double.tryParse('$value');
  return amount?.toStringAsFixed(2) ?? '0.00';
}

String _formatTimestamp(Object? value) {
  final date =
      value is DateTime ? value : DateTime.tryParse(value?.toString() ?? '');
  if (date == null) return value?.toString() ?? 'غير محدد';
  return date.toLocal().toString().split('.').first;
}

String _detailFieldLabel(String field) {
  const labels = {
    'id': 'المعرف',
    'order_id': 'رقم الطلب',
    'customer_id': 'معرف العميل',
    'customer_name': 'اسم العميل',
    'customer_phone': 'هاتف العميل',
    'merchant_id': 'معرف التاجر',
    'merchant_name': 'اسم التاجر',
    'driver_id': 'معرف السائق',
    'driver_name': 'اسم السائق',
    'courier_name': 'اسم السائق',
    'driver_phone': 'هاتف السائق',
    'driver_status': 'حالة السائق',
    'status': 'الحالة',
    'payment_method': 'طريقة الدفع',
    'payment_proof_id': 'معرف إيصال الدفع',
    'created_at': 'تاريخ إنشاء الطلب',
    'updated_at': 'آخر تحديث',
    'confirmed_at': 'تاريخ التأكيد',
    'accepted_at': 'تاريخ القبول',
    'preparing_at': 'تاريخ بدء التجهيز',
    'shipped_at': 'تاريخ الشحن',
    'picked_up_at': 'تاريخ استلام السائق',
    'delivered_at': 'تاريخ التسليم',
    'cancelled_at': 'تاريخ الإلغاء',
    'driver_assigned_at': 'تاريخ إسناد السائق',
    'dispatcher_assigned_at': 'تاريخ إسناد مسؤول التوصيل',
    'delivery_address': 'عنوان التسليم',
    'shipping_address': 'عنوان الشحن',
    'current_location': 'الموقع الحالي',
    'eta': 'الوقت المتوقع',
    'subtotal': 'المجموع الفرعي',
    'shipping_fee': 'أجرة التوصيل',
    'commission': 'العمولة',
    'total': 'الإجمالي',
    'cancelled_by': 'أُلغي بواسطة',
    'cancellation_reason': 'سبب الإلغاء',
    'delivery_otp_verified': 'تم التحقق من رمز التسليم',
    'pickup_otp_verified': 'تم التحقق من رمز الاستلام',
    'delivery_otp_attempts': 'محاولات رمز التسليم',
    'delivery_otp_locked': 'حالة قفل رمز التسليم',
    'delivery_otp_expires_at': 'انتهاء صلاحية رمز التسليم',
  };
  return labels[field] ??
      field.replaceAll('_', ' ').replaceAllMapped(
            RegExp(r'([a-z])([A-Z])'),
            (match) => '${match.group(1)} ${match.group(2)}',
          );
}

class LogoManagementScreen extends StatelessWidget {
  const LogoManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminDetailScreen(
      title: 'إدارة اللوجو',
      subtitle: 'إدارة شعار المنصة، الألوان، والهوية البصرية.',
      metrics: [
        MetricCardData(
          label: 'النسخ المتاحة',
          value: '4',
          color: Color(0xFFD4AF37),
          icon: Icons.palette_rounded,
        ),
        MetricCardData(
          label: 'الحالة',
          value: 'نشط',
          color: Color(0xFF10B981),
          icon: Icons.check_circle_rounded,
        ),
      ],
      rows: [
        ActionRowData(
          label: 'تحديث الشعار',
          value: 'رفع ملف SVG أو PNG',
          icon: Icons.upload_file_rounded,
          color: Color(0xFF8B5CF6),
        ),
        ActionRowData(
          label: 'إدارة الألوان',
          value: 'اللون الأساسي: ذهبي',
          icon: Icons.color_lens_rounded,
          color: Color(0xFFD4AF37),
        ),
      ],
    );
  }
}

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key, this.service});

  final AdminService? service;

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  late Future<List<Map<String, dynamic>>> _profilesFuture;
  final _searchController = TextEditingController();
  String _roleFilter = 'all';
  String _verificationFilter = 'all';
  bool _showArchivedProfiles = false;
  late final AdminService _service;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? AdminService();
    _profilesFuture = _loadProfiles();
  }

  Future<List<Map<String, dynamic>>> _loadProfiles() {
    return _service.getProfilesForAdmin(
      limit: null,
      propagateErrors: true,
      includeArchived: true,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _profilesFuture = _loadProfiles();
    });
    await _profilesFuture;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _filterProfiles(
    List<Map<String, dynamic>> profiles,
  ) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = profiles.where((profile) {
      final isArchived = profile['is_archived'] == true;
      final role = (profile['role'] ?? 'customer').toString().toLowerCase();
      final verified =
          profile['is_verified'] == true || profile['isVerified'] == true;
      final searchable = [
        profile['full_name'],
        profile['fullName'],
        profile['phone'],
        profile['email'],
      ].whereType<Object>().join(' ').toLowerCase();
      return isArchived == _showArchivedProfiles &&
          (_roleFilter == 'all' || role == _roleFilter) &&
          (_verificationFilter == 'all' ||
              verified == (_verificationFilter == 'verified')) &&
          (query.isEmpty || searchable.contains(query));
    }).toList();
    filtered.sort((left, right) {
      final leftName = (left['full_name'] ?? left['fullName'] ?? '')
          .toString()
          .toLowerCase();
      final rightName = (right['full_name'] ?? right['fullName'] ?? '')
          .toString()
          .toLowerCase();
      return leftName.compareTo(rightName);
    });
    return filtered;
  }

  String _roleLabel(String role) {
    switch (role.toLowerCase()) {
      case 'customer':
        return 'عميل';
      case 'merchant':
        return 'تاجر';
      case 'driver':
        return 'سائق';
      case 'admin':
        return 'مدير';
      default:
        return role.isEmpty ? 'غير محدد' : role;
    }
  }

  Future<void> _showRoleEditor(Map<String, dynamic> profile) async {
    final profileId = (profile['id'] ?? '').toString();
    if (profileId.trim().isEmpty) {
      _showMessage('تعذر تعديل الحساب لعدم توفر معرّف المستخدم');
      return;
    }

    final currentRole = (profile['role'] ?? 'customer').toString();
    var selectedRole = const {'customer', 'merchant', 'driver'}
            .contains(currentRole.toLowerCase())
        ? currentRole.toLowerCase()
        : 'customer';
    final role = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تعديل دور المستخدم'),
          content: DropdownButtonFormField<String>(
            initialValue: selectedRole,
            decoration: const InputDecoration(labelText: 'الدور'),
            items: const [
              DropdownMenuItem(value: 'customer', child: Text('عميل')),
              DropdownMenuItem(value: 'merchant', child: Text('تاجر')),
              DropdownMenuItem(value: 'driver', child: Text('سائق')),
            ],
            onChanged: (value) {
              if (value != null) {
                setDialogState(() => selectedRole = value);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selectedRole),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (role == null || role == currentRole.toLowerCase()) return;

    try {
      final updated = await _service.updateProfileRoleForAdmin(
        profileId: profileId,
        role: role,
      );
      if (!mounted) return;
      if (!updated) {
        _showMessage('تعذر حفظ دور المستخدم');
        return;
      }
      profile['role'] = role;
      setState(() {});
      _showMessage('تم تحديث دور المستخدم');
    } catch (error) {
      if (mounted) {
        _showMessage('فشل تحديث دور المستخدم: ${AppErrorMessage.from(error)}');
      }
      return;
    }
    try {
      await _refresh();
    } catch (error) {
      if (mounted) {
        _showMessage(
          'تم حفظ الدور لكن تعذر تحديث القائمة: ${AppErrorMessage.from(error)}',
        );
      }
    }
  }

  Future<void> _toggleVerification(Map<String, dynamic> profile) async {
    final profileId = (profile['id'] ?? '').toString();
    if (profileId.trim().isEmpty) {
      _showMessage('تعذر تحديث الحساب لعدم توفر معرّف المستخدم');
      return;
    }

    final isVerified =
        profile['is_verified'] == true || profile['isVerified'] == true;

    try {
      final updated = await _service.updateProfileVerificationForAdmin(
        profileId: profileId,
        isVerified: !isVerified,
      );
      if (!mounted) return;
      if (!updated) {
        _showMessage('تعذر تحديث حالة التوثيق');
        return;
      }
      profile['is_verified'] = !isVerified;
      setState(() {});
      _showMessage(isVerified ? 'تم إلغاء توثيق الحساب' : 'تم توثيق الحساب');
    } catch (error) {
      if (mounted) {
        _showMessage('فشل تحديث حالة التوثيق: ${AppErrorMessage.from(error)}');
      }
      return;
    }
    try {
      await _refresh();
    } catch (error) {
      if (mounted) {
        _showMessage(
          'تم تحديث التوثيق لكن تعذر تحديث القائمة: '
          '${AppErrorMessage.from(error)}',
        );
      }
    }
  }

  Future<void> _toggleProfileArchived(Map<String, dynamic> profile) async {
    final profileId = (profile['id'] ?? '').toString();
    final archived = profile['is_archived'] == true;
    final name = (profile['full_name'] ?? profile['fullName'] ?? 'هذا الحساب')
        .toString();
    if (profileId.trim().isEmpty ||
        (profile['role']?.toString().toLowerCase() == 'admin')) {
      _showMessage('لا يمكن أرشفة حساب المدير أو حساب بلا معرّف');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(archived ? 'استعادة الحساب' : 'أرشفة الحساب'),
        content: Text(
          archived
              ? 'هل تريد إظهار حساب «$name» مجددًا في قائمة الحسابات؟'
              : 'سيُخفى حساب «$name» من القائمة النشطة مع إبقاء بياناته وسجلاته. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(archived ? 'استعادة' : 'أرشفة'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.setProfileArchivedForAdmin(
        profileId: profileId,
        archived: !archived,
      );
      if (!mounted) return;
      setState(() => profile['is_archived'] = !archived);
      await _refresh();
      _showMessage(archived ? 'تمت استعادة الحساب' : 'تمت أرشفة الحساب');
    } catch (error) {
      if (mounted)
        _showMessage('تعذر تحديث الحساب: ${AppErrorMessage.from(error)}');
    }
  }

  Future<void> _deleteProfile(Map<String, dynamic> profile) async {
    final profileId = (profile['id'] ?? '').toString().trim();
    final role = (profile['role'] ?? 'customer').toString().toLowerCase();
    final name = (profile['full_name'] ?? profile['fullName'] ?? 'هذا الحساب')
        .toString();
    if (profileId.isEmpty || role == 'admin') {
      _showMessage('لا يمكن حذف حساب المدير أو حساب بلا معرّف');
      return;
    }

    final auth = AuthService();
    final requester =
        await auth.loadSession() ?? await auth.getCurrentProfile();
    if (!mounted) return;
    if (requester == null ||
        requester.role != 'admin' ||
        requester.phone.trim().isEmpty) {
      _showMessage('تعذر التحقق من حساب المدير لإتمام الحذف');
      return;
    }

    final password = await showAccountDeletionDialog(
      context,
      accountName: name,
      accountDescription: 'الحساب',
    );
    if (password == null || !mounted) return;

    try {
      await AccountDeletionService().deleteAccount(
        profileId: profileId,
        requesterPhone: requester.phone,
        password: password,
      );
      await _refresh();
      if (mounted) _showMessage('تم حذف الحساب نهائياً');
    } on AccountDeletionException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('تعذر حذف الحساب. حاول مرة أخرى.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _metricCard({
    required String label,
    required int value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value.toString(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openProfileDetails(Map<String, dynamic> profile) {
    Navigator.of(context).push(
      slideFadeRoute(
        page: AdminProfileDetailsScreen(
          profile: Map<String, dynamic>.from(profile),
        ),
      ),
    );
  }

  Widget _profileCard(Map<String, dynamic> profile) {
    final name =
        (profile['full_name'] ?? profile['fullName'] ?? 'مستخدم').toString();
    final phone = (profile['phone'] ?? '').toString();
    final email = (profile['email'] ?? '').toString();
    final role = (profile['role'] ?? 'customer').toString();
    final verified =
        profile['is_verified'] == true || profile['isVerified'] == true;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openProfileDetails(profile),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFEFF6FF),
                foregroundColor: const Color(0xFF2563EB),
                child: Text(name.trim().isEmpty ? 'م' : name.trim()[0]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (phone.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        phone,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (phone.isEmpty && email.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        _profileBadge(
                          _roleLabel(role),
                          const Color(0xFFEFF6FF),
                          const Color(0xFF1D4ED8),
                        ),
                        _profileBadge(
                          verified ? 'موثق' : 'غير موثق',
                          verified
                              ? const Color(0xFFECFDF5)
                              : const Color(0xFFFFF7ED),
                          verified
                              ? const Color(0xFF047857)
                              : const Color(0xFFC2410C),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.open_in_new_rounded,
                size: 17,
                color: Color(0xFF94A3B8),
              ),
              PopupMenuButton<String>(
                tooltip: 'إجراءات المستخدم',
                onSelected: (action) {
                  if (action == 'role') {
                    _showRoleEditor(profile);
                  } else if (action == 'verification') {
                    _toggleVerification(profile);
                  } else if (action == 'delete') {
                    _deleteProfile(profile);
                  } else {
                    _toggleProfileArchived(profile);
                  }
                },
                itemBuilder: (context) => [
                  if (role.toLowerCase() != 'admin')
                    const PopupMenuItem(
                      value: 'role',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.manage_accounts_outlined),
                        title: Text('تعديل الدور'),
                      ),
                    ),
                  PopupMenuItem(
                    value: 'verification',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        verified
                            ? Icons.verified_user_outlined
                            : Icons.verified_user_rounded,
                      ),
                      title: Text(verified ? 'إلغاء التوثيق' : 'توثيق الحساب'),
                    ),
                  ),
                  if (role.toLowerCase() != 'admin')
                    PopupMenuItem(
                      value: 'archive',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          profile['is_archived'] == true
                              ? Icons.unarchive_outlined
                              : Icons.archive_outlined,
                        ),
                        title: Text(profile['is_archived'] == true
                            ? 'استعادة الحساب'
                            : 'أرشفة الحساب'),
                      ),
                    ),
                  if (role.toLowerCase() != 'admin')
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.delete_forever_outlined,
                          color: Color(0xFFB91C1C),
                        ),
                        title: Text(
                          'حذف نهائي',
                          style: TextStyle(color: Color(0xFFB91C1C)),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _profileBadge(String label, Color background, Color foreground) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: const Text('إدارة المستخدمين'),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _profilesFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 100),
                  const Icon(
                    Icons.cloud_off_rounded,
                    size: 48,
                    color: Color(0xFFDC2626),
                  ),
                  const SizedBox(height: 16),
                  const Center(
                    child: Text(
                      'تعذر تحميل المستخدمين',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      AppErrorMessage.from(snapshot.error!),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF6B7280)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('إعادة المحاولة'),
                    ),
                  ),
                ],
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final profiles = snapshot.data!;
            final filteredProfiles = _filterProfiles(profiles);
            final verifiedCount = profiles
                .where((profile) =>
                    profile['is_verified'] == true ||
                    profile['isVerified'] == true)
                .length;
            final merchantCount = profiles
                .where((profile) =>
                    profile['role']?.toString().toLowerCase() == 'merchant')
                .length;

            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'الحسابات والأدوار',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'ابحث عن الحسابات، راجع بياناتها، وحدّث الدور أو حالة التوثيق.',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('عرض الحسابات المؤرشفة'),
                    value: _showArchivedProfiles,
                    onChanged: (value) =>
                        setState(() => _showArchivedProfiles = value),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _metricCard(
                        label: 'إجمالي الحسابات',
                        value: profiles.length,
                        icon: Icons.people_alt_rounded,
                        color: const Color(0xFF2563EB),
                      ),
                      const SizedBox(width: 10),
                      _metricCard(
                        label: 'التجار',
                        value: merchantCount,
                        icon: Icons.storefront_rounded,
                        color: const Color(0xFF059669),
                      ),
                      const SizedBox(width: 10),
                      _metricCard(
                        label: 'الحسابات الموثقة',
                        value: verifiedCount,
                        icon: Icons.verified_user_rounded,
                        color: const Color(0xFF7C3AED),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'ابحث بالاسم أو الهاتف أو البريد',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'مسح البحث',
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _roleFilter,
                          decoration: InputDecoration(
                            labelText: 'الدور',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'all',
                              child: Text('كل الأدوار'),
                            ),
                            DropdownMenuItem(
                              value: 'customer',
                              child: Text('العملاء'),
                            ),
                            DropdownMenuItem(
                              value: 'merchant',
                              child: Text('التجار'),
                            ),
                            DropdownMenuItem(
                              value: 'driver',
                              child: Text('السائقون'),
                            ),
                            DropdownMenuItem(
                              value: 'admin',
                              child: Text('المديرون'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _roleFilter = value);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _verificationFilter,
                          decoration: InputDecoration(
                            labelText: 'التوثيق',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'all',
                              child: Text('كل الحالات'),
                            ),
                            DropdownMenuItem(
                              value: 'verified',
                              child: Text('موثق'),
                            ),
                            DropdownMenuItem(
                              value: 'unverified',
                              child: Text('غير موثق'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _verificationFilter = value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'قائمة المستخدمين',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Text(
                        '${filteredProfiles.length} نتيجة',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (filteredProfiles.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Column(
                        children: [
                          Icon(
                            Icons.person_search_rounded,
                            size: 40,
                            color: Color(0xFF94A3B8),
                          ),
                          SizedBox(height: 8),
                          Text('لا توجد حسابات مطابقة للبحث أو التصفية'),
                        ],
                      ),
                    )
                  else
                    ...filteredProfiles.map(
                      (profile) => Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: _profileCard(profile),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MerchantDisplayDeliveryFeeDialog extends StatefulWidget {
  const _MerchantDisplayDeliveryFeeDialog({
    required this.currentFee,
    required this.globalFee,
    this.allowForAllMerchants = true,
  });

  final Object? currentFee;
  final double? globalFee;
  final bool allowForAllMerchants;

  @override
  State<_MerchantDisplayDeliveryFeeDialog> createState() =>
      _MerchantDisplayDeliveryFeeDialogState();
}

class _MerchantDisplayDeliveryFeeDialogState
    extends State<_MerchantDisplayDeliveryFeeDialog> {
  late final TextEditingController _controller;
  bool _forAllMerchants = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: (widget.currentFee ?? widget.globalFee)?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('أجرة التوصيل الظاهرة للتاجر'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.allowForAllMerchants)
            RadioGroup<bool>(
              groupValue: _forAllMerchants,
              onChanged: (value) => setState(() => _forAllMerchants = value!),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    value: false,
                    title: Text('هذا التاجر فقط'),
                  ),
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    value: true,
                    title: Text('جميع التجار'),
                    subtitle: Text(
                      'السعر الفردي المحدد لتاجر يبقى له الأولوية',
                    ),
                  ),
                ],
              ),
            ),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'مبلغ ثابت للطلب كاملًا',
              suffixText: CurrencyService.yerCurrency.symbol,
              helperText: 'اتركه فارغًا لإزالة السعر المحدد',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            _MerchantDisplayDeliveryFeeSelection(
              forAllMerchants: _forAllMerchants,
            ),
          ),
          child: const Text('إزالة التحديد'),
        ),
        FilledButton(
          onPressed: () {
            final text = _controller.text.trim();
            if (text.isEmpty) {
              Navigator.of(context).pop(
                _MerchantDisplayDeliveryFeeSelection(
                  forAllMerchants: _forAllMerchants,
                ),
              );
              return;
            }
            final fee = double.tryParse(text);
            if (fee == null || !fee.isFinite || fee < 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('أدخل مبلغًا صحيحًا وغير سالب')),
              );
              return;
            }
            Navigator.of(context).pop(
              _MerchantDisplayDeliveryFeeSelection(
                forAllMerchants: _forAllMerchants,
                fee: fee,
              ),
            );
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

class _MerchantDisplayDeliveryFeeSelection {
  const _MerchantDisplayDeliveryFeeSelection({
    required this.forAllMerchants,
    this.fee,
  });

  final bool forAllMerchants;
  final double? fee;
}

class _MerchantCreationSectionTitle extends StatelessWidget {
  const _MerchantCreationSectionTitle({
    required this.title,
    required this.icon,
  });

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF713F2B)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class MerchantManagementAdminScreen extends StatefulWidget {
  const MerchantManagementAdminScreen({super.key, this.service});

  final AdminService? service;

  @override
  State<MerchantManagementAdminScreen> createState() =>
      _MerchantManagementAdminScreenState();
}

class _MerchantManagementAdminScreenState
    extends State<MerchantManagementAdminScreen> {
  late Future<List<Map<String, dynamic>>> _merchantsFuture;
  late final AdminService _service;
  final _searchController = TextEditingController();
  String _verificationFilter = 'all';

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? AdminService();
    _merchantsFuture = _loadMerchants();
  }

  Future<List<Map<String, dynamic>>> _loadMerchants() {
    return _service.getProfilesForAdmin(
      role: 'merchant',
      limit: null,
      propagateErrors: true,
    );
  }

  Future<void> _refresh() async {
    final future = _loadMerchants();
    setState(() {
      _merchantsFuture = future;
    });
    await future;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isVerified(Map<String, dynamic> merchant) =>
      merchant['is_verified'] == true || merchant['isVerified'] == true;

  Future<void> _showCreateMerchantDialog() async {
    final formKey = GlobalKey<FormState>();
    final fullNameController = TextEditingController();
    final shopNameController = TextEditingController();
    final phoneController = TextEditingController();
    final categoryController = TextEditingController();
    final locationController = TextEditingController();
    final cityController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final contactPhoneControllers = <TextEditingController>[];
    final walletNameControllers = <TextEditingController>[];
    final walletAccountControllers = <TextEditingController>[];
    var saving = false;
    var showPassword = false;
    var showConfirmPassword = false;
    String? formError;

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 620,
              maxHeight: MediaQuery.sizeOf(context).height * 0.92,
            ),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsetsDirectional.fromSTEB(22, 18, 12, 18),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF713F2B), Color(0xFF9A5A3D)],
                    ),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.storefront_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'إنشاء حساب تاجر',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'أنشئ الحساب ووثّقه ثم أدخل بيانات المتجر',
                              style: TextStyle(
                                color: Color(0xFFEADBD4),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'إغلاق',
                        onPressed: saving
                            ? null
                            : () => Navigator.pop(dialogContext, false),
                        color: Colors.white,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7F3EE),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.verified_user_outlined,
                                  color: Color(0xFF713F2B),
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'لن يُرسل رمز تحقق. سيُوثق الحساب باعتماد المدير. '
                                    'اختر كلمة مرور أولية وشاركها مع التاجر بطريقة آمنة.',
                                    style: TextStyle(height: 1.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          const _MerchantCreationSectionTitle(
                            title: 'بيانات التاجر',
                            icon: Icons.person_outline_rounded,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            key: const ValueKey('admin-merchant-full-name'),
                            controller: fullNameController,
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              labelText: 'الاسم الكامل *',
                              prefixIcon: const Icon(Icons.person_outline),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                    ? 'أدخل الاسم الكامل'
                                    : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            key: const ValueKey('admin-merchant-phone'),
                            controller: phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              labelText: 'رقم الدخول الأساسي *',
                              helperText: 'سيستخدمه التاجر لتسجيل الدخول',
                              prefixIcon: const Icon(Icons.phone_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            validator: (value) {
                              final normalized =
                                  AuthService().normalizePhone(value ?? '');
                              return AppConstants.isYemenPhoneValid(normalized)
                                  ? null
                                  : 'أدخل رقم هاتف يمني صحيح';
                            },
                          ),
                          const SizedBox(height: 22),
                          const _MerchantCreationSectionTitle(
                            title: 'بيانات المتجر',
                            icon: Icons.storefront_outlined,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            key: const ValueKey('admin-merchant-shop-name'),
                            controller: shopNameController,
                            decoration: InputDecoration(
                              labelText: 'اسم المتجر *',
                              prefixIcon:
                                  const Icon(Icons.store_mall_directory),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                    ? 'أدخل اسم المتجر'
                                    : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: categoryController,
                            decoration: InputDecoration(
                              labelText: 'فئة المتجر (اختياري)',
                              hintText: 'مثل: أزياء، أغذية، إلكترونيات',
                              prefixIcon: const Icon(Icons.category_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            key: ValueKey(
                                'admin-merchant-city-${cityController.text}'),
                            initialValue: yemeniCities.contains(
                              cityController.text,
                            )
                                ? cityController.text
                                : null,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'مدينة / منطقة المتجر *',
                              prefixIcon: const Icon(Icons.location_city),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            items: yemeniCities
                                .map(
                                  (city) => DropdownMenuItem(
                                    value: city,
                                    child: Text(city),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              setDialogState(
                                () => cityController.text = value ?? '',
                              );
                            },
                            validator: (value) =>
                                value == null ? 'اختر مدينة المتجر' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: locationController,
                            minLines: 2,
                            maxLines: 3,
                            decoration: InputDecoration(
                              labelText: 'العنوان التفصيلي (اختياري)',
                              hintText: 'الحي، الشارع، وأقرب معلم',
                              alignLabelWithHint: true,
                              prefixIcon: const Icon(Icons.place_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'أرقام تواصل إضافية',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: saving
                                    ? null
                                    : () => setDialogState(
                                          () => contactPhoneControllers
                                              .add(TextEditingController()),
                                        ),
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('إضافة رقم'),
                              ),
                            ],
                          ),
                          if (contactPhoneControllers.isEmpty)
                            const Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                'اختياري — أضف رقمًا بديلًا للتواصل مع المتجر.',
                                style: TextStyle(
                                  color: Color(0xFF6B7280),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ...contactPhoneControllers.asMap().entries.map(
                            (entry) {
                              final index = entry.key;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: entry.value,
                                        keyboardType: TextInputType.phone,
                                        decoration: InputDecoration(
                                          labelText: 'رقم التواصل ${index + 1}',
                                          prefixIcon:
                                              const Icon(Icons.phone_in_talk),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          ),
                                        ),
                                        validator: (value) {
                                          final phone = value?.trim() ?? '';
                                          if (phone.isEmpty) return null;
                                          return AppConstants.isYemenPhoneValid(
                                            AuthService().normalizePhone(phone),
                                          )
                                              ? null
                                              : 'أدخل رقم هاتف يمني صحيح';
                                        },
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'حذف الرقم',
                                      onPressed: saving
                                          ? null
                                          : () => setDialogState(() {
                                                entry.value.dispose();
                                                contactPhoneControllers
                                                    .removeAt(index);
                                              }),
                                      icon: const Icon(
                                        Icons.remove_circle_outline_rounded,
                                        color: Color(0xFFB91C1C),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'محافظ استلام المستحقات',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: saving
                                    ? null
                                    : () => setDialogState(() {
                                          walletNameControllers
                                              .add(TextEditingController());
                                          walletAccountControllers
                                              .add(TextEditingController());
                                        }),
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('إضافة محفظة'),
                              ),
                            ],
                          ),
                          if (walletNameControllers.isEmpty)
                            const Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                'اختياري — يمكن إضافة بيانات المحافظ لاحقًا.',
                                style: TextStyle(
                                  color: Color(0xFF6B7280),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ...List.generate(walletNameControllers.length, (
                            index,
                          ) {
                            final nameController = walletNameControllers[index];
                            final accountController =
                                walletAccountControllers[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          controller: nameController,
                                          decoration: InputDecoration(
                                            labelText: 'اسم المحفظة',
                                            prefixIcon: const Icon(
                                              Icons
                                                  .account_balance_wallet_outlined,
                                            ),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                          ),
                                          validator: (value) {
                                            if (accountController.text
                                                    .trim()
                                                    .isEmpty &&
                                                (value?.trim().isEmpty ??
                                                    true)) {
                                              return null;
                                            }
                                            return value?.trim().isNotEmpty ==
                                                    true
                                                ? null
                                                : 'أدخل اسم المحفظة';
                                          },
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'حذف المحفظة',
                                        onPressed: saving
                                            ? null
                                            : () => setDialogState(() {
                                                  nameController.dispose();
                                                  accountController.dispose();
                                                  walletNameControllers
                                                      .removeAt(index);
                                                  walletAccountControllers
                                                      .removeAt(index);
                                                }),
                                        icon: const Icon(
                                          Icons.remove_circle_outline_rounded,
                                          color: Color(0xFFB91C1C),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: accountController,
                                    keyboardType: TextInputType.phone,
                                    decoration: InputDecoration(
                                      labelText: 'رقم المحفظة / الحساب',
                                      prefixIcon:
                                          const Icon(Icons.numbers_rounded),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    validator: (value) {
                                      if (nameController.text.trim().isEmpty &&
                                          (value?.trim().isEmpty ?? true)) {
                                        return null;
                                      }
                                      return value?.trim().isNotEmpty == true
                                          ? null
                                          : 'أدخل رقم المحفظة';
                                    },
                                  ),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 22),
                          const _MerchantCreationSectionTitle(
                            title: 'بيانات الدخول',
                            icon: Icons.lock_outline_rounded,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: passwordController,
                            obscureText: !showPassword,
                            decoration: InputDecoration(
                              labelText: 'كلمة المرور الأولية *',
                              helperText: '6 أحرف على الأقل',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: showPassword
                                    ? 'إخفاء كلمة المرور'
                                    : 'إظهار كلمة المرور',
                                onPressed: () => setDialogState(
                                  () => showPassword = !showPassword,
                                ),
                                icon: Icon(
                                  showPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            validator: (value) =>
                                AppConstants.isStrongPassword(value ?? '')
                                    ? null
                                    : 'يجب ألا تقل كلمة المرور عن 6 أحرف',
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: confirmPasswordController,
                            obscureText: !showConfirmPassword,
                            decoration: InputDecoration(
                              labelText: 'تأكيد كلمة المرور *',
                              prefixIcon: const Icon(Icons.lock_reset_outlined),
                              suffixIcon: IconButton(
                                tooltip: showConfirmPassword
                                    ? 'إخفاء كلمة المرور'
                                    : 'إظهار كلمة المرور',
                                onPressed: () => setDialogState(
                                  () => showConfirmPassword =
                                      !showConfirmPassword,
                                ),
                                icon: Icon(
                                  showConfirmPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            validator: (value) =>
                                value == passwordController.text
                                    ? null
                                    : 'كلمتا المرور غير متطابقتين',
                          ),
                          if (formError != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFFECACA),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.error_outline_rounded,
                                    color: Color(0xFFB91C1C),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      formError!,
                                      style: const TextStyle(
                                        color: Color(0xFFB91C1C),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: saving
                              ? null
                              : () => Navigator.pop(dialogContext, false),
                          child: const Text('إلغاء'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: saving
                              ? null
                              : () async {
                                  if (!formKey.currentState!.validate()) return;
                                  setDialogState(() {
                                    saving = true;
                                    formError = null;
                                  });
                                  try {
                                    final auth = AuthService();
                                    final admin = await auth.loadSession() ??
                                        await auth.getCurrentProfile();
                                    if (admin == null ||
                                        admin.id.trim().isEmpty) {
                                      setDialogState(
                                        () => formError =
                                            'تعذر التحقق من حساب المدير الحالي',
                                      );
                                      return;
                                    }
                                    final didCreate = await _service
                                        .createMerchantAccountForAdmin(
                                      fullName: fullNameController.text,
                                      shopName: shopNameController.text,
                                      phone: phoneController.text,
                                      password: passwordController.text,
                                      adminId: admin.id,
                                      shopCategory: categoryController.text,
                                      shopLocation: locationController.text,
                                      city: cityController.text,
                                      shopContactPhones: contactPhoneControllers
                                          .map((controller) => controller.text)
                                          .toList(),
                                      shopWallets: List.generate(
                                        walletNameControllers.length,
                                        (index) => {
                                          'provider':
                                              walletNameControllers[index].text,
                                          'account_number':
                                              walletAccountControllers[index]
                                                  .text,
                                        },
                                      ),
                                    );
                                    if (!didCreate) {
                                      setDialogState(
                                        () => formError =
                                            'رقم الهاتف مسجل مسبقًا في النظام',
                                      );
                                      return;
                                    }
                                    if (dialogContext.mounted) {
                                      Navigator.pop(dialogContext, true);
                                    }
                                  } catch (error) {
                                    setDialogState(
                                      () => formError =
                                          AppErrorMessage.from(error),
                                    );
                                  } finally {
                                    if (dialogContext.mounted) {
                                      setDialogState(() => saving = false);
                                    }
                                  }
                                },
                          icon: saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.person_add_alt_1_rounded),
                          label: Text(
                            saving ? 'جارٍ الإنشاء...' : 'إنشاء الحساب',
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

    fullNameController.dispose();
    shopNameController.dispose();
    phoneController.dispose();
    categoryController.dispose();
    locationController.dispose();
    cityController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    for (final controller in contactPhoneControllers) {
      controller.dispose();
    }
    for (final controller in walletNameControllers) {
      controller.dispose();
    }
    for (final controller in walletAccountControllers) {
      controller.dispose();
    }

    if (created == true && mounted) {
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إنشاء حساب التاجر وتوثيقه')),
        );
      }
    }
  }

  List<Map<String, dynamic>> _filterMerchants(
    List<Map<String, dynamic>> merchants,
  ) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = merchants.where((merchant) {
      final verified = _isVerified(merchant);
      final searchable = [
        merchant['full_name'],
        merchant['shop_name'],
        merchant['phone'],
        merchant['email'],
        merchant['shop_category'],
        merchant['shop_location'],
        merchant['shop_region'],
        if (merchant['shop_contact_phones'] is List)
          ...(merchant['shop_contact_phones'] as List),
      ].whereType<Object>().join(' ').toLowerCase();
      return (_verificationFilter == 'all' ||
              verified == (_verificationFilter == 'verified')) &&
          (query.isEmpty || searchable.contains(query));
    }).toList();
    filtered.sort((left, right) {
      final leftName = (left['shop_name'] ?? left['full_name'] ?? '')
          .toString()
          .toLowerCase();
      final rightName = (right['shop_name'] ?? right['full_name'] ?? '')
          .toString()
          .toLowerCase();
      return leftName.compareTo(rightName);
    });
    return filtered;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleMerchantVerification(
    Map<String, dynamic> merchant,
  ) async {
    final merchantId = (merchant['id'] ?? '').toString().trim();
    if (merchantId.isEmpty) {
      _showMessage('تعذر تحديث المتجر لعدم توفر معرّف التاجر');
      return;
    }
    final verified = _isVerified(merchant);
    try {
      final updated = await _service.updateProfileVerificationForAdmin(
        profileId: merchantId,
        isVerified: !verified,
      );
      if (!mounted) return;
      if (!updated) {
        _showMessage('تعذر تحديث حالة توثيق المتجر');
        return;
      }
      merchant['is_verified'] = !verified;
      setState(() {});
      _showMessage(verified ? 'تم إلغاء توثيق المتجر' : 'تم توثيق المتجر');
      try {
        await _refresh();
      } catch (error) {
        if (mounted) {
          _showMessage(
            'تم تحديث التوثيق لكن تعذر تحديث القائمة: '
            '${AppErrorMessage.from(error)}',
          );
        }
      }
    } catch (error) {
      if (mounted) {
        _showMessage('فشل تحديث توثيق المتجر: ${AppErrorMessage.from(error)}');
      }
    }
  }

  Future<void> _setMerchantDisplayDeliveryFee(
    Map<String, dynamic> merchant,
  ) async {
    final merchantId = (merchant['id'] ?? '').toString().trim();
    if (merchantId.isEmpty) {
      _showMessage('تعذر تحديث المتجر لعدم توفر معرّف التاجر');
      return;
    }

    try {
      final globalFee =
          await _service.getGlobalMerchantDisplayDeliveryFeeForAdmin();
      if (!mounted) return;
      final currentFee = merchant['merchant_display_delivery_fee'] ??
          merchant['merchantDisplayDeliveryFee'];
      final selection = await showDialog<_MerchantDisplayDeliveryFeeSelection>(
        context: context,
        builder: (_) => _MerchantDisplayDeliveryFeeDialog(
          currentFee: currentFee,
          globalFee: globalFee,
        ),
      );
      if (selection == null || !mounted) return;

      final updated = selection.forAllMerchants
          ? await _service.updateGlobalMerchantDisplayDeliveryFeeForAdmin(
              deliveryFee: selection.fee,
            )
          : await _service.updateMerchantDisplayDeliveryFeeForAdmin(
              merchantId: merchantId,
              deliveryFee: selection.fee,
            );
      if (!mounted) return;
      if (!updated) {
        _showMessage('تعذر تحديث أجرة التوصيل الظاهرة للتاجر');
        return;
      }
      if (!selection.forAllMerchants) {
        if (selection.fee == null) {
          merchant.remove('merchant_display_delivery_fee');
          merchant.remove('merchantDisplayDeliveryFee');
        } else {
          merchant['merchant_display_delivery_fee'] = selection.fee;
        }
      }
      setState(() {});
      _showMessage(
        selection.fee == null
            ? selection.forAllMerchants
                ? 'تمت إزالة أجرة التوصيل الثابتة لجميع التجار'
                : 'تمت إزالة أجرة التوصيل الثابتة'
            : selection.forAllMerchants
                ? 'تم تحديث أجرة التوصيل الثابتة لجميع التجار'
                : 'تم تحديث أجرة التوصيل الظاهرة للتاجر',
      );
    } catch (error) {
      if (mounted) {
        _showMessage(
          'فشل تحديث أجرة التوصيل الظاهرة للتاجر: '
          '${AppErrorMessage.from(error)}',
        );
      }
    }
  }

  Widget _merchantMetric({
    required String label,
    required int value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value.toString(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openMerchantDetails(Map<String, dynamic> merchant) {
    Navigator.of(context).push(
      slideFadeRoute(
        page: AdminProfileDetailsScreen(
          profile: Map<String, dynamic>.from(merchant),
        ),
      ),
    );
  }

  Widget _merchantCard(Map<String, dynamic> merchant) {
    final shopName =
        (merchant['shop_name'] ?? merchant['full_name'] ?? 'متجر بدون اسم')
            .toString();
    final owner = (merchant['full_name'] ?? '').toString();
    final phone = (merchant['phone'] ?? '').toString();
    final category = (merchant['shop_category'] ?? '').toString();
    final location = (merchant['shop_location'] ??
            merchant['shop_region'] ??
            merchant['city'] ??
            '')
        .toString();
    final verified = _isVerified(merchant);
    final contactPhones = merchant['shop_contact_phones'] is List
        ? (merchant['shop_contact_phones'] as List)
            .map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty)
            .toList()
        : const <String>[];

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openMerchantDetails(merchant),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      color: Color(0xFF059669),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shopName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        if (owner.isNotEmpty && owner != shopName)
                          Text(
                            owner,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.open_in_new_rounded,
                    size: 17,
                    color: Color(0xFF94A3B8),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'إجراءات المتجر',
                    onSelected: (action) {
                      if (action == 'verification') {
                        _toggleMerchantVerification(merchant);
                      } else if (action == 'display_delivery_fee') {
                        _setMerchantDisplayDeliveryFee(merchant);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'verification',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            verified
                                ? Icons.verified_user_outlined
                                : Icons.verified_user_rounded,
                          ),
                          title: Text(
                            verified ? 'إلغاء التوثيق' : 'توثيق المتجر',
                          ),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'display_delivery_fee',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.local_shipping_outlined),
                          title: Text('تحديد أجرة التوصيل الظاهرة'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  _merchantBadge(
                    verified ? 'موثق' : 'غير موثق',
                    verified
                        ? const Color(0xFFECFDF5)
                        : const Color(0xFFFFF7ED),
                    verified
                        ? const Color(0xFF047857)
                        : const Color(0xFFC2410C),
                  ),
                  if (category.isNotEmpty)
                    _merchantBadge(
                      category,
                      const Color(0xFFEFF6FF),
                      const Color(0xFF1D4ED8),
                    ),
                ],
              ),
              if (phone.isNotEmpty || location.isNotEmpty) ...[
                const SizedBox(height: 12),
                if (phone.isNotEmpty)
                  _merchantInfoRow(Icons.phone_outlined, phone),
                if (location.isNotEmpty) ...[
                  if (phone.isNotEmpty) const SizedBox(height: 7),
                  _merchantInfoRow(Icons.location_on_outlined, location),
                ],
              ],
              if (merchant['merchant_display_delivery_fee'] != null ||
                  merchant['merchantDisplayDeliveryFee'] != null) ...[
                const SizedBox(height: 8),
                _merchantInfoRow(
                  Icons.local_shipping_outlined,
                  'أجرة التوصيل الظاهرة: '
                  '${(merchant['merchant_display_delivery_fee'] ?? merchant['merchantDisplayDeliveryFee'])} '
                  '${CurrencyService.yerCurrency.symbol}',
                ),
              ],
              if (contactPhones.isNotEmpty) ...[
                const SizedBox(height: 8),
                _merchantInfoRow(
                  Icons.contact_phone_outlined,
                  'أرقام التواصل: ${contactPhones.join('، ')}',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _merchantBadge(String label, Color background, Color foreground) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _merchantInfoRow(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF64748B)),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Color(0xFF475569), fontSize: 12),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: const Text('إدارة التجار'),
          actions: [
            IconButton(
              tooltip: 'إنشاء حساب تاجر',
              onPressed: _showCreateMerchantDialog,
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
            IconButton(
              tooltip: 'تحديث',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _merchantsFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 100),
                  const Icon(
                    Icons.cloud_off_rounded,
                    size: 48,
                    color: Color(0xFFDC2626),
                  ),
                  const SizedBox(height: 16),
                  const Center(
                    child: Text(
                      'تعذر تحميل بيانات التجار',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      AppErrorMessage.from(snapshot.error!),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF64748B)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('إعادة المحاولة'),
                    ),
                  ),
                ],
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final merchants = snapshot.data!;
            final verifiedCount = merchants.where(_isVerified).length;
            final filteredMerchants = _filterMerchants(merchants);

            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'المتاجر المسجلة',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'راجع بيانات المتاجر وابحث حسب الاسم أو النشاط أو المنطقة.',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _merchantMetric(
                        label: 'إجمالي المتاجر',
                        value: merchants.length,
                        icon: Icons.storefront_rounded,
                        color: const Color(0xFF059669),
                      ),
                      const SizedBox(width: 10),
                      _merchantMetric(
                        label: 'موثقة',
                        value: verifiedCount,
                        icon: Icons.verified_user_rounded,
                        color: const Color(0xFF2563EB),
                      ),
                      const SizedBox(width: 10),
                      _merchantMetric(
                        label: 'غير موثقة',
                        value: merchants.length - verifiedCount,
                        icon: Icons.pending_actions_rounded,
                        color: const Color(0xFFEA580C),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'ابحث عن متجر أو تاجر أو هاتف أو فئة',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'مسح البحث',
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _verificationFilter,
                    decoration: InputDecoration(
                      labelText: 'حالة التوثيق',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text('جميع المتاجر'),
                      ),
                      DropdownMenuItem(
                        value: 'verified',
                        child: Text('المتاجر الموثقة'),
                      ),
                      DropdownMenuItem(
                        value: 'unverified',
                        child: Text('المتاجر غير الموثقة'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _verificationFilter = value);
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'قائمة المتاجر',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Text(
                        '${filteredMerchants.length} متجر',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (filteredMerchants.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Column(
                        children: [
                          Icon(
                            Icons.store_mall_directory_outlined,
                            size: 40,
                            color: Color(0xFF94A3B8),
                          ),
                          SizedBox(height: 8),
                          Text('لا توجد متاجر مطابقة للبحث أو التصفية'),
                        ],
                      ),
                    )
                  else
                    ...filteredMerchants.map(
                      (merchant) => Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: _merchantCard(merchant),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class DriverManagementScreen extends StatefulWidget {
  const DriverManagementScreen({super.key, this.service});

  final AdminService? service;

  @override
  State<DriverManagementScreen> createState() => _DriverManagementScreenState();
}

class _DriverManagementScreenState extends State<DriverManagementScreen> {
  late final AdminService _service;
  late Future<_DriverManagementData> _dataFuture;
  final _searchController = TextEditingController();
  final Set<String> _updatingDriverIds = {};
  String _availabilityFilter = 'all';

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? AdminService();
    _dataFuture = _loadData();
  }

  Future<_DriverManagementData> _loadData() async {
    final results = await Future.wait<Object>([
      _service.getDriverDispatchSummary(),
      _service.getProfilesForAdmin(
        role: 'driver',
        limit: null,
        propagateErrors: true,
      ),
    ]);
    return _DriverManagementData(
      summary: results[0] as AdminDriverDispatchSummary,
      drivers: results[1] as List<Map<String, dynamic>>,
    );
  }

  Future<void> _refresh() async {
    final future = _loadData();
    setState(() {
      _dataFuture = future;
    });
    try {
      await future;
    } catch (_) {
      // The FutureBuilder presents the load error and retry action.
    }
  }

  Future<void> _openOrderNotification(String orderId) async {
    await Navigator.of(context).push(
      slideFadeRoute(
        page: OrderManagementScreen(initialOrderId: orderId),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isAvailable(Map<String, dynamic> driver) {
    final value =
        driver['is_available'] ?? driver['isAvailable'] ?? driver['available'];
    return value == true || value?.toString().toLowerCase() == 'true';
  }

  List<Map<String, dynamic>> _filterDrivers(
    List<Map<String, dynamic>> drivers,
  ) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = drivers.where((driver) {
      final available = _isAvailable(driver);
      final name = (driver['full_name'] ?? driver['fullName'] ?? '').toString();
      final phone = (driver['phone'] ?? '').toString();
      final region = (driver['region'] ?? driver['city'] ?? '').toString();
      final vehicle =
          (driver['vehicle_type'] ?? driver['vehicleType'] ?? '').toString();
      final matchesAvailability = _availabilityFilter == 'all' ||
          available == (_availabilityFilter == 'available');
      return matchesAvailability &&
          (query.isEmpty ||
              '$name $phone $region $vehicle'.toLowerCase().contains(query));
    }).toList();
    filtered.sort((left, right) {
      final leftName = (left['full_name'] ?? left['fullName'] ?? '').toString();
      final rightName =
          (right['full_name'] ?? right['fullName'] ?? '').toString();
      return leftName.compareTo(rightName);
    });
    return filtered;
  }

  Future<void> _setAvailability(
    Map<String, dynamic> driver,
    bool isAvailable,
  ) async {
    final driverId = (driver['id'] ?? '').toString().trim();
    if (driverId.isEmpty) {
      _showMessage('تعذر تحديث السائق لعدم توفر معرّف الحساب');
      return;
    }

    setState(() => _updatingDriverIds.add(driverId));
    try {
      final updated = await _service.updateDriverAvailabilityForAdmin(
        driverId: driverId,
        isAvailable: isAvailable,
      );
      if (!mounted) return;
      if (!updated) {
        _showMessage('تعذر تحديث حالة توفر السائق');
        return;
      }
      driver['is_available'] = isAvailable;
      setState(() {});
      _showMessage(
        isAvailable ? 'تم تفعيل توفر السائق' : 'تم إيقاف توفر السائق',
      );
    } catch (error) {
      if (mounted) {
        _showMessage('فشل تحديث حالة السائق: ${AppErrorMessage.from(error)}');
      }
    } finally {
      if (mounted) setState(() => _updatingDriverIds.remove(driverId));
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _metricCard(String label, int value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value.toString(),
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: Color(0xFF6B7280), fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _driverCard(Map<String, dynamic> driver) {
    final id = (driver['id'] ?? '').toString();
    final name =
        (driver['full_name'] ?? driver['fullName'] ?? 'سائق').toString();
    final phone = (driver['phone'] ?? '').toString();
    final region =
        (driver['region'] ?? driver['city'] ?? 'منطقة غير محددة').toString();
    final vehicle =
        (driver['vehicle_type'] ?? driver['vehicleType'] ?? 'وسيلة غير محددة')
            .toString();
    final available = _isAvailable(driver);
    final busy = _updatingDriverIds.contains(id);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor:
                  available ? const Color(0xFFECFDF5) : const Color(0xFFF3F4F6),
              foregroundColor:
                  available ? const Color(0xFF047857) : const Color(0xFF6B7280),
              child: const Icon(Icons.delivery_dining_rounded),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (phone.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      phone,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 5),
                  Text(
                    '$region • $vehicle',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    available ? 'متاح لاستلام الطلبات' : 'غير متاح',
                    style: TextStyle(
                      color: available
                          ? const Color(0xFF047857)
                          : const Color(0xFF6B7280),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (busy)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Tooltip(
                message: 'تغيير توفر $name',
                child: Switch(
                  value: available,
                  onChanged: (value) => _setAvailability(driver, value),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _assignmentCard(Map<String, dynamic> assignment) {
    final status = (assignment['status'] ?? '').toString();
    final statusLabel = switch (status) {
      'accepted' => 'مقبول',
      'confirmed' => 'مؤكد',
      'preparing' => 'قيد التجهيز',
      'shipped' => 'جاهز للاستلام من المتجر',
      'picked_up' => 'تم تسليم الطلب للسائق',
      'delivered' => 'تم التسليم',
      _ => status.isEmpty ? 'غير محدد' : status,
    };
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: const CircleAvatar(
        backgroundColor: Color(0xFFEFF6FF),
        child: Icon(Icons.local_shipping_rounded, color: Color(0xFF2563EB)),
      ),
      title: Text('طلب ${assignment['order_id'] ?? 'غير محدد'}'),
      subtitle: Text(
        '${assignment['courier_name'] ?? 'غير مخصص'} • $statusLabel',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        statusLabel,
        style: const TextStyle(
          color: Color(0xFF475569),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _loadError(Object error) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 100),
        const Icon(Icons.cloud_off_rounded, size: 48, color: Color(0xFFDC2626)),
        const SizedBox(height: 14),
        const Center(
          child: Text(
            'تعذر تحميل بيانات السائقين',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          AppErrorMessage.from(error),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF6B7280)),
        ),
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('إعادة المحاولة'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: const Text('إدارة السائقين'),
          actions: [
            NotificationBell(onAdminOrderTap: _openOrderNotification),
            IconButton(
              tooltip: 'تحديث',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: FutureBuilder<_DriverManagementData>(
          future: _dataFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) return _loadError(snapshot.error!);
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final data = snapshot.data!;
            final drivers = data.drivers;
            final filteredDrivers = _filterDrivers(drivers);
            final availableCount = drivers.where(_isAvailable).length;

            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'متابعة السائقين والتوصيلات',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'ابحث حسب الاسم أو رقم الهاتف أو المنطقة، وحدّث حالة التوفر.',
                    style: TextStyle(color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 2.3,
                    children: [
                      _metricCard(
                        'إجمالي السائقين',
                        drivers.length,
                        Icons.people_alt_rounded,
                        const Color(0xFF2563EB),
                      ),
                      _metricCard(
                        'السائقون النشطون',
                        data.summary.activeDrivers,
                        Icons.delivery_dining_rounded,
                        const Color(0xFF10B981),
                      ),
                      _metricCard(
                        'متاحون',
                        availableCount,
                        Icons.verified_user_rounded,
                        const Color(0xFF059669),
                      ),
                      _metricCard(
                        'في الطريق',
                        data.summary.inTransitOrders,
                        Icons.map_rounded,
                        const Color(0xFFF59E0B),
                      ),
                      _metricCard(
                        'التخصيصات الحالية',
                        data.summary.assignments.length,
                        Icons.assignment_rounded,
                        const Color(0xFF8B5CF6),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'ابحث عن سائق',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'مسح البحث',
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('الكل'),
                        selected: _availabilityFilter == 'all',
                        onSelected: (_) =>
                            setState(() => _availabilityFilter = 'all'),
                      ),
                      ChoiceChip(
                        label: const Text('متاحون'),
                        selected: _availabilityFilter == 'available',
                        onSelected: (_) =>
                            setState(() => _availabilityFilter = 'available'),
                      ),
                      ChoiceChip(
                        label: const Text('غير متاحين'),
                        selected: _availabilityFilter == 'unavailable',
                        onSelected: (_) => setState(
                          () => _availabilityFilter = 'unavailable',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${filteredDrivers.length} سائق',
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (filteredDrivers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.person_search_rounded,
                            size: 42,
                            color: Color(0xFF94A3B8),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            drivers.isEmpty
                                ? 'لا توجد حسابات سائقين'
                                : 'لا يوجد سائقون مطابقون للبحث أو التصفية',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    )
                  else
                    ...filteredDrivers.map(
                      (driver) => Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: _driverCard(driver),
                      ),
                    ),
                  const SizedBox(height: 12),
                  const Text(
                    'التوصيلات الحالية',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (data.summary.assignments.isEmpty)
                    const Card(
                      elevation: 0,
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('لا توجد توصيلات نشطة حالياً'),
                      ),
                    )
                  else
                    ...data.summary.assignments.map(_assignmentCard),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DriverManagementData {
  const _DriverManagementData({
    required this.summary,
    required this.drivers,
  });

  final AdminDriverDispatchSummary summary;
  final List<Map<String, dynamic>> drivers;
}

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  late Future<AdminDriverDispatchSummary> _summaryFuture;
  String _driverName = 'السائق';
  String _driverId = '';
  String _driverPhone = '';
  String _driverVehicle = '';
  bool _driverSessionInvalid = false;
  bool _showCompleted = false;
  bool _favoritesOnly = false;
  String _statusFilter = 'all';
  String _assignmentQuery = '';
  String _favoritesDriverId = '';
  final TextEditingController _assignmentSearchController =
      TextEditingController();
  final Set<String> _favoriteOrderIds = {};
  final Set<String> _collapsedOrderIds = {};
  final Set<String> _busyOrderIds = {};

  @override
  void initState() {
    super.initState();
    _summaryFuture = _loadDriverSummary();
  }

  @override
  void dispose() {
    _assignmentSearchController.dispose();
    super.dispose();
  }

  Future<AdminDriverDispatchSummary> _loadDriverSummary() async {
    final profile = await AuthService().loadSession() ??
        await AuthService().getCurrentProfile();
    final driverId = profile?.id.trim() ?? '';
    final driverPhone = profile?.phone.trim() ?? '';
    if (profile == null ||
        profile.role.trim().toLowerCase() != 'driver' ||
        (driverId.isEmpty && driverPhone.isEmpty)) {
      _driverSessionInvalid = true;
      return const AdminDriverDispatchSummary(
        activeDrivers: 0,
        inTransitOrders: 0,
        availableDrivers: 0,
        assignments: [],
      );
    }

    _driverSessionInvalid = false;
    _driverName =
        profile.fullName.trim().isNotEmpty ? profile.fullName : 'السائق';
    _driverId = driverId;
    _driverPhone = driverPhone;
    _driverVehicle = profile.vehicleType?.trim() ?? '';
    final summary = await AdminService().getDriverDispatchSummary(
      driverId: driverId,
      driverName: profile.fullName,
      driverPhone: driverPhone,
      includeCompleted: true,
    );
    final preferencesId = _driverPreferenceId;
    if (_favoritesDriverId != preferencesId) {
      await _loadFavoriteAssignments(preferencesId);
    }
    return summary;
  }

  String get _driverPreferenceId {
    final id = _driverId.isNotEmpty ? _driverId : _driverPhone;
    return id.replaceAll(RegExp(r'[.#$\[\]/]'), '_');
  }

  Future<void> _loadFavoriteAssignments(String driverId) async {
    try {
      final snapshot = await FirebaseDatabaseService.instance
          .read('driver_preferences/$driverId/favorites');
      if (!mounted || _driverPreferenceId != driverId) return;
      setState(() {
        _favoriteOrderIds
          ..clear()
          ..addAll(snapshot.entries
              .where(
                (entry) =>
                    entry.value == true ||
                    (entry.value is Map && entry.value['value'] == true),
              )
              .map((entry) => entry.key));
        _favoritesDriverId = driverId;
      });
    } catch (error, stackTrace) {
      debugPrint('Failed to load driver favorite tasks: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _toggleFavorite(String orderId) async {
    final driverPreferenceId = _driverPreferenceId;
    if (orderId.isEmpty || driverPreferenceId.isEmpty) return;
    final wasFavorite = _favoriteOrderIds.contains(orderId);
    setState(() {
      if (wasFavorite) {
        _favoriteOrderIds.remove(orderId);
      } else {
        _favoriteOrderIds.add(orderId);
      }
    });
    try {
      final path = 'driver_preferences/$driverPreferenceId/favorites/$orderId';
      if (wasFavorite) {
        await FirebaseDatabaseService.instance.delete(path);
      } else {
        await FirebaseDatabaseService.instance.update(
          'driver_preferences/$driverPreferenceId/favorites',
          {orderId: true},
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to update favorite task $orderId: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        if (wasFavorite) {
          _favoriteOrderIds.add(orderId);
        } else {
          _favoriteOrderIds.remove(orderId);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حفظ تمييز المهمة')),
      );
    }
  }

  DateTime _assignmentDate(Map<String, dynamic> assignment) {
    final value = assignment['created_at'] ?? assignment['createdAt'];
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed != null) return parsed;
    final milliseconds = int.tryParse(value?.toString() ?? '');
    return milliseconds == null
        ? DateTime.fromMillisecondsSinceEpoch(0)
        : DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  String _assignmentStatusFilterLabel(String status) => switch (status) {
        'delivered' => 'تم التسليم',
        'cancelled' => 'ملغاة',
        'picked_up' => 'في الطريق',
        'shipped' => 'جاهزة للاستلام',
        'preparing' => 'قيد التجهيز',
        'confirmed' => 'مؤكدة',
        'accepted' => 'مقبولة',
        _ => 'كل الحالات',
      };

  void _reload() {
    setState(() {
      _summaryFuture = _loadDriverSummary();
    });
  }

  Future<void> _returnToLogin() async {
    await AuthService().clearSession();
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      slideFadeRoute(page: const PhoneLoginScreen()),
      (route) => false,
    );
  }

  Future<void> _signOut() async {
    final shouldSignOut = await showLogoutConfirmationDialog(
      context,
      message: 'هل تريد تسجيل الخروج من حساب السائق؟',
    );
    if (!shouldSignOut || !mounted) return;

    await AuthService().clearSession();
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      slideFadeRoute(page: const PhoneLoginScreen()),
      (route) => false,
    );
  }

  Future<void> _changePassword() async {
    Navigator.of(context).pop();
    final changed = await showPasswordChangeDialog(context);
    if (!mounted || !changed) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تغيير كلمة المرور بنجاح')),
    );
  }

  void _selectAssignments(bool showCompleted) {
    Navigator.of(context).pop();
    setState(() => _showCompleted = showCompleted);
  }

  Future<void> _openAssignmentLocation(Map<String, dynamic> assignment) async {
    final latitude = assignment['latitude']?.toString().trim() ?? '';
    final longitude = assignment['longitude']?.toString().trim() ?? '';
    if (latitude.isEmpty || longitude.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد إحداثيات محفوظة لهذا الطلب')),
      );
      return;
    }

    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude',
    );
    if (!await canLaunchUrl(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح موقع التسليم')),
      );
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _acceptAssignment(Map<String, dynamic> assignment) async {
    final orderId = (assignment['order_id'] ?? '').toString();
    if (orderId.isEmpty || !_busyOrderIds.add(orderId)) return;
    setState(() {});
    final success = await AdminService().acceptDriverAssignment(
      orderId: orderId,
      driverId: _driverId,
      driverName: _driverName,
      driverPhone: _driverPhone,
    );
    if (!mounted) return;
    setState(() => _busyOrderIds.remove(orderId));
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر قبول المهمة، حدّث القائمة وحاول')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم قبول مهمة الطلب $orderId')),
    );
    _reload();
  }

  Future<void> _updateEta(Map<String, dynamic> assignment) async {
    final orderId = (assignment['order_id'] ?? '').toString();
    if (orderId.isEmpty || !_busyOrderIds.add(orderId)) return;
    final etaController = TextEditingController(
      text: (assignment['eta'] ?? '').toString(),
    );
    final eta = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تحديث وقت الوصول المتوقع'),
        content: TextField(
          controller: etaController,
          decoration: const InputDecoration(
            labelText: 'الوقت المتوقع للوصول',
            hintText: 'مثال: 20 دقيقة',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final value = etaController.text.trim();
              if (value.isEmpty) return;
              Navigator.pop(dialogContext, value);
            },
            child: const Text('حفظ التحديث'),
          ),
        ],
      ),
    );
    etaController.dispose();
    if (!mounted) {
      _busyOrderIds.remove(orderId);
      return;
    }
    if (eta == null) {
      setState(() => _busyOrderIds.remove(orderId));
      return;
    }

    final success = await AdminService().updateDriverEta(
      orderId: orderId,
      driverId: _driverId,
      driverName: _driverName,
      driverPhone: _driverPhone,
      eta: eta,
    );
    if (!mounted) return;
    setState(() => _busyOrderIds.remove(orderId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success
            ? 'تم تحديث وقت الوصول المتوقع للعميل'
            : 'تعذر تحديث معلومات التوصيل'),
      ),
    );
    if (success) _reload();
  }

  String _assignmentStatusLabel(
    String orderStatus,
    String driverStatus,
  ) {
    if (orderStatus == 'delivered') return 'تم التسليم';
    if (orderStatus == 'cancelled') return 'ملغي';
    if (orderStatus == 'picked_up') return 'الطلب معك';
    if (orderStatus == 'shipped') return 'جاهز للاستلام من المتجر';
    if (driverStatus == 'accepted') return 'قبلت المهمة • بانتظار تجهيز المتجر';
    return 'مهمة جديدة';
  }

  Color _assignmentStatusColor(String orderStatus) {
    return switch (orderStatus) {
      'delivered' => const Color(0xFF15803D),
      'cancelled' => const Color(0xFFB91C1C),
      'picked_up' => const Color(0xFF2563EB),
      'shipped' => const Color(0xFFB45309),
      _ => const Color(0xFF64748B),
    };
  }

  Future<void> _confirmMerchantPickup(String orderId) async {
    if (orderId.isEmpty || !_busyOrderIds.add(orderId)) return;
    setState(() {});
    try {
      final controller = TextEditingController();
      final enteredOtp = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('استلام الطلب من التاجر'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              labelText: 'رمز التاجر للسائق',
              counterText: '',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('تحقق واستلم'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (!mounted) return;
      if (enteredOtp == null || enteredOtp.trim().isEmpty) return;
      if (!RegExp(r'^\d{6}$').hasMatch(enteredOtp.trim())) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('أدخل رمز التاجر المكون من 6 أرقام')),
        );
        return;
      }

      final orderService = OrderService();
      final updated = await orderService.confirmPickupOtp(
        orderId: orderId,
        otp: enteredOtp,
      );
      if (!mounted) return;
      if (updated == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              orderService.lastPickupOtpError ?? 'رمز التاجر غير صحيح',
            ),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تأكيد استلام الطلب من التاجر')),
      );
      if (!mounted) return;
      _reload();
    } finally {
      _busyOrderIds.remove(orderId);
      if (mounted) setState(() {});
    }
  }

  Future<void> _confirmDeliveryToCustomer(String orderId) async {
    if (orderId.isEmpty || _busyOrderIds.contains(orderId)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد تسليم الطلب للعميل'),
        content: const Text(
          'هل سلّمت الطلب بالكامل للعميل؟ بعد التأكيد سيُسجّل الطلب كمكتمل.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.check_rounded),
            label: const Text('تأكيد التسليم'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_busyOrderIds.add(orderId)) return;
    setState(() {});
    try {
      final delivered = await OrderService().confirmDeliveryByDriver(
        orderId: orderId,
        driverId: _driverId,
        driverPhone: _driverPhone,
      );
      if (!mounted) return;
      if (delivered == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر تأكيد التسليم؛ تحقق من إسناد الطلب وحالته'),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تأكيد تسليم الطلب للعميل')),
      );
      _reload();
    } finally {
      _busyOrderIds.remove(orderId);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('لوحة السائق'),
          actions: [
            const AccountSwitcherButton(),
            Builder(
              builder: (context) => IconButton(
                tooltip: 'القائمة الجانبية',
                onPressed: () => Scaffold.of(context).openEndDrawer(),
                icon: const Icon(Icons.menu_rounded),
              ),
            ),
          ],
        ),
        endDrawer: Drawer(
          width: 310,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0xFFE8EEF7),
                      foregroundColor: Color(0xFF1D4ED8),
                      child: Icon(Icons.delivery_dining_rounded),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _driverName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _driverPhone.isEmpty ? 'حساب السائق' : _driverPhone,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'إغلاق القائمة',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Divider(height: 32),
                ListTile(
                  leading: const Icon(Icons.local_shipping_rounded),
                  title: const Text('المهام الحالية'),
                  selected: !_showCompleted,
                  onTap: () => _selectAssignments(false),
                ),
                ListTile(
                  leading: const Icon(Icons.task_alt_rounded),
                  title: const Text('المهام المنجزة'),
                  selected: _showCompleted,
                  onTap: () => _selectAssignments(true),
                ),
                const Divider(height: 28),
                ListTile(
                  leading: const Icon(Icons.support_agent_rounded),
                  title: const Text('مركز مساعدة السائق'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      slideFadeRoute(page: const SupportCenterScreen()),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.lock_reset_rounded),
                  title: const Text('تغيير كلمة المرور'),
                  onTap: _changePassword,
                ),
                const Divider(height: 28),
                ListTile(
                  leading: const Icon(Icons.logout_rounded, color: Colors.red),
                  title: const Text(
                    'تسجيل الخروج',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    _signOut();
                  },
                ),
                const Divider(height: 28),
                const AppVersionListTile(),
              ],
            ),
          ),
        ),
        body: FutureBuilder<AdminDriverDispatchSummary>(
          future: _summaryFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: FilledButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('تعذر تحميل الطلبات، أعد المحاولة'),
                ),
              );
            }
            if (_driverSessionInvalid) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.lock_outline_rounded,
                        size: 48,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'يرجى تسجيل الدخول بحساب سائق لعرض مهامك.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _returnToLogin,
                        icon: const Icon(Icons.login_rounded),
                        label: const Text('تسجيل الدخول'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final summary = snapshot.data ??
                const AdminDriverDispatchSummary(
                  activeDrivers: 0,
                  inTransitOrders: 0,
                  availableDrivers: 0,
                  assignments: [],
                );
            final activeAssignments = summary.assignments
                .where((item) =>
                    item['status'] != 'delivered' &&
                    item['status'] != 'cancelled')
                .toList();
            final completedAssignments = summary.assignments
                .where((item) =>
                    item['status'] == 'delivered' ||
                    item['status'] == 'cancelled')
                .toList();
            final assignments = (_showCompleted
                    ? completedAssignments
                    : activeAssignments)
                .where((assignment) {
              final orderId = assignment['order_id']?.toString() ?? '';
              if (_favoritesOnly && !_favoriteOrderIds.contains(orderId)) {
                return false;
              }
              if (_statusFilter != 'all' &&
                  assignment['status']?.toString() != _statusFilter) {
                return false;
              }
              if (_assignmentQuery.isEmpty) return true;
              final searchValues = [
                orderId,
                assignment['customer_name'],
                assignment['customer_phone'],
                assignment['delivery_address'],
              ].map((value) => value?.toString().toLowerCase() ?? '');
              return searchValues
                  .any((value) => value.contains(_assignmentQuery));
            }).toList()
              ..sort((left, right) {
                final order =
                    _assignmentDate(left).compareTo(_assignmentDate(right));
                return -order;
              });

            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF111827), Color(0xFF0F172A)],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'مرحبًا، $_driverName',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${_driverVehicle.isEmpty ? 'سائق توصيل' : _driverVehicle} • ${activeAssignments.length} مهمة نشطة',
                                style: const TextStyle(
                                  color: Color(0xFFE5E7EB),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _reload,
                          icon: const Icon(Icons.refresh_rounded,
                              color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.35,
                    children: [
                      _DriverMetricCard(
                        label: 'مهام نشطة',
                        value: activeAssignments.length.toString(),
                        color: const Color(0xFF10B981),
                        icon: Icons.person_add_alt_rounded,
                      ),
                      _DriverMetricCard(
                        label: 'في الطريق',
                        value: activeAssignments
                            .where((item) => item['status'] == 'picked_up')
                            .length
                            .toString(),
                        color: const Color(0xFF3B82F6),
                        icon: Icons.map_rounded,
                      ),
                      _DriverMetricCard(
                        label: 'جاهزة للاستلام',
                        value: activeAssignments
                            .where((item) => item['status'] == 'shipped')
                            .length
                            .toString(),
                        color: const Color(0xFF8B5CF6),
                        icon: Icons.storefront_rounded,
                      ),
                      _DriverMetricCard(
                        label: 'مكتملة',
                        value: completedAssignments
                            .where((item) => item['status'] == 'delivered')
                            .length
                            .toString(),
                        color: const Color(0xFFF59E0B),
                        icon: Icons.navigation_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _showCompleted ? 'المهام المنجزة' : 'مهامي الحالية',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text('نشطة ${activeAssignments.length}'),
                        selected: !_showCompleted,
                        onSelected: (_) =>
                            setState(() => _showCompleted = false),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Text('منجزة ${completedAssignments.length}'),
                        selected: _showCompleted,
                        onSelected: (_) =>
                            setState(() => _showCompleted = true),
                      ),
                      FilterChip(
                        avatar: Icon(
                          _favoritesOnly
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: const Color(0xFFD4AF37),
                        ),
                        label: const Text('المميزة بنجمة'),
                        selected: _favoritesOnly,
                        onSelected: (selected) =>
                            setState(() => _favoritesOnly = selected),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _assignmentSearchController,
                    onChanged: (value) => setState(
                      () => _assignmentQuery = value.trim().toLowerCase(),
                    ),
                    decoration: InputDecoration(
                      hintText: 'ابحث برقم الطلب أو اسم العميل أو هاتفه',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _assignmentQuery.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'مسح البحث',
                              onPressed: () {
                                _assignmentSearchController.clear();
                                setState(() => _assignmentQuery = '');
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      DropdownButton<String>(
                        value: _statusFilter,
                        underline: const SizedBox.shrink(),
                        items: const [
                          'all',
                          'accepted',
                          'confirmed',
                          'preparing',
                          'shipped',
                          'picked_up',
                          'delivered',
                          'cancelled',
                        ]
                            .map(
                              (status) => DropdownMenuItem(
                                value: status,
                                child: Text(
                                  _assignmentStatusFilterLabel(status),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (status) {
                          if (status != null) {
                            setState(() => _statusFilter = status);
                          }
                        },
                      ),
                      const Chip(
                        avatar: Icon(Icons.schedule_rounded, size: 18),
                        label: Text('الأحدث أولًا'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (assignments.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.delivery_dining_rounded,
                            size: 38,
                            color: Color(0xFF94A3B8),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            assignments.isEmpty &&
                                    (_assignmentQuery.isNotEmpty ||
                                        _favoritesOnly ||
                                        _statusFilter != 'all')
                                ? 'لا توجد مهام تطابق عوامل البحث والتصفية'
                                : _showCompleted
                                    ? 'لا توجد مهام منجزة بعد'
                                    : 'لا توجد مهام نشطة مسندة إليك',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else
                    ...assignments.map((assignment) {
                      final orderId =
                          assignment['order_id']?.toString() ?? '#000';
                      final currentStatus =
                          assignment['status']?.toString() ?? 'preparing';
                      final driverStatus =
                          assignment['driver_status']?.toString() ?? 'assigned';
                      final statusColor = _assignmentStatusColor(currentStatus);
                      final isBusy = _busyOrderIds.contains(orderId);
                      final eta = assignment['eta']?.toString() ?? 'قريبا';
                      final customerName =
                          assignment['customer_name']?.toString() ?? 'العميل';
                      final customerPhone =
                          assignment['customer_phone']?.toString().trim() ?? '';

                      final isFavorite = _favoriteOrderIds.contains(orderId);
                      final isCollapsed = _collapsedOrderIds.contains(orderId);

                      return Card(
                        color: Colors.white,
                        surfaceTintColor: Colors.transparent,
                        elevation: 1,
                        shadowColor: const Color(0x14000000),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: const BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(13),
                                    ),
                                    child: Icon(
                                      Icons.local_shipping_rounded,
                                      color: statusColor,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'الطلب $orderId',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 17,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: isFavorite
                                        ? 'إزالة من المهام المميزة'
                                        : 'تمييز المهمة بنجمة',
                                    onPressed: () => _toggleFavorite(orderId),
                                    color: const Color(0xFFD4AF37),
                                    icon: Icon(
                                      isFavorite
                                          ? Icons.star_rounded
                                          : Icons.star_border_rounded,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: isCollapsed
                                        ? 'عرض تفاصيل المهمة'
                                        : 'تصغير تفاصيل المهمة',
                                    onPressed: () => setState(() {
                                      if (isCollapsed) {
                                        _collapsedOrderIds.remove(orderId);
                                      } else {
                                        _collapsedOrderIds.add(orderId);
                                      }
                                    }),
                                    icon: Icon(
                                      isCollapsed
                                          ? Icons.expand_more_rounded
                                          : Icons.expand_less_rounded,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  _assignmentStatusLabel(
                                    currentStatus,
                                    driverStatus,
                                  ),
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              if (!isCollapsed) ...[
                                const SizedBox(height: 12),
                                const Divider(height: 1),
                                const SizedBox(height: 12),
                                Text(
                                  'حالة المهمة: ${driverStatus == 'accepted' ? 'مقبولة' : 'بانتظار قبولك'}',
                                ),
                                const SizedBox(height: 6),
                                Text('الوقت المتوقع: $eta'),
                                const SizedBox(height: 6),
                                Text(
                                  'العنوان: ${assignment['delivery_address']?.toString() ?? 'غير محدد'}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (assignment['total'] != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'إجمالي الطلب: ${assignment['total']} '
                                    '${assignment['currency_symbol'] ?? assignment['currencySymbol'] ?? 'ر.ي'}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.person_outline_rounded,
                                      size: 20,
                                      color: Color(0xFF64748B),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text('العميل: $customerName'),
                                    ),
                                  ],
                                ),
                                if (customerPhone.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.phone_outlined,
                                        size: 20,
                                        color: Color(0xFF0EA5E9),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(child: Text(customerPhone)),
                                      IconButton(
                                        tooltip: 'الاتصال بالعميل',
                                        onPressed: () async {
                                          final uri =
                                              Uri.parse('tel:$customerPhone');
                                          if (await canLaunchUrl(uri)) {
                                            await launchUrl(uri);
                                          }
                                        },
                                        icon: const Icon(
                                          Icons.call_rounded,
                                          color: Color(0xFF10B981),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: TextButton.icon(
                                    onPressed: () =>
                                        _openAssignmentLocation(assignment),
                                    icon: const Icon(Icons.map_outlined),
                                    label: const Text('فتح موقع التسليم'),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: currentStatus == 'shipped'
                                        ? FilledButton.icon(
                                            onPressed: isBusy
                                                ? null
                                                : () => _confirmMerchantPickup(
                                                      orderId,
                                                    ),
                                            icon: isBusy
                                                ? const SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                                  )
                                                : const Icon(
                                                    Icons.pin_outlined,
                                                  ),
                                            label: Text(
                                              isBusy
                                                  ? 'جارٍ التحقق...'
                                                  : 'تأكيد الاستلام',
                                            ),
                                          )
                                        : currentStatus == 'picked_up'
                                            ? FilledButton.icon(
                                                onPressed: isBusy
                                                    ? null
                                                    : () =>
                                                        _confirmDeliveryToCustomer(
                                                          orderId,
                                                        ),
                                                icon: isBusy
                                                    ? const SizedBox(
                                                        width: 18,
                                                        height: 18,
                                                        child:
                                                            CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                      )
                                                    : const Icon(
                                                        Icons.task_alt_rounded,
                                                      ),
                                                label: Text(
                                                  isBusy
                                                      ? 'جارٍ تأكيد التسليم...'
                                                      : 'تأكيد التسليم',
                                                ),
                                              )
                                            : currentStatus == 'delivered' ||
                                                    currentStatus == 'cancelled'
                                                ? OutlinedButton.icon(
                                                    onPressed: null,
                                                    icon: Icon(
                                                      Icons.task_alt_rounded,
                                                    ),
                                                    label: Text('مغلقة'),
                                                  )
                                                : driverStatus == 'accepted'
                                                    ? OutlinedButton.icon(
                                                        onPressed: null,
                                                        icon: Icon(
                                                          Icons
                                                              .storefront_rounded,
                                                        ),
                                                        label: Text(
                                                          'بانتظار تجهيز المتجر',
                                                        ),
                                                      )
                                                    : FilledButton.icon(
                                                        onPressed: isBusy
                                                            ? null
                                                            : () =>
                                                                _acceptAssignment(
                                                                  assignment,
                                                                ),
                                                        icon: isBusy
                                                            ? const SizedBox(
                                                                width: 18,
                                                                height: 18,
                                                                child:
                                                                    CircularProgressIndicator(
                                                                  strokeWidth:
                                                                      2,
                                                                ),
                                                              )
                                                            : const Icon(
                                                                Icons
                                                                    .check_rounded,
                                                              ),
                                                        label: const Text(
                                                          'قبول المهمة',
                                                        ),
                                                      ),
                                  ),
                                  if (driverStatus == 'accepted' &&
                                      currentStatus != 'delivered' &&
                                      currentStatus != 'cancelled') ...[
                                    const SizedBox(width: 8),
                                    IconButton.filledTonal(
                                      tooltip: 'تحديث وقت الوصول',
                                      onPressed: isBusy
                                          ? null
                                          : () => _updateEta(assignment),
                                      icon:
                                          const Icon(Icons.access_time_rounded),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DriverMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _DriverMetricCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }
}

class BalanceManagementScreen extends StatefulWidget {
  const BalanceManagementScreen({
    super.key,
    this.adminService,
    this.walletService,
  });

  final AdminService? adminService;
  final MerchantWalletService? walletService;

  @override
  State<BalanceManagementScreen> createState() =>
      _BalanceManagementScreenState();
}

class _BalanceManagementScreenState extends State<BalanceManagementScreen> {
  late final AdminService _adminService;
  late final MerchantWalletService _walletService;
  late Future<_BalanceManagementData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _adminService = widget.adminService ?? AdminService();
    _walletService = widget.walletService ?? MerchantWalletService();
    _dataFuture = _loadData();
  }

  Future<_BalanceManagementData> _loadData() async {
    final results = await Future.wait<Object>([
      _adminService.getProfilesForAdmin(
        limit: null,
        propagateErrors: true,
      ),
      _walletService.getRequests(propagateErrors: true),
    ]);
    return _BalanceManagementData(
      profiles: results[0] as List<Map<String, dynamic>>,
      requests: results[1] as List<MerchantWithdrawalRequest>,
    );
  }

  Future<void> _refresh() async {
    final future = _loadData();
    setState(() {
      _dataFuture = future;
    });
    await future;
  }

  void _open(Widget screen) {
    Navigator.of(context).push(slideFadeRoute(page: screen));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة الأرصدة والحسابات'),
          actions: [
            IconButton(
              tooltip: 'تحديث البيانات',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: FutureBuilder<_BalanceManagementData>(
          future: _dataFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cloud_off_rounded,
                        size: 44,
                        color: Color(0xFFB91C1C),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'تعذر تحميل الحسابات والعمليات المالية',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(AppErrorMessage.from(snapshot.error!),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final data = snapshot.data!;
            final customers = data.countForRole('customer');
            final merchants = data.countForRole('merchant');
            final drivers = data.countForRole('driver');
            final openRequests = data.requests
                .where((request) =>
                    request.status == 'pending' || request.status == 'approved')
                .length;
            final recentRequests = data.requests.take(5).toList();

            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF111827), Color(0xFF1F2937)],
                        begin: Alignment.centerRight,
                        end: Alignment.centerLeft,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ملخص الحسابات والتسويات',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$openRequests طلب سحب مفتوح · '
                          '$customers عميل · $merchants تاجر · $drivers سائق',
                          style: const TextStyle(color: Color(0xFFE5E7EB)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 700 ? 4 : 2;
                      return GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: columns,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 1.25,
                        children: [
                          _BalanceMetricCard(
                            label: 'إجمالي الحسابات',
                            value: data.profiles.length.toString(),
                            icon: Icons.people_alt_rounded,
                            color: const Color(0xFF3B82F6),
                          ),
                          _BalanceMetricCard(
                            label: 'حسابات التجار',
                            value: merchants.toString(),
                            icon: Icons.storefront_rounded,
                            color: const Color(0xFF8B5CF6),
                          ),
                          _BalanceMetricCard(
                            label: 'حسابات العملاء',
                            value: customers.toString(),
                            icon: Icons.person_rounded,
                            color: const Color(0xFF10B981),
                          ),
                          _BalanceMetricCard(
                            label: 'طلبات السحب المفتوحة',
                            value: openRequests.toString(),
                            icon: Icons.payments_rounded,
                            color: const Color(0xFFF59E0B),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'إجراءات الإدارة',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  _BalanceActionTile(
                    title: 'إدارة حسابات المستخدمين',
                    subtitle: 'البحث في الحسابات ومراجعة الأدوار والتوثيق',
                    icon: Icons.manage_accounts_rounded,
                    onTap: () => _open(const UserManagementScreen()),
                  ),
                  _BalanceActionTile(
                    title: 'أرصدة التجار وطلبات السحب',
                    subtitle: 'مراجعة طلبات السحب واعتمادها أو تأكيد تحويلها',
                    icon: Icons.account_balance_wallet_rounded,
                    onTap: () => _open(const MerchantWalletAdminScreen()),
                  ),
                  _BalanceActionTile(
                    title: 'حركات وإيصالات الدفع',
                    subtitle:
                        'مراجعة إثباتات الدفع والعمليات المرتبطة بالطلبات',
                    icon: Icons.receipt_long_rounded,
                    onTap: () => _open(const ReceiptManagementScreen()),
                  ),
                  _BalanceActionTile(
                    title: 'حسابات الدفع الإلكترونية',
                    subtitle: 'تحديث بيانات حسابات الدفع المعتمدة',
                    icon: Icons.wallet_rounded,
                    onTap: () => _open(const WalletManagementScreen()),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'أحدث طلبات السحب',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            _open(const MerchantWalletAdminScreen()),
                        child: const Text('عرض الكل'),
                      ),
                    ],
                  ),
                  if (recentRequests.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Center(child: Text('لا توجد طلبات سحب مسجلة')),
                      ),
                    )
                  else
                    ...recentRequests.map(
                      (request) => _WithdrawalRequestTile(request: request),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BalanceManagementData {
  const _BalanceManagementData({
    required this.profiles,
    required this.requests,
  });

  final List<Map<String, dynamic>> profiles;
  final List<MerchantWithdrawalRequest> requests;

  int countForRole(String role) => profiles
      .where((profile) => profile['role']?.toString().toLowerCase() == role)
      .length;
}

class _BalanceMetricCard extends StatelessWidget {
  const _BalanceMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 10),
          Text(value,
              style:
                  const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
        ],
      ),
    );
  }
}

class _BalanceActionTile extends StatelessWidget {
  const _BalanceActionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
      ),
    );
  }
}

class _WithdrawalRequestTile extends StatelessWidget {
  const _WithdrawalRequestTile({required this.request});

  final MerchantWithdrawalRequest request;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (request.status) {
      'approved' => const Color(0xFF3B82F6),
      'paid' => const Color(0xFF10B981),
      'rejected' => const Color(0xFFB91C1C),
      _ => const Color(0xFFF59E0B),
    };
    final statusLabel = switch (request.status) {
      'approved' => 'بانتظار التحويل',
      'paid' => 'تم التحويل',
      'rejected' => 'مرفوض',
      _ => 'قيد المراجعة',
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.12),
          child: Icon(Icons.payments_rounded, color: statusColor),
        ),
        title: Text(
          '${request.amount.toStringAsFixed(2)} ${request.currencySymbol}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('التاجر: ${request.merchantId} · $statusLabel'),
        trailing: Text(
          '${request.createdAt.toLocal().day}/'
          '${request.createdAt.toLocal().month}/'
          '${request.createdAt.toLocal().year}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
        ),
      ),
    );
  }
}

class MerchantWalletAdminScreen extends StatefulWidget {
  const MerchantWalletAdminScreen({super.key});

  @override
  State<MerchantWalletAdminScreen> createState() =>
      _MerchantWalletAdminScreenState();
}

class _MerchantWalletAdminScreenState extends State<MerchantWalletAdminScreen> {
  final _service = MerchantWalletService();
  late Future<List<MerchantWithdrawalRequest>> _requestsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _requestsFuture = _service.getRequests();
  }

  Future<void> _update(
    MerchantWithdrawalRequest request,
    String status,
  ) async {
    final saved = await _service.updateRequestStatus(
      request: request,
      status: status,
    );
    if (!mounted) return;
    setState(_load);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text(saved ? 'تم تحديث حالة طلب السحب' : 'تعذر تحديث الطلب')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('محافظ التجار وطلبات السحب'),
          actions: [
            IconButton(
              onPressed: () => setState(_load),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: FutureBuilder<List<MerchantWithdrawalRequest>>(
          future: _requestsFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final requests = snapshot.data!;
            if (requests.isEmpty) {
              return const Center(child: Text('لا توجد طلبات سحب حاليًا'));
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: requests.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final request = requests[index];
                final pending = request.status == 'pending';
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${request.amount.toStringAsFixed(2)} ${request.currencySymbol}',
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Text('التاجر: ${request.merchantId}'),
                        Text(
                            'الحساب: ${request.accountName} - ${request.accountNumber}'),
                        Text('الحالة: ${_statusLabel(request.status)}'),
                        if (pending) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () => _update(request, 'approved'),
                                  icon: const Icon(Icons.check_rounded),
                                  label: const Text('اعتماد'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _update(request, 'rejected'),
                                  icon: const Icon(Icons.close_rounded),
                                  label: const Text('رفض'),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (request.status == 'approved') ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => _update(request, 'paid'),
                              icon: const Icon(Icons.paid_rounded),
                              label: const Text('تأكيد التحويل للتاجر'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  String _statusLabel(String status) => switch (status) {
        'approved' => 'معتمد وينتظر التحويل',
        'paid' => 'تم التحويل',
        'rejected' => 'مرفوض',
        _ => 'قيد المراجعة',
      };
}

class WalletManagementScreen extends StatefulWidget {
  const WalletManagementScreen({super.key, this.paymentService});

  final PaymentService? paymentService;

  @override
  State<WalletManagementScreen> createState() => _WalletManagementScreenState();
}

class _WalletManagementScreenState extends State<WalletManagementScreen> {
  late final PaymentService _paymentService;
  late Future<List<Map<String, dynamic>>> _walletsFuture;

  @override
  void initState() {
    super.initState();
    _paymentService = widget.paymentService ?? PaymentService();
    _loadWallets();
  }

  void _loadWallets() {
    _walletsFuture = _paymentService.getPaymentWallets().then((wallets) {
      if (wallets.any((wallet) => wallet['id'] == 'jib')) return wallets;
      return [
        ...wallets,
        {
          'id': 'jib',
          'provider': 'jib',
          'name': '',
          'account_number': '',
        },
      ];
    });
  }

  Future<void> _editWallet([Map<String, dynamic>? wallet]) async {
    final providerController = TextEditingController(
      text: wallet?['provider']?.toString() == 'jib'
          ? 'محفظة جيب'
          : wallet?['provider']?.toString() ?? '',
    );
    final nameController =
        TextEditingController(text: wallet?['name']?.toString() ?? '');
    final accountController = TextEditingController(
      text: wallet?['account_number']?.toString() ?? '',
    );
    String? logoUrl = wallet?['logo_url']?.toString().trim();
    if (logoUrl?.isEmpty == true) logoUrl = null;
    Uint8List? logoPreviewBytes;
    var isUploadingLogo = false;
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: Text(wallet == null ? 'إضافة محفظة دفع' : 'تعديل المحفظة'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: providerController,
                      decoration: const InputDecoration(
                        labelText: 'اسم المحفظة',
                        border: OutlineInputBorder(),
                      ),
                      validator: _requiredWalletField,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'اسم صاحب الحساب',
                        border: OutlineInputBorder(),
                      ),
                      validator: _requiredWalletField,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: accountController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'رقم الحساب أو المحفظة',
                        border: OutlineInputBorder(),
                      ),
                      validator: _requiredWalletField,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: isUploadingLogo
                          ? null
                          : () async {
                              setDialogState(() => isUploadingLogo = true);
                              try {
                                final file = await ImagePicker().pickImage(
                                  source: ImageSource.gallery,
                                  imageQuality: 85,
                                  maxWidth: 1000,
                                  maxHeight: 1000,
                                );
                                if (file == null) return;
                                final bytes = await file.readAsBytes();
                                final compacted =
                                    await MediaUploadService.compactImageBytes(
                                  bytes,
                                  maxWidth: 500,
                                  maxHeight: 500,
                                  targetSizeBytes: 150000,
                                  quality: 72,
                                );
                                if (compacted == null) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('تعذر تجهيز صورة الشعار'),
                                      ),
                                    );
                                  }
                                  return;
                                }
                                final uploaded =
                                    await MediaUploadService.uploadImage(
                                  compacted,
                                  fileName:
                                      'wallet-logo-${DateTime.now().millisecondsSinceEpoch}.jpg',
                                  contentType: 'image/jpeg',
                                  mediaType: 'products',
                                );
                                if (uploaded == null) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('تعذر رفع شعار المحفظة'),
                                      ),
                                    );
                                  }
                                  return;
                                }
                                if (dialogContext.mounted) {
                                  setDialogState(() {
                                    logoUrl = uploaded;
                                    logoPreviewBytes = compacted;
                                  });
                                }
                              } catch (error) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'تعذر اختيار شعار المحفظة: $error',
                                      ),
                                    ),
                                  );
                                }
                              } finally {
                                if (dialogContext.mounted) {
                                  setDialogState(() => isUploadingLogo = false);
                                }
                              }
                            },
                      icon: isUploadingLogo
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.image_outlined),
                      label: Text(
                        isUploadingLogo
                            ? 'جار رفع الشعار...'
                            : logoUrl == null
                                ? 'إضافة شعار المحفظة'
                                : 'تغيير شعار المحفظة',
                      ),
                    ),
                    if (logoUrl != null || logoPreviewBytes != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: logoPreviewBytes != null
                                ? Image.memory(
                                    logoPreviewBytes!,
                                    width: 64,
                                    height: 64,
                                    fit: BoxFit.cover,
                                  )
                                : Image(
                                    image: MediaUploadService.imageProvider(
                                          logoUrl!,
                                        ) ??
                                        NetworkImage(logoUrl!),
                                    width: 64,
                                    height: 64,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.broken_image_outlined,
                                      size: 40,
                                    ),
                                  ),
                          ),
                          IconButton(
                            tooltip: 'إزالة الشعار',
                            onPressed: isUploadingLogo
                                ? null
                                : () => setDialogState(() {
                                      logoUrl = null;
                                      logoPreviewBytes = null;
                                    }),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isUploadingLogo
                    ? null
                    : () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: isUploadingLogo
                    ? null
                    : () {
                        if (formKey.currentState!.validate()) {
                          Navigator.pop(dialogContext, true);
                        }
                      },
                child: const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );

    if (result == true) {
      final id = wallet?['id']?.toString() ??
          'wallet-${DateTime.now().millisecondsSinceEpoch}';
      final saved = await _paymentService.savePaymentWallet(
        id: id,
        provider: id == 'jib' ? 'jib' : providerController.text,
        name: nameController.text,
        accountNumber: accountController.text,
        logoUrl: logoUrl,
      );
      providerController.dispose();
      nameController.dispose();
      accountController.dispose();
      if (!mounted) return;
      setState(_loadWallets);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(saved ? 'تم حفظ بيانات المحفظة' : 'تعذر حفظ المحفظة'),
        ),
      );
      return;
    }
    providerController.dispose();
    nameController.dispose();
    accountController.dispose();
  }

  String? _requiredWalletField(String? value) =>
      value == null || value.trim().isEmpty ? 'هذا الحقل مطلوب' : null;

  Future<void> _deleteWallet(Map<String, dynamic> wallet) async {
    final id = wallet['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف المحفظة'),
          content: Text(
            'هل تريد حذف محفظة ${_walletLabel(wallet)}؟ لن تظهر للعملاء بعد ذلك.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await _paymentService.deletePaymentWallet(id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حذف المحفظة')),
      );
      return;
    }
    if (!mounted) return;
    setState(_loadWallets);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حذف المحفظة')),
    );
  }

  String _walletLabel(Map<String, dynamic> wallet) {
    final provider = wallet['provider']?.toString().trim() ?? '';
    if (provider == 'jib') return 'محفظة جيب';
    return provider.isNotEmpty ? provider : 'محفظة إلكترونية';
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة المحافظ الإلكترونية'),
          actions: [
            IconButton(
              onPressed: () => setState(_loadWallets),
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'تحديث',
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _editWallet,
          icon: const Icon(Icons.add_rounded),
          label: const Text('إضافة محفظة'),
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _walletsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('تعذر تحميل المحافظ الإلكترونية'),
                    TextButton(
                      onPressed: () => setState(_loadWallets),
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              );
            }
            final wallets = snapshot.data ?? const [];
            if (wallets.isEmpty) {
              return const Center(child: Text('لا توجد محافظ دفع مضافة'));
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              itemCount: wallets.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final wallet = wallets[index];
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.account_balance_wallet_rounded),
                    ),
                    title: Text(_walletLabel(wallet)),
                    subtitle: Text(
                      '${wallet['name'] ?? ''}\n'
                      'رقم الحساب: ${wallet['account_number'] ?? ''}',
                    ),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) {
                        if (action == 'edit') _editWallet(wallet);
                        if (action == 'delete') _deleteWallet(wallet);
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'edit', child: Text('تعديل')),
                        if (wallet['id'] != 'jib')
                          const PopupMenuItem(
                              value: 'delete', child: Text('حذف')),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class MerchantCategoryManagementScreen extends StatefulWidget {
  const MerchantCategoryManagementScreen({
    super.key,
    this.database,
  });

  final DatabaseService? database;

  @override
  State<MerchantCategoryManagementScreen> createState() =>
      _MerchantCategoryManagementScreenState();
}

class _MerchantCategoryManagementScreenState
    extends State<MerchantCategoryManagementScreen> {
  late final MerchantCategoryService _service;
  late Future<Map<String, dynamic>> _categoriesFuture;

  @override
  void initState() {
    super.initState();
    _service = MerchantCategoryService(database: widget.database);
    _refresh();
  }

  void _refresh() {
    final refreshFuture = _service.getAllCategories();
    _categoriesFuture = _lastMerchantCategoryMap.isEmpty
        ? refreshFuture.then((data) {
            _lastMerchantCategoryMap = data;
            return data;
          })
        : Future.value(_lastMerchantCategoryMap).then((data) async {
            final refreshed = await refreshFuture;
            _lastMerchantCategoryMap = refreshed;
            return refreshed;
          });
  }

  Future<void> _addCategory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة فئة متجر'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textDirection: TextDirection.rtl,
          decoration: const InputDecoration(
            labelText: 'اسم الفئة',
            hintText: 'مثل: أزياء، عطور، إلكترونيات',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (name == null || name.trim().isEmpty) return;
    try {
      await _service.addCategory(name);
      if (!mounted) return;
      setState(_refresh);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت إضافة فئة المتجر')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر إضافة الفئة إلى قاعدة البيانات')),
      );
    }
  }

  Future<void> _deleteCategory(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف فئة المتجر'),
        content: Text(
          'هل تريد حذف فئة المتجر «$name»؟ لا يمكن التراجع عن هذا الإجراء.',
        ),
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

    try {
      await _service.deleteCategory(id);
      if (!mounted) return;
      setState(_refresh);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حذف الفئة')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _categoriesFuture,
      builder: (context, snapshot) {
        final categories = snapshot.data ?? const <String, dynamic>{};
        final rows = categories.entries.map((entry) {
          final value = entry.value;
          final name = value is Map
              ? value['name']?.toString() ?? 'فئة متجر'
              : value.toString();
          return ListTile(
            leading: const CircleAvatar(
              child: Icon(Icons.storefront_rounded),
            ),
            title: Text(name),
            subtitle: const Text('تظهر للتاجر أثناء إنشاء الحساب'),
            trailing: IconButton(
              tooltip: 'حذف الفئة',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _deleteCategory(entry.key, name),
            ),
          );
        }).toList();

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('إدارة فئات المتاجر'),
              actions: [
                IconButton(
                  tooltip: 'إضافة فئة',
                  onPressed: _addCategory,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: _addCategory,
              icon: const Icon(Icons.add_rounded),
              label: const Text('إضافة فئة'),
            ),
            body: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'الفئات المعتمدة للتجار',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'أضف الفئات التي يمكن للتاجر اختيارها عند التسجيل.',
                  style: TextStyle(color: Color(0xFF6B7280)),
                ),
                const SizedBox(height: 18),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Center(child: CircularProgressIndicator())
                else if (rows.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(22),
                      child: Text('لا توجد فئات بعد. أضف أول فئة للمتاجر.'),
                    ),
                  )
                else
                  Card(
                    child: Column(children: rows),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class ProductCategoryManagementScreen extends StatefulWidget {
  const ProductCategoryManagementScreen({
    super.key,
    this.database,
  });

  final DatabaseService? database;

  @override
  State<ProductCategoryManagementScreen> createState() =>
      _ProductCategoryManagementScreenState();
}

class _ProductCategoryNameDialog extends StatefulWidget {
  const _ProductCategoryNameDialog({
    required this.title,
    required this.label,
    required this.hint,
  });

  final String title;
  final String label;
  final String hint;

  @override
  State<_ProductCategoryNameDialog> createState() =>
      _ProductCategoryNameDialogState();
}

class _ProductCategoryNameDialogState
    extends State<_ProductCategoryNameDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Form(
          key: _formKey,
          child: TextFormField(
            controller: _controller,
            autofocus: true,
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'يرجى إدخال الاسم'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                Navigator.pop(context, _controller.text.trim());
              }
            },
            child: const Text('إضافة'),
          ),
        ],
      );
}

class _ProductCategoryManagementScreenState
    extends State<ProductCategoryManagementScreen> {
  late final MerchantCategoryService _service;
  late Future<Map<String, dynamic>> _categoriesFuture;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _service = MerchantCategoryService(database: widget.database);
    _refresh();
  }

  void _refresh() {
    _categoriesFuture = _service.getAllProductCategories();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<String?> _showCategoryNameDialog() {
    return showDialog<String>(
      context: context,
      builder: (_) => const _ProductCategoryNameDialog(
        title: 'إضافة قسم رئيسي',
        label: 'اسم القسم الرئيسي',
        hint: 'مثل: ملابس، إلكترونيات، منزلية',
      ),
    );
  }

  Future<String?> _showSubcategoryNameDialog(String parentName) {
    return showDialog<String>(
      context: context,
      builder: (_) => _ProductCategoryNameDialog(
        title: 'إضافة قسم فرعي',
        label: 'اسم القسم الفرعي',
        hint: 'قسم فرعي ضمن $parentName',
      ),
    );
  }

  Future<void> _addCategory() async {
    final name = await _showCategoryNameDialog();
    if (name == null) return;

    try {
      await _service.addProductCategory(name);
      if (!mounted) return;
      setState(_refresh);
      _showMessage('تمت إضافة القسم الرئيسي');
    } catch (error) {
      if (!mounted) return;
      _showMessage(_categoryErrorMessage(error, 'تعذر إضافة القسم الرئيسي'));
    }
  }

  Future<void> _addSubcategory(String parentId, String parentName) async {
    final name = await _showSubcategoryNameDialog(parentName);
    if (name == null) return;
    try {
      await _service.addProductSubcategory(parentId, name);
      if (!mounted) return;
      setState(_refresh);
      _showMessage('تمت إضافة القسم الفرعي');
    } catch (error) {
      if (!mounted) return;
      _showMessage(_categoryErrorMessage(error, 'تعذر إضافة القسم الفرعي'));
    }
  }

  Future<void> _selectCategoryImage(
    String id, {
    required bool cover,
  }) async {
    final label = cover ? 'صورة الغلاف' : 'شعار القسم';
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1200,
        maxHeight: 1000,
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      final compacted = await MediaUploadService.compactImageBytes(
        bytes,
        maxWidth: cover ? 1200 : 500,
        maxHeight: cover ? 800 : 500,
        targetSizeBytes: cover ? 240000 : 150000,
        quality: 74,
      );
      if (compacted == null) {
        _showMessage('تعذر تجهيز $label');
        return;
      }

      final uploaded = await MediaUploadService.uploadImage(
        compacted,
        fileName:
            'category-${cover ? 'cover' : 'logo'}-${DateTime.now().millisecondsSinceEpoch}.jpg',
        contentType: 'image/jpeg',
        mediaType: 'products',
      );
      if (uploaded == null) {
        _showMessage('تعذر رفع $label');
        return;
      }

      await _service.setProductCategoryImage(
        id,
        cover: cover,
        imageUrl: uploaded,
      );
      if (!mounted) return;
      setState(_refresh);
      _showMessage('تم تحديث $label');
    } catch (error, stackTrace) {
      debugPrint('Failed to upload product category $label: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) _showMessage('تعذر تحديث $label');
    }
  }

  Future<void> _removeCategoryImage(
    String id, {
    required bool cover,
  }) async {
    final label = cover ? 'صورة الغلاف' : 'شعار القسم';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('إزالة $label'),
        content: Text('هل تريد إزالة $label والعودة إلى الصورة التلقائية؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('إزالة'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.setProductCategoryImage(id, cover: cover);
      if (!mounted) return;
      setState(_refresh);
      _showMessage('تمت إزالة $label');
    } catch (error, stackTrace) {
      debugPrint('Failed to remove product category $label: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) _showMessage('تعذر إزالة $label');
    }
  }

  Future<void> _setCategoryActive(String id, bool active) async {
    try {
      await _service.setProductCategoryActive(id, active);
      if (!mounted) return;
      setState(_refresh);
      _showMessage(
          active ? 'تم تفعيل القسم الرئيسي' : 'تم إيقاف القسم الرئيسي');
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        _categoryErrorMessage(error, 'تعذر تحديث حالة القسم الرئيسي'),
      );
    }
  }

  Future<void> _setSubcategoryActive(
    String parentId,
    String id,
    bool active,
  ) async {
    try {
      await _service.setProductSubcategoryActive(parentId, id, active);
      if (!mounted) return;
      setState(_refresh);
      _showMessage(active ? 'تم تفعيل القسم الفرعي' : 'تم إيقاف القسم الفرعي');
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        _categoryErrorMessage(error, 'تعذر تحديث حالة القسم الفرعي'),
      );
    }
  }

  Future<void> _deleteCategory(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف القسم الرئيسي'),
        content: Text(
          'هل تريد حذف القسم الرئيسي «$name» وجميع أقسامه الفرعية؟ '
          'لن يظهر للتجار عند إضافة منتجات جديدة.',
        ),
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

    try {
      await _service.deleteProductCategory(id);
      if (!mounted) return;
      setState(_refresh);
      _showMessage('تم حذف القسم الرئيسي');
    } catch (error) {
      if (!mounted) return;
      _showMessage(_categoryErrorMessage(error, 'تعذر حذف القسم الرئيسي'));
    }
  }

  Future<void> _moveCategory(String id, int offset) async {
    try {
      final categories = await _service.getAllProductCategories();
      final orderedCategories = categories.entries.toList()
        ..sort((first, second) {
          final order = _categorySortOrder(first.value).compareTo(
            _categorySortOrder(second.value),
          );
          return order == 0
              ? _categoryName(first.value).compareTo(
                  _categoryName(second.value),
                )
              : order;
        });
      final currentIndex =
          orderedCategories.indexWhere((category) => category.key == id);
      final nextIndex = currentIndex + offset;
      if (currentIndex < 0 ||
          nextIndex < 0 ||
          nextIndex >= orderedCategories.length) {
        return;
      }

      final movedCategory = orderedCategories.removeAt(currentIndex);
      orderedCategories.insert(nextIndex, movedCategory);
      await _service.setProductCategoryOrder(
        orderedCategories.map((category) => category.key).toList(),
      );
      if (!mounted) return;
      setState(_refresh);
      _showMessage('تم تحديث ترتيب الأقسام الرئيسية');
    } catch (error) {
      if (!mounted) return;
      setState(_refresh);
      _showMessage(_categoryErrorMessage(error, 'تعذر تحديث ترتيب الأقسام'));
    }
  }

  Future<void> _deleteSubcategory(
    String parentId,
    String id,
    String name,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف القسم الفرعي'),
        content: Text('هل تريد حذف القسم الفرعي «$name»؟'),
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
    try {
      await _service.deleteProductSubcategory(parentId, id);
      if (!mounted) return;
      setState(_refresh);
      _showMessage('تم حذف القسم الفرعي');
    } catch (error) {
      if (!mounted) return;
      _showMessage(_categoryErrorMessage(error, 'تعذر حذف القسم الفرعي'));
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _categoryErrorMessage(Object error, String fallback) {
    if (error is StateError) {
      return error.message.toString();
    }
    if (error is ArgumentError) {
      return error.message?.toString() ?? fallback;
    }
    return fallback;
  }

  String _categoryName(Object? value) =>
      value is Map ? value['name']?.toString() ?? '' : value?.toString() ?? '';

  int _categorySortOrder(Object? value) {
    final order =
        value is Map ? value['sort_order'] ?? value['sortOrder'] : null;
    if (order is num) return order.toInt();
    return int.tryParse(order?.toString() ?? '') ?? 0;
  }

  bool _isCategoryActive(Object? value) =>
      value is! Map || value['active'] != false;

  Map<String, dynamic> _subcategories(Object? value) {
    if (value is! Map || value['subcategories'] is! Map) {
      return const <String, dynamic>{};
    }
    return Map<String, dynamic>.from(value['subcategories'] as Map);
  }

  Widget _buildSubcategoryTile(
    String parentId,
    MapEntry<String, dynamic> entry,
  ) {
    final name = _categoryName(entry.value);
    final active = _isCategoryActive(entry.value);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 34),
      child: ListTile(
        dense: true,
        leading: Icon(
          Icons.subdirectory_arrow_left_rounded,
          color: active ? const Color(0xFF0F766E) : const Color(0xFF9CA3AF),
        ),
        title: Text(name),
        subtitle: Text(active ? 'نشط — متاح للتاجر' : 'موقوف — مخفي عن التاجر'),
        trailing: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Switch(
              value: active,
              onChanged: (value) =>
                  _setSubcategoryActive(parentId, entry.key, value),
            ),
            PopupMenuButton<String>(
              tooltip: 'إجراءات القسم الفرعي',
              onSelected: (action) {
                if (action == 'delete') {
                  _deleteSubcategory(parentId, entry.key, name);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'delete', child: Text('حذف')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _categoriesFuture,
      builder: (context, snapshot) {
        final categories = snapshot.data ?? const <String, dynamic>{};
        final query = _searchQuery.trim().toLowerCase();
        final entries = categories.entries.where((entry) {
          final parentMatches =
              _categoryName(entry.value).toLowerCase().contains(query);
          final childrenMatch = _subcategories(entry.value).values.any(
                (child) => _categoryName(child).toLowerCase().contains(query),
              );
          return parentMatches || childrenMatch;
        }).toList()
          ..sort((first, second) {
            final order = _categorySortOrder(first.value).compareTo(
              _categorySortOrder(second.value),
            );
            return order == 0
                ? _categoryName(first.value).compareTo(
                    _categoryName(second.value),
                  )
                : order;
          });
        final activeParents = categories.values.where(_isCategoryActive).length;
        final activeSubcategories = categories.values
            .expand((category) => _subcategories(category).values)
            .where(_isCategoryActive)
            .length;
        final inactiveSubcategories = categories.values
                .expand((category) => _subcategories(category).values)
                .length -
            activeSubcategories;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('إدارة أقسام المنتجات'),
              actions: [
                IconButton(
                  tooltip: 'تحديث الأقسام',
                  onPressed: () => setState(_refresh),
                  icon: const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  tooltip: 'إضافة قسم رئيسي',
                  onPressed: _addCategory,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: _addCategory,
              icon: const Icon(Icons.add_rounded),
              label: const Text('إضافة قسم رئيسي'),
            ),
            body: snapshot.connectionState == ConnectionState.waiting
                ? const Center(child: CircularProgressIndicator())
                : snapshot.hasError
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('تعذر تحميل أقسام المنتجات'),
                            const SizedBox(height: 8),
                            FilledButton(
                              onPressed: () => setState(_refresh),
                              child: const Text('إعادة المحاولة'),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          const Text(
                            'الأقسام المتاحة للتجار',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'أنشئ الأقسام الرئيسية ثم أضف الأقسام الفرعية التابعة '
                            'لها. لا تظهر الأقسام الموقوفة للتاجر عند إضافة منتج.',
                            style: TextStyle(color: Color(0xFF6B7280)),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            children: [
                              Chip(
                                  label: Text(
                                      'أقسام رئيسية نشطة: $activeParents')),
                              Chip(
                                label: Text(
                                  'أقسام فرعية نشطة: $activeSubcategories',
                                ),
                              ),
                              Chip(
                                label: Text(
                                  'أقسام فرعية موقوفة: $inactiveSubcategories',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _searchController,
                            onChanged: (value) =>
                                setState(() => _searchQuery = value),
                            decoration: InputDecoration(
                              labelText: 'البحث في الأقسام',
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: _searchQuery.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'مسح البحث',
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _searchQuery = '');
                                      },
                                      icon: const Icon(Icons.clear_rounded),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (categories.isEmpty)
                            const Card(
                              child: Padding(
                                padding: EdgeInsets.all(22),
                                child: Text(
                                  'لا توجد أقسام بعد. أضف أول قسم رئيسي.',
                                ),
                              ),
                            )
                          else if (entries.isEmpty)
                            const Card(
                              child: Padding(
                                padding: EdgeInsets.all(22),
                                child: Text('لا توجد أقسام مطابقة للبحث'),
                              ),
                            )
                          else
                            Card(
                              child: Column(
                                children: [
                                  for (final entry in entries) ...[
                                    Builder(
                                      builder: (context) {
                                        final parentName =
                                            _categoryName(entry.value);
                                        final categoryIndex =
                                            entries.indexOf(entry);
                                        final record = entry.value is Map
                                            ? Map<String, dynamic>.from(
                                                entry.value as Map,
                                              )
                                            : const <String, dynamic>{};
                                        final logoUrl =
                                            (record['logo_image_url'] ??
                                                        record['logo_url'] ??
                                                        record['image_url'])
                                                    ?.toString()
                                                    .trim() ??
                                                '';
                                        final coverUrl = (record[
                                                        'cover_image_url'] ??
                                                    record['cover_url'] ??
                                                    record['banner_image_url'])
                                                ?.toString()
                                                .trim() ??
                                            '';
                                        final logoProvider =
                                            MediaUploadService.imageProvider(
                                          logoUrl,
                                        );
                                        final children =
                                            _subcategories(entry.value)
                                                .entries
                                                .where((child) {
                                          return query.isEmpty ||
                                              parentName
                                                  .toLowerCase()
                                                  .contains(query) ||
                                              _categoryName(child.value)
                                                  .toLowerCase()
                                                  .contains(query);
                                        }).toList()
                                              ..sort((first, second) =>
                                                  _categoryName(first.value)
                                                      .compareTo(
                                                    _categoryName(second.value),
                                                  ));
                                        return ExpansionTile(
                                          key: PageStorageKey(entry.key),
                                          leading: CircleAvatar(
                                            backgroundImage: logoProvider,
                                            child: logoProvider == null
                                                ? Icon(
                                                    _isCategoryActive(
                                                      entry.value,
                                                    )
                                                        ? Icons.category_rounded
                                                        : Icons
                                                            .pause_circle_outline,
                                                  )
                                                : null,
                                          ),
                                          title: Text(parentName),
                                          subtitle: Text(
                                            _isCategoryActive(entry.value)
                                                ? '${children.length} قسم فرعي'
                                                : 'موقوف — لن يظهر للتاجر',
                                          ),
                                          trailing: Wrap(
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              Switch(
                                                value: _isCategoryActive(
                                                  entry.value,
                                                ),
                                                onChanged: (active) =>
                                                    _setCategoryActive(
                                                  entry.key,
                                                  active,
                                                ),
                                              ),
                                              PopupMenuButton<String>(
                                                tooltip:
                                                    'إجراءات القسم الرئيسي',
                                                onSelected: (action) {
                                                  if (action == 'add_child') {
                                                    _addSubcategory(
                                                      entry.key,
                                                      parentName,
                                                    );
                                                  } else if (action ==
                                                      'delete') {
                                                    _deleteCategory(
                                                      entry.key,
                                                      parentName,
                                                    );
                                                  } else if (action ==
                                                      'move_up') {
                                                    _moveCategory(
                                                      entry.key,
                                                      -1,
                                                    );
                                                  } else if (action ==
                                                      'move_down') {
                                                    _moveCategory(
                                                      entry.key,
                                                      1,
                                                    );
                                                  } else if (action ==
                                                      'set_logo') {
                                                    _selectCategoryImage(
                                                      entry.key,
                                                      cover: false,
                                                    );
                                                  } else if (action ==
                                                      'set_cover') {
                                                    _selectCategoryImage(
                                                      entry.key,
                                                      cover: true,
                                                    );
                                                  } else if (action ==
                                                      'remove_logo') {
                                                    _removeCategoryImage(
                                                      entry.key,
                                                      cover: false,
                                                    );
                                                  } else if (action ==
                                                      'remove_cover') {
                                                    _removeCategoryImage(
                                                      entry.key,
                                                      cover: true,
                                                    );
                                                  }
                                                },
                                                itemBuilder: (_) => [
                                                  const PopupMenuItem(
                                                    value: 'add_child',
                                                    child: Text(
                                                      'إضافة قسم فرعي',
                                                    ),
                                                  ),
                                                  if (query.isEmpty &&
                                                      categoryIndex > 0)
                                                    const PopupMenuItem(
                                                      value: 'move_up',
                                                      child: Text(
                                                        'تحريك للأعلى',
                                                      ),
                                                    ),
                                                  if (query.isEmpty &&
                                                      categoryIndex <
                                                          entries.length - 1)
                                                    const PopupMenuItem(
                                                      value: 'move_down',
                                                      child: Text(
                                                        'تحريك للأسفل',
                                                      ),
                                                    ),
                                                  PopupMenuItem(
                                                    value: 'set_logo',
                                                    child: Text(
                                                      logoUrl.isEmpty
                                                          ? 'اختيار شعار القسم'
                                                          : 'تغيير شعار القسم',
                                                    ),
                                                  ),
                                                  PopupMenuItem(
                                                    value: 'set_cover',
                                                    child: Text(
                                                      coverUrl.isEmpty
                                                          ? 'اختيار صورة الغلاف'
                                                          : 'تغيير صورة الغلاف',
                                                    ),
                                                  ),
                                                  if (logoUrl.isNotEmpty)
                                                    const PopupMenuItem(
                                                      value: 'remove_logo',
                                                      child: Text(
                                                        'إزالة شعار القسم',
                                                      ),
                                                    ),
                                                  if (coverUrl.isNotEmpty)
                                                    const PopupMenuItem(
                                                      value: 'remove_cover',
                                                      child: Text(
                                                        'إزالة صورة الغلاف',
                                                      ),
                                                    ),
                                                  const PopupMenuItem(
                                                    value: 'delete',
                                                    child: Text('حذف القسم'),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          children: [
                                            if (children.isEmpty)
                                              const Padding(
                                                padding: EdgeInsets.all(12),
                                                child: Text(
                                                  'لا توجد أقسام فرعية بعد',
                                                ),
                                              )
                                            else
                                              ...children.map(
                                                (child) =>
                                                    _buildSubcategoryTile(
                                                  entry.key,
                                                  child,
                                                ),
                                              ),
                                            TextButton.icon(
                                              onPressed: () => _addSubcategory(
                                                entry.key,
                                                parentName,
                                              ),
                                              icon: const Icon(
                                                Icons.add_rounded,
                                              ),
                                              label: const Text(
                                                'إضافة قسم فرعي',
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ),
                        ],
                      ),
          ),
        );
      },
    );
  }
}

class _AdminMerchantPickerDialog extends StatefulWidget {
  const _AdminMerchantPickerDialog({
    required this.merchants,
    required this.onEditDeliveryFee,
  });

  final List<Map<String, dynamic>> merchants;
  final Future<void> Function(Map<String, dynamic> merchant) onEditDeliveryFee;

  @override
  State<_AdminMerchantPickerDialog> createState() =>
      _AdminMerchantPickerDialogState();
}

class _AdminMerchantPickerDialogState
    extends State<_AdminMerchantPickerDialog> {
  final _searchController = TextEditingController();
  Map<String, dynamic>? _selectedMerchant;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = widget.merchants.where((merchant) {
      final searchable = [
        merchant['id'],
        merchant['full_name'],
        merchant['shop_name'],
        merchant['phone'],
        merchant['email'],
        merchant['shop_category'],
        merchant['shop_location'],
        merchant['shop_region'],
        merchant['city'],
      ].whereType<Object>().join(' ').toLowerCase();
      return query.isEmpty || searchable.contains(query);
    }).toList();

    return AlertDialog(
      title: const Text('اختيار التاجر'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('admin-merchant-picker-search'),
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'ابحث بالاسم أو المتجر أو الهاتف أو الموقع',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'مسح البحث',
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 280,
              child: filtered.isEmpty
                  ? const Center(child: Text('لا توجد نتائج مطابقة'))
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final merchant = filtered[index];
                        final id = merchant['id'].toString();
                        final isSelected = _selectedMerchant?['id'] == id;
                        final shopName = (merchant['shop_name'] ??
                                merchant['full_name'] ??
                                'متجر بدون اسم')
                            .toString();
                        final details = [
                          merchant['full_name'],
                          merchant['phone'],
                          merchant['shop_category'],
                          merchant['shop_location'] ??
                              merchant['shop_region'] ??
                              merchant['city'],
                        ]
                            .whereType<Object>()
                            .map((value) => value.toString().trim())
                            .where((value) => value.isNotEmpty)
                            .toSet()
                            .join(' • ');
                        final deliveryFee =
                            merchant['merchant_display_delivery_fee'] ??
                                merchant['merchantDisplayDeliveryFee'];

                        return ListTile(
                          selected: isSelected,
                          leading: Icon(
                            isSelected
                                ? Icons.radio_button_checked_rounded
                                : Icons.storefront_outlined,
                          ),
                          title: Text(shopName),
                          subtitle: Text(
                            [
                              details,
                              if (deliveryFee != null)
                                'أجرة التوصيل الظاهرة: $deliveryFee '
                                    '${CurrencyService.yerCurrency.symbol}',
                            ].where((value) => value.isNotEmpty).join('\n'),
                          ),
                          isThreeLine: details.contains('•'),
                          onTap: () => setState(
                            () => _selectedMerchant = merchant,
                          ),
                          trailing: IconButton(
                            tooltip: 'تعديل أجرة التوصيل لهذا التاجر',
                            onPressed: () async {
                              await widget.onEditDeliveryFee(merchant);
                              if (mounted) setState(() {});
                            },
                            icon: const Icon(Icons.local_shipping_outlined),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _selectedMerchant == null
              ? null
              : () => Navigator.pop(context, _selectedMerchant),
          icon: const Icon(Icons.add_rounded),
          label: const Text('اختيار وإضافة منتج'),
        ),
      ],
    );
  }
}

class ProductManagementAdminScreen extends StatefulWidget {
  const ProductManagementAdminScreen({
    super.key,
    this.databaseService,
  });

  final DatabaseService? databaseService;

  @override
  State<ProductManagementAdminScreen> createState() =>
      _ProductManagementAdminScreenState();
}

class _ProductManagementAdminScreenState
    extends State<ProductManagementAdminScreen> {
  late Future<List<Map<String, dynamic>>> _productsFuture;
  String _statusFilter = 'pending';
  final _productSearchController = TextEditingController();
  final _merchantSearchController = TextEditingController();
  String _categoryFilter = 'all';
  bool _newestFirst = true;
  PricingConfig _pricingConfig = const PricingConfig();

  DatabaseService get _database =>
      widget.databaseService ?? FirebaseDatabaseService.instance;

  AdminService get _adminService => AdminService(databaseService: _database);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _productsFuture = _loadProducts();
  }

  Future<void> _addProductForMerchant() async {
    try {
      final profiles = await _database.read('profiles');
      final merchants = <Map<String, dynamic>>[];
      for (final entry in profiles.entries) {
        if (entry.value is! Map) continue;
        final profile = Map<String, dynamic>.from(entry.value as Map);
        if ((profile['role'] ?? '').toString().toLowerCase() != 'merchant' ||
            profile['is_archived'] == true) {
          continue;
        }
        merchants.add({
          ...profile,
          'id': (profile['id'] ?? entry.key).toString(),
        });
      }
      merchants.sort((left, right) {
        final leftName =
            (left['shop_name'] ?? left['full_name'] ?? '').toString();
        final rightName =
            (right['shop_name'] ?? right['full_name'] ?? '').toString();
        return leftName.toLowerCase().compareTo(rightName.toLowerCase());
      });

      if (!mounted) return;
      if (merchants.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا يوجد تجار لاختيارهم')),
        );
        return;
      }

      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => _AdminMerchantPickerDialog(
          merchants: merchants,
          onEditDeliveryFee: _editMerchantDeliveryFeeForAdmin,
        ),
      );
      if (selected == null || !mounted) return;

      final merchantName =
          (selected['shop_name'] ?? selected['full_name'] ?? 'متجر بدون اسم')
              .toString();
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => MerchantProductManagementScreen(
            ownerMerchantId: selected['id'].toString(),
            ownerMerchantName: merchantName,
            adminManaged: true,
            startWithAddProduct: true,
            currencySymbol: CurrencyService.yerCurrency.symbol,
          ),
        ),
      );
      if (mounted) setState(_refresh);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تعذر فتح نموذج إضافة المنتج: ${AppErrorMessage.from(error)}',
            ),
          ),
        );
      }
    }
  }

  Future<void> _editMerchantDeliveryFeeForAdmin(
    Map<String, dynamic> merchant,
  ) async {
    try {
      final globalFee =
          await _adminService.getGlobalMerchantDisplayDeliveryFeeForAdmin();
      if (!mounted) return;
      final selection = await showDialog<_MerchantDisplayDeliveryFeeSelection>(
        context: context,
        builder: (_) => _MerchantDisplayDeliveryFeeDialog(
          currentFee: merchant['merchant_display_delivery_fee'] ??
              merchant['merchantDisplayDeliveryFee'],
          globalFee: globalFee,
          allowForAllMerchants: false,
        ),
      );
      if (selection == null || !mounted) return;
      final updated =
          await _adminService.updateMerchantDisplayDeliveryFeeForAdmin(
        merchantId: (merchant['id'] ?? '').toString(),
        deliveryFee: selection.fee,
      );
      if (!updated) {
        throw StateError('تعذر حفظ أجرة التوصيل لهذا التاجر');
      }
      if (selection.fee == null) {
        merchant.remove('merchant_display_delivery_fee');
        merchant.remove('merchantDisplayDeliveryFee');
      } else {
        merchant['merchant_display_delivery_fee'] = selection.fee;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تحديث أجرة التوصيل للتاجر')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تعذر تحديث أجرة التوصيل: ${AppErrorMessage.from(error)}',
            ),
          ),
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadProducts() async {
    final database = widget.databaseService ?? FirebaseDatabaseService.instance;
    final snapshots = await Future.wait([
      database.read('products'),
      database.read('profiles'),
      database.read('settings/pricing'),
    ]);
    _pricingConfig = PricingConfig.fromJson(snapshots[2]);
    final merchants = <String, String>{};
    for (final entry in snapshots[1].entries) {
      if (entry.value is! Map) continue;
      final profile = Map<String, dynamic>.from(entry.value as Map);
      final id = (profile['id'] ?? entry.key).toString();
      final name = (profile['shop_name'] ??
              profile['shopName'] ??
              profile['full_name'] ??
              '')
          .toString();
      if (id.isNotEmpty && name.isNotEmpty) merchants[id] = name;
    }

    final products = <Map<String, dynamic>>[];
    for (final entry in snapshots[0].entries) {
      if (entry.value is! Map) continue;
      final product = Map<String, dynamic>.from(entry.value as Map);
      final merchantId = (product['merchant_id'] ?? '').toString();
      products.add({
        ...product,
        'id': entry.key,
        'merchant_name': product['merchant_name'] ?? merchants[merchantId],
      });
    }
    products.sort(_compareProductDates);
    return products;
  }

  int _compareProductDates(
    Map<String, dynamic> first,
    Map<String, dynamic> second,
  ) {
    DateTime? createdAt(Map<String, dynamic> product) {
      final value = product['submitted_at'] ??
          product['created_at'] ??
          product['submittedAt'] ??
          product['createdAt'];
      if (value is num) {
        return DateTime.fromMillisecondsSinceEpoch(value.toInt());
      }
      return DateTime.tryParse(value?.toString() ?? '');
    }

    final firstDate = createdAt(first);
    final secondDate = createdAt(second);
    if (firstDate == null) return secondDate == null ? 0 : 1;
    if (secondDate == null) return -1;
    final comparison = secondDate.compareTo(firstDate);
    return _newestFirst ? comparison : -comparison;
  }

  @override
  void dispose() {
    _productSearchController.dispose();
    _merchantSearchController.dispose();
    super.dispose();
  }

  String _approvalStatus(Map<String, dynamic> product) {
    final status = (product['approval_status'] ?? '').toString();
    return {'pending', 'approved', 'rejected'}.contains(status)
        ? status
        : 'approved';
  }

  Future<void> _reviewPriceChange(Map<String, dynamic> product) async {
    final id = (product['id'] ?? '').toString();
    final requestedPrice = double.tryParse(
      product['requested_price']?.toString() ?? '',
    );
    if (id.isEmpty || requestedPrice == null || !requestedPrice.isFinite) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('بيانات طلب تعديل السعر غير صالحة')),
      );
      return;
    }

    final reasonController = TextEditingController();
    var validationError = '';
    final decision = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('مراجعة طلب تعديل السعر'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('المنتج: ${product['name'] ?? 'منتج'}'),
              Text('السعر الحالي: ${product['price'] ?? 0}'),
              Text(
                'السعر المطلوب: $requestedPrice '
                '${product['currency_symbol'] ?? 'ر.س'}',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                minLines: 2,
                maxLines: 4,
                onChanged: (_) => setDialogState(() {}),
                decoration: InputDecoration(
                  labelText: 'ملاحظة للتاجر أو سبب الرفض',
                  errorText: validationError.isEmpty ? null : validationError,
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
            TextButton(
              onPressed: () {
                final reason = reasonController.text.trim();
                if (reason.isEmpty) {
                  setDialogState(
                    () => validationError = 'سبب الرفض مطلوب للتاجر',
                  );
                  return;
                }
                Navigator.pop(dialogContext, {
                  'status': 'rejected',
                  'reason': reason,
                });
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('رفض مع السبب'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, {
                'status': 'approved',
                'reason': reasonController.text.trim(),
              }),
              child: const Text('الموافقة على السعر'),
            ),
          ],
        ),
      ),
    );
    reasonController.dispose();
    if (decision == null) return;

    final approved = decision['status'] == 'approved';
    try {
      await FirebaseDatabaseService.instance.update('products/$id', {
        if (approved) 'price': requestedPrice,
        'price_change_status': decision['status'],
        'price_change_review_reason': decision['reason'],
        'price_change_reviewed_at': DateTime.now().toIso8601String(),
      });
      if (!mounted) return;
      setState(_refresh);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approved
                ? 'تمت الموافقة على تعديل السعر'
                : 'تم رفض طلب السعر وحُفظ السبب للتاجر',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حفظ قرار تعديل السعر')),
      );
    }
  }

  void _showProductReviewImage(String source) {
    final provider = MediaUploadService.imageProvider(source);
    if (provider == null) return;
    showProductImageFullscreen(context, provider);
  }

  Future<void> _reviewProduct(Map<String, dynamic> product) async {
    final savedCommissionValue = double.tryParse(
      product['commission_value_override']?.toString() ?? '',
    );
    var commissionEnabled = savedCommissionValue != null;
    final savedCommissionMode = product['commission_mode_override']?.toString();
    var commissionMode = {'percent', 'fixed'}.contains(savedCommissionMode)
        ? savedCommissionMode!
        : 'percent';
    var commissionValueText = savedCommissionValue?.toString() ?? '';
    var approvalNote = '';
    var commissionValidationError = '';

    Future<String?> showRejectionReasonDialog() async {
      var rejectionReason = '';
      var validationError = '';
      return showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            scrollable: true,
            title: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.block_outlined,
                    color: Color(0xFFB91C1C),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('رفض المنتج'),
                      SizedBox(height: 4),
                      Text(
                        'اكتب سبب الرفض للتاجر',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.normal,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Text(
                      'سيتم رفض «${product['name'] ?? 'المنتج'}»، وإرسال هذا السبب إلى التاجر مع إشعار الرفض.',
                      style: const TextStyle(
                        color: Color(0xFF92400E),
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    key: const ValueKey('admin-product-rejection-reason'),
                    minLines: 3,
                    maxLines: 5,
                    autofocus: true,
                    onChanged: (value) {
                      rejectionReason = value;
                      if (validationError.isNotEmpty) {
                        setDialogState(() => validationError = '');
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'سبب الرفض',
                      hintText: 'اذكر ما يلزم تعديله في المنتج',
                      alignLabelWithHint: true,
                      errorText:
                          validationError.isEmpty ? null : validationError,
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('إلغاء'),
              ),
              FilledButton.icon(
                onPressed: () {
                  final reason = rejectionReason.trim();
                  if (reason.isEmpty) {
                    setDialogState(
                      () => validationError = 'سبب الرفض مطلوب',
                    );
                    return;
                  }
                  Navigator.pop(dialogContext, reason);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB91C1C),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.check_rounded),
                label: const Text('تأكيد الرفض'),
              ),
            ],
          ),
        ),
      );
    }

    final decision = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Map<String, dynamic>? buildDecision(
            String status, {
            String? decisionReason,
          }) {
            double? commissionValue;
            if (commissionEnabled) {
              commissionValue = double.tryParse(commissionValueText.trim());
              if (commissionValue == null ||
                  !commissionValue.isFinite ||
                  commissionValue < 0) {
                setDialogState(
                  () => commissionValidationError =
                      'أدخل قيمة عمولة رقمية صحيحة وغير سالبة',
                );
                return null;
              }
              commissionValidationError = '';
            }
            return {
              'status': status,
              'reason': (decisionReason ?? approvalNote).trim(),
              'commission_mode_override':
                  commissionEnabled ? commissionMode : null,
              'commission_value_override':
                  commissionEnabled ? commissionValue : null,
            };
          }

          final images = resolveAdminProductImageUrls(product);
          final videoUrl = (product['video_url'] ?? product['videoUrl'] ?? '')
              .toString()
              .trim();
          final currency = (product['currency_symbol'] ?? 'ر.س').toString();
          final colors = _productReviewValues(
            product['colors'] ?? product['available_colors'],
          ).join('، ');
          final sizes = _productReviewValues(
            product['sizes'] ?? product['available_sizes'],
          ).join('، ');

          Widget detailLine(String label, Object? rawValue) {
            final value = rawValue?.toString().trim() ?? '';
            if (value.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.all(4),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F6F4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE9E2DD)),
                ),
                child: Text(
                  '$label: $value',
                  style: const TextStyle(height: 1.4),
                ),
              ),
            );
          }

          Widget sectionTitle(String title, IconData icon) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: const Color(0xFF713F2B)),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          }

          final approvalStatus = _approvalStatus(product);
          final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
          final statusLabel = switch (approvalStatus) {
            'pending' => 'بانتظار المراجعة',
            'approved' => 'معتمد',
            'rejected' => 'مرفوض',
            _ => 'غير محدد',
          };

          return Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 920,
                maxHeight: MediaQuery.sizeOf(context).height * 0.92,
              ),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsetsDirectional.fromSTEB(22, 18, 12, 18),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF713F2B), Color(0xFF9A5A3D)],
                      ),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.fact_check_outlined,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'معاينة ومراجعة المنتج',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                (product['name'] ?? 'منتج').toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFEADBD4),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            statusLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'إغلاق',
                          onPressed: () => Navigator.pop(dialogContext),
                          color: Colors.white,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          sectionTitle(
                              'صور المنتج', Icons.photo_library_outlined),
                          if (images.isNotEmpty)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'صور المنتج (${images.length})',
                                  style: const TextStyle(
                                    color: Color(0xFF6B7280),
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 154,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: images.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 10),
                                    itemBuilder: (context, index) {
                                      final provider =
                                          MediaUploadService.imageProvider(
                                        images[index],
                                      );
                                      return InkWell(
                                        key: ValueKey(
                                            'admin-product-image-tap-$index'),
                                        onTap: () => _showProductReviewImage(
                                          images[index],
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          child: Container(
                                            width: 154,
                                            height: 154,
                                            color: const Color(0xFFF3EFEC),
                                            child: provider == null
                                                ? const Icon(
                                                    Icons.broken_image_rounded,
                                                    color: Color(0xFF8A817B),
                                                  )
                                                : Image(
                                                    key: ValueKey(
                                                      'admin-product-image-$index',
                                                    ),
                                                    image: provider,
                                                    fit: BoxFit.cover,
                                                    errorBuilder:
                                                        (_, __, ___) =>
                                                            const Icon(
                                                      Icons
                                                          .broken_image_rounded,
                                                      color: Color(0xFF8A817B),
                                                    ),
                                                  ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            )
                          else
                            Container(
                              height: 100,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8F6F4),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFE9E2DD),
                                ),
                              ),
                              child: const Text('لا توجد صور مرفقة'),
                            ),
                          if (videoUrl.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8F6F4),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFE9E2DD),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.video_library_outlined,
                                    color: Color(0xFF713F2B),
                                  ),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Text(
                                      'فيديو المنتج مرفق',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => showProductVideoFullscreen(
                                      context,
                                      videoUrl: videoUrl,
                                    ),
                                    icon: const Icon(
                                      Icons.play_circle_outline_rounded,
                                    ),
                                    label: const Text('مشاهدة فيديو المنتج'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          sectionTitle(
                            'بيانات المنتج والتاجر',
                            Icons.inventory_2_outlined,
                          ),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: const Color(0xFFE9E2DD),
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x0A000000),
                                  blurRadius: 12,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (product['name'] ?? 'منتج').toString(),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: [
                                    detailLine(
                                      'التاجر',
                                      product['merchant_name'] ?? 'غير معروف',
                                    ),
                                    detailLine(
                                      'معرف التاجر',
                                      product['merchant_id'],
                                    ),
                                    detailLine(
                                      'الفئة',
                                      product['category'] ??
                                          product['categories'],
                                    ),
                                    detailLine('معرف المنتج', product['id']),
                                    detailLine(
                                      'السعر',
                                      '${product['price'] ?? 0} $currency',
                                    ),
                                    if (product[
                                            'merchant_claimed_original_price'] !=
                                        null)
                                      detailLine(
                                        'السعر الأصلي المعلن من التاجر',
                                        '${product['merchant_claimed_original_price']} $currency',
                                      ),
                                    detailLine(
                                      'الكمية المتاحة',
                                      product['stock'] ?? product['inventory'],
                                    ),
                                    detailLine('المقاسات', sizes),
                                    detailLine('الألوان', colors),
                                    detailLine(
                                      'الوصف والتفاصيل',
                                      product['description'],
                                    ),
                                    detailLine(
                                      'التوفر المطلوب',
                                      product['requested_available'] ??
                                          product['available'],
                                    ),
                                    detailLine(
                                      'تاريخ الإرسال',
                                      product['submitted_at'] ??
                                          product['created_at'] ??
                                          product['submittedAt'] ??
                                          product['createdAt'],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          sectionTitle(
                            'العمولة وسعر البيع',
                            Icons.price_change_outlined,
                          ),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFBF7),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: const Color(0xFFF0E0D5),
                              ),
                            ),
                            child: Column(
                              children: [
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: commissionEnabled,
                                  title: const Text(
                                    'تحديد عمولة خاصة لهذا المنتج',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  subtitle: Text(
                                    commissionEnabled
                                        ? 'تتجاوز هذه القيمة عمولة الفئة والعمولة العامة'
                                        : 'سيستخدم المنتج عمولة الفئة أو العمولة العامة',
                                  ),
                                  onChanged: (enabled) {
                                    setDialogState(() {
                                      commissionEnabled = enabled ?? false;
                                      commissionValidationError = '';
                                    });
                                  },
                                ),
                                if (commissionEnabled) ...[
                                  const SizedBox(height: 10),
                                  DropdownButtonFormField<String>(
                                    initialValue: commissionMode,
                                    decoration: InputDecoration(
                                      labelText: 'نوع العمولة',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'percent',
                                        child: Text('نسبة من سعر المنتج'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'fixed',
                                        child: Text('مبلغ ثابت لكل قطعة'),
                                      ),
                                    ],
                                    onChanged: (value) {
                                      if (value == null) return;
                                      setDialogState(
                                        () => commissionMode = value,
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    key: const ValueKey(
                                      'admin-product-commission-value',
                                    ),
                                    initialValue: commissionValueText,
                                    textInputAction: TextInputAction.done,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    onFieldSubmitted: (_) =>
                                        FocusScope.of(context).unfocus(),
                                    onChanged: (value) {
                                      setDialogState(() {
                                        commissionValueText = value;
                                        commissionValidationError = '';
                                      });
                                    },
                                    decoration: InputDecoration(
                                      labelText: commissionMode == 'percent'
                                          ? 'نسبة العمولة (%)'
                                          : 'العمولة لكل قطعة (ر.ي)',
                                      errorText:
                                          commissionValidationError.isEmpty
                                              ? null
                                              : commissionValidationError,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                                  Builder(
                                    builder: (context) {
                                      final basePrice = double.tryParse(
                                            product['price']?.toString() ?? '',
                                          ) ??
                                          0;
                                      final commissionValue = double.tryParse(
                                        commissionValueText.trim(),
                                      );
                                      final commissionAmount =
                                          commissionValue == null
                                              ? 0.0
                                              : ProductModel
                                                  .commissionAmountForPrice(
                                                  price: basePrice,
                                                  mode: commissionMode,
                                                  value: commissionValue,
                                                );
                                      return Container(
                                        width: double.infinity,
                                        margin: const EdgeInsets.only(top: 14),
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEFF7F1),
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                        child: Text(
                                          'سعر البيع بعد العمولة: '
                                          '${(basePrice + commissionAmount).toStringAsFixed(2)} '
                                          '$currency',
                                          style: const TextStyle(
                                            color: Color(0xFF176B3A),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          sectionTitle(
                            'قرار المراجعة',
                            Icons.rate_review_outlined,
                          ),
                          const Text(
                            'يمكن إضافة ملاحظة اختيارية عند الاعتماد. سيُطلب سبب الرفض في نافذة تأكيد منفصلة.',
                            style: TextStyle(
                              color: Color(0xFF6B7280),
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            key: const ValueKey('admin-product-approval-note'),
                            initialValue: approvalNote,
                            minLines: 3,
                            maxLines: 5,
                            onChanged: (value) {
                              approvalNote = value;
                            },
                            decoration: InputDecoration(
                              labelText:
                                  'ملاحظة للتاجر عند الاعتماد (اختيارية)',
                              alignLabelWithHint: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!keyboardVisible) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('إلغاء'),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              final rejectionReason =
                                  await showRejectionReasonDialog();
                              if (rejectionReason == null ||
                                  !dialogContext.mounted) {
                                return;
                              }
                              final result = buildDecision(
                                'rejected',
                                decisionReason: rejectionReason,
                              );
                              if (result != null) {
                                Navigator.pop(dialogContext, result);
                              }
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFB91C1C),
                            ),
                            icon: const Icon(Icons.block_outlined),
                            label: const Text('رفض مع السبب'),
                          ),
                          FilledButton.icon(
                            onPressed: () {
                              final result = buildDecision('approved');
                              if (result != null) {
                                Navigator.pop(dialogContext, result);
                              }
                            },
                            icon: const Icon(Icons.check_rounded),
                            label: Text(
                              approvalStatus == 'pending'
                                  ? 'اعتماد ونشر'
                                  : 'حفظ المراجعة',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
    if (decision == null) return;

    final id = (product['id'] ?? '').toString();
    if (id.isEmpty) return;
    final isApproved = decision['status'] == 'approved';
    final requestedAvailable = product['requested_available'] == null
        ? product['available'] == true || product['available'] == 'true'
        : product['requested_available'] == true ||
            product['requested_available'] == 'true';
    try {
      final database =
          widget.databaseService ?? FirebaseDatabaseService.instance;
      final reviewedAt = DateTime.now().toIso8601String();
      await database.update('products/$id', {
        'approval_status': decision['status'],
        'review_reason': decision['reason'],
        'reviewed_at': reviewedAt,
        'available': isApproved && requestedAvailable,
        'commission_mode_override': decision['commission_mode_override'],
        'commission_value_override': decision['commission_value_override'],
      });
      var rejectionNotificationSent = true;
      if (!isApproved) {
        rejectionNotificationSent =
            await NotificationService(databaseService: database).notifyProfile(
          profileId: (product['merchant_id'] ?? '').toString(),
          role: 'merchant',
          title: 'تم رفض منتجك',
          body: 'تم رفض المنتج "${product['name'] ?? 'منتج'}". '
              'السبب: ${decision['reason']}',
          type: 'product_rejected',
          productId: id,
          status: 'rejected',
          eventId: 'product-rejected-$id-$reviewedAt',
        );
      }
      if (!mounted) return;
      setState(_refresh);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isApproved
                ? 'تم اعتماد المنتج ونشره'
                : rejectionNotificationSent
                    ? 'تم رفض المنتج وإرسال إشعار للتاجر'
                    : 'تم رفض المنتج، لكن تعذر إرسال إشعار للتاجر',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حفظ قرار مراجعة المنتج')),
      );
    }
  }

  Future<void> _toggleProductArchived(Map<String, dynamic> product) async {
    final id = (product['id'] ?? '').toString();
    if (id.isEmpty) return;
    final archived = product['is_archived'] == true;
    final productName = (product['name'] ?? 'هذا المنتج').toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(archived ? 'استعادة المنتج' : 'أرشفة المنتج'),
        content: Text(
          archived
              ? 'هل تريد إعادة «$productName» إلى قائمة المنتجات؟'
              : 'سيُخفى «$productName» عن العملاء والتاجر مع إبقاء بياناته وطلباته السابقة. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(archived ? 'استعادة' : 'أرشفة'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AdminService().setProductArchivedForAdmin(
        productId: id,
        archived: !archived,
      );
      if (!mounted) return;
      setState(_refresh);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(archived ? 'تمت استعادة المنتج' : 'تمت أرشفة المنتج'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر تحديث المنتج: ${AppErrorMessage.from(error)}'),
        ),
      );
    }
  }

  Future<void> _deleteProductAfterOrderReview(
    Map<String, dynamic> product,
  ) async {
    final productId = (product['id'] ?? '').toString().trim();
    if (productId.isEmpty) return;

    final database = widget.databaseService ?? FirebaseDatabaseService.instance;
    late final List<Map<String, dynamic>> linkedOrders;
    try {
      linkedOrders = await _loadOrdersForProduct(database, productId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تعذر التحقق من طلبات المنتج، لذلك لم يتم حذفه: '
            '${AppErrorMessage.from(error)}',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;

    final activeOrders = linkedOrders.where(_isActiveProductOrder).toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          activeOrders.isNotEmpty
              ? 'لا يمكن حذف المنتج الآن'
              : 'مراجعة حذف المنتج',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('المنتج: ${product['name'] ?? 'منتج'}'),
              Text('التاجر: ${product['merchant_name'] ?? 'غير معروف'}'),
              const SizedBox(height: 12),
              if (linkedOrders.isEmpty)
                const Text('لم يتم العثور على طلبات مرتبطة بهذا المنتج.'),
              if (linkedOrders.isNotEmpty) ...[
                Text('الطلبات المرتبطة: ${linkedOrders.length}'),
                const SizedBox(height: 8),
                for (final order in linkedOrders) ...[
                  _buildProductOrderReview(order, productId),
                  const SizedBox(height: 8),
                ],
              ],
              if (activeOrders.isNotEmpty)
                const Text(
                  'يوجد طلب نشط مرتبط بهذا المنتج. أكمل الطلب أو ألغِه قبل '
                  'حذف المنتج لتجنب التأثير على العميل والتاجر والسائق.',
                  style: TextStyle(
                    color: Color(0xFFB91C1C),
                    fontWeight: FontWeight.w600,
                  ),
                )
              else if (linkedOrders.isNotEmpty)
                const Text(
                  'راجع الطلبات أعلاه. ستبقى بيانات المنتجات داخل الطلبات '
                  'المنتهية، وسيُحذف سجل المنتج من قائمة المنتجات.',
                )
              else
                const Text('سيُحذف سجل المنتج نهائيًا.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(activeOrders.isNotEmpty ? 'إغلاق' : 'إلغاء'),
          ),
          if (activeOrders.isEmpty)
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('تأكيد الحذف'),
            ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    try {
      final latestOrders = await _loadOrdersForProduct(database, productId);
      final latestActiveOrders =
          latestOrders.where(_isActiveProductOrder).toList();
      if (latestActiveOrders.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('توقف حذف المنتج'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ظهر طلب نشط مرتبط بالمنتج أثناء المراجعة. لم يتم الحذف:',
                  ),
                  const SizedBox(height: 8),
                  for (final order in latestActiveOrders) ...[
                    _buildProductOrderReview(order, productId),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('إغلاق'),
              ),
            ],
          ),
        );
        return;
      }
      await database.delete('products/$productId');
      if (!mounted) return;
      setState(_refresh);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف المنتج')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر حذف المنتج: ${AppErrorMessage.from(error)}'),
        ),
      );
    }
  }

  Future<List<Map<String, dynamic>>> _loadOrdersForProduct(
    DatabaseService database,
    String productId,
  ) async {
    final orders = await database.read('orders');
    return orders.entries
        .where((entry) => entry.value is Map)
        .map((entry) {
          final order = Map<String, dynamic>.from(entry.value as Map);
          order.putIfAbsent('id', () => entry.key);
          return order;
        })
        .where((order) => _orderContainsProduct(order, productId))
        .toList();
  }

  bool _orderContainsProduct(Map<String, dynamic> order, String productId) {
    final items = order['items'] ?? order['order_items'];
    if (items is List) {
      return items.whereType<Map>().any((item) =>
          (item['product_id'] ?? item['productId'] ?? '').toString().trim() ==
          productId);
    }
    if (items is Map) {
      return items.entries.any((entry) =>
          entry.key.toString() == productId ||
          (entry.value is Map &&
              ((entry.value as Map)['product_id'] ??
                          (entry.value as Map)['productId'] ??
                          '')
                      .toString()
                      .trim() ==
                  productId));
    }
    return false;
  }

  bool _isActiveProductOrder(Map<String, dynamic> order) {
    final status = (order['status'] ?? '').toString().trim().toLowerCase();
    return !{'delivered', 'cancelled', 'rejected', 'completed'}
        .contains(status);
  }

  Widget _buildProductOrderReview(
    Map<String, dynamic> order,
    String productId,
  ) {
    final items = order['items'] ?? order['order_items'];
    final productItems = items is List
        ? items.whereType<Map>().where((item) =>
            (item['product_id'] ?? item['productId'] ?? '').toString().trim() ==
            productId)
        : const <Map>[];
    final quantity = productItems.fold<int>(
      0,
      (total, item) =>
          total + (int.tryParse(item['quantity']?.toString() ?? '') ?? 0),
    );
    final rawStatus = (order['status'] ?? '').toString();
    final status = switch (rawStatus.trim().toLowerCase()) {
      'new' => 'جديد',
      'pending_payment' => 'بانتظار الدفع',
      'awaiting_confirmation' => 'بانتظار تأكيد الدفع',
      'confirmed' => 'مؤكد',
      'preparing' => 'قيد التجهيز',
      'accepted' => 'مقبول',
      'picked_up' => 'تم الاستلام من المتجر',
      'shipped' => 'قيد التوصيل',
      'delivered' || 'completed' => 'مكتمل',
      'cancelled' => 'ملغي',
      'rejected' => 'مرفوض',
      _ => rawStatus.isEmpty ? 'غير محددة' : rawStatus,
    };
    final customer = (order['customer_name'] ??
            order['customerName'] ??
            order['customer_id'] ??
            order['customerId'] ??
            'غير معروف')
        .toString();
    final driver = (order['driver_name'] ??
            order['driverName'] ??
            order['driver_id'] ??
            order['driverId'] ??
            order['assigned_driver_id'] ??
            order['assignedDriverId'] ??
            'غير معيّن')
        .toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('رقم الطلب: ${OrderNumber.fromOrder(order)}'),
          Text(
              'الحالة: $status${_isActiveProductOrder(order) ? ' • نشط' : ' • منتهٍ'}'),
          Text('العميل: $customer'),
          Text('السائق: $driver'),
          if (quantity > 0) Text('كمية المنتج في الطلب: $quantity'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مراجعة المنتجات'),
          actions: [
            IconButton(
              tooltip: 'إضافة منتج لتاجر',
              onPressed: _addProductForMerchant,
              icon: const Icon(Icons.add_box_outlined),
            ),
            IconButton(
              tooltip: 'تحديث',
              onPressed: () => setState(_refresh),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _productsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'تعذر تحميل المنتجات: '
                  '${AppErrorMessage.from(snapshot.error!)}',
                ),
              );
            }
            final products = snapshot.data ?? const <Map<String, dynamic>>[];
            final categories = products
                .map((product) => (product['category'] ?? '').toString().trim())
                .where((category) => category.isNotEmpty)
                .toSet()
                .toList()
              ..sort();
            final pendingCount = products
                .where(
                  (product) =>
                      product['is_archived'] != true &&
                      (_approvalStatus(product) == 'pending' ||
                          product['price_change_status'] == 'pending'),
                )
                .length;
            final productQuery =
                _productSearchController.text.trim().toLowerCase();
            final merchantQuery =
                _merchantSearchController.text.trim().toLowerCase();
            final filtered = products.where((product) {
              if (_statusFilter == 'archived') {
                if (product['is_archived'] != true) return false;
              } else if (product['is_archived'] == true) {
                return false;
              }
              if (_statusFilter != 'archived' && _statusFilter != 'all') {
                final status = _approvalStatus(product);
                final priceStatus =
                    (product['price_change_status'] ?? '').toString();
                if (_statusFilter == 'pending') {
                  if (status != 'pending' && priceStatus != 'pending') {
                    return false;
                  }
                } else if (_statusFilter == 'rejected') {
                  if (status != 'rejected' && priceStatus != 'rejected') {
                    return false;
                  }
                } else if (status != _statusFilter) {
                  return false;
                }
              }

              final name = (product['name'] ?? '').toString().toLowerCase();
              final productId = (product['id'] ?? '').toString().toLowerCase();
              if (productQuery.isNotEmpty &&
                  !name.contains(productQuery) &&
                  !productId.contains(productQuery)) {
                return false;
              }
              final merchantName =
                  (product['merchant_name'] ?? '').toString().toLowerCase();
              final merchantId =
                  (product['merchant_id'] ?? '').toString().toLowerCase();
              if (merchantQuery.isNotEmpty &&
                  !merchantName.contains(merchantQuery) &&
                  !merchantId.contains(merchantQuery)) {
                return false;
              }
              if (_categoryFilter != 'all' &&
                  (product['category'] ?? '').toString().trim() !=
                      _categoryFilter) {
                return false;
              }
              return true;
            }).toList();
            filtered.sort(_compareProductDates);

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.pending_actions_rounded),
                      const SizedBox(width: 8),
                      Text('طلبات بانتظار المراجعة: $pendingCount'),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Column(
                    children: [
                      TextField(
                        controller: _productSearchController,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'البحث باسم المنتج أو رقمه',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _productSearchController.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'مسح البحث',
                                  onPressed: () {
                                    _productSearchController.clear();
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _merchantSearchController,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'البحث عن تاجر بالاسم أو الرقم',
                          prefixIcon: const Icon(Icons.storefront_rounded),
                          suffixIcon: _merchantSearchController.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'مسح بحث التاجر',
                                  onPressed: () {
                                    _merchantSearchController.clear();
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _categoryFilter,
                              decoration:
                                  const InputDecoration(labelText: 'الفئة'),
                              items: [
                                const DropdownMenuItem(
                                  value: 'all',
                                  child: Text('كل الفئات'),
                                ),
                                if (_categoryFilter != 'all' &&
                                    !categories.contains(_categoryFilter))
                                  DropdownMenuItem(
                                    value: _categoryFilter,
                                    child: Text(_categoryFilter),
                                  ),
                                ...categories.map(
                                  (category) => DropdownMenuItem(
                                    value: category,
                                    child: Text(
                                      category,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _categoryFilter = value);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<bool>(
                              initialValue: _newestFirst,
                              decoration:
                                  const InputDecoration(labelText: 'الترتيب'),
                              items: const [
                                DropdownMenuItem(
                                  value: true,
                                  child: Text('الأحدث أولاً'),
                                ),
                                DropdownMenuItem(
                                  value: false,
                                  child: Text('الأقدم أولاً'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _newestFirst = value);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      _buildFilter('pending', 'قيد المراجعة'),
                      _buildFilter('approved', 'معتمدة'),
                      _buildFilter('rejected', 'مرفوضة'),
                      _buildFilter('all', 'الكل'),
                      _buildFilter('archived', 'مؤرشفة'),
                    ],
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(_statusFilter == 'pending'
                              ? 'لا توجد منتجات بانتظار المراجعة'
                              : 'لا توجد منتجات في هذه القائمة'),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final product = filtered[index];
                            final status = _approvalStatus(product);
                            final productCommission = double.tryParse(
                                  product['commission_value_override']
                                          ?.toString() ??
                                      '',
                                ) ??
                                _pricingConfig.commissionByMerchant[
                                    (product['merchant_id'] ?? '')
                                        .toString()] ??
                                _pricingConfig.commissionByCategory[
                                    (product['category'] ?? '').toString()] ??
                                _pricingConfig.commissionValue;
                            final productCommissionMode =
                                product['commission_mode_override']
                                        ?.toString() ??
                                    _pricingConfig.commissionMode;
                            final productBasePrice = double.tryParse(
                                  product['price']?.toString() ?? '',
                                ) ??
                                0;
                            final productSalePrice = productBasePrice +
                                ProductModel.commissionAmountForPrice(
                                  price: productBasePrice,
                                  mode: productCommissionMode,
                                  value: productCommission,
                                );
                            final image = (product['image_url'] ??
                                    product['imageUrl'] ??
                                    '')
                                .toString();
                            final reason =
                                (product['review_reason'] ?? '').toString();
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: image.trim().isEmpty
                                          ? const SizedBox(
                                              width: 64,
                                              height: 64,
                                              child: Icon(Icons.image_rounded),
                                            )
                                          : Image.network(
                                              image,
                                              width: 64,
                                              height: 64,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  const SizedBox(
                                                width: 64,
                                                height: 64,
                                                child: Icon(
                                                    Icons.broken_image_rounded),
                                              ),
                                            ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            (product['name'] ?? 'منتج')
                                                .toString(),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            'التاجر: ${product['merchant_name'] ?? 'غير معروف'}',
                                          ),
                                          Text(
                                            'الفئة: ${product['category'] ?? 'غير محددة'} • '
                                            'رقم المنتج: ${product['id'] ?? 'غير متوفر'}',
                                          ),
                                          Text(
                                            'سعر البيع: ${productSalePrice.toStringAsFixed(2)} '
                                            '${product['currency_symbol'] ?? 'ر.س'} • '
                                            '${_approvalStatusLabel(status)}',
                                          ),
                                          Text(
                                            'العمولة: ${productCommission.toStringAsFixed(2)}'
                                            '${productCommissionMode == 'fixed' ? ' ر.ي/قطعة' : '%'}',
                                          ),
                                          if (status == 'rejected' &&
                                              reason.trim().isNotEmpty)
                                            Text('سبب الرفض: $reason'),
                                          if (product['price_change_status'] ==
                                              'pending') ...[
                                            Text(
                                              'طلب تعديل السعر: '
                                              '${product['price'] ?? 0} ← '
                                              '${product['requested_price'] ?? 0} '
                                              '${product['currency_symbol'] ?? 'ر.س'}',
                                            ),
                                            Align(
                                              alignment: Alignment.centerRight,
                                              child: TextButton.icon(
                                                onPressed: () =>
                                                    _reviewPriceChange(product),
                                                icon: const Icon(
                                                  Icons.price_change_rounded,
                                                ),
                                                label: const Text(
                                                  'مراجعة طلب السعر',
                                                ),
                                              ),
                                            ),
                                          ],
                                          if (product['price_change_status'] ==
                                              'rejected')
                                            Text(
                                              'سبب رفض السعر: '
                                              '${product['price_change_review_reason'] ?? ''}',
                                            ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (product['is_archived'] != true)
                                          IconButton(
                                            tooltip: status == 'pending'
                                                ? 'معاينة ومراجعة'
                                                : 'مراجعة المنتج',
                                            onPressed: () =>
                                                _reviewProduct(product),
                                            icon: Icon(status == 'pending'
                                                ? Icons.visibility_rounded
                                                : Icons.fact_check_rounded),
                                          ),
                                        IconButton(
                                          tooltip:
                                              product['is_archived'] == true
                                                  ? 'استعادة المنتج'
                                                  : 'أرشفة المنتج',
                                          onPressed: () =>
                                              _toggleProductArchived(product),
                                          icon: Icon(
                                            product['is_archived'] == true
                                                ? Icons.unarchive_outlined
                                                : Icons.archive_outlined,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'حذف المنتج',
                                          onPressed: () =>
                                              _deleteProductAfterOrderReview(
                                            product,
                                          ),
                                          color: const Color(0xFFB91C1C),
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _approvalStatusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'قيد المراجعة';
      case 'rejected':
        return 'مرفوض';
      default:
        return 'معتمد';
    }
  }

  Widget _buildFilter(String value, String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _statusFilter == value,
        onSelected: (_) => setState(() => _statusFilter = value),
      ),
    );
  }
}
