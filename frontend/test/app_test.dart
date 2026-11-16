import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/core/constants/app_constants.dart';
import 'package:she_m_app/data/models/user_model.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/main.dart';
import 'package:she_m_app/presentation/admin/admin_dashboard_screen.dart';
import 'package:she_m_app/presentation/admin/admin_management_detail_screens.dart';
import 'package:she_m_app/presentation/admin/merchant_management_screen.dart';
import 'package:she_m_app/presentation/common/app_startup_screen.dart';
import 'package:she_m_app/presentation/common/role_dashboard_router.dart';
import 'package:she_m_app/presentation/auth/profile_setup_screen.dart';
import 'package:she_m_app/presentation/dashboard/customer_dashboard_screen.dart';
import 'package:she_m_app/presentation/dashboard/marketplace_dashboard.dart';
import 'package:she_m_app/presentation/delivery/central_dispatcher_dashboard_screen.dart';

void main() {
  test('firebase config is active and Yemen phone numbers normalize correctly',
      () {
    expect(AppConstants.isFirebaseConfigured, isTrue);
    expect(AppConstants.requirePhoneVerificationOnSignup, isTrue);
    expect(AuthService().normalizePhone('771234567'), '+967771234567');
    expect(AuthService().normalizePhone('0771234567'), '+967771234567');
    expect(AuthService().normalizePhone('00967 771 234 567'), '+967771234567');
    expect(AuthService().normalizePhone('٠٧٧١٢٣٤٥٦٧'), '+967771234567');
  });

  test('auth service rejects invalid Yemen phone before login', () async {
    final result = await AuthService().loginWithPassword(
      phone: '12345',
      password: 'Abc12345',
    );

    expect(result, isFalse);
  });

  test('OTP accepts Arabic numerals for a Yemeni phone number', () async {
    final result = await AuthService().verifyOtp(
      phone: '٠٧٧١٢٣٤٥٦٧',
      otp: '١٢٣٤٥٦',
    );

    expect(result['success'], isFalse);
    expect(result['error'], 'يرجى طلب رمز تحقق لهذا الرقم أولاً');
  });

  test('account registration requires prior phone verification', () async {
    final authService = AuthService();
    final profile = await authService.registerUser(
      fullName: 'Yemeni Customer',
      phone: '0771234567',
      role: 'customer',
      password: 'StrongPass1',
    );

    expect(profile, isNull);
    expect(
      authService.lastError,
      'يرجى التحقق من رقم الهاتف قبل إنشاء الحساب',
    );
  });

  test('auth service loads a missing session cleanly', () async {
    final profile = await AuthService().loadSession();
    expect(profile, isNull);
  });

  test('app defaults to the customer storefront for guest browsing', () {
    expect(const SheMApp().initialScreen, isA<CustomerDashboardScreen>());
  });

  test('product app links resolve query IDs and preserve legacy links', () {
    expect(
      productIdFromAppLink(
        Uri.parse(
          'https://she-m-8d0f5.web.app/product_details?id=product-123',
        ),
      ),
      'product-123',
    );
    expect(
      productIdFromAppLink(
        Uri.parse('shem://product_details?id=product-123'),
      ),
      'product-123',
    );
    expect(
      productIdFromAppLink(Uri.parse('shem://product/product-123')),
      'product-123',
    );
    expect(
      productIdFromAppLink(
        Uri.parse('https://app.example.com/product_details?id=product-123'),
      ),
      isNull,
    );
    expect(
      productIdFromAppLink(
        Uri.parse('https://unrelated.example/product_details?id=product-123'),
      ),
      isNull,
    );
  });

  test('product links are allowed only for customers and guests', () {
    UserModel profileForRole(String role) => UserModel(
          id: 'test-$role',
          fullName: 'Test user',
          phone: '+967771234567',
          role: role,
          isVerified: true,
          createdAt: DateTime(2026),
        );

    expect(canOpenProductLinkForProfile(null), isTrue);
    expect(canOpenProductLinkForProfile(profileForRole('customer')), isTrue);
    expect(canOpenProductLinkForProfile(profileForRole(' Merchant ')), isFalse);
    expect(canOpenProductLinkForProfile(profileForRole('driver')), isFalse);
  });

  test('dashboard routing selects the screen for each supported role', () {
    expect(dashboardForRole('customer'), isA<CustomerDashboardScreen>());
    expect(dashboardForRole('admin'), isA<AdminDashboardScreen>());
    expect(dashboardForRole('merchant'), isA<MerchantManagementScreen>());
    expect(dashboardForRole('driver'), isA<DriverDashboardScreen>());
    expect(
      dashboardForRole('central_dispatcher'),
      isA<CentralDispatcherDashboardScreen>(),
    );
    expect(
        dashboardForRole('manager'), isA<CentralDispatcherDashboardScreen>());
    expect(dashboardForRole(' Merchant '), isA<MerchantManagementScreen>());
  });

  test('restored profiles open dashboards matching their roles', () {
    UserModel profileForRole(String role) => UserModel(
          id: 'test-$role',
          fullName: 'Test user',
          phone: '+967771234567',
          role: role,
          isVerified: true,
          createdAt: DateTime(2026),
        );

    expect(
      initialScreenForProfile(profileForRole('admin')),
      isA<AdminDashboardScreen>(),
    );
    expect(
      initialScreenForProfile(profileForRole('merchant')),
      isA<MerchantManagementScreen>(),
    );
    expect(
      initialScreenForProfile(profileForRole('driver')),
      isA<DriverDashboardScreen>(),
    );
    expect(
      initialScreenForProfile(profileForRole('manager')),
      isA<CentralDispatcherDashboardScreen>(),
    );
  });

  testWidgets('startup screen shows app identity and loading state',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AppStartupScreen()),
    );

    expect(find.text('شيـم'), findsOneWidget);
    expect(find.text('تجربتك المميزة للتسوق'), findsOneWidget);
    expect(find.text('جارٍ تجهيز التطبيق...'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  test('incomplete customer profiles resume setup instead of dashboard', () {
    final incompleteProfiles = [
      UserModel(
        id: 'google-user',
        fullName: 'Google User',
        phone: '',
        role: 'customer',
        isVerified: true,
        createdAt: DateTime(2026),
      ),
      UserModel(
        id: 'google-user-with-phone',
        fullName: 'Google User',
        phone: '+967771234567',
        role: 'customer',
        isVerified: true,
        city: 'صنعاء',
        createdAt: DateTime(2026),
      ),
    ];

    for (final profile in incompleteProfiles) {
      final screen = initialScreenForProfile(profile);
      expect(screen, isA<ProfileSetupScreen>());
      expect((screen as ProfileSetupScreen).existingProfile, same(profile));
    }

    final completeProfile = UserModel(
      id: 'complete-customer',
      fullName: 'Customer',
      phone: '+967771234567',
      role: 'customer',
      isVerified: true,
      city: 'صنعاء',
      address: 'شارع التحرير، جوار الحديقة',
      createdAt: DateTime(2026),
    );
    expect(
      initialScreenForProfile(completeProfile),
      isA<CustomerDashboardScreen>(),
    );
  });

  testWidgets(
      'profile setup screen shows role selection and role-specific fields',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ProfileSetupScreen(phone: '771234567'),
        ),
      ),
    );

    expect(find.text('نوع الحساب'), findsOneWidget);
    expect(find.text('عميل'), findsWidgets);
    expect(find.text('تاجر'), findsOneWidget);
    expect(find.text('سائق'), findsOneWidget);

    await tester.tap(find.text('تاجر'));
    await tester.pumpAndSettle();
    expect(find.text('اسم المتجر'), findsWidgets);

    await tester.tap(find.text('سائق'));
    await tester.pumpAndSettle();
    expect(find.text('نوع المركبة'), findsOneWidget);
    expect(find.text('رقم اللوحة'), findsOneWidget);
  });

  testWidgets('marketplace dashboard renders in constrained width',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: SizedBox(
            width: 360,
            height: 800,
            child: MarketplaceDashboardScreen(),
          ),
        ),
      ),
    );

    expect(find.text('مرحباً بك في She M'), findsOneWidget);
    expect(find.text('الرئيسية'), findsOneWidget);
  });
}
