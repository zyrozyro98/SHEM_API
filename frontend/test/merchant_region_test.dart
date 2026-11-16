import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/presentation/checkout/delivery_address_screen.dart';

void main() {
  test('store region takes priority over profile city for delivery pricing',
      () {
    expect(
      resolveMerchantRegion({
        'city': 'صنعاء',
        'shop_region': 'إب',
      }),
      'إب',
    );
  });

  test('region lookup supports legacy keys and ignores blank store region', () {
    expect(
      resolveMerchantRegion({
        'shop_region': ' ',
        'shopRegion': '',
        'region': 'تعز',
        'city': 'صنعاء',
      }),
      'تعز',
    );
  });
}
