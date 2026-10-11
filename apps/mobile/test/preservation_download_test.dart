import 'dart:async';
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
      var wrong = false,
          objectGets = 0,
          redirect = false,
          deleteDuring = false,
          deleted = false;
      final sub = server.listen((r) async {
        if (r.uri.path.startsWith('/v1/')) {
          expect(r.headers.value('Authorization'), 'Bearer synthetic');
          if (deleted) {
            r.response.statusCode = 409;
            r.response.write(
              jsonEncode({
                'error': {'code': 'FILE_NOT_STORED'},
              }),
            );
            await r.response.close();
            return;
          }
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
            if (deleteDuring) deleted = true;
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
        redirect = false;
        deleteDuring = true;
        await expectLater(
          transport.download(object, () async {}),
          throwsA(isA<PreservationFileUnavailable>()),
        );
        expect(objectGets, 3);
        await expectLater(
          transport.validateCurrent(object, () async {}),
          throwsA(isA<PreservationFileUnavailable>()),
        );
        expect(objectGets, 3);
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
  test('stalled current-access request times out and closes its connection', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final arrived = Completer<void>();
    final sub = server.listen((request) {
      if (!arrived.isCompleted) arrived.complete();
      // Deliberately never respond; the client must close on its own deadline.
    });
    final object = PreservationObject(
      owner: preservationId(1),
      recording: preservationId(2),
      generation: preservationId(3),
      checksum: 'a' * 64,
      size: 1,
      revision: 1,
    );
    final auth = AuthSession(
      userId: object.owner,
      deviceId: preservationId(4),
      accessToken: 'synthetic',
      refreshToken: 'synthetic',
      accessExpiresAt: DateTime.now().add(const Duration(hours: 1)),
      refreshExpiresAt: DateTime.now().add(const Duration(days: 1)),
    );
    final transport = HttpPreservationDownload(
      Uri.parse('http://127.0.0.1:${server.port}'),
      () async => auth,
      allowLocalHttp: true,
      timeout: const Duration(milliseconds: 100),
    );
    try {
      await expectLater(
        transport.validateCurrent(object, () async {}),
        throwsA(isA<PreservationNetworkFailure>()),
      );
      expect(arrived.isCompleted, isTrue);
    } finally {
      await sub.cancel();
      await server.close(force: true);
    }
  });
}
