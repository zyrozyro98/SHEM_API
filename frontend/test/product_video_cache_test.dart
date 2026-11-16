import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/presentation/common/product_video_cache.dart';

void main() {
  test('reuses a network video controller across preview leases', () async {
    final firstLease =
        ProductVideoCache.acquireNetwork('https://example.com/product.mp4');
    final firstController = firstLease.controller;
    await ProductVideoCache.release(firstLease);

    final secondLease =
        ProductVideoCache.acquireNetwork('https://example.com/product.mp4');

    expect(identical(secondLease.controller, firstController), isTrue);
    await ProductVideoCache.release(secondLease);
  });
}
