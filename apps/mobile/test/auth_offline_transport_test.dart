import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/auth/auth_adapters.dart';
import 'package:song_record/features/auth/auth_session.dart';

import 'auth_session_test.dart' as fixtures;

void main() {
  test(
    'connection refusal is proven unsent and does not invalidate local login',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final api = HttpAuthApi(
        Uri.parse('http://127.0.0.1:${server.port}'),
        allowLocalHttp: true,
      );
      await server.close(force: true);
      await expectLater(
        api.refresh(fixtures.session()),
        throwsA(
          isA<AuthFailure>().having(
            (e) => e.requestNotSent,
            'no request sent',
            isTrue,
          ),
        ),
      );
    },
  );

  test('lost refresh response preserves local use without replaying consumed token', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var refreshes = 0;
    server.listen((request) async {
      await request.drain<void>();
      if (request.uri.path == '/v1/auth/refresh') {
        refreshes++;
        final socket = await request.response.detachSocket();
        socket.destroy();
      } else {
        request.response.statusCode = 404;
        await request.response.close();
      }
    });
    final vault = fixtures.Vault()
      ..value = jsonEncode(fixtures.session(minutes: -1).toJson());
    final auth = AuthController(
      api: HttpAuthApi(
        Uri.parse('http://127.0.0.1:${server.port}'),
        allowLocalHttp: true,
      ),
      vault: vault,
      proofs: fixtures.Proofs(),
      now: () => fixtures.time,
      openAccount: (_) async {},
      closeAccount: () async {},
    );
    addTearDown(auth.dispose);
    await auth.restore();
    await expectLater(auth.validSession(), throwsA(isA<AuthFailure>()));
    expect(auth.phase, AuthPhase.ready);
    expect(auth.serverLoginRequired, isTrue);
    expect(refreshes, 1);
    await auth.restore();
    await expectLater(auth.validSession(), throwsA(isA<AuthFailure>()));
    expect(refreshes, 1);
  });
}
