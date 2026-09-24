import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/auth/login_gate.dart';

import 'auth_session_test.dart' as fixtures;

void main() {
  testWidgets('작은 화면 큰 글꼴에서 로그인 취소 후 다시 누를 수 있다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final proof = fixtures.Proofs()..cancel = true;
    final api = fixtures.Api();
    final auth = AuthController(
      api: api,
      vault: fixtures.Vault(),
      proofs: proof,
      openAccount: (_) async {},
      closeAccount: () async {},
    );
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      LoginGate(
        controller: auth,
        config: AppConfig(
          environment: AppEnvironment.dev,
          apiBaseUrl: Uri.parse('http://127.0.0.1:8080'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final google = find.widgetWithText(FilledButton, 'Google로 계속하기');
    await tester.ensureVisible(google);
    await tester.tap(google);
    await tester.pumpAndSettle();
    expect(find.text('로그인을 취소했어요.'), findsOneWidget);
    expect(api.logins, 0);
    final kakao = find.widgetWithText(FilledButton, '카카오로 계속하기');
    await tester.ensureVisible(kakao);
    expect(tester.widget<FilledButton>(kakao).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
