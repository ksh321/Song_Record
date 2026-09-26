import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/auth/account_actions.dart';
import 'package:song_record/features/auth/auth_session.dart';

import 'auth_session_test.dart' as fixtures;

class LogoutApi extends fixtures.Api implements AccountActionsApi {
  final List<AuthSession> loggedOut = [];
  Object? logoutError;
  @override
  Future<void> logout(AuthSession session) async {
    if (logoutError != null) throw logoutError!;
    loggedOut.add(session);
  }

  @override
  Future<void> unlinkProvider(AuthSession session, String provider) async {}
}

void main() {
  late LogoutApi api;
  late fixtures.Vault vault;
  late AuthController auth;
  late List<String> opened;
  late int closed;
  setUp(() async {
    api = LogoutApi();
    vault = fixtures.Vault();
    opened = [];
    closed = 0;
    auth = AuthController(
      api: api,
      vault: vault,
      proofs: fixtures.Proofs(),
      now: () => fixtures.time,
      openAccount: (id) async {
        opened.add(id);
      },
      closeAccount: () async {
        closed++;
      },
    );
    await auth.signIn('GOOGLE');
    closed = 0;
  });
  test('로그아웃은 서버 세션을 종료하고 계정 핸들만 닫는다', () async {
    await auth.signOut();
    expect(api.loggedOut, hasLength(1));
    expect(closed, 1);
    expect(auth.session, isNull);
    expect(auth.phase, AuthPhase.signedOut);
    expect(vault.value, isNull);
    await auth.signIn('GOOGLE');
    expect(opened, ['account-a', 'account-a']);
  });
  test('서버 연결 실패는 성공으로 표시하지 않고 로컬 계정을 보존한다', () async {
    api.logoutError = const AuthFailure('offline');
    await expectLater(auth.signOut(), throwsA(isA<AuthFailure>()));
    expect(closed, 0);
    expect(auth.session, isNotNull);
    expect(auth.phase, AuthPhase.ready);
    expect(vault.value, isNotNull);
    expect(auth.busy, isFalse);
  });
  test('갱신 응답을 기다린 후 새 갱신 토큰으로 로그아웃한다', () async {
    auth.session = fixtures.session(minutes: 0);
    api.pending = Completer<AuthSession>();
    final refreshing = auth.validSession();
    await Future<void>.delayed(Duration.zero);
    final logout = auth.signOut();
    api.pending!.complete(fixtures.session(access: 'rotated'));
    await refreshing;
    await logout;
    expect(api.loggedOut.single.refreshToken, 'refresh-rotated');
    expect(auth.session, isNull);
    expect(vault.value, isNull);
  });
  test('로그아웃 표식은 앱 재시작 시 이전 세션을 복구하지 않는다', () async {
    vault.value = jsonEncode({'signedOut': true});
    final restored = AuthController(
      api: api,
      vault: vault,
      proofs: fixtures.Proofs(),
      openAccount: (id) async {
        fail('must not open');
      },
      closeAccount: () async {},
    );
    await restored.restore();
    expect(restored.phase, AuthPhase.signedOut);
    expect(restored.session, isNull);
  });
  test('녹음 중 사전 검사가 실패하면 서버 로그아웃을 호출하지 않는다', () async {
    final recording = AuthController(
      api: api,
      vault: vault,
      proofs: fixtures.Proofs(),
      now: () => fixtures.time,
      openAccount: (_) async {},
      closeAccount: () async {},
      prepareLogout: () async {
        throw const AuthFailure('recording');
      },
    );
    await recording.signIn('GOOGLE');
    await expectLater(recording.signOut(), throwsA(isA<AuthFailure>()));
    expect(api.loggedOut, isEmpty);
    expect(recording.phase, AuthPhase.ready);
  });
}
