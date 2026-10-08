import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/uploads/upload_transport.dart';

import '../tool/upload_verification_fixture.dart';

class RealUploadHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('approval sends frozen identity and auth only to API, never follows redirect', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final f = UploadFixture(Directory.systemTemp), auth = await f.session();
      final work = UploadWork(
        uploadFixtureId(10),
        uploadFixtureId(20),
        null,
        null,
        uploadFixtureId(30),
        3,
        'a' * 64,
      );
      var calls = 0;
      final observed = <String, String?>{};
      server.listen((r) async {
        calls++;
        observed['path'] = r.uri.path;
        observed['auth'] = r.headers.value('Authorization');
        observed['operation'] = r.headers.value('Idempotency-Key');
        await r.drain<void>();
        r.response.statusCode = 302;
        r.response.headers.set(
          'Location',
          'http://127.0.0.1:${server.port}/should-not-follow',
        );
        await r.response.close();
      });
      try {
        final transport = HttpUploadTransport(
          Uri.parse('http://127.0.0.1:${server.port}'),
          allowLocalHttp: true,
        );
        final response = await transport.authorize(work, auth, () async {});
        expect(response.status, 302);
        expect(calls, 1);
        expect(observed['path'], '/v1/recordings/${work.recordingId}/uploads');
        expect(observed['auth'], 'Bearer synthetic-only');
        expect(observed['operation'], work.operationId);
      } finally {
        await server.close(force: true);
      }
    }, RealUploadHttp());
  });
  test('PUT refuses credential-bearing, external and plain HTTP addresses before network', () async {
    final transport = HttpUploadTransport(
      Uri.parse('https://api.example.invalid'),
    );
    for (final url in [
      'http://${'a' * 32}.r2.cloudflarestorage.com/x',
      'https://other.example/x',
      'https://secret@${'a' * 32}.r2.cloudflarestorage.com/x',
    ]) {
      await expectLater(
        transport.put(Uri.parse(url), {}, Uint8List.fromList([1]), () async {}),
        throwsFormatException,
      );
    }
  });
}
