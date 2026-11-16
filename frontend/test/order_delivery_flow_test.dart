import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/services/delivery_pricing_service.dart';
import 'package:she_m_app/data/services/delivery_service.dart';
import 'package:she_m_app/data/services/driver_service.dart';
import 'package:she_m_app/data/services/order_service.dart';
import 'package:she_m_app/presentation/admin/merchant_management_screen.dart';

void main() {
  test('merchant orders are sorted newest first and show local date and time',
      () {
    final oldest = {
      'id': 'oldest',
      'created_at': '2026-10-04T08:15:00.000Z',
    };
    final newest = {
      'id': 'newest',
      'created_at': '2026-10-05T10:42:00.000Z',
    };
    final withoutDate = {'id': 'undated'};

    final sorted = sortMerchantOrdersNewestFirst([oldest, withoutDate, newest]);
    final localDateTime = DateTime.parse(newest['created_at']!).toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');

    expect(sorted.map((order) => order['id']), ['newest', 'oldest', 'undated']);
    expect(
      formatMerchantOrderDateTime(newest),
      '${twoDigits(localDateTime.day)}/${twoDigits(localDateTime.month)}/'
      '${localDateTime.year} • ${twoDigits(localDateTime.hour)}:'
      '${twoDigits(localDateTime.minute)}',
    );
    expect(formatMerchantOrderDateTime(withoutDate), 'غير محدد');
  });

  test('merchant approval moves a new order directly to preparing', () {
    expect(nextMerchantOrderStatus('new'), 'preparing');
    expect(nextMerchantOrderStatus('confirmed'), 'preparing');
    expect(nextMerchantOrderStatus('pending_payment'), 'confirmed');
  });

  test('delivery fee is calculated by region and distance', () {
    final fee = DeliveryPricingService.calculateFee(
      orderSubtotal: 20000,
      region: 'صنعاء',
      distanceKm: 12,
    );

    expect(fee, greaterThanOrEqualTo(1200));
    expect(fee, lessThanOrEqualTo(3000));
  });

  test('driver profile stores vehicle type and region', () {
    const driver = DriverProfile(
      id: 'd-1',
      fullName: 'سائق جديد',
      phone: '966500000000',
      region: 'صنعاء',
      vehicleType: 'دراجة نارية',
      isAvailable: true,
    );

    expect(driver.region, 'صنعاء');
    expect(driver.vehicleType, 'دراجة نارية');
    expect(driver.toJson()['vehicle_type'], 'دراجة نارية');
  });

  test('driver registration creates a profile and keeps it in the region list',
      () {
    final created = DriverService.registerDriver(
      fullName: 'سائق اختبار',
      phone: '966500099999',
      region: 'صنعاء',
      vehicleType: 'سيارة صغيرة',
      isAvailable: true,
    );

    expect(created.fullName, 'سائق اختبار');
    expect(created.region, 'صنعاء');
    expect(created.vehicleType, 'سيارة صغيرة');
    expect(
      DriverService.getDriversForRegion('صنعاء').any(
        (driver) => driver.phone == '966500099999',
      ),
      isTrue,
    );
  });

  test('best available driver is selected by region and vehicle type', () {
    final driver = DriverService.findBestDriverForOrder(
      region: 'صنعاء',
      vehicleType: 'سيارة صغيرة',
    );

    expect(driver, isNotNull);
    expect(driver!.region, 'صنعاء');
    expect(driver.vehicleType, 'سيارة صغيرة');
  });

  test('dispatch reserves the selected driver and marks them unavailable', () {
    final selected = DriverService.dispatchBestDriverForOrder(
      orderId: 'order-999',
      region: 'صنعاء',
      vehicleType: 'سيارة صغيرة',
    );

    expect(selected, isNotNull);
    expect(selected!.isAvailable, isFalse);
    expect(
      DriverService.getNearbyDrivers(
        region: 'صنعاء',
        vehicleType: 'سيارة صغيرة',
      ).any((driver) => driver.id == selected.id),
      isFalse,
    );
  });

  test('order auto-assignment picks a compatible driver for the order',
      () async {
    final assigned = await OrderService.autoAssignDriverForOrder(
      orderId: 'order-1000',
      region: 'صنعاء',
      vehicleType: 'سيارة صغيرة',
    );

    expect(assigned, isNotNull);
    expect(assigned!.region, 'صنعاء');
    expect(assigned.vehicleType, 'سيارة صغيرة');
  });

  test('driver accepts order and confirms pickup without a customer code', () {
    final driver = DriverService.getDriversForRegion('صنعاء').first;
    final accepted = DriverService.acceptAssignedOrder(
      orderId: 'order-2000',
      driverId: driver.id,
    );
    final pickedUp = DriverService.confirmPickup(
      orderId: 'order-2000',
      driverId: driver.id,
    );

    expect(accepted, isTrue);
    expect(pickedUp, isTrue);
    expect(DriverService.getOrderStatus('order-2000'), 'picked_up');
  });

  test('driver lifecycle labels distinguish pickup states', () {
    expect(DeliveryService.statusLabel('accepted'), 'تم قبول الطلب');
    expect(DeliveryService.statusLabel('shipped'), 'جاهز للاستلام من المتجر');
    expect(DeliveryService.statusLabel('picked_up'), 'تم تسليم الطلب للسائق');
    expect(DeliveryService.statusLabel('rejected'), 'مرفوض');
    expect(DeliveryService.statusLabel('pending'), 'انتظار تأكيد الدفع');
  });
}
