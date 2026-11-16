import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/presentation/admin/merchant_management_screen.dart';

void main() {
  test('parses a valid latitude and longitude from the store location field',
      () {
    final parsed = MerchantStoreSettingsScreen.parseLocationFromText(
      '24.713600, 46.675300',
    );

    expect(parsed, isNotNull);
    expect(parsed!['latitude'], closeTo(24.7136, 0.0001));
    expect(parsed['longitude'], closeTo(46.6753, 0.0001));
  });

  test('returns null for an invalid location text', () {
    expect(MerchantStoreSettingsScreen.parseLocationFromText('صنعاء'), isNull);
  });
}
