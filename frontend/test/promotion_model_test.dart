import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/models/promotion_model.dart';

void main() {
  test('promotion model normalizes GitHub blob URLs to raw image URLs', () {
    final promotion = PromotionModel.fromJson({
      'title': 'عرض جديد',
      'image_url': 'https://github.com/demo/store/blob/main/assets/banner.png',
      'product_id': 'p1',
      'merchant_id': 'm1',
      'is_active': true,
      'approval_status': 'approved',
    });

    expect(
      promotion.imageUrl,
      'https://raw.githubusercontent.com/demo/store/main/assets/banner.png',
    );
  });
}
