import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  AccountStore? activeStore;
  const accountChannel = MethodChannel('song_record/account');
  final controller = AuthController(
    api: HttpAuthApi(
      config.apiBaseUrl,
      allowLocalHttp: kDebugMode && config.environment == AppEnvironment.dev,
    ),
    vault: vault,
    proofs: SdkSocialProofSource(googleClientId: google, kakaoKey: kakao),
    openAccount: (id) async {
      final store = await stores.openAccount(id);
      try {
        await accountChannel.invokeMethod<void>('setAccount', {
          'userId': id,
          'environment': config.environment.name,
        });
        activeStore = store;
      } catch (_) {
        activeStore = null;
        await stores.logout();
        rethrow;
      }
    },
    closeAccount: () async {
      await accountChannel.invokeMethod<void>(
        'setAccount',
        const <String, Object?>{'userId': null},
      );
      activeStore = null;
      await stores.logout();
    },
    prepareLogout: () => accountChannel.invokeMethod<void>('prepareLogout'),
    exportRecovery: () async {
      final store = activeStore;
      if (store == null) throw const AuthFailure('로그인이 필요해요.');
      await accountChannel.invokeMethod<void>('prepareLogout');
      final data = await store.recoveryData();
      return await accountChannel.invokeMethod<bool>('exportRecovery', {
            'data': data,
          }) ??
          false;
    },
  );
  runApp(LoginGate(controller: controller, config: config));
}
