import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/sync/change_feed_transport.dart';
import 'package:song_record/features/auth/auth_session.dart';

const id = '11111111-1111-4111-8111-111111111111';
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
  late Uri endpoint;
  late HttpChangeFeedTransport transport;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    endpoint = Uri.parse('http://127.0.0.1:${server.port}');
    transport = HttpChangeFeedTransport(endpoint, allowLocalHttp: true);
  });
  tearDown(() async {
    await server.close(force: true);
  });

  test(
    'fixed GET sends exact cursor, bounded limit and session only to origin',
    () async {
      server.listen((request) async {
        expect(request.method, 'GET');
        expect(request.uri.path, '/v1/sync/changes');
        expect(request.uri.queryParameters, {
          'after_seq': '9223372036854775807',
          'limit': '100',
        });
        expect(request.headers.value('Authorization'), 'Bearer synthetic-test');
        expect(request.headers.value('X-Device-Id'), id);
        expect(request.headers.value('Idempotency-Key'), isNull);
        expect(await request.fold<int>(0, (sum, data) => sum + data.length), 0);
        request.response.write('{}');
        await request.response.close();
      });
      final result = await transport.send(
        ChangeFeedRequest(9223372036854775807, limit: 100),
        session,
        () {},
      );
      expect(result.status, 200);
      expect(result.body, '{}');
      expect(result.toString(), isNot(contains('{}')));
    },
  );

  test(
    'redirect, auth and expired cursor are returned without any follow-up',
    () async {
      var calls = 0;
      const statuses = [302, 401, 403, 409];
      server.listen((request) async {
        request.response.statusCode = statuses[calls++];
        request.response.headers.set('Location', '/must-not-follow');
        request.response.write('{"error":{"code":"CURSOR_EXPIRED"}}');
        await request.response.close();
      });
      for (final status in statuses) {
        expect(
          (await transport.send(ChangeFeedRequest(0), session, () {})).status,
          status,
        );
      }
      expect(calls, 4);
    },
  );

  test('account switch during delayed body refuses stale data', () async {
    final arrived = Completer<void>(), release = Completer<void>();
    var active = true;
    server.listen((request) async {
      arrived.complete();
      await release.future;
      request.response.write('{}');
      await request.response.close();
    });
    final result = transport.send(ChangeFeedRequest(0), session, () {
      if (!active) throw StateError('Account changed');
    });
    final check = expectLater(result, throwsStateError);
    await arrived.future;
    active = false;
    release.complete();
    await check;
  });

  test('initial stale fence sends no request', () async {
    var calls = 0;
    server.listen((request) {
      calls++;
      request.response.close();
    });
    await expectLater(
      transport.send(ChangeFeedRequest(0), session, () {
        throw StateError('Account changed');
      }),
      throwsStateError,
    );
    expect(calls, 0);
  });

  test('one bounded attempt retains status when the body stalls', () async {
    var calls = 0;
    server.listen((request) async {
      calls++;
      request.response.statusCode = 403;
      request.response.write('{');
      await request.response.flush();
    });
    final bounded = HttpChangeFeedTransport(
      endpoint,
      allowLocalHttp: true,
      timeout: const Duration(milliseconds: 250),
    );
    await expectLater(
      bounded.send(ChangeFeedRequest(0), session, () {}),
      throwsA(
        isA<ChangeFeedTransportFailure>().having(
          (e) => e.receivedStatus,
          'status',
          403,
        ),
      ),
    );
    expect(calls, 1);
  });

  test('oversized and invalid UTF8 bodies never return partial data', () async {
    var calls = 0;
    server.listen((request) async {
      request.response.add(calls++ == 0 ? List.filled(9, 65) : [0xff]);
      await request.response.close();
    });
    final bounded = HttpChangeFeedTransport(
      endpoint,
      allowLocalHttp: true,
      maxResponseBytes: 8,
    );
    for (var i = 0; i < 2; i++) {
      await expectLater(
        bounded.send(ChangeFeedRequest(0), session, () {}),
        throwsA(isA<ChangeFeedTransportFailure>()),
      );
    }
    expect(calls, 2);
  });

  test(
    'invalid request and unsafe endpoints are rejected before transport',
    () {
      expect(() => ChangeFeedRequest(-1), throwsArgumentError);
      for (final limit in [0, 101]) {
        expect(() => ChangeFeedRequest(0, limit: limit), throwsArgumentError);
      }
      for (final url in [
        'http://example.com',
        'https://user:pass@example.com',
        'https://example.com/?token=x',
        'https://example.com/#x',
      ]) {
        expect(
          () => HttpChangeFeedTransport(Uri.parse(url), allowLocalHttp: true),
          throwsArgumentError,
        );
      }
      expect(() => HttpChangeFeedTransport(endpoint), throwsArgumentError);
      expect(
        () => HttpChangeFeedTransport(
          endpoint,
          allowLocalHttp: true,
          timeout: Duration.zero,
        ),
        throwsArgumentError,
      );
      expect(
        () => HttpChangeFeedTransport(
          endpoint,
          allowLocalHttp: true,
          maxResponseBytes: 0,
        ),
        throwsArgumentError,
      );
    },
  );
}
