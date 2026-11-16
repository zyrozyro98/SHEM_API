import 'package:flutter/material.dart';
import 'package:she_m_app/core/errors/app_error.dart';
import 'package:geolocator/geolocator.dart';
import 'package:she_m_app/core/animations/route_transitions.dart';
import 'package:she_m_app/presentation/common/custom_appbar.dart';
import 'package:she_m_app/data/models/order_model.dart';
import 'package:she_m_app/data/models/order_number.dart';
import 'package:she_m_app/data/models/user_model.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/data/services/cart_service.dart';
import 'package:she_m_app/data/services/currency_service.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/data/services/order_service.dart';
import 'package:she_m_app/data/services/pricing_service.dart';
import 'package:she_m_app/presentation/auth/phone_login_screen.dart';
import 'package:she_m_app/presentation/checkout/order_confirmation_copy.dart';
import 'package:she_m_app/presentation/orders/customer_order_detail_screen.dart';
import 'package:she_m_app/presentation/payment/wallet_payment_screen.dart';
import 'package:she_m_app/presentation/common/delivery_address_book.dart';

String resolveMerchantRegion(Map<String, dynamic> profile) {
  for (final key in ['shop_region', 'shopRegion', 'region', 'city']) {
    final region = profile[key]?.toString().trim() ?? '';
    if (region.isNotEmpty) return region;
  }
  return '';
}

String deliveryAddressWithoutDescription(String? address) {
  final value = address?.trim() ?? '';
  final markerIndex = value.indexOf('الوصف:');
  if (markerIndex < 0) return value;
  return value
      .substring(0, markerIndex)
      .replaceFirst(RegExp(r'\s*-\s*$'), '')
      .trim();
}

String deliveryLocationDescription(String? address) {
  final value = address?.trim() ?? '';
  final markerIndex = value.indexOf('الوصف:');
  if (markerIndex < 0) return '';

  return value
      .substring(markerIndex + 'الوصف:'.length)
      .split(RegExp(r'\s*-\s*الوصف:\s*'))
      .map((description) => description.trim())
      .where(
        (description) =>
            description.isNotEmpty && description != 'الموقع الحالي للجهاز',
      )
      .toSet()
      .join(' - ');
}

String? deliveryAddressCoordinates(String? address) {
  final value = deliveryAddressWithoutDescription(address);
  return _coordinateText(value);
}

String? _coordinateText(Object? value) {
  final normalized = value?.toString().trim() ?? '';
  return RegExp(r'^-?\d+(?:\.\d+)?\s*,\s*-?\d+(?:\.\d+)?$').hasMatch(normalized)
      ? normalized
      : null;
}

String formatDeliveryAddress(String? address, String? description) {
  final cleanAddress = deliveryAddressWithoutDescription(address);
  final cleanDescription = description?.trim() ?? '';
  return [
    if (cleanAddress.isNotEmpty) cleanAddress,
    if (cleanDescription.isNotEmpty) 'الوصف: $cleanDescription',
  ].join(' - ');
}

class DeliveryAddressScreen extends StatefulWidget {
  const DeliveryAddressScreen({
    super.key,
    this.selectedProductIds,
  });

  final Set<String>? selectedProductIds;

  static String? resolveCustomerId(UserModel? profile) {
    if (profile == null) {
      return null;
    }

    final id = profile.id.trim();
    if (id.isNotEmpty) {
      return id;
    }

    final phone = profile.phone.trim();
    return phone.isNotEmpty ? phone : null;
  }

  @override
  State<DeliveryAddressScreen> createState() => _DeliveryAddressScreenState();
}

class _DeliveryAddressScreenState extends State<DeliveryAddressScreen> {
  UserModel? _profile;
  List<DeliveryAddress> _deliveryAddresses = [];
  String? _selectedDeliveryAddressId;
  String? _editingAddressId;
  PricingConfig _pricingConfig = const PricingConfig();
  String _currencySymbol = CurrencyService.yerCurrency.symbol;
  Map<String, CurrencyOption> _currenciesByCode = const {};
  double? _distanceKm;
  final Map<String, String> _merchantRegions = {};
  bool _pricingLoaded = false;
  bool _currenciesLoaded = false;
  bool _merchantRegionsLoaded = false;
  bool _distanceLoaded = false;
  bool _isSubmitting = false;
  bool _isLocatingCurrentLocation = false;
  Future<Position>? _freshPositionRequest;
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _locationCoordinatesController =
      TextEditingController();
  final TextEditingController _locationDescriptionController =
      TextEditingController();
  final TextEditingController _addressLabelController =
      TextEditingController(text: 'عنوان التوصيل');

  List<CartEntry> get _checkoutItems {
    final items = CartService.instance.items;
    final selectedIds = widget.selectedProductIds;
    if (selectedIds == null) return items;
    return items
        .where((item) => selectedIds.contains(item.product.id))
        .toList();
  }

  @override
  void dispose() {
    _cityController.dispose();
    _addressController.dispose();
    _locationCoordinatesController.dispose();
    _locationDescriptionController.dispose();
    _addressLabelController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadPricing();
    _loadCurrency();
    _loadDistance();
    _loadMerchantRegions();
  }

  Future<void> _loadMerchantRegions() async {
    final merchantIds = _checkoutItems
        .map((entry) => entry.product.merchantId.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final ids = merchantIds.toList();
    try {
      final profiles = await Future.wait(
        ids.map(
          (id) => FirebaseDatabaseService.instance.read('profiles/$id'),
        ),
      );
      if (!mounted) return;
      for (var index = 0; index < profiles.length; index++) {
        final region = resolveMerchantRegion(profiles[index]);
        if (region.isNotEmpty) {
          _merchantRegions[ids[index]] = region;
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تعذر تحميل مناطق التجار: ${AppErrorMessage.from(error)}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _merchantRegionsLoaded = true);
      }
    }
  }

  Future<void> _loadCurrency() async {
    final currencies = await CurrencyService().getCurrencies();
    if (!mounted) return;
    setState(() {
      _currenciesByCode = {
        for (final currency in currencies)
          currency.code.toUpperCase(): currency,
      };
      _currenciesLoaded = true;
    });
  }

  double? _rateToYER(String currencyCode) {
    if (currencyCode.toUpperCase() == CurrencyService.yerCode) return 1;
    return _currenciesByCode[currencyCode.toUpperCase()]?.rateToYER;
  }

  Future<void> _loadDistance() async {
    try {
      final profile = await AuthService().loadSession();
      if (profile == null) return;
      final checkoutItems = _checkoutItems;
      final merchantId =
          checkoutItems.isEmpty ? '' : checkoutItems.first.product.merchantId;
      if (merchantId.isEmpty) return;

      final merchant =
          await FirebaseDatabaseService.instance.read('profiles/$merchantId');
      final merchantPoint = _parseCoordinates(
        merchant['shop_location'] ?? merchant['shopLocation'],
      );
      if (merchantPoint == null) return;

      var customerPoint = _parseCoordinates(
        profile.selectedDeliveryAddress?.locationCoordinates ??
            profile.currentLocation ??
            profile.address,
      );
      if (customerPoint == null) {
        Position? current;
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse) {
          try {
            current = await _getFreshPosition();
          } catch (_) {
            current = null;
          }
        }
        if (current != null) {
          customerPoint = (current.latitude, current.longitude);
        }
      }
      if (customerPoint == null || !mounted) return;
      final resolvedCustomerPoint = customerPoint;
      setState(() {
        _distanceKm = PricingService.distanceBetweenKm(
          merchantPoint.$1,
          merchantPoint.$2,
          resolvedCustomerPoint.$1,
          resolvedCustomerPoint.$2,
        );
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تعذر تحديد مسافة التوصيل: ${AppErrorMessage.from(error)}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _distanceLoaded = true);
      }
    }
  }

  (double, double)? _parseCoordinates(Object? value) {
    final match = RegExp(
      r'(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)',
    ).firstMatch(value?.toString() ?? '');
    if (match == null) return null;
    return (
      double.parse(match.group(1)!),
      double.parse(match.group(2)!),
    );
  }

  Future<void> _loadPricing() async {
    final config = await PricingService().load();
    CartService.instance.updateVatRates(config);
    if (mounted) {
      setState(() {
        _pricingConfig = config;
        _pricingLoaded = true;
      });
    }
  }

  Future<void> _fillCurrentLocation() async {
    if (_isLocatingCurrentLocation) return;

    setState(() => _isLocatingCurrentLocation = true);
    try {
      final position = await _getFreshPosition();
      if (!mounted) return;
      _setLocationFields(position);

      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تعبئة الموقع الحالي تلقائيًا')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppErrorMessage.from(error),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLocatingCurrentLocation = false);
    }
  }

  Future<Position> _getFreshPosition() async {
    final activeRequest = _freshPositionRequest;
    if (activeRequest != null) return activeRequest;

    final request = () async {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('يرجى تفعيل خدمة الموقع في الجهاز');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('يرجى السماح للتطبيق بالوصول إلى موقعك');
      }

      return Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 8),
        ),
      );
    }();

    _freshPositionRequest = request;
    try {
      return await request;
    } finally {
      if (identical(_freshPositionRequest, request)) {
        _freshPositionRequest = null;
      }
    }
  }

  void _setLocationFields(Position position) {
    _locationCoordinatesController.text =
        '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
  }

  Future<void> _saveAddress() async {
    final authService = AuthService();
    final profile = _profile ??
        await authService.loadSession() ??
        await authService.getCurrentProfile();
    if (profile == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لم يتم العثور على حساب مستخدم')),
      );
      return;
    }

    final city = _cityController.text.trim();
    final address = _addressController.text.trim();
    final description = _locationDescriptionController.text.trim();
    final finalAddress = formatDeliveryAddress(address, description);
    final label = _addressLabelController.text.trim();

    if (label.isEmpty || city.isEmpty || finalAddress.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('أدخل اسم العنوان والمدينة والعنوان التفصيلي'),
        ),
      );
      return;
    }

    final item = DeliveryAddress(
      id: _editingAddressId ?? DateTime.now().microsecondsSinceEpoch.toString(),
      label: label,
      city: city,
      address: finalAddress,
      locationCoordinates: _locationCoordinatesController.text.trim().isEmpty
          ? null
          : _locationCoordinatesController.text.trim(),
    );
    final addresses = [
      for (final saved in _deliveryAddresses)
        if (saved.id != item.id) saved,
      item,
    ];
    final updated = await authService.updateDeliveryAddresses(
      profile: profile,
      addresses: addresses,
      selectedAddressId: item.id,
    );
    if (!mounted) return;
    if (updated == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authService.lastError ?? 'تعذر حفظ عنوان التوصيل'),
        ),
      );
      return;
    }
    setState(() {
      _profile = updated;
      _deliveryAddresses = addresses;
      _selectedDeliveryAddressId = item.id;
      _editingAddressId = null;
      _addressLabelController.text = 'عنوان التوصيل';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تمت إضافة عنوان التوصيل')),
    );
  }

  Future<void> _loadProfile() async {
    final authService = AuthService();
    final profile = await authService.loadSession() ??
        await authService.getCurrentProfile();
    if (!mounted) return;
    if (profile == null) {
      setState(() => _profile = null);
      return;
    }

    _deliveryAddresses = profile.savedDeliveryAddresses;
    _selectedDeliveryAddressId = profile.selectedDeliveryAddress?.id;
    _cityController.text = profile.city ?? '';
    final selectedAddress = profile.selectedDeliveryAddress;
    final savedAddress = selectedAddress?.address ?? profile.address;
    final legacyCoordinates = deliveryAddressCoordinates(savedAddress);
    _locationCoordinatesController.text =
        selectedAddress?.locationCoordinates ??
            _coordinateText(profile.currentLocation) ??
            legacyCoordinates ??
            '';
    _addressController.text = legacyCoordinates == null
        ? deliveryAddressWithoutDescription(savedAddress)
        : '';
    _locationDescriptionController.text =
        deliveryLocationDescription(savedAddress);

    setState(() => _profile = profile);
  }

  @override
  Widget build(BuildContext context) {
    final checkoutItems = _checkoutItems;
    final hasExchangeRates = checkoutItems.every(
      (item) => _rateToYER(item.product.currencyCode) != null,
    );
    final subtotal = checkoutItems.fold<double>(0, (sum, item) {
      final rate = _rateToYER(item.product.currencyCode);
      return sum + (rate == null ? 0 : item.lineTotal * rate);
    });
    final quantities =
        checkoutItems.map((item) => item.quantity).toList(growable: false);
    final products = checkoutItems.map((item) {
      final rate = _rateToYER(item.product.currencyCode) ?? 0;
      final effectiveCommissionValue = item.product.effectiveCommissionValue;
      return item.product.copyWith(
        price: item.product.price * rate,
        effectiveCommissionValue: effectiveCommissionValue == null
            ? null
            : effectiveCommissionValue *
                (item.product.effectiveCommissionMode == 'fixed' ? rate : 1),
      );
    }).toList(growable: false);
    final commission = PricingService.commissionForProducts(
      products,
      quantities,
      _pricingConfig,
    );
    final includedCommission =
        PricingService.commissionIncludedInProductPrices(products, quantities);
    final deliveryFee = PricingService.deliveryFee(
      subtotal: subtotal,
      distanceKm: _distanceKm ?? _pricingConfig.fallbackDistanceKm,
      config: _pricingConfig,
      customerRegion: _cityController.text.trim().isNotEmpty
          ? _cityController.text.trim()
          : (_profile?.city ?? ''),
      merchantRegions: checkoutItems
          .map((item) => _merchantRegions[item.product.merchantId] ?? '')
          .where((region) => region.isNotEmpty),
      productIds: checkoutItems.map((item) => item.product.id),
      merchantIds: checkoutItems.map((item) => item.product.merchantId),
      commission: commission,
    );
    final total = subtotal + deliveryFee;
    final checkoutPricingReady = _pricingLoaded &&
        _merchantRegionsLoaded &&
        _distanceLoaded &&
        _currenciesLoaded &&
        hasExchangeRates;
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'عنوان التوصيل',
        icon: Icons.location_on_rounded,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
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
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'تأكيد الطلب',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'اختر عنوان التسليم المناسب لك',
                            style: TextStyle(color: Color(0xFF6B7280)),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4AF37).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.location_on_rounded,
                        color: Color(0xFFD4AF37),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const _StepRow(),
              const SizedBox(height: 18),
              DeliveryAddressBook(
                addresses: _deliveryAddresses,
                selectedId: _selectedDeliveryAddressId,
                onSelect: (id) {
                  final selected = _deliveryAddresses
                      .where((item) => item.id == id)
                      .firstOrNull;
                  if (selected == null) return;
                  setState(() {
                    _selectedDeliveryAddressId = id;
                    _cityController.text = selected.city;
                    final legacyCoordinates =
                        deliveryAddressCoordinates(selected.address);
                    _locationCoordinatesController.text =
                        selected.locationCoordinates ?? legacyCoordinates ?? '';
                    _addressController.text = legacyCoordinates == null
                        ? deliveryAddressWithoutDescription(selected.address)
                        : '';
                    _locationDescriptionController.text =
                        deliveryLocationDescription(selected.address);
                  });
                },
                onAdd: () {
                  setState(() {
                    _addressLabelController.text = 'عنوان التوصيل';
                    _cityController.clear();
                    _addressController.clear();
                    _locationCoordinatesController.clear();
                    _locationDescriptionController.clear();
                    _editingAddressId = null;
                    _selectedDeliveryAddressId = null;
                  });
                },
                onEdit: (address) {
                  setState(() {
                    _selectedDeliveryAddressId = address.id;
                    _editingAddressId = address.id;
                    _addressLabelController.text = address.label;
                    _cityController.text = address.city;
                    final legacyCoordinates =
                        deliveryAddressCoordinates(address.address);
                    _locationCoordinatesController.text =
                        address.locationCoordinates ?? legacyCoordinates ?? '';
                    _addressController.text = legacyCoordinates == null
                        ? deliveryAddressWithoutDescription(address.address)
                        : '';
                    _locationDescriptionController.text =
                        deliveryLocationDescription(address.address);
                  });
                },
                onDelete: (address) async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('حذف عنوان التوصيل'),
                      content: Text('هل تريد حذف «${address.label}»؟'),
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
                  if (confirmed != true ||
                      !context.mounted ||
                      _profile == null) {
                    return;
                  }
                  final addresses = _deliveryAddresses
                      .where((item) => item.id != address.id)
                      .toList();
                  final selectedId = _selectedDeliveryAddressId == address.id
                      ? addresses.firstOrNull?.id
                      : _selectedDeliveryAddressId;
                  if (selectedId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('أضف عنوانًا قبل حذف العنوان الحالي'),
                      ),
                    );
                    return;
                  }
                  final authService = AuthService();
                  final updated = await authService.updateDeliveryAddresses(
                    profile: _profile!,
                    addresses: addresses,
                    selectedAddressId: selectedId,
                  );
                  if (!context.mounted) return;
                  if (updated == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          authService.lastError ?? 'تعذر حذف العنوان',
                        ),
                      ),
                    );
                    return;
                  }
                  setState(() {
                    _deliveryAddresses = addresses;
                    _selectedDeliveryAddressId = selectedId;
                    _profile = updated;
                  });
                },
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'إضافة عنوان توصيل جديد',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _addressLabelController,
                      decoration: const InputDecoration(
                        labelText: 'اسم العنوان (المنزل، العمل...)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _cityController,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'المدينة',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.location_city_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _locationCoordinatesController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'إحداثيات الموقع',
                        hintText: 'حدد موقعك الحالي لإضافتها',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.my_location_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _addressController,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'العنوان التفصيلي',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.home_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _locationDescriptionController,
                      decoration: const InputDecoration(
                        labelText: 'وصف الموقع (اختياري)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.pin_drop_rounded),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isLocatingCurrentLocation
                            ? null
                            : _fillCurrentLocation,
                        icon: _isLocatingCurrentLocation
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.my_location_rounded),
                        label: Text(_isLocatingCurrentLocation
                            ? 'جارٍ تحديد الموقع...'
                            : 'تحديد الموقع الحالي'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _saveAddress,
                        icon: const Icon(Icons.save_rounded),
                        label: Text(
                          _editingAddressId == null
                              ? 'حفظ العنوان الجديد'
                              : 'تحديث العنوان',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ملخص الطلب',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_currenciesLoaded && !hasExchangeRates) ...[
                      const Text(
                        'لا يمكن إكمال الطلب قبل أن يحدد المدير سعر صرف '
                        'العملة المستخدمة للمنتج بالريال اليمني.',
                        style: TextStyle(
                          color: Color(0xFFFCA5A5),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'المجموع الفرعي',
                          style: TextStyle(color: Colors.white70),
                        ),
                        Text(
                          '${subtotal.toStringAsFixed(0)} $_currencySymbol',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'أجرة التوصيل',
                          style: TextStyle(color: Colors.white70),
                        ),
                        Text(
                          '${deliveryFee.toStringAsFixed(0)} $_currencySymbol',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Divider(color: Colors.white24, height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'الإجمالي',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${total.toStringAsFixed(0)} $_currencySymbol',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: ElevatedButton(
            onPressed: _isSubmitting || !checkoutPricingReady
                ? null
                : () async {
                    if (_isSubmitting) return;
                    setState(() => _isSubmitting = true);
                    final scaffoldMessenger =
                        ScaffoldMessenger.maybeOf(context);
                    final navigator = Navigator.of(context);
                    final authService = AuthService();
                    final profile = await authService.loadSession() ??
                        await authService.getCurrentProfile();
                    final customerId =
                        DeliveryAddressScreen.resolveCustomerId(profile);
                    if (customerId == null) {
                      if (mounted) {
                        setState(() => _isSubmitting = false);
                        navigator.pushReplacement(
                          slideFadeRoute(
                            page: PhoneLoginScreen(
                              returnToCheckout: true,
                              checkoutProductIds: widget.selectedProductIds ??
                                  checkoutItems
                                      .map((item) => item.product.id)
                                      .toSet(),
                            ),
                          ),
                        );
                      }
                      return;
                    }

                    final selectedAddress = _deliveryAddresses
                        .where(
                          (item) => item.id == _selectedDeliveryAddressId,
                        )
                        .firstOrNull;
                    if (selectedAddress == null) {
                      scaffoldMessenger?.showSnackBar(
                        const SnackBar(
                          content: Text('اختر عنوانًا أو أضف عنوانًا جديدًا'),
                        ),
                      );
                      if (mounted) setState(() => _isSubmitting = false);
                      return;
                    }
                    final savedProfile =
                        await authService.updateDeliveryAddresses(
                      profile: profile!,
                      addresses: _deliveryAddresses,
                      selectedAddressId: selectedAddress.id,
                    );
                    if (savedProfile == null) {
                      scaffoldMessenger?.showSnackBar(
                        SnackBar(
                          content: Text(
                            authService.lastError ?? 'تعذر حفظ عنوان التوصيل',
                          ),
                        ),
                      );
                      if (mounted) setState(() => _isSubmitting = false);
                      return;
                    }
                    if (mounted) setState(() => _profile = savedProfile);

                    if (checkoutItems.isEmpty) {
                      scaffoldMessenger?.showSnackBar(
                        const SnackBar(
                          content: Text('يرجى إضافة منتجات قبل تأكيد الطلب'),
                        ),
                      );
                      if (mounted) setState(() => _isSubmitting = false);
                      return;
                    }

                    final orderItems = checkoutItems.map((entry) {
                      final rate = _rateToYER(entry.product.currencyCode)!;
                      return OrderItem(
                        productId: entry.product.id,
                        productName: entry.product.name,
                        productCategory: entry.product.category,
                        productDescription: entry.product.description,
                        quantity: entry.quantity,
                        unitPrice: entry.product.priceIncludingVat,
                        total: entry.lineTotal,
                        baseUnitPrice: entry.product.price,
                        vatAmount: entry.vatTotal,
                        baseUnitPriceYER: entry.product.price * rate,
                        vatAmountYER: entry.vatTotal * rate,
                        totalYER: entry.lineTotal * rate,
                        rateToYER: rate,
                        merchantClaimedOriginalPrice:
                            entry.product.merchantClaimedOriginalPrice,
                        selectedColor: entry.selectedColor,
                        selectedSize: entry.selectedSize,
                        imageUrl: entry.product.imageUrl,
                        currencyCode: entry.product.currencyCode,
                        currencySymbol: entry.product.currencySymbol,
                        merchantId: entry.product.merchantId,
                        merchantName: entry.product.merchantName,
                      );
                    }).toList();

                    navigator.pushReplacement(
                      slideFadeRoute(
                        page: WalletPaymentScreen(
                          customerId: customerId,
                          items: orderItems,
                          productIds: checkoutItems
                              .map((item) => item.product.id)
                              .toList(),
                          subtotal: subtotal,
                          shippingFee: deliveryFee,
                          commission: includedCommission,
                        ),
                      ),
                    );
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : Text(
                      checkoutPricingReady
                          ? 'تأكيد الطلب'
                          : 'جارٍ تحميل أسعار التوصيل...',
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow();

  @override
  Widget build(BuildContext context) {
    final steps = ['العنوان', 'الدفع', 'التأكيد'];

    return Row(
      children: List.generate(steps.length, (index) {
        final isActive = index == 0;
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isActive
                        ? Theme.of(context).colorScheme.primary
                        : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}. ${steps[index]}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color:
                            isActive ? Colors.black : const Color(0xFF374151),
                      ),
                    ),
                  ),
                ),
              ),
              if (index < steps.length - 1) const SizedBox(width: 8),
            ],
          ),
        );
      }),
    );
  }
}

class OrderConfirmationScreen extends StatefulWidget {
  final String orderId;

  const OrderConfirmationScreen({super.key, required this.orderId});

  @override
  State<OrderConfirmationScreen> createState() =>
      _OrderConfirmationScreenState();
}

class _OrderConfirmationScreenState extends State<OrderConfirmationScreen> {
  late final Future<OrderModel?> _orderFuture;

  @override
  void initState() {
    super.initState();
    _orderFuture = OrderService().getOrderById(widget.orderId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'حالة الطلب',
        icon: Icons.local_shipping_rounded,
      ),
      body: FutureBuilder<OrderModel?>(
        future: _orderFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final order = snapshot.data;
          if (order == null) {
            return const Center(child: Text('تعذر تحميل حالة الطلب'));
          }

          final status = order.status;
          final pendingReview = status == 'awaiting_confirmation';
          final statusColor =
              pendingReview ? const Color(0xFFF59E0B) : const Color(0xFF10B981);

          return Directionality(
            textDirection: TextDirection.rtl,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: pendingReview
                            ? const [Color(0xFFFFFBEB), Color(0xFFFFFFFF)]
                            : const [Color(0xFFE9F7EE), Color(0xFFFFFFFF)],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: pendingReview
                            ? const Color(0xFFFDE68A)
                            : const Color(0xFFDCFCE7),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          pendingReview
                              ? Icons.hourglass_top_rounded
                              : Icons.check_circle_rounded,
                          size: 48,
                          color: statusColor,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          orderConfirmationTitleForStatus(status),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'رقم الطلب: #${OrderNumber.fromId(widget.orderId)}',
                          style: const TextStyle(
                            color: Color(0xFF4B5563),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'حالة الطلب: ${orderConfirmationStatusLabel(status)}',
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          orderConfirmationMessageForStatus(status),
                          style: const TextStyle(
                            color: Color(0xFF4B5563),
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'ماذا تريد الآن؟',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pushReplacement(
                          slideFadeRoute(
                            page: CustomerOrderDetailScreen(
                              orderId: widget.orderId,
                              orderService: OrderService(),
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.receipt_long_rounded),
                      label: const Text('عرض تفاصيل الطلب'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: const Color(0xFFD4AF37),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context)
                            .popUntil((route) => route.isFirst);
                      },
                      icon: const Icon(Icons.home_rounded),
                      label: const Text('العودة للرئيسية'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        foregroundColor: const Color(0xFF111827),
                        side: const BorderSide(color: Color(0xFF111827)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
