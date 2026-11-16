import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:she_m_app/data/services/account_deletion_service.dart';

void main() {
  const profileId = 'customer-1';
  const phone = '+967771234567';
  const password = 'correct horse';

  test('reports an unpublished deletion route instead of a connection error',
      () async {
    final service = AccountDeletionService(
      baseUrl: 'https://api.example.test',
      client: MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/accounts/$profileId');
        return http.Response(
          '<html><body>Cannot DELETE</body></html>',
          404,
          headers: {'content-type': 'text/html'},
        );
      }),
    );

    await expectLater(
      service.deleteAccount(
        profileId: profileId,
        requesterPhone: phone,
        password: password,
      ),
      throwsA(
        isA<AccountDeletionException>().having(
          (error) => error.message,
          'message',
          contains('404'),
        ),
      ),
    );
  });

  test('accepts a successful account deletion response', () async {
    final service = AccountDeletionService(
      baseUrl: 'https://api.example.test',
      client: MockClient((_) async => http.Response('{"success":true}', 200)),
    );

    await service.deleteAccount(
      profileId: profileId,
      requesterPhone: phone,
      password: password,
    );
  });
}
