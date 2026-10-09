import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/search/karaoke_http.dart';
import 'package:song_record/features/search/karaoke_search.dart';

void main() {
  final session = AuthSession(
    userId: 'fixture-owner',
    deviceId: 'fixture-device',
    accessToken: 'fixture-access',
    refreshToken: 'fixture-refresh',
    accessExpiresAt: DateTime.utc(2030),
    refreshExpiresAt: DateTime.utc(2030),
  );
  test('authenticated GET uses selected query and rejects KY account matches and foreign brands', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var invalid = false;
    server.listen((request) async {
      expect(request.uri.path, '/v1/karaoke/search');
      expect(request.uri.queryParameters, {
        'brand': 'TJ',
        'kind': 'NUMBER',
        'q': '00123',
      });
      expect(request.headers.value('Authorization'), 'Bearer fixture-access');
      expect(request.headers.value('X-Device-Id'), 'fixture-device');
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'results': [
            {
              'brand': invalid ? 'KY' : 'TJ',
              'number': '00123',
              'title': '원본 (LIVE)',
              'artist': '가수',
              'provider': 'MANANA',
              'source_ref': 'manana:tj:00123',
              'source_token': 's1.fixture',
              'expires_at': '2026-01-02T00:00:00Z',
              'matched_song_id': null,
            },
          ],
        }),
      );
      await request.response.close();
    });
    final api = HttpKaraokeSearch(
      Uri.parse('http://127.0.0.1:${server.port}'),
      allowLocalHttp: true,
    );
    const query = KaraokeQuery(KaraokeBrand.tj, KaraokeKind.number, ' 00123 ');
    expect((await api.search(query, session)).single.number, '00123');
    invalid = true;
    await expectLater(
      api.search(query, session),
      throwsA(isA<KaraokeFailure>()),
    );
  });
  test('provider failure is not empty, redirects do not leak credentials and untrusted origins are rejected', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var redirect = false;
    server.listen((r) async {
      r.response.statusCode = redirect ? 302 : 503;
      r.response.headers.set('Location', 'https://example.invalid/');
      r.response.write('{"error":{"code":"SEARCH_PROVIDER_UNAVAILABLE"}}');
      await r.response.close();
    });
    final api = HttpKaraokeSearch(
      Uri.parse('http://127.0.0.1:${server.port}'),
      allowLocalHttp: true,
    );
    const q = KaraokeQuery(KaraokeBrand.tj, KaraokeKind.title, '곡');
    await expectLater(api.search(q, session), throwsA(isA<KaraokeFailure>()));
    redirect = true;
    await expectLater(api.search(q, session), throwsA(isA<KaraokeFailure>()));
    expect(
      () => HttpKaraokeSearch(
        Uri.parse('http://example.com/'),
        allowLocalHttp: true,
      ),
      throwsArgumentError,
    );
    expect(
      () => HttpKaraokeSearch(Uri.parse('https://user:password@example.com/')),
      throwsArgumentError,
    );
  });
}
