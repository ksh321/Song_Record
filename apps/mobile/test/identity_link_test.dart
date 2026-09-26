import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/auth/identity_link.dart';
import 'package:song_record/features/auth/identity_link_screen.dart';

import 'auth_session_test.dart' as fixtures;

class LinkApi implements IdentityLinkApi {
  final calls = <String>[];
  List<String> providers = ['GOOGLE'];
  bool conflict = false;
  @override
  Future<List<String>> identities(AuthSession session) async => providers;
  @override
  Future<LinkChallenge> beginLink(
    AuthSession session,
    String provider,
    String target,
  ) async {
    calls.add('begin:$provider:$target:${session.userId}');
    return const LinkChallenge('reauth-id', 'reauth-nonce');
  }

  @override
  Future<LinkChallenge> reauthenticate(
    AuthSession session,
    String id,
    String proof,
  ) async {
    calls.add('reauth:$id:$proof');
    return const LinkChallenge('link-id', 'link-nonce');
  }

  @override
  Future<void> finishLink(AuthSession session, String id, String proof) async {
    calls.add('link:$id:$proof');
    if (conflict) throw const AuthFailure('다른 계정에서 사용 중이에요.', status: 409);
    providers = ['GOOGLE', 'KAKAO'];
  }
}

class LinkProofs implements IdentityLinkProofSource {
  final calls = <String>[];
  String? cancelProvider;
  @override
  Future<String> linkProof(String provider, String nonce) async {
    calls.add('$provider:$nonce');
    if (cancelProvider == provider) throw LoginCancelled();
    return '$provider-proof';
  }
}

void main() {
  late AuthController auth;
  late LinkApi api;
  late LinkProofs proofs;
  late IdentityLinkFlow flow;
  late fixtures.Vault vault;
  var opens = 0;
  var closes = 0;
  setUp(() {
    opens = 0;
    closes = 0;
    vault = fixtures.Vault()..value = 'unchanged';
    auth =
        AuthController(
            api: fixtures.Api(),
            vault: vault,
            proofs: fixtures.Proofs(),
            openAccount: (_) async {
              opens++;
            },
            closeAccount: () async {
              closes++;
            },
            now: () => fixtures.time,
          )
          ..session = fixtures.session()
          ..phase = AuthPhase.ready;
    api = LinkApi();
    proofs = LinkProofs();
    flow = IdentityLinkFlow(auth, api, proofs);
  });
  tearDown(() => auth.dispose());
  test('계정 확인 후 새 수단을 연결하고 기존 세션과 로컬 계정을 유지한다', () async {
    final previous = auth.session;
    await flow.link('GOOGLE', 'KAKAO');
    expect(api.calls, [
      'begin:GOOGLE:KAKAO:account-a',
      'reauth:reauth-id:GOOGLE-proof',
      'link:link-id:KAKAO-proof',
    ]);
    expect(proofs.calls, ['GOOGLE:reauth-nonce', 'KAKAO:link-nonce']);
    expect(auth.session, same(previous));
    expect(vault.value, 'unchanged');
    expect(opens, 0);
    expect(closes, 0);
  });
  test('기존 계정 인증 취소는 새 수단 인증을 시작하지 않는다', () async {
    proofs.cancelProvider = 'GOOGLE';
    await expectLater(
      flow.link('GOOGLE', 'KAKAO'),
      throwsA(isA<LoginCancelled>()),
    );
    expect(api.calls.length, 1);
    expect(proofs.calls.length, 1);
  });
  test('새 계정 인증 취소는 연결 API를 호출하지 않고 재시도할 수 있다', () async {
    proofs.cancelProvider = 'KAKAO';
    await expectLater(
      flow.link('GOOGLE', 'KAKAO'),
      throwsA(isA<LoginCancelled>()),
    );
    expect(api.calls.length, 2);
    proofs.cancelProvider = null;
    await flow.link('GOOGLE', 'KAKAO');
    expect(api.providers, contains('KAKAO'));
  });
  test('다른 사용자 계정 충돌을 전달하고 계정을 바꾸지 않는다', () async {
    api.conflict = true;
    await expectLater(
      flow.link('GOOGLE', 'KAKAO'),
      throwsA(isA<AuthFailure>()),
    );
    expect(auth.session!.userId, 'account-a');
    expect(opens, 0);
    expect(closes, 0);
    expect(api.providers, ['GOOGLE']);
  });
  testWidgets('계정 연결 화면은 연결 상태와 취소를 표시한다', (tester) async {
    await tester.pumpWidget(MaterialApp(home: IdentityLinkScreen(flow: flow)));
    await tester.pumpAndSettle();
    expect(find.text('연결됨'), findsOneWidget);
    await tester.tap(find.text('연결'));
    await tester.pumpAndSettle();
    expect(find.text('본인 확인 시작'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(api.calls, isEmpty);
  });
  testWidgets('연결 성공 후 두 수단이 연결됨으로 표시된다', (tester) async {
    await tester.pumpWidget(MaterialApp(home: IdentityLinkScreen(flow: flow)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('연결'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('본인 확인 시작'));
    await tester.pumpAndSettle();
    expect(find.text('연결됨'), findsNWidgets(2));
    expect(find.text('카카오 계정을 연결했어요.'), findsOneWidget);
  });
}
