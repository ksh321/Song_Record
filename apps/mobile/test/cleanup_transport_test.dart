import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/files/cleanup_confirmation.dart';
import 'package:song_record/features/auth/auth_session.dart';

import '../tool/local_preservation_fixture.dart';

void main() {
  test(
    'terminal GET requires matching owner, token, recording and generation',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final owner = preservationId(1),
          id = preservationId(2),
          gen = preservationId(3),
          key = preservationId(4);
      final expiry = DateTime.now().toUtc().add(const Duration(minutes: 15));
      final auth = AuthSession(
        userId: owner,
        deviceId: preservationId(5),
        accessToken: 'synthetic',
        refreshToken: 'synthetic',
        accessExpiresAt: expiry,
        refreshExpiresAt: expiry,
      );
      String state = 'DELETING';
      var wrong = false;
      final sub = server.listen((r) async {
        expect(r.method, 'GET');
        expect(r.uri.query, isEmpty);
        expect(r.uri.path, '/v1/recordings/$id/retention');
        expect(r.headers.value('Authorization'), 'Bearer synthetic');
        expect(r.headers.value('X-Cleanup-Confirmation-Id'), key);
        expect(r.headers.value('Idempotency-Key'), isNull);
        r.response.headers.contentType = ContentType.json;
        r.response.write(
          jsonEncode({
            'recording_id': id,
            'cleanup_confirmation': {
              'token': key,
              'user_id': owner,
              'recording_id': id,
              'generation': wrong ? preservationId(9) : gen,
              'state': state,
            },
          }),
        );
        await r.response.close();
      });
      try {
        final client = HttpCleanupTransport(
          Uri.parse('http://127.0.0.1:${server.port}'),
          () async => auth,
          allowLocalHttp: true,
        );
        final token = CleanupToken.fromWire({
          'token': key,
          'user_id': owner,
          'recording_id': id,
          'generation': gen,
          'sha256': 'a' * 64,
          'size_bytes': 12,
          'cloud_revision': 3,
          'expires_at': expiry.toIso8601String(),
        });
        expect(await client.terminal(token, () async {}), isNull);
        for (final terminal in ['SUCCEEDED', 'CANCELLED', 'EXPIRED']) {
          state = terminal;
          expect(await client.terminal(token, () async {}), terminal);
        }
        wrong = true;
        await expectLater(
          client.terminal(token, () async {}),
          throwsA(isA<CleanupNetworkFailure>()),
        );
        wrong = false;
        state = 'UNKNOWN';
        await expectLater(
          client.terminal(token, () async {}),
          throwsA(isA<CleanupNetworkFailure>()),
        );
      } finally {
        await sub.cancel();
        await server.close(force: true);
      }
    },
  );

  test('cleanup preview and confirmation use authenticated exact token wire identities', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    final owner = preservationId(1),
        recording = preservationId(2),
        device = preservationId(3),
        key = preservationId(4);
    final expiry = DateTime.now().toUtc().add(const Duration(minutes: 15));
    final auth = AuthSession(
      userId: owner,
      deviceId: device,
      accessToken: 'synthetic',
      refreshToken: 'synthetic',
      accessExpiresAt: expiry,
      refreshExpiresAt: expiry,
    );
    var mismatch = false;
    final sub = server.listen((r) async {
      expect(r.headers.value('Authorization'), 'Bearer synthetic');
      expect(r.headers.value('X-Device-Id'), device);
      expect(r.headers.value('Idempotency-Key'), isNotNull);
      final body = jsonDecode(await utf8.decoder.bind(r).join()) as Map;
      r.response.headers.contentType = ContentType.json;
      if (r.uri.path.endsWith('/cleanup-previews')) {
        expect(body['recording_ids'], [recording]);
        r.response.write(
          jsonEncode({
            'items': [
              {
                'token': key,
                'user_id': owner,
                'recording_id': recording,
                'generation': preservationId(5),
                'sha256': 'a' * 64,
                'size_bytes': 12,
                'cloud_revision': 3,
                'expires_at': expiry.toIso8601String(),
                'hold_reasons': ['WAITING_LOCAL_CONFIRM'],
              },
            ],
          }),
        );
      } else {
        expect(body, {
          'token': key,
          'mode': 'LOCAL_VERIFIED',
          'device_id': device,
          'sha256': 'a' * 64,
        });
        r.response.write(
          jsonEncode({
            'token': mismatch ? preservationId(9) : key,
            'state': 'CONFIRMED',
            'expires_at': expiry.toIso8601String(),
          }),
        );
      }
      await r.response.close();
    });
    try {
      final transport = HttpCleanupTransport(
        base,
        () async => auth,
        allowLocalHttp: true,
      );
      final token = await transport.preview(
        owner,
        recording,
        preservationId(6),
        () async {},
      );
      await transport.confirmLocal(token, preservationId(7), () async {});
      mismatch = true;
      await expectLater(
        transport.confirmLocal(token, preservationId(8), () async {}),
        throwsA(isA<CleanupNetworkFailure>()),
      );
    } finally {
      await sub.cancel();
      await server.close(force: true);
    }
  });
}
