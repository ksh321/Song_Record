import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/audio/playback_ticket.dart';
import 'package:song_record/core/files/recording_download.dart';

import '../tool/local_preservation_fixture.dart';

void main() {
  final owner = preservationId(1), id = preservationId(2);
  final bytes = Uint8List.fromList([1, 2, 3, 4]);
  test(
    'object HTTP refuses redirects and API credentials, checks exact size',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var mode = 0;
      server.listen((r) async {
        expect(r.headers.value('Authorization'), isNull);
        expect(r.headers.value('X-Device-Id'), isNull);
        if (mode == 1) {
          r.response.statusCode = 302;
          r.response.headers.set('Location', '/other');
        } else {
          r.response.add(mode == 2 ? [1, 2] : bytes);
        }
        await r.response.close();
      });
      final ticket = PlaybackTicket(
        owner: owner,
        recording: id,
        generation: preservationId(3),
        checksum: sha256.convert(bytes).toString(),
        size: 4,
        revision: 1,
        url: Uri.parse('http://127.0.0.1:${server.port}/audio'),
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
        allowLocalHttp: true,
      );
      try {
        expect(
          await const HttpSignedAudioDownload().fetch(ticket, () async {}),
          bytes,
        );
        mode = 1;
        await expectLater(
          const HttpSignedAudioDownload().fetch(ticket, () async {}),
          throwsStateError,
        );
        mode = 2;
        await expectLater(
          const HttpSignedAudioDownload().fetch(ticket, () async {}),
          throwsStateError,
        );
      } finally {
        await server.close(force: true);
      }
    },
  );
}
