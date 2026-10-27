import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/auth/auth_session.dart';

final time = DateTime.utc(2026, 9, 24);
AuthSession session({
  String user = 'account-a',
  String access = 'access',
  int minutes = 15,
}) => AuthSession(
  userId: user,
  deviceId: 'device',
  accessToken: access,
  refreshToken: 'refresh-$access',
  accessExpiresAt: time.add(Duration(minutes: minutes)),
  refreshExpiresAt: time.add(const Duration(days: 30)),
);

class Vault implements SessionVault {
  String? value;
  bool failWrite = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    if (failWrite) {
      throw StateError('locked');
    }
    this.value = value;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class Proofs implements SocialProofSource {
  bool cancel = false;
  @override
  Future<String> proof(String provider) async {
    if (cancel) {
      throw LoginCancelled();
    }
    return 'proof';
  }
}

class Api implements AuthApi {
  int logins = 0, refreshes = 0;
  AuthSession next = session();
  Object? meError, refreshError;
  String? meUser;
  Completer<AuthSession>? pending;
  @override
  Future<AuthSession> login(String provider, String proof) async {
    logins++;
    return next;
  }

  @override
  Future<String> me(AuthSession s) async {
    if (meError != null) {
      throw meError!;
    }
    return meUser ?? s.userId;
  }

  @override
  Future<AuthSession> refresh(AuthSession s) async {
    refreshes++;
    if (refreshError != null) {
      throw refreshError!;
    }
    return pending?.future ?? Future.value(next);
  }
}

void main() {
  late Vault vault;
  late Api api;
  late Proofs proofs;
  late AuthController auth;
  late List<String> opened;
  late int closed;
  setUp(() {
    vault = Vault();
    api = Api();
    proofs = Proofs();
    opened = [];
    closed = 0;
    auth = AuthController(
      api: api,
      vault: vault,
      proofs: proofs,
      now: () => time,
      openAccount: (id) async {
        opened.add(id);
      },
      closeAccount: () async {
        closed++;
      },
    );
  });
  tearDown(() => auth.dispose());
  test(
    'login blocks a new validation from rotating the previous credentials',
    () async {
      vault.value = jsonEncode(session(minutes: 0).toJson());
      await auth.restore();
      final signingIn = auth.reauthenticate('GOOGLE');
      await expectLater(auth.validSession(), throwsA(isA<AuthFailure>()));
      await signingIn;
      expect(api.refreshes, 0);
      expect(auth.phase, AuthPhase.ready);
      expect(opened, ['account-a']);
      expect(jsonDecode(vault.value!)['accessToken'], api.next.accessToken);
    },
  );
  test('탈퇴 접수 중 갱신 응답이 기존 계정을 다시 활성화하지 않는다', () async {
    auth.phase = AuthPhase.ready;
    auth.session = session(minutes: 0);
    auth.notifyListeners();
    api.pending = Completer<AuthSession>();
    final rotating = auth.validSession();
    final rejected = expectLater(rotating, throwsA(isA<AuthFailure>()));
    await Future<void>.delayed(Duration.zero);
    final accepted = auth.deletionAccepted('account-a');
    expect(auth.phase, AuthPhase.signedOut);
    expect(auth.session, isNull);
    await auth.signIn('GOOGLE');
    expect(api.logins, 0);
    api.pending!.complete(session());
    await rejected;
    await accepted;
    expect(auth.session, isNull);
    expect(jsonDecode(vault.value!), {'signedOut': true});
    expect(closed, 1);
    await auth.deletionAccepted('account-b');
    expect(closed, 1);
  });
  test('account epoch keeps token refresh but invalidates away-and-back account scope', () {
    auth.phase = AuthPhase.ready;
    auth.session = session();
    auth.notifyListeners();
    final start = auth.accountEpoch;
    auth.session = session(access: 'refreshed');
    auth.notifyListeners();
    expect(auth.accountEpoch, start);
    auth.session = session(user: 'account-b');
    auth.notifyListeners();
    auth.session = session();
    auth.notifyListeners();
    expect(auth.accountEpoch, greaterThan(start));
  });
  test('저장된 세션이 없으면 로그인 화면', () async {
    await auth.restore();
    expect(auth.phase, AuthPhase.signedOut);
    expect(api.logins, 0);
  });
  test('로그인 취소는 서버 요청과 저장을 하지 않는다', () async {
    await auth.restore();
    proofs.cancel = true;
    await auth.signIn('GOOGLE');
    expect(api.logins, 0);
    expect(vault.value, isNull);
    expect(opened, isEmpty);
    expect(auth.message, contains('취소'));
    expect(auth.busy, isFalse);
  });
  test('로그인 결과를 저장한 뒤 검증된 계정 저장소를 연다', () async {
    await auth.restore();
    await auth.signIn('GOOGLE');
    expect(auth.phase, AuthPhase.ready);
    expect(opened, ['account-a']);
    expect(
      AuthSession.fromJson(jsonDecode(vault.value!) as Map<String, dynamic>)
          .userId,
      'account-a',
    );
  });
  test('재실행은 보안 저장된 계정을 열고 서버 접근 전에 소유자를 확인한다', () async {
    vault.value = jsonEncode(session().toJson());
    await auth.restore();
    expect(auth.phase, AuthPhase.ready);
    expect(opened, ['account-a']);
    expect(api.refreshes, 0);
  });
  test('연결 실패는 저장된 인증 정보를 보존하고 재시도한다', () async {
    vault.value = jsonEncode(session().toJson());
    api.meError = const AuthFailure('offline');
    await auth.restore();
    expect(auth.phase, AuthPhase.ready);
    expect(vault.value, isNotNull);
    expect(opened, ['account-a']);
    await expectLater(auth.validSession(), throwsA(isA<AuthFailure>()));
    expect(auth.phase, AuthPhase.ready);
    api.meError = null;
    await auth.validSession();
    expect(auth.phase, AuthPhase.ready);
  });
  test('서버 소유자가 다르면 다른 계정 저장소를 열지 않는다', () async {
    vault.value = jsonEncode(session().toJson());
    api.meUser = 'account-b';
    await auth.restore();
    await expectLater(auth.validSession(), throwsA(isA<AuthFailure>()));
    expect(opened, ['account-a']);
    expect(closed, 1);
    expect(vault.value, isNull);
    expect(auth.phase, AuthPhase.signedOut);
  });
  test('동시 갱신은 서버 요청 한 번과 같은 새 토큰을 공유한다', () async {
    auth.session = session(minutes: 0);
    api.pending = Completer<AuthSession>();
    final first = auth.validSession();
    final second = auth.validSession();
    await Future<void>.delayed(Duration.zero);
    expect(api.refreshes, 1);
    expect(
      (jsonDecode(vault.value!) as Map<String, dynamic>)['refreshPending'],
      isTrue,
    );
    api.pending!.complete(session(access: 'rotated'));
    final values = await Future.wait([first, second]);
    expect(values.map((s) => s.accessToken), ['rotated', 'rotated']);
    expect(
      (jsonDecode(vault.value!) as Map<String, dynamic>)['refreshPending'],
      isNull,
    );
  });
  test('갱신 중 종료된 앱은 이전 refresh 토큰을 재전송하지 않는다', () async {
    vault.value = jsonEncode({
      ...session(minutes: 0).toJson(),
      'refreshPending': true,
    });
    await auth.restore();
    expect(api.refreshes, 0);
    expect(auth.phase, AuthPhase.ready);
    expect(auth.serverLoginRequired, isTrue);
    expect(vault.value, isNotNull);
    await expectLater(auth.validSession(), throwsA(isA<AuthFailure>()));
    expect(api.refreshes, 0);
  });
  test('갱신 응답 유실은 서버 재로그인을 요구하지만 로컬 저장소는 유지한다', () async {
    auth.session = session(minutes: 0);
    auth.phase = AuthPhase.ready;
    api.refreshError = const AuthFailure('timeout');
    await expectLater(auth.validSession(), throwsA(isA<AuthFailure>()));
    expect(auth.phase, AuthPhase.ready);
    expect(auth.serverLoginRequired, isTrue);
    expect(vault.value, isNotNull);
    expect(closed, 0);
    await expectLater(auth.validSession(), throwsA(isA<AuthFailure>()));
    expect(api.refreshes, 1);
  });
  test('갱신 응답의 계정 변경을 차단한다', () async {
    auth.session = session(minutes: 0);
    api.next = session(user: 'account-b');
    await expectLater(auth.validSession(), throwsA(isA<AuthFailure>()));
    expect(opened, isEmpty);
    expect(auth.session, isNull);
  });
  test('보안 저장 실패 시 로그인 완료로 표시하지 않는다', () async {
    await auth.restore();
    vault.failWrite = true;
    await auth.signIn('KAKAO');
    expect(auth.phase, AuthPhase.signedOut);
    expect(opened, isEmpty);
    expect(auth.busy, isFalse);
  });
  test('만료된 refresh는 전송하지 않는다', () async {
    final old = session();
    auth.session = AuthSession(
      userId: old.userId,
      deviceId: old.deviceId,
      accessToken: old.accessToken,
      refreshToken: old.refreshToken,
      accessExpiresAt: time,
      refreshExpiresAt: time,
    );
    await expectLater(auth.validSession(), throwsA(isA<AuthFailure>()));
    expect(api.refreshes, 0);
  });
  test('세션 문자열은 토큰을 노출하지 않는다', () {
    expect(session().toString(), isNot(contains('refresh-access')));
  });
  test(
    'offline cold start opens the same local owner without contacting auth',
    () async {
      vault.value = jsonEncode(session(minutes: -10).toJson());
      auth.setNetworkAvailable(false);
      api.meError = StateError('must not call server');
      api.refreshError = StateError('must not rotate offline');
      await auth.restore();
      expect(opened, ['account-a']);
      expect(auth.phase, AuthPhase.ready);
      await expectLater(auth.validSession(), throwsA(isA<AuthFailure>()));
      expect(api.refreshes, 0);
      expect(auth.serverLoginRequired, isFalse);
      expect(jsonDecode(vault.value!)['refreshPending'], isNull);
      api.meError = null;
      api.refreshError = null;
      auth.setNetworkAvailable(true);
      expect((await auth.validSession()).userId, 'account-a');
      expect(api.refreshes, 1);
      expect(opened, ['account-a']);
      expect(closed, 0);
    },
  );
  test(
    'proven unsent refresh preserves credentials for reconnection',
    () async {
      vault.value = jsonEncode(session(minutes: -10).toJson());
      await auth.restore();
      api.refreshError = const AuthFailure(
        'no connection',
        requestNotSent: true,
      );
      await expectLater(auth.validSession(), throwsA(isA<AuthFailure>()));
      expect(auth.phase, AuthPhase.ready);
      expect(auth.serverLoginRequired, isFalse);
      expect(jsonDecode(vault.value!)['refreshPending'], isNull);
      api.refreshError = null;
      expect((await auth.validSession()).userId, 'account-a');
      expect(api.refreshes, 2);
    },
  );
  test('expired and revoked credentials never remove local access or permit server calls', () async {
    vault.value = jsonEncode({
      ...session().toJson(),
      'refreshExpiresAt': time.toIso8601String(),
    });
    await auth.restore();
    expect(auth.phase, AuthPhase.ready);
    expect(auth.serverLoginRequired, isTrue);
    await expectLater(auth.validSession(), throwsA(isA<AuthFailure>()));
    expect(api.refreshes, 0);
    expect(closed, 0);
  });
  test('reauthentication cannot switch the local owner and same owner retains store', () async {
    vault.value = jsonEncode({
      ...session().toJson(),
      'serverLoginRequired': true,
    });
    await auth.restore();
    api.next = session(user: 'account-b');
    await auth.reauthenticate('GOOGLE');
    expect(auth.session!.userId, 'account-a');
    expect(auth.serverLoginRequired, isTrue);
    expect(opened, ['account-a']);
    api.next = session(access: 'renewed');
    await auth.reauthenticate('GOOGLE');
    expect(auth.serverLoginRequired, isFalse);
    expect(auth.session!.accessToken, 'renewed');
    expect(opened, ['account-a']);
    expect(closed, 0);
  });
  test(
    'explicit logout tombstone and malformed vault do not open any owner',
    () async {
      vault.value = jsonEncode({'signedOut': true});
      await auth.restore();
      expect(auth.phase, AuthPhase.signedOut);
      expect(opened, isEmpty);
      vault.value = '{broken';
      await auth.restore();
      expect(auth.phase, AuthPhase.unavailable);
      expect(opened, isEmpty);
    },
  );
}
