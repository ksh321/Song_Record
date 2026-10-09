import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/files/local_preservation.dart';
import 'package:song_record/core/files/preservation_download.dart';
import 'package:song_record/features/auth/auth_session.dart';

import '../tool/local_preservation_fixture.dart';

void main() {
  test(
    'authenticated ticket and bounded object GET never forward API credentials',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final base = Uri.parse('http://127.0.0.1:${server.port}');
      final bytes = Uint8List.fromList(utf8.encode('synthetic-download'));
      final object = PreservationObject(
        owner: preservationId(1),
        recording: preservationId(2),
        generation: preservationId(3),
        checksum: sha256.convert(bytes).toString(),
        size: bytes.length,
        revision: 2,
      );
      final auth = AuthSession(
        userId: object.owner,
        deviceId: preservationId(4),
        accessToken: 'synthetic',
        refreshToken: 'synthetic',
        accessExpiresAt: DateTime.now().add(const Duration(hours: 1)),
        refreshExpiresAt: DateTime.now().add(const Duration(days: 1)),
      );
      var wrong = false, objectGets = 0, redirect = false;
      final sub = server.listen((r) async {
        if (r.uri.path.startsWith('/v1/')) {
          expect(r.headers.value('Authorization'), 'Bearer synthetic');
          r.response.headers.contentType = ContentType.json;
          r.response.write(
            jsonEncode({
              'user_id': object.owner,
              'recording_id': object.recording,
              'generation': wrong ? preservationId(9) : object.generation,
              'sha256': object.checksum,
              'size_bytes': object.size,
              'cloud_revision': object.revision,
              'expires_at': DateTime.now()
                  .add(const Duration(minutes: 5))
                  .toUtc()
                  .toIso8601String(),
              'url': base.resolve('/object').toString(),
            }),
          );
        } else {
          objectGets++;
          expect(r.headers.value('Authorization'), isNull);
          expect(r.headers.value('X-Device-Id'), isNull);
          if (redirect) {
            r.response.statusCode = 302;
            r.response.headers.set(
              'Location',
              base.resolve('/other').toString(),
            );
          } else {
            r.response.add(bytes);
          }
        }
        await r.response.close();
      });
      try {
        final transport = HttpPreservationDownload(
          base,
          () async => auth,
          allowLocalHttp: true,
        );
        expect(await transport.download(object, () async {}), bytes);
        wrong = true;
        await expectLater(
          transport.download(object, () async {}),
          throwsA(isA<PreservationNetworkFailure>()),
        );
        expect(objectGets, 1);
        wrong = false;
        redirect = true;
        await expectLater(
          transport.download(object, () async {}),
          throwsA(isA<PreservationNetworkFailure>()),
        );
        expect(objectGets, 2);
      } finally {
        await sub.cancel();
        await server.close(force: true);
      }
    },
  );
  test('production transport rejects cleartext endpoint', () {
    expect(
      () => HttpPreservationDownload(
        Uri.parse('http://127.0.0.1'),
        () async => throw StateError('unused'),
      ),
      throwsArgumentError,
    );
  });
}
