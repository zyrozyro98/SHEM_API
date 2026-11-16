import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/services/currency_service.dart';
import 'package:she_m_app/data/services/order_service.dart';
import 'package:she_m_app/data/models/user_model.dart';
import 'package:she_m_app/presentation/admin/merchant_management_screen.dart';

void main() {
  test('keeps only the active merchant records in shared dashboard data', () {
    const merchantId = 'merchant-42';
    final records = [
      {'id': 'p1', 'merchant_id': 'merchant-42', 'name': 'Product A'},
      {'id': 'p2', 'merchant_id': 'merchant-99', 'name': 'Product B'},
      {'id': 'p3', 'merchant_id': '', 'name': 'Product C'},
      {'id': 'p4', 'merchant_id': 'merchant-42', 'name': 'Product D'},
    ];

    final filtered = MerchantManagementScreen.filterMerchantRecords(
      merchantId: merchantId,
      records: records,
    );

    expect(filtered.map((item) => item['id']).toList(), ['p1', 'p4']);
  });

  test('finds merchant orders through their items and sorts new orders', () {
    final orders = [
      {
        'id': 'new-old',
        'status': 'new',
        'created_at': '2026-10-01T10:00:00Z',
        'items': [
          {'product_id': 'product-1', 'quantity': 1},
        ],
      },
      {
        'id': 'new-latest',
        'status': 'new',
        'created_at': '2026-10-02T10:00:00Z',
        'items': [
          {'merchant_id': 'merchant-42', 'quantity': 2},
        ],
      },
      {
        'id': 'other-merchant',
        'status': 'new',
        'items': [
          {'merchant_id': 'merchant-99'},
        ],
      },
      {
        'id': 'pending-payment',
        'status': 'pending_payment',
        'items': [
          {'merchant_id': 'merchant-42'},
        ],
      },
    ];

    final merchantOrders = MerchantManagementScreen.filterOrdersForMerchant(
      merchantId: 'merchant-42',
      orders: orders,
      merchantProductIds: {'product-1'},
    );
    final newOrders =
        MerchantManagementScreen.filterNewMerchantOrders(merchantOrders);

    expect(merchantOrders.map((order) => order['id']).toSet(), {
      'new-old',
      'new-latest',
    });
    expect(newOrders.map((order) => order['id']).toList(), [
      'new-latest',
      'new-old',
    ]);
  });

  test('product ownership overrides stale merchant ids in mixed orders', () {
    final productOwners = OrderService.productOwnersById({
      'products/owned': {'merchant_id': 'merchant-42'},
      'products/foreign': {'id': 'foreign', 'merchant_id': 'merchant-99'},
    });
    final orders = [
      {
        'id': 'mixed-order',
        'status': 'new',
        'items': [
          {
            'product_id': 'products/owned',
            'product_name': 'My product',
            'merchant_id': 'merchant-99',
            'total_yer': 100,
          },
          {
            'product_id': 'foreign',
            'product_name': 'Other merchant product',
            'merchant_id': 'merchant-42',
            'total_yer': 200,
          },
        ],
      },
    ];

    final merchantOrders = MerchantManagementScreen.filterOrdersForMerchant(
      merchantId: 'merchant-42',
      orders: orders,
      productOwners: productOwners,
    );

    expect(merchantOrders, hasLength(1));
    expect(
      (merchantOrders.single['merchant_items'] as List)
          .map((item) => item['product_name']),
      ['My product'],
    );
    expect(
      merchantProductsTotalInYER(
        orders.single,
        merchantId: 'merchant-42',
        productOwners: productOwners,
      ),
      100,
    );
  });

  test('dashboard order summary only shows explicitly scoped merchant items',
      () {
    final order = {
      'items': [
        {'product_name': 'منتج تاجر آخر', 'quantity': 1},
      ],
      'merchant_items': [
        {'product_name': 'منتجي', 'quantity': 2},
      ],
    };

    expect(merchantOrderItemsSummary(order), 'منتجي + 1 منتجات');
    expect(
      merchantOrderItemsSummary({
        'items': [
          {'product_name': 'منتج تاجر آخر', 'quantity': 1},
        ],
      }),
      'تفاصيل الطلب',
    );
  });

  test('order thumbnails include only products canonically owned by merchant',
      () {
    const ownedImage = 'https://example.com/owned.png';
    const foreignImage = 'https://example.com/foreign.png';
    final order = {
      'items': [
        {
          'product_id': 'owned',
          'merchant_id': 'merchant-99',
          'image_url': ownedImage,
        },
        {
          'product_id': 'foreign',
          'merchant_id': 'merchant-42',
          'image_url': foreignImage,
        },
      ],
    };

    expect(
      merchantOrderProductImages(
        order: order,
        merchantId: 'merchant-42',
        productsSnapshot: {
          'owned': {'merchant_id': 'merchant-42'},
          'foreign': {'merchant_id': 'merchant-99'},
        },
      ),
      [ownedImage],
    );
  });

  test('merchant totals include only their non-rejected products', () {
    final order = {
      'subtotal': 3750,
      'shipping_fee': 2400,
      'total': 6150,
      'items': [
        {
          'merchant_id': 'merchant-42',
          'product_id': 'owned',
          'total_yer': 1000,
        },
        {
          'merchant_id': 'merchant-99',
          'product_id': 'other',
          'total_yer': 2000,
        },
        {
          'merchant_id': 'merchant-42',
          'product_id': 'rejected',
          'status': 'rejected',
          'total_yer': 500,
        },
        {
          'product_id': 'legacy-owned',
          'total_yer': 250,
        },
      ],
    };

    expect(
      merchantProductsTotalInYER(
        order,
        merchantId: 'merchant-42',
        merchantProductIds: {'legacy-owned'},
      ),
      1250,
    );
  });

  test('merchant displays base product prices without app commission', () {
    final merchantItem = {
      'merchant_id': 'merchant-42',
      'quantity': 2,
      'unit_price': 120,
      'total_yer': 240,
      'base_unit_price': 100,
      'base_unit_price_yer': 100,
    };
    final order = {
      'commission': 40,
      'items': [
        merchantItem,
        {
          'merchant_id': 'merchant-99',
          'quantity': 1,
          'total_yer': 500,
          'base_unit_price_yer': 450,
        },
      ],
    };

    expect(merchantProductUnitPrice(merchantItem), 100);
    expect(
      merchantProductsTotalInYER(order, merchantId: 'merchant-42'),
      200,
    );
  });

  test('legacy merchant totals remove only their share of included commission',
      () {
    final order = {
      'commission': 60,
      'commission_included_in_subtotal': true,
      'items': [
        {
          'merchant_id': 'merchant-42',
          'total_yer': 120,
        },
        {
          'merchant_id': 'merchant-99',
          'total_yer': 240,
        },
      ],
    };

    expect(
      merchantProductsTotalInYER(order, merchantId: 'merchant-42'),
      100,
    );
    expect(
      merchantProductsTotalInYER(order, merchantId: 'merchant-99'),
      200,
    );
  });

  test('merchant dashboard revenue excludes delivery and other sellers', () {
    final dashboard = MerchantManagementScreen.buildDashboardData(
      merchantProfile: {'id': 'merchant-42'},
      merchantProductIds: {'owned'},
      currencies: const [],
      orders: [
        {
          'id': 'order-1',
          'status': 'delivered',
          'total': 6150,
          'shipping_fee': 2400,
          'items': [
            {
              'merchant_id': 'merchant-42',
              'product_id': 'owned',
              'total_yer': 1000,
              'base_unit_price_yer': 800,
            },
            {
              'merchant_id': 'merchant-99',
              'product_id': 'other',
              'total_yer': 2000,
              'base_unit_price_yer': 1800,
            },
          ],
        },
      ],
    );

    expect(dashboard.totalRevenue, 800);
    expect(dashboard.recentOrders.single['report_total_yer'], 800);
  });

  test('merchant dashboard does not count cancelled orders as revenue', () {
    final dashboard = MerchantManagementScreen.buildDashboardData(
      merchantProfile: {'id': 'merchant-42'},
      merchantProductIds: {'owned'},
      currencies: const [],
      orders: [
        {
          'id': 'delivered',
          'status': 'delivered',
          'items': [
            {
              'merchant_id': 'merchant-42',
              'product_id': 'owned',
              'base_unit_price_yer': 800,
            },
          ],
        },
        {
          'id': 'cancelled',
          'status': 'cancelled',
          'items': [
            {
              'merchant_id': 'merchant-42',
              'product_id': 'owned',
              'base_unit_price_yer': 5000,
            },
          ],
        },
      ],
    );

    expect(dashboard.totalRevenue, 800);
    expect(dashboard.recentOrders, hasLength(2));
  });

  test('merchant product totals convert currencies without adding delivery',
      () {
    final total = merchantProductsTotalInYER(
      {
        'total': 140,
        'shipping_fee': 40,
        'items': [
          {
            'merchant_id': 'merchant-42',
            'total': 2,
            'currency_code': 'SAR',
          },
          {
            'merchant_id': 'merchant-99',
            'total': 100,
            'currency_code': 'SAR',
          },
        ],
      },
      merchantId: 'merchant-42',
      currencies: const [
        CurrencyOption(
          title: 'ريال سعودي',
          code: 'SAR',
          symbol: 'ر.س',
          rateToYER: 50,
        ),
      ],
    );

    expect(total, 100);
  });

  test('retains the merchant display fee in profile serialization', () {
    final profile = UserModel.fromJson({
      'id': 'merchant-1',
      'full_name': 'Owner',
      'phone': '711111111',
      'role': 'merchant',
      'is_verified': true,
      'merchant_display_delivery_fee': 750,
      'created_at': '2026-01-01T00:00:00.000Z',
    });
    final serialized = profile.copyWith(shopName: 'Store').toJson();

    expect(serialized['merchant_display_delivery_fee'], 750);
  });
}
