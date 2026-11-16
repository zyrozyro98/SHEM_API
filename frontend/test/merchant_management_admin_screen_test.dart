import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/services/admin_service.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/presentation/admin/admin_management_detail_screens.dart';
import 'package:she_m_app/presentation/admin/merchant_management_screen.dart';

void main() {
  test('merchant product date sort works within each availability filter', () {
    final products = [
      {
        'name': 'متاح قديم',
        'available': true,
        'created_at': '2025-01-01T00:00:00Z',
      },
      {
        'name': 'متاح جديد',
        'available': true,
        'created_at': '2025-03-01T00:00:00Z',
      },
      {
        'name': 'غير متاح قديم',
        'available': false,
        'createdAt': '2025-02-01T00:00:00Z',
      },
      {
        'name': 'غير متاح جديد',
        'available': false,
        'createdAt': '2025-04-01T00:00:00Z',
      },
    ];

    for (final availability in ['available', 'unavailable']) {
      final filtered = MerchantManagementScreen.filterProductsForMerchantPanel(
        records: products,
        query: '',
        availability: availability,
      );
      final newest = MerchantManagementScreen.sortProductsForMerchantPanel(
        records: filtered,
      );
      final oldest = MerchantManagementScreen.sortProductsForMerchantPanel(
        records: filtered,
        sortBy: 'oldest',
      );

      expect(newest.first['name'], contains('جديد'));
      expect(oldest.first['name'], contains('قديم'));
    }
  });

  test('merchant product date sort supports submitted and numeric dates', () {
    final products = [
      {
        'id': 'created-old',
        'name': 'قديم',
        'created_at': '2025-01-01T00:00:00Z',
      },
      {
        'id': 'submitted-new',
        'name': 'الأحدث',
        'submitted_at': '2025-03-01T00:00:00Z',
      },
      {
        'id': 'numeric-middle',
        'name': 'متوسط',
        'createdAt':
            DateTime.parse('2025-02-01T00:00:00Z').millisecondsSinceEpoch,
      },
      {'id': 'no-date', 'name': 'بدون تاريخ'},
    ];

    final newest = MerchantManagementScreen.sortProductsForMerchantPanel(
      records: products,
    );
    final oldest = MerchantManagementScreen.sortProductsForMerchantPanel(
      records: products,
      sortBy: 'oldest',
    );

    expect(newest.map((product) => product['id']), [
      'submitted-new',
      'numeric-middle',
      'created-old',
      'no-date',
    ]);
    expect(oldest.map((product) => product['id']), [
      'created-old',
      'numeric-middle',
      'submitted-new',
      'no-date',
    ]);
  });

  testWidgets('loads all merchants and searches across store fields',
      (tester) async {
    final profiles = <String, dynamic>{
      for (var index = 1; index <= 7; index++)
        'merchant-$index': {
          'full_name': 'Owner $index',
          'shop_name': 'Store $index',
          'phone': '71111111$index',
          'shop_category': index == 7 ? 'Bakery' : 'General',
          'role': 'merchant',
          'is_verified': false,
        },
    };
    await tester.pumpWidget(_screenApp(profiles));
    await tester.pumpAndSettle();

    expect(find.text('7'), findsNWidgets(2));
    expect(find.text('Store 1'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Bakery');
    await tester.pumpAndSettle();

    expect(find.text('Store 7'), findsOneWidget);
    expect(find.text('Store 1'), findsNothing);
    expect(find.text('1 متجر'), findsOneWidget);
  });

  testWidgets('admin can open the no-OTP merchant creation form',
      (tester) async {
    final database = _MerchantProfilesDatabase({});
    await tester.pumpWidget(_screenApp(database.profiles, database: database));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('إنشاء حساب تاجر'));
    await tester.pumpAndSettle();

    expect(find.text('إنشاء حساب تاجر'), findsOneWidget);
    expect(find.textContaining('لن يُرسل رمز تحقق'), findsOneWidget);
    expect(find.text('بيانات التاجر'), findsOneWidget);
    expect(find.text('بيانات المتجر'), findsOneWidget);
    expect(find.text('مدينة / منطقة المتجر *'), findsOneWidget);
    expect(find.text('أرقام تواصل إضافية'), findsOneWidget);
    expect(find.text('محافظ استلام المستحقات'), findsOneWidget);
    expect(find.text('كلمة المرور الأولية *'), findsOneWidget);
    expect(find.text('تأكيد كلمة المرور *'), findsOneWidget);
  });

  testWidgets('verification action updates merchant profile', (tester) async {
    final database = _MerchantProfilesDatabase({
      'merchant-1': {
        'full_name': 'Test Owner',
        'shop_name': 'Test Shop',
        'phone': '711111111',
        'role': 'merchant',
        'is_verified': false,
      },
    });
    await tester.pumpWidget(
      _screenApp(database.profiles, database: database),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('إجراءات المتجر'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('توثيق المتجر'));
    await tester.pumpAndSettle();

    expect(database.profiles['merchant-1']['is_verified'], isTrue);
    expect(find.text('موثق'), findsOneWidget);
  });

  testWidgets('tapping a merchant card opens complete store details',
      (tester) async {
    final profiles = <String, dynamic>{
      'merchant-1': {
        'full_name': 'Test Owner',
        'shop_name': 'Test Shop',
        'shop_category': 'Bakery',
        'shop_region': 'Sanaa',
        'shop_wallets': [
          {
            'wallet_name': 'Primary Wallet',
            'account_number': '700000123',
          },
        ],
        'phone': '711111111',
        'role': 'merchant',
        'is_verified': true,
      },
    };
    await tester.pumpWidget(_screenApp(profiles));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Test Shop'));
    await tester.pumpAndSettle();

    expect(find.text('تفاصيل المتجر'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('بيانات المتجر والمحافظ'), findsOneWidget);
    expect(find.text('محافظ استلام المستحقات'), findsOneWidget);
    expect(find.textContaining('Primary Wallet'), findsOneWidget);
    expect(find.textContaining('700000123'), findsOneWidget);
  });

  testWidgets('admin can configure a fixed delivery fee shown to a merchant',
      (tester) async {
    final database = _MerchantProfilesDatabase({
      'merchant-1': {
        'full_name': 'Test Owner',
        'shop_name': 'Test Shop',
        'role': 'merchant',
      },
    });
    await tester.pumpWidget(
      _screenApp(database.profiles, database: database),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('إجراءات المتجر'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تحديد أجرة التوصيل الظاهرة'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '750');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(
      database.profiles['merchant-1']['merchant_display_delivery_fee'],
      750,
    );
    expect(find.textContaining('أجرة التوصيل الظاهرة: 750'), findsOneWidget);

    await tester.tap(find.byTooltip('إجراءات المتجر'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تحديد أجرة التوصيل الظاهرة'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(database.profiles['merchant-1']['merchant_display_delivery_fee'],
        isNull);
    expect(find.textContaining('أجرة التوصيل الظاهرة: 750'), findsNothing);
  });

  testWidgets('admin can configure a fixed delivery fee for all merchants',
      (tester) async {
    final database = _MerchantProfilesDatabase({
      'merchant-1': {
        'full_name': 'Test Owner',
        'shop_name': 'Test Shop',
        'role': 'merchant',
      },
      'merchant-2': {
        'full_name': 'Other Owner',
        'shop_name': 'Other Shop',
        'role': 'merchant',
      },
    });
    await tester.pumpWidget(
      _screenApp(database.profiles, database: database),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('إجراءات المتجر').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تحديد أجرة التوصيل الظاهرة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('جميع التجار'));
    await tester.enterText(find.byType(TextField).last, '900');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(database.pricing['merchant_display_delivery_fee'], 900);
    expect(
      database.profiles.values.every(
        (profile) => profile['merchant_display_delivery_fee'] == null,
      ),
      isTrue,
    );
    expect(find.text('تم تحديث أجرة التوصيل الثابتة لجميع التجار'),
        findsOneWidget);
  });
}

Widget _screenApp(
  Map<String, dynamic> profiles, {
  _MerchantProfilesDatabase? database,
}) {
  return MaterialApp(
    home: MerchantManagementAdminScreen(
      service: AdminService(
        databaseService: database ?? _MerchantProfilesDatabase(profiles),
      ),
    ),
  );
}

class _MerchantProfilesDatabase implements DatabaseService {
  _MerchantProfilesDatabase(this.profiles);

  final Map<String, dynamic> profiles;
  final Map<String, dynamic> pricing = {};

  @override
  Future<Map<String, dynamic>> read(String path) async {
    if (path == 'profiles') return profiles;
    if (path == 'settings/pricing') return pricing;
    return {};
  }

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
  ) async {
    if (path == 'settings/pricing') {
      pricing.addAll(data);
      return data;
    }
    final profileId = path.substring('profiles/'.length);
    profiles[profileId] = {
      ...Map<String, dynamic>.from(profiles[profileId] as Map),
      ...data,
    };
    return data;
  }

  @override
  Future<Map<String, dynamic>?> updateIf(
    String path, {
    required bool Function(Map<String, dynamic> current) condition,
    required Map<String, dynamic> updates,
  }) async =>
      updates;

  @override
  Future<void> delete(String path) async {}
}
