import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/models/product_model.dart';
import 'package:she_m_app/data/services/cart_service.dart';
import 'package:she_m_app/data/services/pricing_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (_) async => null);

  setUp(() {
    CartService.instance.clear();
  });

  test(
      'same product should be merged into one cart item across different variants',
      () {
    final product = const ProductModel(
      id: 'p-1',
      name: 'قميص',
      price: 199,
      category: 'ملابس',
      description: 'وصف',
      colors: ['أبيض', 'أسود'],
      sizes: ['S', 'M'],
      imageUrl: '',
      available: true,
      merchantId: 'm-1',
      merchantName: 'متجر تجريبي',
    );

    CartService.instance.addProduct(product, color: 'أبيض', size: 'S');
    CartService.instance.addProduct(product, color: 'أسود', size: 'M');

    expect(CartService.instance.items.length, 1);
    expect(CartService.instance.items.first.quantity, 2);
    expect(CartService.instance.items.first.selectedColor, 'أسود');
    expect(CartService.instance.items.first.selectedSize, 'M');
  });

  test('removing checked out products keeps unchecked products in the cart',
      () {
    const selectedProduct = ProductModel(
      id: 'p-selected',
      name: 'المنتج المحدد',
      price: 100,
      category: 'عام',
      description: '',
      imageUrl: '',
      available: true,
      merchantId: 'm-1',
    );
    const remainingProduct = ProductModel(
      id: 'p-remaining',
      name: 'المنتج المتبقي',
      price: 200,
      category: 'عام',
      description: '',
      imageUrl: '',
      available: true,
      merchantId: 'm-1',
    );

    CartService.instance.addProduct(selectedProduct);
    CartService.instance.addProduct(remainingProduct);
    CartService.instance.removeProducts(['p-selected']);

    expect(
      CartService.instance.items.map((item) => item.product.id),
      ['p-remaining'],
    );
  });

  test('refreshing cart ignores legacy VAT pricing rules', () {
    const categoryProduct = ProductModel(
      id: 'category',
      name: 'منتج فئة',
      price: 100,
      category: 'ملابس',
      description: '',
      imageUrl: '',
      available: true,
      merchantId: 'm-1',
    );
    const overrideProduct = ProductModel(
      id: 'override',
      name: 'منتج خاص',
      price: 100,
      category: 'ملابس',
      description: '',
      imageUrl: '',
      available: true,
      merchantId: 'm-1',
      vatRateOverride: 20,
    );
    const exemptProduct = ProductModel(
      id: 'exempt',
      name: 'منتج معفى',
      price: 100,
      category: 'ملابس',
      description: '',
      imageUrl: '',
      available: true,
      merchantId: 'm-1',
    );

    CartService.instance.addProduct(categoryProduct);
    CartService.instance.addProduct(overrideProduct);
    CartService.instance.addProduct(exemptProduct);
    CartService.instance.updateVatRates(
      const PricingConfig(
        vatRate: 12,
        vatByCategory: {'ملابس': 5},
        vatExemptProductIds: {'exempt'},
      ),
    );

    expect(
      CartService.instance.items.map((entry) => entry.product.vatRate),
      [0, 0, 0],
    );
  });
}
