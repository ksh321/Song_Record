import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/features/auth/auth_adapters.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/auth/login_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  const google = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
  const kakao = String.fromEnvironment('KAKAO_NATIVE_APP_KEY');
  if (google.isEmpty || kakao.isEmpty) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(child: Text('로그인 설정이 필요합니다. 앱 실행 설정을 확인해 주세요.')),
          ),
        ),
      ),
    );
    return;
  }
  final stores = AccountStoreManager(environment: config.environment);
  final vault = SecureSessionVault(
    '${config.environment.name}:${config.apiBaseUrl}',
  );
  // Explicit one-run developer test option. Never active in release/staging/prod.
  const resetForVerification = bool.fromEnvironment(
    'RESET_AUTH_FOR_VERIFICATION',
  );
  if (kDebugMode &&
      config.environment == AppEnvironment.dev &&
      resetForVerification) {
    await vault.clear(); // No local database or audio deletion; not server-side logout.
  }
  final controller = AuthController(
    api: HttpAuthApi(
      config.apiBaseUrl,
      allowLocalHttp: kDebugMode && config.environment == AppEnvironment.dev,
    ),
    vault: vault,
    proofs: SdkSocialProofSource(googleClientId: google, kakaoKey: kakao),
    openAccount: (id) async {
      await stores.openAccount(id);
    },
    closeAccount: stores.logout,
  );
  runApp(LoginGate(controller: controller, config: config));
}
