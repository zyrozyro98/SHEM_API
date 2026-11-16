import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/models/order_model.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/data/services/support_service.dart';
import 'package:she_m_app/presentation/admin/support_management_screen.dart';

class _FakeSupportDatabase implements DatabaseService {
  final Map<String, Map<String, dynamic>> rows = {};

  @override
  Future<Map<String, dynamic>> read(String path) async {
    final direct = rows[path];
    if (direct != null) return Map<String, dynamic>.from(direct);

    final prefix = '$path/';
    final descendants = <String, dynamic>{};
    for (final entry in rows.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      final remainder = entry.key.substring(prefix.length);
      if (remainder.contains('/')) continue;
      descendants[remainder] = Map<String, dynamic>.from(entry.value);
    }
    return descendants;
  }

  @override
  Future<Map<String, dynamic>> write(
    String path,
    Map<String, dynamic> data,
  ) async {
    rows[path] = Map<String, dynamic>.from(data);
    return Map<String, dynamic>.from(data);
  }

  @override
  Future<Map<String, dynamic>> update(
    String path,
    Map<String, dynamic> data,
  ) async {
    rows[path] = {...?rows[path], ...data};
    return Map<String, dynamic>.from(rows[path]!);
  }

  @override
  Future<Map<String, dynamic>?> updateIf(
    String path, {
    required bool Function(Map<String, dynamic> current) condition,
    required Map<String, dynamic> updates,
  }) async {
    final current = await read(path);
    if (current.isEmpty || !condition(current)) return null;
    return update(path, updates);
  }

  @override
  Future<void> delete(String path) async {
    rows.remove(path);
  }
}

void main() {
  test('order item preserves merchant and product refund snapshot fields', () {
    const item = OrderItem(
      productId: 'product-1',
      productName: 'حذاء',
      productCategory: 'أحذية',
      productDescription: 'جلد طبيعي',
      quantity: 2,
      unitPrice: 100,
      total: 200,
      merchantId: 'merchant-1',
      merchantName: 'متجر الأحذية',
      merchantClaimedOriginalPrice: 65,
    );

    final restored = OrderItem.fromJson(item.toJson());

    expect(restored.productName, 'حذاء');
    expect(restored.productCategory, 'أحذية');
    expect(restored.productDescription, 'جلد طبيعي');
    expect(restored.merchantName, 'متجر الأحذية');
    expect(restored.merchantClaimedOriginalPrice, 65);
    expect(restored.total, 200);
  });

  test('support contact settings can be updated and loaded', () async {
    final service = SupportService(databaseService: _FakeSupportDatabase());

    await service.saveSupportContact(
      phone: '+967771234567',
      whatsappPhone: '+967771234567',
      email: 'help@example.com',
      workingHours: '9:00 - 17:00',
      responseTime: 'خلال يوم عمل',
    );
    final contact = await service.getSupportContact();

    expect(contact['phone'], '+967771234567');
    expect(contact['whatsapp_phone'], '+967771234567');
    expect(contact['email'], 'help@example.com');
    expect(contact['working_hours'], '9:00 - 17:00');
    expect(contact['response_time'], 'خلال يوم عمل');
  });

  test('refund snapshots order, customer, merchant and claimed amounts',
      () async {
    final database = _FakeSupportDatabase()
      ..rows['orders/order-1'] = {
        'id': 'order-1',
        'customer_id': 'customer-1',
        'status': 'delivered',
        'created_at': '2026-10-01T10:00:00.000Z',
        'payment_method': 'cash_on_delivery',
        'subtotal': 300,
        'shipping_fee': 20,
        'total': 320,
        'items': [
          {
            'product_id': 'product-1',
            'product_name': 'قميص قديم',
            'product_category': 'ملابس',
            'product_description': 'وصف وقت البيع',
            'merchant_id': 'merchant-1',
            'merchant_name': 'متجر النخبة',
            'unit_price': 150,
            'merchant_claimed_original_price': 90,
            'quantity': 2,
            'total': 300,
            'currency_symbol': 'ر.س',
          },
        ],
      }
      ..rows['profiles/customer-1'] = {
        'id': 'customer-1',
        'full_name': 'عميل الاختبار',
        'phone': '+967700000001',
        'email': 'customer@example.com',
        'city': 'صنعاء',
        'address': 'شارع التحرير',
      }
      ..rows['profiles/merchant-1'] = {
        'id': 'merchant-1',
        'full_name': 'صاحب المتجر',
        'shop_name': 'متجر النخبة',
        'phone': '+967700000002',
        'email': 'merchant@example.com',
      }
      ..rows['products/product-1'] = {
        'id': 'product-1',
        'name': 'قميص جديد الاسم',
        'category': 'فئة محدثة',
        'description': 'وصف محدث',
        'merchant_claimed_original_price': 120,
      };
    final service = SupportService(databaseService: database);

    final request = await service.createRefundRequest(
      customerId: 'customer-1',
      orderId: 'order-1',
      itemIndex: 0,
      reason: 'المنتج تالف أو معيب',
      customerMessage: 'وصل المنتج متضررًا',
    );

    expect(request['customer_claimed_amount'], 300);
    expect(request['amount_due_to_customer'], 300);
    expect(request['merchant_claimed_original_price'], 90);
    expect(request['merchant_claimed_total'], 180);
    expect((request['product_snapshot'] as Map)['name'], 'قميص قديم');
    expect(
        (request['product_snapshot'] as Map)['description'], 'وصف وقت البيع');
    expect((request['customer_snapshot'] as Map)['address'], 'شارع التحرير');
    expect((request['merchant_snapshot'] as Map)['shop_name'], 'متجر النخبة');
    expect((request['order_snapshot'] as Map)['total'], 320);
    expect(
        database.rows.containsKey('refund_requests/${request['id']}'), isTrue);
    expect(
      database.rows.containsKey(
        'customers/customer-1/refund_requests/${request['id']}',
      ),
      isTrue,
    );
  });

  test('refund requests verify order ownership and reject duplicate pending',
      () async {
    final database = _FakeSupportDatabase()
      ..rows['orders/order-3'] = {
        'id': 'order-3',
        'customer_id': 'customer-owner',
        'items': [
          {
            'product_id': 'product-3',
            'product_name': 'منتج',
            'merchant_id': 'merchant-3',
            'quantity': 1,
            'unit_price': 50,
            'total': 50,
          },
        ],
      };
    final service = SupportService(databaseService: database);

    await expectLater(
      service.createRefundRequest(
        customerId: 'other-customer',
        orderId: 'order-3',
        itemIndex: 0,
        reason: 'المنتج تالف',
        customerMessage: 'وصف',
      ),
      throwsA(isA<StateError>()),
    );

    await service.createRefundRequest(
      customerId: 'customer-owner',
      orderId: 'order-3',
      itemIndex: 0,
      reason: 'المنتج تالف',
      customerMessage: 'وصف',
    );
    await expectLater(
      service.createRefundRequest(
        customerId: 'customer-owner',
        orderId: 'order-3',
        itemIndex: 0,
        reason: 'المنتج تالف',
        customerMessage: 'طلب مكرر',
      ),
      throwsA(isA<StateError>()),
    );

    final savedRequest = (await service.getRefundRequests()).single;
    await database.update(
      'refund_requests/${savedRequest['id']}',
      {'status': 'approved'},
    );
    await expectLater(
      service.createRefundRequest(
        customerId: 'customer-owner',
        orderId: 'order-3',
        itemIndex: 0,
        reason: 'المنتج تالف',
        customerMessage: 'طلب آخر بعد الاعتماد',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('admin review updates status and enforces customer claim ceiling',
      () async {
    final database = _FakeSupportDatabase()
      ..rows['refund_requests/refund-1'] = {
        'id': 'refund-1',
        'customer_id': 'customer-1',
        'customer_claimed_amount': 100,
        'status': 'pending',
      };
    final service = SupportService(databaseService: database);

    expect(
      await service.reviewRefundRequest(
        requestId: 'refund-1',
        status: 'approved',
        approvedAmount: 120,
        adminNote: 'مبلغ أعلى من الطلب',
        reviewedBy: 'admin-1',
      ),
      isNull,
    );

    final reviewed = await service.reviewRefundRequest(
      requestId: 'refund-1',
      status: 'approved',
      approvedAmount: 80,
      adminNote: 'اعتماد جزئي',
      reviewedBy: 'admin-1',
    );

    expect(reviewed?['status'], 'approved');
    expect(reviewed?['approved_amount'], 80);
    expect(reviewed?['reviewed_by'], 'admin-1');
    expect(
      database.rows['customers/customer-1/refund_requests/refund-1']
          ?['approved_amount'],
      80,
    );
  });

  testWidgets('admin can inspect full refund snapshots and merchant claim',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = _FakeSupportDatabase()
      ..rows['refund_requests/refund-2'] = {
        'id': 'refund-2',
        'status': 'pending',
        'created_at': '2026-10-16T12:30:00.000Z',
        'customer_id': 'customer-1',
        'customer_snapshot': {
          'full_name': 'عميل مفصل',
          'phone': '+967700000001',
          'email': 'customer@example.com',
          'city': 'صنعاء',
          'address': 'شارع التحرير',
        },
        'order_id': 'order-2',
        'order_snapshot': {
          'id': 'order-2',
          'created_at': '2026-10-10T10:00:00.000Z',
          'status': 'delivered',
          'payment_method': 'cash_on_delivery',
          'total': 240,
          'delivery_address': 'شارع التحرير',
        },
        'product_id': 'product-2',
        'product_snapshot': {
          'name': 'حذاء استرداد',
          'category': 'أحذية',
          'description': 'حذاء جلدي',
          'image_url': 'https://example.com/shoe.jpg',
        },
        'merchant_id': 'merchant-1',
        'merchant_snapshot': {
          'shop_name': 'متجر الأحذية',
          'full_name': 'تاجر مفصل',
          'phone': '+967700000002',
          'email': 'merchant@example.com',
        },
        'reason': 'المنتج تالف',
        'customer_message': 'وصلت العبوة مفتوحة',
        'quantity': 2,
        'unit_price': 120,
        'currency_symbol': 'ر.س',
        'customer_claimed_amount': 240,
        'merchant_claimed_original_price': 75,
        'merchant_claimed_total': 150,
      };

    await tester.pumpWidget(
      MaterialApp(
        home: AdminRefundManagementScreen(
          supportService: SupportService(databaseService: database),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('refund_request_refund-2')));
    await tester.pumpAndSettle();

    expect(find.text('تفاصيل الاسترداد · refund-2'), findsOneWidget);
    expect(find.text('عميل مفصل'), findsOneWidget);
    expect(find.text('متجر الأحذية'), findsOneWidget);
    expect(find.text('حذاء استرداد'), findsNWidgets(2));
    expect(find.text('240 ر.س'), findsAtLeastNWidgets(1));
    expect(find.text('75 ر.س'), findsOneWidget);
    expect(find.text('150 ر.س'), findsOneWidget);
    expect(find.text('وصلت العبوة مفتوحة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
