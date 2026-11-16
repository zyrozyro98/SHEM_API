import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:she_m_app/data/services/backend_warmup_service.dart';

void main() {
  test('warm-up retries a cold response and caches a successful probe',
      () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.method, 'GET');
      expect(request.url.path, '/');
      return http.Response('', requests == 1 ? 503 : 200);
    });
    final service = BackendWarmupService(
      client: client,
      baseUrl: 'https://api.example.test',
      retryDelay: Duration.zero,
    );

    expect(await service.ensureReady(), isTrue);
    expect(await service.ensureReady(), isTrue);
    expect(requests, 2);

    client.close();
  });
}
