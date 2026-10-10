import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/charts/popular_chart.dart';
import 'package:song_record/features/charts/popular_chart_http.dart';
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
  test('actual local HTTP uses only published endpoint and current session headers', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final scope = const ChartScope(KaraokeBrand.tj, ChartPeriod.weekly);
    final request = server.first.then((r) async {
      expect(r.uri.path, '/v1/charts/popular');
      expect(r.uri.queryParameters, {'brand': 'TJ', 'period': 'WEEKLY'});
      expect(r.headers.value('Authorization'), 'Bearer fixture-access');
      expect(r.headers.value('X-Device-Id'), 'fixture-device');
      r.response.headers.contentType = ContentType.json;
      r.response.write(
        jsonEncode({
          'brand': 'TJ',
          'period': 'WEEKLY',
          'provider': 'MANANA',
          'source_url': scope.sourceUrl,
          'fetched_at': '2026-10-01T00:00:00Z',
          'revision': 2,
          'stale': true,
          'items': [
            {
              'position': 1,
              'number': '00123',
              'title': '원본',
              'artist': '가수',
              'source_token': 's1.fixture',
            },
          ],
        }),
      );
      await r.response.close();
    });
    final chart = await HttpPopularChart(
      Uri.parse('http://127.0.0.1:${server.port}'),
      allowLocalHttp: true,
    ).read(scope, session);
    await request;
    expect(chart.stale, isTrue);
    expect(chart.items.single.number, '00123');
  });
  test(
    '503 keeps no-source distinct and external plaintext is rejected',
    () async {
      expect(
        () => HttpPopularChart(
          Uri.parse('http://example.com'),
          allowLocalHttp: true,
        ),
        throwsArgumentError,
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final request = server.first.then((r) async {
        r.response.statusCode = 503;
        r.response.headers.contentType = ContentType.json;
        r.response.write(
          jsonEncode({
            'error': {'code': 'CHART_SOURCE_UNAVAILABLE'},
          }),
        );
        await r.response.close();
      });
      await expectLater(
        HttpPopularChart(
          Uri.parse('http://127.0.0.1:${server.port}'),
          allowLocalHttp: true,
        ).read(const ChartScope(KaraokeBrand.ky, ChartPeriod.daily), session),
        throwsA(
          isA<ChartFailure>().having(
            (e) => e.code,
            'code',
            'CHART_SOURCE_UNAVAILABLE',
          ),
        ),
      );
      await request;
    },
  );
}
