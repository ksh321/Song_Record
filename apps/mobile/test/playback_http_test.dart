import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/audio/playback_http.dart';
import 'package:song_record/features/auth/auth_session.dart';

import '../tool/local_preservation_fixture.dart';

void main() {
  test('POST ticket binds owner and recording, bounds response, never follows redirects', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    var mode = 'normal', calls = 0, other = 0;
    final owner = preservationId(1), id = preservationId(2);
    final auth = AuthSession(
      userId: owner,
      deviceId: preservationId(4),
      accessToken: 'synthetic',
      refreshToken: 'synthetic',
      accessExpiresAt: DateTime.now().add(const Duration(hours: 1)),
      refreshExpiresAt: DateTime.now().add(const Duration(days: 1)),
    );
    final listener = server.listen((request) async {
      if (request.uri.path == '/other') {
        other++;
      } else {
        calls++;
        expect(request.method, 'POST');
        expect(request.uri.path, '/v1/recordings/$id/playback-url');
        expect(request.headers.value('Authorization'), 'Bearer synthetic');
        expect(request.headers.value('X-Device-Id'), auth.deviceId);
        if (mode == 'redirect') {
          request.response.statusCode = 302;
          request.response.headers.set(
            'Location',
            base.resolve('/other').toString(),
          );
        } else if (mode == 'large') {
          request.response.write('x' * 16385);
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'user_id': mode == 'foreign' ? preservationId(9) : owner,
              'recording_id': id,
              'generation': preservationId(3),
              'sha256': 'a' * 64,
              'size_bytes': 12,
              'cloud_revision': 1,
              'url': 'https://fixture.r2.cloudflarestorage.com/audio?signature=synthetic',
              'expires_at': DateTime.now()
                  .add(const Duration(minutes: 5))
                  .toUtc()
                  .toIso8601String(),
            }),
          );
        }
      }
      await request.response.close();
    });
    try {
      final transport = HttpPlaybackUrls(
        base,
        () async => auth,
        allowLocalHttp: true,
      );
      final ticket = await transport.issue(id, () async {});
      expect(ticket.owner, owner);
      expect(ticket.recording, id);
      for (final next in ['foreign', 'redirect', 'large']) {
        mode = next;
        await expectLater(
          transport.issue(id, () async {}),
          throwsA(isA<PlaybackRequestFailure>()),
        );
      }
      expect(calls, 4);
      expect(other, 0);
      await expectLater(
        transport.issue(id, () async {
          throw StateError('account switched');
        }),
        throwsA(isA<PlaybackRequestFailure>()),
      );
      expect(calls, 4);
    } finally {
      await listener.cancel();
      await server.close(force: true);
    }
  });
  test('production transport rejects cleartext and embedded credentials', () {
    for (final base in [
      'http://127.0.0.1',
      'https://user:password@example.com',
      'https://example.com?query=1',
    ]) {
      expect(
        () => HttpPlaybackUrls(
          Uri.parse(base),
          () async => throw StateError('unused'),
        ),
        throwsArgumentError,
      );
    }
  });
}
