import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/services/auth_service.dart';

void main() {
  test('saved account accepts epoch expiration values from the API', () {
    final expires = DateTime.now().toUtc().add(const Duration(days: 30));
    final session = SavedAccountSession.fromJson({
      'profile_id': 'customer-1',
      'session_id': 'session-1',
      'session_secret': 'secret',
      'expires_at': expires.millisecondsSinceEpoch,
      'full_name': 'عميل',
      'phone': '+967700000000',
      'role': 'customer',
    });

    expect(session.expiresAt, isA<DateTime>());
    expect(session.expiresAt.isAfter(DateTime.now().toUtc()), isTrue);
    expect(session.profileId, 'customer-1');
  });
}
