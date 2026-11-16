import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/models/user_model.dart';
import 'package:she_m_app/presentation/common/delivery_address_book.dart';

void main() {
  test('delivery addresses round-trip and retain the selected address', () {
    final profile = UserModel.fromJson({
      'id': 'customer-1',
      'full_name': 'عميل',
      'phone': '+967700000000',
      'role': 'customer',
      'is_verified': true,
      'delivery_addresses': [
        {
          'id': 'home',
          'label': 'المنزل',
          'city': 'صنعاء',
          'address': 'شارع التحرير',
        },
        {
          'id': 'work',
          'label': 'العمل',
          'city': 'صنعاء',
          'address': 'شارع الزبيري',
          'location_coordinates': '15.3694, 44.1910',
        },
      ],
      'selected_delivery_address_id': 'work',
      'created_at': '2026-01-01T00:00:00Z',
    });

    expect(profile.savedDeliveryAddresses, hasLength(2));
    expect(profile.selectedDeliveryAddress?.id, 'work');
    final restored = UserModel.fromJson(profile.toJson());
    expect(restored.selectedDeliveryAddress?.address, 'شارع الزبيري');
    expect(
      restored.selectedDeliveryAddress?.locationCoordinates,
      '15.3694, 44.1910',
    );
  });

  test('legacy profile address remains selectable for migration', () {
    final profile = UserModel.fromJson({
      'city': 'عدن',
      'address': 'المنصورة',
    });

    expect(profile.savedDeliveryAddresses.single.id, 'legacy');
    expect(profile.selectedDeliveryAddress?.city, 'عدن');
  });

  testWidgets('address book selects and adds addresses', (tester) async {
    String? selectedId;
    var addTapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeliveryAddressBook(
            addresses: const [
              DeliveryAddress(
                id: 'home',
                label: 'المنزل',
                city: 'صنعاء',
                address: 'شارع التحرير',
              ),
            ],
            selectedId: null,
            onSelect: (id) => selectedId = id,
            onAdd: () => addTapped = true,
            onEdit: (_) {},
            onDelete: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('المنزل'));
    await tester.pump();
    expect(selectedId, 'home');

    await tester.tap(find.text('إضافة عنوان جديد'));
    expect(addTapped, isTrue);
  });

  testWidgets('address editor keeps coordinates separate from address text',
      (tester) async {
    DeliveryAddress? savedAddress;
    const initialAddress = DeliveryAddress(
      id: 'home',
      label: 'المنزل',
      city: 'صنعاء',
      address: 'شارع التحرير',
      locationCoordinates: '15.3694, 44.1910',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                savedAddress = await showDeliveryAddressEditor(
                  context,
                  initial: initialAddress,
                );
              },
              child: const Text('تعديل'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('تعديل'));
    await tester.pumpAndSettle();
    expect(find.text('15.3694, 44.1910'), findsOneWidget);
    expect(find.text('شارع التحرير'), findsOneWidget);

    await tester.tap(find.text('حفظ العنوان'));
    await tester.pumpAndSettle();
    expect(savedAddress?.address, 'شارع التحرير');
    expect(savedAddress?.locationCoordinates, '15.3694, 44.1910');
  });
}
