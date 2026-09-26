import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/auth/auth_adapters.dart';
import 'package:song_record/features/auth/auth_session.dart';

import 'auth_session_test.dart' as fixtures;

void main() {
  test('서버의 error.code를 읽어 다른 계정 연결 충돌을 안내한다', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      await request.drain<void>();
      request.response.statusCode = 409;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"error":{"code":"IDENTITY_IN_USE"}}');
      await request.response.close();
    });
    try {
      final api = HttpAuthApi(
        Uri.parse('http://127.0.0.1:${server.port}'),
        allowLocalHttp: true,
      );
      await expectLater(
        api.finishLink(fixtures.session(), 'challenge', 'synthetic-proof'),
        throwsA(
          isA<AuthFailure>()
              .having((e) => e.status, 'status', 409)
              .having((e) => e.message, 'message', contains('다른 노래기록 계정')),
        ),
      );
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  test('JSON이 아닌 인증 오류도 HTTP 401을 유지한다', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      await request.drain<void>();
      request.response.statusCode = 401;
      request.response.write('Unauthorized');
      await request.response.close();
    });
    try {
      final api = HttpAuthApi(
        Uri.parse('http://127.0.0.1:${server.port}'),
        allowLocalHttp: true,
      );
      await expectLater(
        api.identities(fixtures.session()),
        throwsA(isA<AuthFailure>().having((e) => e.status, 'status', 401)),
      );
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });
}
