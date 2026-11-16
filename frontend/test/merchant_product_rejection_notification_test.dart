import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/presentation/support/notifications_screen.dart';

void main() {
  testWidgets('rejection details show product information and edit action',
      (tester) async {
    var editOpened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MerchantProductRejectionDetailsScreen(
          product: const {
            'id': 'product-1',
            'name': 'عباءة',
            'category': 'ملابس',
            'price': 250,
            'currency_symbol': 'ر.س',
            'stock': 3,
            'colors': ['أسود', 'بني'],
            'sizes': ['S', 'M'],
            'description': 'عباءة عملية',
            'review_reason': 'الصورة غير واضحة',
          },
          rejectionReason: 'الصورة غير واضحة',
          onEdit: () => editOpened = true,
        ),
      ),
    );

    expect(find.text('عباءة'), findsOneWidget);
    expect(find.text('سبب الرفض'), findsOneWidget);
    expect(find.text('الصورة غير واضحة'), findsOneWidget);
    expect(find.text('ملابس'), findsOneWidget);
    expect(find.text('250 ر.س'), findsOneWidget);
    expect(find.text('أسود، بني'), findsOneWidget);
    expect(find.text('S، M'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    final editButton = find.text('فتح شاشة تعديل المنتج');
    await tester.ensureVisible(editButton);
    await tester.tap(editButton);
    expect(editOpened, isTrue);
  });
}
