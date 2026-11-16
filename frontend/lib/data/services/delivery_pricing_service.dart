class DeliveryPricingService {
  static const double commissionRate = 0.10;

  static const Map<String, double> _baseFeesByRegion = {
    'صنعاء': 1200,
    'عدن': 1400,
    'تعز': 1300,
  };

  static double calculateFee({
    required double orderSubtotal,
    required String region,
    required double distanceKm,
  }) {
    final baseFee = _baseFeesByRegion[region] ?? 1500;
    final distanceFee = distanceKm * 65;
    return (baseFee + distanceFee).roundToDouble();
  }

  static Map<String, dynamic> calculateOrderSummary({
    required double subtotal,
    required String region,
    required double distanceKm,
    double commissionRateValue = commissionRate,
  }) {
    final deliveryFee = calculateFee(
      orderSubtotal: subtotal,
      region: region,
      distanceKm: distanceKm,
    );
    final sellerCommission = subtotal * commissionRateValue;
    final total = subtotal + sellerCommission + deliveryFee;

    return {
      'subtotal': subtotal,
      'seller_commission': sellerCommission,
      'delivery_fee': deliveryFee,
      'total': total,
      'region': region,
      'distance_km': distanceKm,
    };
  }
}
