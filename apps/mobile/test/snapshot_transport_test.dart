import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/sync/snapshot_transport.dart';
import 'package:song_record/features/auth/auth_session.dart';

const id = '00000000-0000-4000-8000-000000000001';
final session = AuthSession(
  userId: id,
  deviceId: id,
  accessToken: 'synthetic-test',
  refreshToken: 'synthetic-unused',
  accessExpiresAt: DateTime.utc(2030),
  refreshExpiresAt: DateTime.utc(2030),
);

void main() {
  late HttpServer server;
  late HttpSnapshotTransport transport;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    transport = HttpSnapshotTransport(
      Uri.parse('http://127.0.0.1:${server.port}'),
      allowLocalHttp: true,
    );
  });
  tearDown(() async {
    await server.close(force: true);
  });

  test(
    'fixed create route preserves operation ID and schema on retry',
    () async {
      final received = <String>[];
      server.listen((request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, '/v1/sync/snapshots');
        expect(request.headers.value('Authorization'), 'Bearer synthetic-test');
        expect(request.headers.value('X-Device-Id'), id);
        received.add(request.headers.value('Idempotency-Key')!);
        expect(await utf8.decoder.bind(request).join(), '{"schema_version":1}');
        request.response.statusCode = 202;
        request.response.write('{}');
        await request.response.close();
      });
      final request = SnapshotHttpRequest.create(id);
      expect((await transport.send(request, session, () {})).status, 202);
      expect((await transport.send(request, session, () {})).status, 202);
      expect(received, [id, id]);
    },
  );

  test(
    'redirect and authentication failure each make only one attempt',
    () async {
      var calls = 0;
      server.listen((request) async {
        calls++;
        request.response.statusCode = [302, 401, 403][calls - 1];
        request.response.headers.set('Location', '/unexpected');
        await request.response.close();
      });
      expect(
        (await transport.send(
          SnapshotHttpRequest.status(id),
          session,
          () {},
        )).status,
        302,
      );
      expect(
        (await transport.send(
          SnapshotHttpRequest.status(id),
          session,
          () {},
        )).status,
        401,
      );
      expect(
        (await transport.send(
          SnapshotHttpRequest.status(id),
          session,
          () {},
        )).status,
        403,
      );
      expect(calls, 3);
    },
  );

  test('timeout makes one attempt and propagates received status', () async {
    var calls = 0;
    server.listen((request) async {
      calls++;
      request.response.statusCode = 202;
      request.response.write('{');
      await request.response.flush();
    });
    final bounded = HttpSnapshotTransport(
      Uri.parse('http://127.0.0.1:${server.port}'),
      allowLocalHttp: true,
      timeout: const Duration(milliseconds: 250),
    );
    await expectLater(
      bounded.send(SnapshotHttpRequest.create(id), session, () {}),
      throwsA(
        isA<SnapshotTransportFailure>().having((e) => e.status, 'status', 202),
      ),
    );
    expect(calls, 1);
  });

  test('account fence after delayed response rejects stale result', () async {
    final arrived = Completer<void>();
    final release = Completer<void>();
    var active = true;
    server.listen((request) async {
      arrived.complete();
      await release.future;
      request.response.write('{}');
      await request.response.close();
    });
    final result = transport.send(SnapshotHttpRequest.status(id), session, () {
      if (!active) throw StateError('Account changed');
    });
    final assertion = expectLater(result, throwsStateError);
    await arrived.future;
    active = false;
    release.complete();
    await assertion;
  });

  test(
    'page encodes cursor and rejects arbitrary routes and unsafe endpoints',
    () async {
      server.listen((request) async {
        expect(request.uri.queryParameters, {
          'entity': 'SONG',
          'limit': '50',
          'cursor': 'sp1.a+b/=',
        });
        expect(request.headers.value('Idempotency-Key'), isNull);
        request.response.write('{}');
        await request.response.close();
      });
      await transport.send(
        SnapshotHttpRequest.page(id, 'SONG', cursor: 'sp1.a+b/='),
        session,
        () {},
      );
      expect(
        () => SnapshotHttpRequest.status('https://example.com'),
        throwsFormatException,
      );
      expect(
        () => SnapshotHttpRequest.page(id, 'INVALID'),
        throwsArgumentError,
      );
      expect(
        () => HttpSnapshotTransport(
          Uri.parse('http://example.com'),
          allowLocalHttp: true,
        ),
        throwsArgumentError,
      );
      expect(
        () => HttpSnapshotTransport(Uri.parse('https://user:pass@example.com')),
        throwsArgumentError,
      );
    },
  );
}
