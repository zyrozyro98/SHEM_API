class AppConstants {
  static const bool isFirebaseConfigured = true;
  static const bool requirePhoneVerificationOnSignup = true;
  static const String firebaseDatabaseUrl =
      'https://she-m-8d0f5-default-rtdb.asia-southeast1.firebasedatabase.app';
  static const String apiBaseUrl = firebaseDatabaseUrl;
  static const String mediaApiBaseUrl = String.fromEnvironment(
    'SHEM_MEDIA_API_BASE_URL',
    defaultValue: 'https://shem-api.onrender.com',
  );

  static const String authEndpoint = '/auth/v1';
  static const String productsEndpoint = '/products';
  static const String ordersEndpoint = '/orders';
  static const String paymentsEndpoint = '/payments';
  static const String mediaEndpoint = '/media';

  static const List<String> supportedRoles = [
    'customer',
    'merchant',
    'driver',
    'admin'
  ];

  static const List<String> orderStatuses = [
    'new',
    'pending_payment',
    'awaiting_confirmation',
    'confirmed',
    'preparing',
    'shipped',
    'delivered',
    'cancelled',
  ];

  static const List<String> paymentMethods = [
    'cash_on_delivery',
    'bank_transfer',
    'wallet',
  ];

  static bool isYemenPhoneValid(String phone) {
    final normalized = phone.trim();
    if (normalized.isEmpty) return false;

    final regex = RegExp(r'^(\+967|967|0)?[0-9]{9}$');
    return regex.hasMatch(normalized);
  }

  static bool isStrongPassword(String password) {
    final value = password.trim();
    return value.length >= 6;
  }
}
