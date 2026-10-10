import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/domain/identifiers.dart';
import 'package:song_record/core/sync/change_feed_receiver.dart';
import 'package:song_record/core/sync/change_feed_transport.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/mutation_transport.dart';
import 'package:song_record/core/sync/snapshot_receiver.dart';
import 'package:song_record/core/sync/snapshot_transport.dart';
import 'package:song_record/core/uploads/upload_dispatcher.dart';
import 'package:song_record/core/uploads/upload_transport.dart';
import 'package:song_record/features/auth/auth_adapters.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/auth/login_gate.dart';
import 'package:song_record/features/sync/change_feed_sync_backend.dart';
import 'package:song_record/features/sync/snapshot_sync_backend.dart';
import 'package:song_record/features/sync/sync_controller.dart';

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
  SyncController? activeSync;
  const accountChannel = MethodChannel('song_record/account');
  late final AuthController controller;
  controller = AuthController(
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
        activeSync?.dispose();
        late final SyncController sync;
        Future<AuthSession> currentSession() async {
          if (!sync.maySend) throw const AuthFailure('전송이 일시 중지됐어요.');
          final session = await controller.validSession();
          if (!sync.maySend) throw const AuthFailure('전송이 일시 중지됐어요.');
          return session;
        }

        sync = SyncController(
          SnapshotSyncBackend(
            receiver: SnapshotReceiver(
              store: store,
              transport: HttpSnapshotTransport(
                config.apiBaseUrl,
                allowLocalHttp:
                    kDebugMode && config.environment == AppEnvironment.dev,
              ),
              newOperationId: () => UuidValue.random().value,
              clock: DateTime.now,
            ),
            session: currentSession,
            outgoing: ChangeFeedSyncBackend(
              allowInitialRestart: true,
              receiver: ChangeFeedReceiver(
                store: store,
                transport: HttpChangeFeedTransport(
                  config.apiBaseUrl,
                  allowLocalHttp:
                      kDebugMode && config.environment == AppEnvironment.dev,
                ),
                isSessionCurrent: (session) =>
                    identical(controller.session, session) &&
                    controller.phase == AuthPhase.ready &&
                    identical(activeStore, store),
                newOperationId: () => UuidValue.random().value,
              ),
              session: currentSession,
              outgoing: RepositorySyncBackend(
                LocalRepository(store),
                HttpMutationTransport(
                  config.apiBaseUrl,
                  allowLocalHttp:
                      kDebugMode && config.environment == AppEnvironment.dev,
                ),
                currentSession,
                uploads: UploadDispatcher(
                  store,
                  HttpUploadTransport(
                    config.apiBaseUrl,
                    allowLocalHttp:
                        kDebugMode && config.environment == AppEnvironment.dev,
                  ),
                  currentSession,
                ),
              ),
            ),
          ),
          conflicts: LocalRepository(store),
        );
        sync.setForeground(
          WidgetsBinding.instance.lifecycleState == null ||
              WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed,
        );
        activeSync = sync;
      } catch (_) {
        activeSync?.dispose();
        activeSync = null;
        activeStore = null;
        await stores.logout();
        rethrow;
      }
    },
    closeAccount: () async {
      activeSync?.dispose();
      activeSync = null;
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
  controller.addListener(() {
    activeSync?.setEnabled(
      controller.phase == AuthPhase.ready && !controller.busy,
    );
  });
  runApp(
    LoginGate(
      controller: controller,
      config: config,
      syncController: () => activeSync,
      localRepository: () =>
          activeStore == null ? null : LocalRepository(activeStore!),
    ),
  );
}
