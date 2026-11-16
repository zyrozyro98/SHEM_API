import 'package:flutter/material.dart';
import 'package:she_m_app/data/services/media_upload_service.dart';

class AdminProfileDetailsScreen extends StatelessWidget {
  const AdminProfileDetailsScreen({
    required this.profile,
    super.key,
  });

  final Map<String, dynamic> profile;

  static const _basicFields = [
    'id',
    'role',
    'is_verified',
    'isVerified',
    'is_archived',
    'isArchived',
    'created_at',
    'createdAt',
    'updated_at',
    'updatedAt',
    'phone_verified_by_admin',
    'email_verified',
    'auth_provider',
    'created_by_admin_id',
  ];

  static const _contactFields = [
    'full_name',
    'fullName',
    'phone',
    'email',
    'city',
    'address',
    'current_location',
    'currentLocation',
  ];

  static const _merchantFields = [
    'shop_name',
    'shopName',
    'shop_category',
    'shopCategory',
    'shop_location',
    'shopLocation',
    'shop_region',
    'shopRegion',
    'shop_contact_phones',
    'shopContactPhones',
    'shop_wallets',
    'shopWallets',
    'merchant_display_delivery_fee',
    'merchantDisplayDeliveryFee',
  ];

  static const _driverFields = [
    'vehicle_type',
    'vehicleType',
    'plate_number',
    'plateNumber',
    'region',
    'is_available',
    'isAvailable',
  ];

  static const _imageFields = {
    'profile_image',
    'profileImage',
    'avatar',
    'avatar_url',
    'shop_banner',
    'shopBanner',
    'shop_logo',
    'shopLogo',
    'logo_url',
    'license_photo',
    'licensePhoto',
    'license_photo_path',
  };

  String get _role => (profile['role'] ?? '').toString().toLowerCase();
  bool get _isMerchant => _role == 'merchant';
  bool get _isDriver => _role == 'driver';

  String get _name {
    final value = _isMerchant
        ? profile['shop_name'] ??
            profile['shopName'] ??
            profile['full_name'] ??
            profile['fullName']
        : profile['full_name'] ?? profile['fullName'];
    return (value ?? 'مستخدم').toString();
  }

  String get _title => _isMerchant ? 'تفاصيل المتجر' : 'تفاصيل المستخدم';

  ImageProvider<Object>? _imageFor(Iterable<String> keys) {
    for (final key in keys) {
      final image = MediaUploadService.imageProvider(profile[key]?.toString());
      if (image != null) return image;
    }
    return null;
  }

  bool _isPrivateField(String key) {
    return RegExp(
      r'(password|token|secret|pin|hash|authorization|otp|credential|auth_uid|firebase_uid|session)',
      caseSensitive: false,
    ).hasMatch(key);
  }

  bool _hasValue(Object? value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is Iterable) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }

  String _fieldLabel(String key) {
    const labels = {
      'id': 'معرّف الحساب',
      'role': 'نوع الحساب',
      'full_name': 'الاسم الكامل',
      'fullName': 'الاسم الكامل',
      'phone': 'رقم الهاتف',
      'email': 'البريد الإلكتروني',
      'city': 'المدينة',
      'address': 'العنوان',
      'current_location': 'الموقع الحالي',
      'currentLocation': 'الموقع الحالي',
      'is_verified': 'التوثيق',
      'isVerified': 'التوثيق',
      'is_archived': 'الأرشفة',
      'isArchived': 'الأرشفة',
      'created_at': 'تاريخ إنشاء الحساب',
      'createdAt': 'تاريخ إنشاء الحساب',
      'updated_at': 'آخر تحديث',
      'updatedAt': 'آخر تحديث',
      'phone_verified_by_admin': 'تم توثيق الهاتف بواسطة المدير',
      'email_verified': 'توثيق البريد الإلكتروني',
      'auth_provider': 'طريقة تسجيل الدخول',
      'created_by_admin_id': 'معرّف المدير المنشئ',
      'shop_name': 'اسم المتجر',
      'shopName': 'اسم المتجر',
      'shop_category': 'فئة المتجر',
      'shopCategory': 'فئة المتجر',
      'shop_location': 'عنوان المتجر',
      'shopLocation': 'عنوان المتجر',
      'shop_region': 'منطقة المتجر',
      'shopRegion': 'منطقة المتجر',
      'shop_contact_phones': 'أرقام التواصل',
      'shopContactPhones': 'أرقام التواصل',
      'shop_wallets': 'محافظ استلام المستحقات',
      'shopWallets': 'محافظ استلام المستحقات',
      'merchant_display_delivery_fee': 'أجرة التوصيل الظاهرة',
      'merchantDisplayDeliveryFee': 'أجرة التوصيل الظاهرة',
      'vehicle_type': 'نوع المركبة',
      'vehicleType': 'نوع المركبة',
      'plate_number': 'رقم اللوحة',
      'plateNumber': 'رقم اللوحة',
      'region': 'المنطقة',
      'is_available': 'متاح لاستلام الطلبات',
      'isAvailable': 'متاح لاستلام الطلبات',
      'license_photo': 'صورة رخصة السائق',
      'licensePhoto': 'صورة رخصة السائق',
      'license_photo_path': 'مسار صورة الرخصة',
      'name': 'الاسم',
      'status': 'الحالة',
      'wallet_name': 'اسم المحفظة',
      'wallet_type': 'نوع المحفظة',
      'account_number': 'رقم الحساب',
      'account_name': 'اسم صاحب الحساب',
      'provider': 'المزوّد',
    };
    return labels[key] ??
        key.replaceAll('_', ' ').replaceAllMapped(
              RegExp(r'([a-z])([A-Z])'),
              (match) => '${match.group(1)} ${match.group(2)}',
            );
  }

  String _formatValue(Object? value, {required String field}) {
    if (value == null) return 'غير محدد';
    if (value is bool) {
      if (field == 'is_verified' || field == 'isVerified') {
        return value ? 'موثق' : 'غير موثق';
      }
      if (field == 'is_archived' || field == 'isArchived') {
        return value ? 'مؤرشف' : 'نشط';
      }
      return value ? 'نعم' : 'لا';
    }
    if (value is DateTime) return _formatDate(value);
    if (value is Map) {
      return value.entries
          .where((entry) => !_isPrivateField(entry.key.toString()))
          .map(
            (entry) => '${_fieldLabel(entry.key.toString())}: '
                '${_formatValue(entry.value, field: entry.key.toString())}',
          )
          .join('\n');
    }
    if (value is Iterable) {
      return value
          .map((item) => _formatValue(item, field: field))
          .where((item) => item.trim().isNotEmpty)
          .join('\n');
    }
    final text = value.toString().trim();
    if (field.toLowerCase().contains('at')) {
      final date = DateTime.tryParse(text);
      if (date != null) return _formatDate(date);
    }
    if (field == 'role') {
      return switch (text.toLowerCase()) {
        'admin' => 'مدير',
        'merchant' => 'تاجر',
        'customer' => 'عميل',
        'driver' => 'سائق',
        _ => text,
      };
    }
    return text;
  }

  String _formatDate(DateTime value) =>
      value.toLocal().toString().split('.').first;

  List<MapEntry<String, Object?>> _entriesFor(List<String> keys) {
    final entries = <MapEntry<String, Object?>>[];
    final labels = <String>{};
    for (final key in keys) {
      final value = profile[key];
      final label = _fieldLabel(key);
      if (!profile.containsKey(key) ||
          !_hasValue(value) ||
          _isPrivateField(key) ||
          !labels.add(label)) {
        continue;
      }
      entries.add(MapEntry(key, value));
    }
    return entries;
  }

  List<MapEntry<String, Object?>> _additionalEntries() {
    final knownFields = {
      ..._basicFields,
      ..._contactFields,
      ..._imageFields,
      if (_isMerchant) ..._merchantFields,
      if (_isDriver) ..._driverFields,
    };
    return profile.entries
        .where(
          (entry) =>
              !knownFields.contains(entry.key) &&
              !_imageFields.contains(entry.key) &&
              !_isPrivateField(entry.key) &&
              _hasValue(entry.value),
        )
        .map((entry) => MapEntry(entry.key, entry.value))
        .toList()
      ..sort((first, second) =>
          _fieldLabel(first.key).compareTo(_fieldLabel(second.key)));
  }

  Widget _section({
    required String title,
    required IconData icon,
    required List<MapEntry<String, Object?>> entries,
  }) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF475569), size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          ...entries.map(
            (entry) => _AdminProfileDetailRow(
              label: _fieldLabel(entry.key),
              value: _formatValue(entry.value, field: entry.key),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final verified =
        profile['is_verified'] == true || profile['isVerified'] == true;
    final profileImage = _imageFor([
      'profile_image',
      'profileImage',
      'avatar',
      'avatar_url',
      'shop_logo',
      'shopLogo',
      'logo_url',
    ]);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isMerchant
              ? const [Color(0xFF713F2B), Color(0xFF9A5A3D)]
              : const [Color(0xFF1D4ED8), Color(0xFF4F46E5)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          ClipOval(
            child: Container(
              width: 68,
              height: 68,
              color: Colors.white.withValues(alpha: 0.18),
              alignment: Alignment.center,
              child: profileImage == null
                  ? Icon(
                      _isMerchant
                          ? Icons.storefront_rounded
                          : Icons.person_rounded,
                      color: Colors.white,
                      size: 34,
                    )
                  : Image(
                      image: profileImage,
                      width: 68,
                      height: 68,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        _isMerchant
                            ? Icons.storefront_rounded
                            : Icons.person_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                if ((profile['phone'] ?? '').toString().trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    profile['phone'].toString(),
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(color: Color(0xFFE2E8F0)),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  children: [
                    _headerBadge(
                      _isMerchant
                          ? 'تاجر'
                          : _formatValue(profile['role'], field: 'role'),
                    ),
                    _headerBadge(verified ? 'موثق' : 'غير موثق'),
                    if (profile['is_archived'] == true) _headerBadge('مؤرشف'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _shopBanner() {
    final banner = _imageFor(['shop_banner', 'shopBanner']);
    if (!_isMerchant || banner == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: 150,
          width: double.infinity,
          child: Image(
            image: banner,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  Widget _licensePhoto() {
    if (!_isDriver) return const SizedBox.shrink();
    final image = _imageFor(
      const ['license_photo', 'licensePhoto', 'license_photo_path'],
    );
    final hasAttachment = [
      'license_photo',
      'licensePhoto',
      'license_photo_path',
    ].any((key) => _hasValue(profile[key]));
    if (!hasAttachment) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'صورة رخصة السائق',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          if (image == null)
            const Text('مرفق رخصة السائق متوفر')
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image(
                image: image,
                height: 180,
                width: double.infinity,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox(
                  height: 100,
                  child: Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleColor =
        _isMerchant ? const Color(0xFF713F2B) : const Color(0xFF1D4ED8);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text(_title),
          backgroundColor: const Color(0xFFF8FAFC),
          foregroundColor: titleColor,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _shopBanner(),
            _header(context),
            const SizedBox(height: 14),
            _section(
              title: 'بيانات الحساب',
              icon: Icons.badge_outlined,
              entries: _entriesFor(_basicFields),
            ),
            _section(
              title: 'معلومات التواصل والموقع',
              icon: Icons.contact_page_outlined,
              entries: _entriesFor(_contactFields),
            ),
            if (_isMerchant)
              _section(
                title: 'بيانات المتجر والمحافظ',
                icon: Icons.storefront_outlined,
                entries: _entriesFor(_merchantFields),
              ),
            if (_isDriver)
              _section(
                title: 'بيانات السائق',
                icon: Icons.delivery_dining_outlined,
                entries: _entriesFor(_driverFields),
              ),
            _licensePhoto(),
            _section(
              title: 'معلومات إضافية',
              icon: Icons.info_outline_rounded,
              entries: _additionalEntries(),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminProfileDetailRow extends StatelessWidget {
  const _AdminProfileDetailRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: const TextStyle(
              color: Color(0xFF1E293B),
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Divider(height: 14),
        ],
      ),
    );
  }
}
