class DriverProfile {
  final String id;
  final String fullName;
  final String phone;
  final String region;
  final String vehicleType;
  final bool isAvailable;

  const DriverProfile({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.region,
    required this.vehicleType,
    required this.isAvailable,
  });

  factory DriverProfile.fromJson(Map<String, dynamic> json) {
    return DriverProfile(
      id: json['id']?.toString() ?? '',
      fullName:
          json['full_name']?.toString() ?? json['fullName']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      region: json['region']?.toString() ?? 'صنعاء',
      vehicleType: json['vehicle_type']?.toString() ??
          json['vehicleType']?.toString() ??
          'دراجة نارية',
      isAvailable: json['is_available'] == true || json['isAvailable'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': fullName,
      'phone': phone,
      'region': region,
      'vehicle_type': vehicleType,
      'is_available': isAvailable,
    };
  }

  DriverProfile copyWith({
    String? id,
    String? fullName,
    String? phone,
    String? region,
    String? vehicleType,
    bool? isAvailable,
  }) {
    return DriverProfile(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      region: region ?? this.region,
      vehicleType: vehicleType ?? this.vehicleType,
      isAvailable: isAvailable ?? this.isAvailable,
    );
  }
}

class DriverService {
  static final Map<String, String> _orderStatusByDriver = {};
  static final Map<String, String> _orderStatusByOrder = {};

  static final List<DriverProfile> _registeredDrivers = [
    const DriverProfile(
      id: 'd-1',
      fullName: 'سائق كريم',
      phone: '966500000001',
      region: 'صنعاء',
      vehicleType: 'دراجة نارية',
      isAvailable: true,
    ),
    const DriverProfile(
      id: 'd-2',
      fullName: 'سائق محمد',
      phone: '966500000002',
      region: 'عمران',
      vehicleType: 'سيارة صغيرة',
      isAvailable: true,
    ),
    const DriverProfile(
      id: 'd-3',
      fullName: 'سائق ناصر',
      phone: '966500000003',
      region: 'ذمار',
      vehicleType: 'دراجة نارية',
      isAvailable: true,
    ),
  ];

  static List<DriverProfile> getDriversForRegion(String region) {
    return [..._registeredDrivers.where((driver) => driver.region == region)];
  }

  static Future<List<DriverProfile>> getDriversForRegionAsync(
    String region,
  ) async {
    return getDriversForRegion(region);
  }

  static DriverProfile registerDriver({
    required String fullName,
    required String phone,
    required String region,
    required String vehicleType,
    bool isAvailable = true,
  }) {
    final driver = DriverProfile(
      id: 'driver-${DateTime.now().millisecondsSinceEpoch}',
      fullName: fullName,
      phone: phone,
      region: region,
      vehicleType: vehicleType,
      isAvailable: isAvailable,
    );

    _registeredDrivers.add(driver);

    return driver;
  }

  static List<DriverProfile> getNearbyDrivers({
    required String region,
    required String vehicleType,
    int limit = 5,
  }) {
    final drivers = [..._registeredDrivers];

    return drivers
        .where((driver) =>
            driver.region == region &&
            driver.isAvailable &&
            _matchesVehicle(driver.vehicleType, vehicleType))
        .take(limit)
        .toList();
  }

  static Future<List<DriverProfile>> getNearbyDriversAsync({
    required String region,
    required String vehicleType,
    int limit = 5,
  }) async {
    return getNearbyDrivers(
      region: region,
      vehicleType: vehicleType,
      limit: limit,
    );
  }

  static DriverProfile? findBestDriverForOrder({
    required String region,
    required String vehicleType,
  }) {
    final candidates = getNearbyDrivers(
      region: region,
      vehicleType: vehicleType,
    );

    if (candidates.isNotEmpty) {
      final best = [...candidates];
      best.sort((a, b) {
        final aScore = _vehicleScore(a.vehicleType, vehicleType);
        final bScore = _vehicleScore(b.vehicleType, vehicleType);
        if (aScore != bScore) {
          return bScore.compareTo(aScore);
        }
        return a.fullName.compareTo(b.fullName);
      });
      return best.first;
    }

    final fallback = _registeredDrivers.where((driver) {
      if (!driver.isAvailable) return false;
      return driver.region == region ||
          _matchesVehicle(driver.vehicleType, vehicleType);
    }).toList();

    return fallback.isNotEmpty ? fallback.first : null;
  }

  static DriverProfile? dispatchBestDriverForOrder({
    required String orderId,
    required String region,
    required String vehicleType,
  }) {
    final driver = findBestDriverForOrder(
      region: region,
      vehicleType: vehicleType,
    );

    if (driver == null) return null;

    final updated = driver.copyWith(isAvailable: false);
    final index = _registeredDrivers.indexWhere((item) => item.id == driver.id);
    if (index != -1) {
      _registeredDrivers[index] = updated;
    }

    _orderStatusByDriver[driver.id] = 'assigned';
    _orderStatusByOrder[orderId] = 'assigned';

    return updated;
  }

  static bool acceptAssignedOrder({
    required String orderId,
    required String driverId,
  }) {
    if (_registeredDrivers.every((driver) => driver.id != driverId)) {
      return false;
    }

    _orderStatusByDriver[driverId] = 'accepted';
    _orderStatusByOrder[orderId] = 'accepted';
    return true;
  }

  static bool confirmPickup({
    required String orderId,
    required String driverId,
  }) {
    if (_registeredDrivers.every((driver) => driver.id != driverId)) {
      return false;
    }

    _orderStatusByDriver[driverId] = 'picked_up';
    _orderStatusByOrder[orderId] = 'picked_up';
    return true;
  }

  static String getOrderStatus(String orderId) {
    return _orderStatusByOrder[orderId] ?? 'assigned';
  }

  static Future<DriverProfile?> dispatchBestDriverForOrderAsync({
    required String orderId,
    required String region,
    required String vehicleType,
  }) async {
    final driver = findBestDriverForOrder(
      region: region,
      vehicleType: vehicleType,
    );

    if (driver == null) return null;

    final updated = driver.copyWith(isAvailable: false);
    final index = _registeredDrivers.indexWhere((item) => item.id == driver.id);
    if (index != -1) {
      _registeredDrivers[index] = updated;
    }

    return updated;
  }

  static bool _matchesVehicle(String driverVehicle, String requestedVehicle) {
    if (driverVehicle == requestedVehicle) return true;
    if (requestedVehicle == 'سيارة صغيرة' && driverVehicle == 'سيارة صغيرة') {
      return true;
    }
    if (requestedVehicle == 'دراجة نارية' && driverVehicle == 'دراجة نارية') {
      return true;
    }
    return false;
  }

  static int _vehicleScore(String driverVehicle, String requestedVehicle) {
    if (driverVehicle == requestedVehicle) return 2;
    if (requestedVehicle == 'سيارة صغيرة' && driverVehicle == 'سيارة صغيرة') {
      return 2;
    }
    if (requestedVehicle == 'دراجة نارية' && driverVehicle == 'دراجة نارية') {
      return 2;
    }
    return 0;
  }
}
