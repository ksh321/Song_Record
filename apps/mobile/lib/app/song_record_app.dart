import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:song_record/app/app_shell.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/core/theme/app_tokens.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/auth/identity_link.dart';
import 'package:song_record/features/charts/popular_chart.dart';
import 'package:song_record/features/charts/popular_chart_http.dart';
import 'package:song_record/features/charts/popular_chart_screen.dart';
import 'package:song_record/features/health/health_screen.dart';
import 'package:song_record/features/recorder/recorder_gateway.dart';
import 'package:song_record/features/search/karaoke_http.dart';
import 'package:song_record/features/search/karaoke_search.dart';
import 'package:song_record/features/search/karaoke_search_screen.dart';
import 'package:song_record/features/search/song_registration.dart';
import 'package:song_record/features/settings/settings_screen.dart';
import 'package:song_record/features/songs/my_song.dart';
import 'package:song_record/features/songs/my_song_detail.dart';
import 'package:song_record/features/songs/my_songs_screen.dart';
import 'package:song_record/features/sync/sync_controller.dart';
import 'package:song_record/network/health_client.dart';
import 'package:song_record/routing/app_routes.dart';

class SongRecordApp extends StatelessWidget {
  const SongRecordApp({
    required this.config,
    this.healthLoader,
    this.identityLink,
    this.authController,
    this.syncController,
    this.localRepository,
    this.recorderGateway = const MethodChannelRecorderGateway(),
    this.accent = AppAccent.initial,
    super.key,
  });

  final AppConfig config;
  final IdentityLinkFlow? identityLink;
  final AuthController? authController;
  final SyncController? syncController;
  final LocalRepository? Function()? localRepository;
  final HealthLoader? healthLoader;
  final RecorderGateway recorderGateway;
  final AppAccent accent;

  @override
  Widget build(BuildContext context) {
    final loadHealth =
        healthLoader ?? HealthClient(apiBaseUrl: config.apiBaseUrl).fetch;

    final SongRegistrationPreparer? prepareRegistration =
        localRepository == null
        ? null
        : (draft) {
            final repository = localRepository!.call();
            final auth = authController;
            if (repository == null ||
                auth?.phase != AuthPhase.ready ||
                repository.userId != auth?.session?.userId) {
              throw StateError('The active account is required');
            }
            final command = draft.prepare(repository);
            return () async {
              await repository.save(command);
              final sync = syncController;
              if (sync != null) unawaited(sync.wake());
            };
          };
    Future<List<KaraokeCandidate>> searchLoad(KaraokeQuery query) async {
      final auth = authController;
      if (auth == null || auth.phase != AuthPhase.ready) {
        throw const KaraokeFailure('로그인이 필요해요.', code: 'LOGIN_REQUIRED');
      }
      final expectedUser = auth.session?.userId;
      final expectedDevice = auth.session?.deviceId;
      final session = await auth.validSession();
      if (auth.phase != AuthPhase.ready ||
          session.userId != expectedUser ||
          session.deviceId != expectedDevice) {
        throw const KaraokeFailure(
          '계정이 변경됐어요. 다시 검색해 주세요.',
          code: 'ACCOUNT_CHANGED',
        );
      }
      final result = await HttpKaraokeSearch(
        config.apiBaseUrl,
        allowLocalHttp: kDebugMode && config.environment == AppEnvironment.dev,
      ).search(query, session);
      if (auth.phase != AuthPhase.ready ||
          auth.session?.userId != session.userId ||
          auth.session?.deviceId != session.deviceId) {
        throw const KaraokeFailure(
          '계정이 변경됐어요. 다시 검색해 주세요.',
          code: 'ACCOUNT_CHANGED',
        );
      }
      return result;
    }

    return MaterialApp(
      title: '노래기록',
      debugShowCheckedModeBanner: config.environment != AppEnvironment.prod,
      initialRoute: AppRoutes.home,
      routes: {
        AppRoutes.home: (context) => AppShell(
          recorderGateway: recorderGateway,
          songsBuilder: (context, findSong) => MySongsScreen(
            auth: authController,
            onFindSong: findSong,
            prepareEdit: (draft) {
              final auth = authController, repository = localRepository?.call();
              if (auth == null ||
                  auth.phase != AuthPhase.ready ||
                  repository == null ||
                  repository.userId != auth.session?.userId) {
                throw StateError('Current account storage is unavailable');
              }
              return draft.prepare(repository);
            },
            watchDetail: (id) => () {
              final auth = authController, repository = localRepository?.call();
              if (auth == null ||
                  auth.phase != AuthPhase.ready ||
                  repository == null ||
                  repository.userId != auth.session?.userId) {
                throw StateError('Current account storage is unavailable');
              }
              return repository
                  .watchSongDetail(id)
                  .asyncMap(
                    (bundle) => MySongDetail.verified(
                      bundle,
                      repository.recordingFileStatus,
                    ),
                  );
            },
            watch: () {
              final auth = authController, repository = localRepository?.call();
              if (auth == null ||
                  auth.phase != AuthPhase.ready ||
                  repository == null ||
                  repository.userId != auth.session?.userId) {
                throw StateError('Current account storage is unavailable');
              }
              return repository.watchActiveSongs().map(
                (rows) => rows.map(MySong.new).toList(),
              );
            },
          ),
          chartBuilder: (context) => PopularChartScreen(
            auth: authController,
            searchLoad: searchLoad,
            prepareRegistration: prepareRegistration,
            load: (scope) async {
              final auth = authController;
              if (auth == null || auth.phase != AuthPhase.ready) {
                throw const ChartFailure('로그인이 필요해요.', code: 'LOGIN_REQUIRED');
              }
              final user = auth.session?.userId,
                  device = auth.session?.deviceId;
              final session = await auth.validSession();
              if (auth.phase != AuthPhase.ready ||
                  session.userId != user ||
                  session.deviceId != device) {
                throw const ChartFailure('계정이 변경됐어요.', code: 'ACCOUNT_CHANGED');
              }
              final chart = await HttpPopularChart(
                config.apiBaseUrl,
                allowLocalHttp:
                    kDebugMode && config.environment == AppEnvironment.dev,
              ).read(scope, session);
              if (auth.phase != AuthPhase.ready ||
                  auth.session?.userId != session.userId ||
                  auth.session?.deviceId != session.deviceId) {
                throw const ChartFailure('계정이 변경됐어요.', code: 'ACCOUNT_CHANGED');
              }
              return chart;
            },
          ),
          searchBuilder: (context) => KaraokeSearchScreen(
            auth: authController,
            prepareRegistration: prepareRegistration,
            load: searchLoad,
          ),
        ),
        AppRoutes.settings: (context) => SettingsScreen(
          showDevelopmentTools: config.environment == AppEnvironment.dev,
          identityLink: identityLink,
          authController: authController,
          syncController: syncController,
        ),
        if (config.environment == AppEnvironment.dev)
          AppRoutes.health: (context) =>
              HealthScreen(config: config, healthLoader: loadHealth),
      },
      theme: AppTheme.dark(accent: accent),
    );
  }
}
