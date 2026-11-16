class UserModel {
  static const Object _sentinel = Object();

  final String id;
  final String fullName;
  final String phone;
  final String? email;
  final String role;
  final bool isVerified;
  final String? city;
  final String? address;
  final List<DeliveryAddress> deliveryAddresses;
  final String? selectedDeliveryAddressId;
  final String? currentLocation;
  final String? passwordHash;
  final String? profileImageData;
  final String? shopCategory;
  final String? shopName;
  final String? shopRegion;
  final double? merchantDisplayDeliveryFee;
  final String? shopLocation;
  final List<String> shopContactPhones;
  final List<Map<String, String>> shopWallets;
  final String? shopBannerUrl;
  final String? vehicleType;
  final String? plateNumber;
  final String? licensePhotoPath;
  final DateTime createdAt;

  const UserModel({
    required this.id,
    required this.fullName,
    required this.phone,
    this.email,
    required this.role,
    required this.isVerified,
    this.city,
    this.address,
    this.deliveryAddresses = const [],
    this.selectedDeliveryAddressId,
    this.currentLocation,
    this.passwordHash,
    this.profileImageData,
    this.shopCategory,
    this.shopName,
    this.shopRegion,
    this.merchantDisplayDeliveryFee,
    this.shopLocation,
    this.shopContactPhones = const [],
    this.shopWallets = const [],
    this.shopBannerUrl,
    this.vehicleType,
    this.plateNumber,
    this.licensePhotoPath,
    required this.createdAt,
  });

  bool get needsCustomerProfileSetup {
    if (role != 'customer') return false;
    return phone.trim().isEmpty ||
        (city?.trim().isEmpty ?? true) ||
        (address?.trim().isEmpty ?? true);
  }

  List<DeliveryAddress> get savedDeliveryAddresses {
    if (deliveryAddresses.isNotEmpty) return deliveryAddresses;
    if ((city?.trim().isNotEmpty ?? false) ||
        (address?.trim().isNotEmpty ?? false)) {
      return [
        DeliveryAddress(
          id: 'legacy',
          label: 'العنوان الحالي',
          city: city ?? '',
          address: address ?? '',
        ),
      ];
    }
    return const [];
  }

  DeliveryAddress? get selectedDeliveryAddress {
    final addresses = savedDeliveryAddresses;
    for (final item in addresses) {
      if (item.id == selectedDeliveryAddressId) return item;
    }
    return addresses.isEmpty ? null : addresses.first;
  }

  static String? normalizeProfileImageValue(Object? value) {
    if (value == null) return null;

    final text = value.toString().trim();
    if (text.isEmpty) return null;
    if (text.startsWith('data:image')) return text;
    if (text.startsWith('http://') || text.startsWith('https://')) {
      return _normalizePublicImageUrl(text);
    }
    return null;
  }

  static String _normalizePublicImageUrl(String value) {
    final match = RegExp(
      r'^https?://github\.com/([^/]+/[^/]+)/blob/([^/]+)/(.*)$',
    ).firstMatch(value);
    if (match == null) return value;

    final repository = match.group(1)!;
    final branch = Uri.encodeComponent(match.group(2)!);
    final path = match.group(3)!.split('/').map(Uri.encodeComponent).join('/');
    return 'https://raw.githubusercontent.com/$repository/$branch/$path';
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id']?.toString() ?? '',
      fullName:
          json['full_name']?.toString() ?? json['fullName']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      email: json['email']?.toString(),
      role: json['role']?.toString() ?? 'customer',
      isVerified: json['is_verified'] == true || json['isVerified'] == true,
      city: json['city']?.toString(),
      address: json['address']?.toString(),
      deliveryAddresses: ((json['delivery_addresses'] ??
                  json['deliveryAddresses']) as List<dynamic>?)
              ?.whereType<Map>()
              .map((value) => DeliveryAddress.fromJson(
                    Map<String, dynamic>.from(value),
                  ))
              .where((value) => value.id.isNotEmpty)
              .toList() ??
          const [],
      selectedDeliveryAddressId: (json['selected_delivery_address_id'] ??
              json['selectedDeliveryAddressId'])
          ?.toString(),
      currentLocation: json['current_location']?.toString(),
      passwordHash: json['password_hash']?.toString(),
      profileImageData: normalizeProfileImageValue(
        json['profile_image'] ??
            json['profileImage'] ??
            json['avatar'] ??
            json['avatar_url'],
      ),
      shopCategory: json['shop_category']?.toString(),
      shopName: json['shop_name']?.toString(),
      shopRegion:
          json['shop_region']?.toString() ?? json['shopRegion']?.toString(),
      merchantDisplayDeliveryFee: _parseOptionalNonNegativeAmount(
        json['merchant_display_delivery_fee'] ??
            json['merchantDisplayDeliveryFee'],
      ),
      shopLocation: json['shop_location']?.toString(),
      shopContactPhones: (json['shop_contact_phones'] as List<dynamic>?)
              ?.map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .toList() ??
          const [],
      shopWallets: (json['shop_wallets'] as List<dynamic>?)
              ?.whereType<Map>()
              .map((value) => Map<String, String>.fromEntries(
                    value.entries
                        .map((entry) => MapEntry(
                              entry.key.toString(),
                              entry.value?.toString().trim() ?? '',
                            ))
                        .where((entry) => entry.value.isNotEmpty),
                  ))
              .where((wallet) =>
                  wallet['provider']?.isNotEmpty == true &&
                  wallet['account_number']?.isNotEmpty == true)
              .toList() ??
          const [],
      shopBannerUrl: _normalizeOptionalImageUrl(
        json['shop_banner'] ??
            json['shopBanner'] ??
            json['banner_url'] ??
            json['bannerUrl'],
      ),
      vehicleType: json['vehicle_type']?.toString(),
      plateNumber: json['plate_number']?.toString(),
      licensePhotoPath: json['license_photo']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  static double? _parseOptionalNonNegativeAmount(Object? value) {
    final amount = value is num ? value.toDouble() : double.tryParse('$value');
    return amount != null && amount.isFinite && amount >= 0 ? amount : null;
  }

  static String? _normalizeOptionalImageUrl(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    if (text.startsWith('data:image')) return text;
    if (text.startsWith('http://') || text.startsWith('https://')) {
      return _normalizePublicImageUrl(text);
    }
    return text;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': fullName,
      'phone': phone,
      'email': email,
      'role': role,
      'is_verified': isVerified,
      'city': city,
      'address': address,
      'delivery_addresses':
          deliveryAddresses.map((value) => value.toJson()).toList(),
      'selected_delivery_address_id': selectedDeliveryAddressId,
      'current_location': currentLocation,
      'password_hash': passwordHash,
      'profile_image': profileImageData,
      'shop_category': shopCategory,
      'shop_name': shopName,
      'shop_region': shopRegion,
      'merchant_display_delivery_fee': merchantDisplayDeliveryFee,
      'shop_location': shopLocation,
      'shop_contact_phones': shopContactPhones,
      'shop_wallets': shopWallets,
      'shop_banner': shopBannerUrl,
      'vehicle_type': vehicleType,
      'plate_number': plateNumber,
      'license_photo': licensePhotoPath,
      'created_at': createdAt.toIso8601String(),
    };
  }

  UserModel copyWith({
    Object? id = _sentinel,
    Object? fullName = _sentinel,
    Object? phone = _sentinel,
    Object? email = _sentinel,
    Object? role = _sentinel,
    Object? isVerified = _sentinel,
    Object? city = _sentinel,
    Object? address = _sentinel,
    Object? deliveryAddresses = _sentinel,
    Object? selectedDeliveryAddressId = _sentinel,
    Object? currentLocation = _sentinel,
    Object? passwordHash = _sentinel,
    Object? profileImageData = _sentinel,
    Object? shopCategory = _sentinel,
    Object? shopName = _sentinel,
    Object? shopRegion = _sentinel,
    Object? merchantDisplayDeliveryFee = _sentinel,
    Object? shopLocation = _sentinel,
    Object? shopContactPhones = _sentinel,
    Object? shopWallets = _sentinel,
    Object? shopBannerUrl = _sentinel,
    Object? vehicleType = _sentinel,
    Object? plateNumber = _sentinel,
    Object? licensePhotoPath = _sentinel,
    Object? createdAt = _sentinel,
  }) {
    return UserModel(
      id: id == _sentinel ? this.id : id as String,
      fullName: fullName == _sentinel ? this.fullName : fullName as String,
      phone: phone == _sentinel ? this.phone : phone as String,
      email: email == _sentinel ? this.email : email as String?,
      role: role == _sentinel ? this.role : role as String,
      isVerified:
          isVerified == _sentinel ? this.isVerified : isVerified as bool,
      city: city == _sentinel ? this.city : city as String?,
      address: address == _sentinel ? this.address : address as String?,
      deliveryAddresses: deliveryAddresses == _sentinel
          ? this.deliveryAddresses
          : deliveryAddresses as List<DeliveryAddress>,
      selectedDeliveryAddressId: selectedDeliveryAddressId == _sentinel
          ? this.selectedDeliveryAddressId
          : selectedDeliveryAddressId as String?,
      currentLocation: currentLocation == _sentinel
          ? this.currentLocation
          : currentLocation as String?,
      passwordHash: passwordHash == _sentinel
          ? this.passwordHash
          : passwordHash as String?,
      profileImageData: profileImageData == _sentinel
          ? this.profileImageData
          : profileImageData as String?,
      shopCategory: shopCategory == _sentinel
          ? this.shopCategory
          : shopCategory as String?,
      shopName: shopName == _sentinel ? this.shopName : shopName as String?,
      shopRegion:
          shopRegion == _sentinel ? this.shopRegion : shopRegion as String?,
      merchantDisplayDeliveryFee: merchantDisplayDeliveryFee == _sentinel
          ? this.merchantDisplayDeliveryFee
          : merchantDisplayDeliveryFee as double?,
      shopLocation: shopLocation == _sentinel
          ? this.shopLocation
          : shopLocation as String?,
      shopContactPhones: shopContactPhones == _sentinel
          ? this.shopContactPhones
          : shopContactPhones as List<String>,
      shopWallets: shopWallets == _sentinel
          ? this.shopWallets
          : shopWallets as List<Map<String, String>>,
      shopBannerUrl: shopBannerUrl == _sentinel
          ? this.shopBannerUrl
          : shopBannerUrl as String?,
      vehicleType:
          vehicleType == _sentinel ? this.vehicleType : vehicleType as String?,
      plateNumber:
          plateNumber == _sentinel ? this.plateNumber : plateNumber as String?,
      licensePhotoPath: licensePhotoPath == _sentinel
          ? this.licensePhotoPath
          : licensePhotoPath as String?,
      createdAt:
          createdAt == _sentinel ? this.createdAt : createdAt as DateTime,
    );
  }
}

class DeliveryAddress {
  const DeliveryAddress({
    required this.id,
    required this.label,
    required this.city,
    required this.address,
    this.locationCoordinates,
  });

  final String id;
  final String label;
  final String city;
  final String address;
  final String? locationCoordinates;

  factory DeliveryAddress.fromJson(Map<String, dynamic> json) =>
      DeliveryAddress(
        id: json['id']?.toString().trim() ?? '',
        label: json['label']?.toString().trim() ?? '',
        city: json['city']?.toString().trim() ?? '',
        address: json['address']?.toString().trim() ?? '',
        locationCoordinates:
            (json['location_coordinates'] ?? json['locationCoordinates'])
                ?.toString()
                .trim(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'city': city,
        'address': address,
        if (locationCoordinates?.trim().isNotEmpty == true)
          'location_coordinates': locationCoordinates!.trim(),
      };
}
