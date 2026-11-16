import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/models/order_model.dart';
import 'package:she_m_app/data/services/catalog_service.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/data/services/promotion_service.dart';
import 'package:she_m_app/presentation/dashboard/customer_dashboard_screen.dart';

class _HomeCatalogDatabase implements DatabaseService {
  _HomeCatalogDatabase(this.data);

  final Map<String, dynamic> data;

  @override
  Future<Map<String, dynamic>> read(String path) async =>
      Map<String, dynamic>.from(data[path] as Map? ?? const {});

  @override
  Future<Map<String, dynamic>> write(
    String path,
    Map<String, dynamic> data,
  ) async =>
      data;

  @override
  Future<Map<String, dynamic>> update(
    String path,
    Map<String, dynamic> data,
  ) async =>
      data;

  @override
  Future<Map<String, dynamic>?> updateIf(
    String path, {
    required bool Function(Map<String, dynamic> current) condition,
    required Map<String, dynamic> updates,
  }) async =>
      null;

  @override
  Future<void> delete(String path) async {}
}

void main() {
  testWidgets('customer home loads the next product batch near the grid end',
      (tester) async {
    final database = _HomeCatalogDatabase({
      'products': {
        for (var index = 0; index < 24; index++)
          'product-${index.toString().padLeft(2, '0')}': {
            'id': 'product-$index',
            'name': 'منتج $index',
            'price': 10 + index,
            'category': 'عام',
            'description': '',
            'image_url': '',
            'available': true,
            'merchant_id': 'merchant-1',
            'submitted_at': DateTime.utc(2026, 11, 4)
                .add(Duration(minutes: index))
                .toIso8601String(),
          },
      },
      'profiles': {
        'merchant-1': {
          'shop_name': 'المتجر',
        },
      },
      'promotions': {},
    });
    final catalog = CatalogService(databaseService: database);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerHomeScreen(
            profile: null,
            orders: const <OrderModel>[],
            currencySymbol: 'ر.س',
            onRefresh: () async {},
            catalogService: catalog,
            promotionService: PromotionService(databaseService: database),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('منتجات مختارة لك'));
    await tester.pumpAndSettle();

    expect(find.text('منتج 11'), findsOneWidget);
    expect(find.text('منتج 0'), findsOneWidget);
    expect(find.text('منتج 12'), findsNothing);

    await tester.ensureVisible(find.text('منتج 0'));
    await tester.pumpAndSettle();

    expect(find.text('منتج 12'), findsOneWidget);

    final products = database.data['products'] as Map;
    final firstProduct = products['product-00'] as Map;
    firstProduct['name'] = 'منتج محدث';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('منتج محدث'), findsOneWidget);
  });
}
