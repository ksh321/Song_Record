import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:song_record/app/app_shell.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/core/theme/app_tokens.dart';
import 'package:song_record/core/widgets/song_discovery_sheet.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/auth/identity_link.dart';
import 'package:song_record/features/backup/import/import_entry_screen.dart';
import 'package:song_record/features/charts/popular_chart.dart';
import 'package:song_record/features/charts/popular_chart_http.dart';
import 'package:song_record/features/charts/popular_chart_screen.dart';
import 'package:song_record/features/health/health_screen.dart';
import 'package:song_record/features/recorder/recorder_gateway.dart';
import 'package:song_record/features/recorder/recording_workspace.dart';
import 'package:song_record/features/search/karaoke_http.dart';
import 'package:song_record/features/search/karaoke_search.dart';
import 'package:song_record/features/search/karaoke_search_screen.dart';
import 'package:song_record/features/search/search_intent.dart';
import 'package:song_record/features/search/song_registration.dart';
import 'package:song_record/features/settings/accent_preferences.dart';
import 'package:song_record/features/settings/classification_screen.dart';
import 'package:song_record/features/settings/settings_api.dart';
import 'package:song_record/features/settings/settings_screen.dart';
import 'package:song_record/features/settings/storage_request_outbox.dart';
import 'package:song_record/features/settings/storage_request_screen.dart';
import 'package:song_record/features/settings/storage_screen.dart';
import 'package:song_record/features/songs/my_song.dart';
import 'package:song_record/features/songs/my_song_detail.dart';
import 'package:song_record/features/songs/my_songs_screen.dart';
import 'package:song_record/features/songs/song_representative.dart';
import 'package:song_record/features/sync/sync_controller.dart';
import 'package:song_record/network/health_client.dart';
import 'package:song_record/routing/app_routes.dart';

import '../core/audio/audio_player.dart';
import '../core/audio/playback_http.dart';
import '../core/database/account_store.dart';
import '../core/database/local_models.dart';
import '../core/sync/snapshot_transport.dart';
import '../features/backup/export/export_controller.dart';
import '../features/backup/export/export_screen.dart';
import '../features/playlists/playlist_library.dart';
import '../features/playlists/playlist_library_screen.dart';
import '../features/recorder/recording_audio_panel.dart';
import '../features/recorder/recording_detail_screen.dart';
import '../features/settings/account_deletion.dart';
import '../features/settings/account_deletion_screen.dart';
import '../features/trash/trash_screens.dart';
import '../features/trash/trash_workflow.dart';

class SongRecordApp extends StatefulWidget {
  const SongRecordApp({
    required this.config,
    this.healthLoader,
    this.identityLink,
    this.authController,
    this.syncController,
    this.localRepository,
    this.accountStore,
    this.recorderGateway = const MethodChannelRecorderGateway(),
    this.accent = AppAccent.initial,
    this.accentPreferences = const DeviceAccentPreferences(),
    super.key,
  });

  final AppConfig config;
  final IdentityLinkFlow? identityLink;
  final AuthController? authController;
  final SyncController? syncController;
  final LocalRepository? Function()? localRepository;
  final AccountStore? Function()? accountStore;
  final HealthLoader? healthLoader;
  final RecorderGateway recorderGateway;
  final AppAccent accent;
  final AccentPreferences accentPreferences;
  @override
  State<SongRecordApp> createState() => _SongRecordAppState();
}

class _SongRecordAppState extends State<SongRecordApp>
    with WidgetsBindingObserver {
  late final ValueNotifier<AppAccent> accentChanges = ValueNotifier(
    widget.accent,
  );
  int accentVersion = 0;
  AppConfig get config => widget.config;
  IdentityLinkFlow? get identityLink => widget.identityLink;
  AuthController? get authController => widget.authController;
  SyncController? get syncController => widget.syncController;
  LocalRepository? Function()? get localRepository => widget.localRepository;
  AccountStore? Function()? get accountStore => widget.accountStore;
  HealthLoader? get healthLoader => widget.healthLoader;
  RecorderGateway get recorderGateway => widget.recorderGateway;
  AppAccent get accent => accentChanges.value;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    restoreAccent();
  }

  StorageRequestOutbox? demand;
  SettingsApi? demandApi;
  AccountStore? demandStore;
  int? demandEpoch;
  StorageRequestOutbox? currentDemand() {
    final store = accountStore?.call(), auth = authController;
    if (store == null ||
        auth?.phase != AuthPhase.ready ||
        store.userId != auth?.session?.userId) {
      return null;
    }
    if (demandStore == store && demandEpoch == auth!.accountEpoch) {
      return demand;
    }
    demand?.dispose();
    demandStore = store;
    demandEpoch = auth!.accountEpoch;
    final epoch = auth.accountEpoch;
    void guard() {
      store.requireActive();
      if (auth.phase != AuthPhase.ready ||
          auth.accountEpoch != epoch ||
          accountStore?.call() != store ||
          auth.session?.userId != store.userId) {
        throw StateError('Demand account changed');
      }
    }

    final scope =
        '${config.environment.name}:${config.apiBaseUrl.origin}:${store.userId}';
    final api = SettingsApi(
      config.apiBaseUrl,
      auth.validSession,
      guard,
      local: kDebugMode && config.environment == AppEnvironment.dev,
    );
    demandApi = api;
    final box = StorageRequestOutbox(
      scope: scope,
      vault: SecureDemandVault(scope),
      accountChanges: auth,
      requireCurrent: guard,
      send: api.sendStorageRequest,
    );
    demand = box;
    unawaited(box.initialize());
    return box;
  }

  Widget demandScreen(BuildContext context) {
    final box = currentDemand(), api = demandApi;
    if (box == null || api == null) {
      return const Scaffold(
        body: SafeArea(child: Center(child: Text('로그인이 필요해요.'))),
      );
    }
    return StorageRequestScreen(
      outbox: box,
      loadHistory: () async {
        final rows = <Map<String, dynamic>>[], seen = <String>{};
        String? cursor;
        do {
          final page = await api.storageRequestsPage(
            cursor: cursor,
          ) as Map<String, dynamic>;
          rows.addAll((page['items'] as List).cast<Map<String, dynamic>>());
          cursor = page['next_cursor'] as String?;
          if (cursor != null && !seen.add(cursor)) {
            throw const FormatException('Repeated demand cursor');
          }
        } while (cursor != null);
        return rows;
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && demand != null) {
      unawaited(demand!.flush());
    }
  }

  Future<void> restoreAccent() async {
    final version = accentVersion;
    try {
      final saved = await widget.accentPreferences.read();
      if (mounted && version == accentVersion && saved != null) {
        setState(() => accentChanges.value = saved);
      }
    } catch (_) {
      /* Initial theme remains usable when device preferences fail. */
    }
  }

  Future<void> saveAccent(AppAccent value) async {
    final version = ++accentVersion;
    await widget.accentPreferences.write(value);
    if (mounted && version == accentVersion) {
      setState(() => accentChanges.value = value);
    }
  }

  @override
  void didUpdateWidget(covariant SongRecordApp old) {
    super.didUpdateWidget(old);
    if (old.accent != widget.accent) {
      accentVersion++;
      accentChanges.value = widget.accent;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    demand?.dispose();
    accentVersion++;
    accentChanges.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    currentDemand();
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
              if (draft.candidate != null) {
                await repository.ensureTjAvailable(draft.candidate!.number);
              }
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

    Future<PublishedChart> chartLoad(ChartScope scope) async {
      final auth = authController;
      if (auth == null || auth.phase != AuthPhase.ready) {
        throw const ChartFailure('로그인이 필요해요.', code: 'LOGIN_REQUIRED');
      }
      final user = auth.session?.userId, device = auth.session?.deviceId;
      final session = await auth.validSession();
      if (auth.phase != AuthPhase.ready ||
          session.userId != user ||
          session.deviceId != device) {
        throw const ChartFailure('계정이 변경됐어요.', code: 'ACCOUNT_CHANGED');
      }
      final chart = await HttpPopularChart(
        config.apiBaseUrl,
        allowLocalHttp: kDebugMode && config.environment == AppEnvironment.dev,
      ).read(scope, session);
      if (auth.phase != AuthPhase.ready ||
          auth.session?.userId != session.userId ||
          auth.session?.deviceId != session.deviceId) {
        throw const ChartFailure('계정이 변경됐어요.', code: 'ACCOUNT_CHANGED');
      }
      return chart;
    }

    TrashActions? trashActions() {
      final auth = authController, repository = localRepository?.call();
      if (auth == null ||
          auth.phase != AuthPhase.ready ||
          repository == null ||
          repository.userId != auth.session?.userId) {
        return null;
      }
      final owner = repository.userId,
          device = auth.session!.deviceId,
          epoch = auth.accountEpoch;
      void current() {
        if (auth.accountEpoch != epoch ||
            auth.phase != AuthPhase.ready ||
            auth.session?.userId != owner ||
            auth.session?.deviceId != device) {
          throw const TrashFailure('계정이 변경됐어요. 다시 열어 주세요.');
        }
      }

      return TrashWorkflow(
        repository: repository,
        api: HttpTrashApi(
          config.apiBaseUrl,
          auth.validSession,
          current,
          allowLocalHttp:
              kDebugMode && config.environment == AppEnvironment.dev,
        ),
        journal: SecureTrashJournal(config.environment.name, owner),
        requireCurrent: current,
        wakeSync: () {
          final sync = syncController;
          if (sync != null) unawaited(sync.wake());
        },
      );
    }

    return MaterialApp(
      builder: (context, child) => RecordingAudioAccess(
        store: () {
          final store = accountStore?.call();
          return authController?.phase == AuthPhase.ready &&
                  store?.userId == authController?.session?.userId
              ? store
              : null;
        },
        createPlayer: (store) {
          final auth = authController!;
          final epoch = auth.accountEpoch;
          void guard() {
            store.requireActive();
            if (auth.phase != AuthPhase.ready ||
                auth.accountEpoch != epoch ||
                accountStore?.call() != store ||
                auth.session?.userId != store.userId) {
              throw StateError('Playback account changed');
            }
          }

          return AudioPlayback(
            store,
            HttpPlaybackUrls(
              config.apiBaseUrl,
              () async {
                guard();
                final session = await auth.validSession();
                guard();
                return session;
              },
              allowLocalHttp:
                  kDebugMode && config.environment == AppEnvironment.dev,
            ),
            AndroidAudioPlayer(),
            requireCurrent: guard,
            accountChanges: auth,
          );
        },
        changes: Listenable.merge([authController, syncController]),
        refresh: () {
          final sync = syncController;
          if (sync != null) unawaited(sync.wake());
        },
        child: child ?? const SizedBox.shrink(),
      ),
      title: '노래기록',
      debugShowCheckedModeBanner: config.environment != AppEnvironment.prod,
      initialRoute: AppRoutes.home,
      routes: {
        AppRoutes.home: (context) => AppShell(
          recorderGateway: recorderGateway,
          playlistsBuilder: (context) {
            final auth = authController;
            if (auth == null) return const Center(child: Text('로그인이 필요해요.'));
            return AnimatedBuilder(
              animation: auth,
              builder: (context, _) {
                final repository = localRepository?.call();
                if (auth.phase != AuthPhase.ready ||
                    repository == null ||
                    repository.userId != auth.session?.userId) {
                  return const Center(child: Text('로그인이 필요해요.'));
                }
                return PlaylistLibraryScreen(
                  key: ValueKey(repository.userId),
                  library: PlaylistLibrary(repository),
                  searchLoad: searchLoad,
                  chartLoad: chartLoad,
                  auth: auth,
                  afterSave: () async {
                    final sync = syncController;
                    if (sync != null) unawaited(sync.wake());
                  },
                );
              },
            );
          },
          recordingBuilder: localRepository == null
              ? null
              : (context) => RecordingWorkspace(
                  trash: trashActions(),
                  gateway: recorderGateway,
                  repository: localRepository!,
                  discoveryBuilder: (context, destination, prepare) => Scaffold(
                    appBar: AppBar(title: const Text('녹음에 사용할 새 곡 찾기')),
                    body: SafeArea(
                      child: destination == SongDiscoveryDestination.charts
                          ? PopularChartScreen(
                              auth: authController,
                              load: chartLoad,
                              searchLoad: searchLoad,
                              prepareRegistration: prepare,
                              intent: const SearchIntent(
                                returnRoute: '/recording/input',
                              ),
                            )
                          : KaraokeSearchScreen(
                              auth: authController,
                              load: searchLoad,
                              prepareRegistration: prepare,
                              intent: const SearchIntent(
                                returnRoute: '/recording/input',
                              ),
                            ),
                    ),
                  ),
                  isCurrent: (repo) =>
                      authController?.phase == AuthPhase.ready &&
                      authController?.session?.userId == repo.userId &&
                      repo.userId == localRepository?.call()?.userId,
                  wakeSync: () {
                    final sync = syncController;
                    if (sync != null) unawaited(sync.wake());
                  },
                ),
          songsBuilder: (context, findSong) => MySongsScreen(
            onOpenRecording: (id) {
              final repository = localRepository?.call();
              if (repository == null ||
                  authController?.phase != AuthPhase.ready ||
                  authController?.session?.userId != repository.userId) {
                return;
              }
              Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => RecordingDetailScreen(
                    id: id,
                    repository: repository,
                    isCurrent: (repo) =>
                        authController?.phase == AuthPhase.ready &&
                        authController?.session?.userId == repo.userId &&
                        repo.userId == localRepository?.call()?.userId,
                    wakeSync: () {
                      final sync = syncController;
                      if (sync != null) unawaited(sync.wake());
                    },
                    trash: trashActions(),
                  ),
                ),
              );
            },
            trash: trashActions(),
            auth: authController,
            watchUnlinked: () {
              final auth = authController, repository = localRepository?.call();
              if (auth == null ||
                  auth.phase != AuthPhase.ready ||
                  repository == null ||
                  repository.userId != auth.session?.userId) {
                throw StateError('Current account storage is unavailable');
              }
              return repository.watchUnlinkedRecordings();
            },
            onFindSong: findSong,
            prepareRepresentative: (detail, recording) {
              final auth = authController, repository = localRepository?.call();
              if (auth == null ||
                  auth.phase != AuthPhase.ready ||
                  repository == null ||
                  repository.userId != auth.session?.userId) {
                throw StateError('Current account storage is unavailable');
              }
              return prepareRepresentative(repository, detail, recording);
            },
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
            load: chartLoad,
          ),
          searchBuilder: (context) => KaraokeSearchScreen(
            auth: authController,
            prepareRegistration: prepareRegistration,
            load: searchLoad,
          ),
        ),
        AppRoutes.settings: (context) => SettingsScreen(
          deletionBuilder: authController?.phase == AuthPhase.ready
              ? (_) {
                  final store = accountStore?.call(), auth = authController;
                  if (store == null ||
                      auth?.phase != AuthPhase.ready ||
                      store.userId != auth?.session?.userId ||
                      auth!.proofs is! IdentityLinkProofSource) {
                    return const Scaffold(
                      body: SafeArea(
                        child: Center(child: Text('최근 계정 재인증을 사용할 수 없어요.')),
                      ),
                    );
                  }
                  final epoch = auth.accountEpoch, owner = store.userId;
                  void guard() {
                    store.requireActive();
                    if (auth.phase != AuthPhase.ready ||
                        auth.accountEpoch != epoch ||
                        auth.session?.userId != owner ||
                        accountStore?.call() != store) {
                      throw StateError('Deletion account changed');
                    }
                  }

                  final api = AccountDeletionApi(
                    config.apiBaseUrl,
                    auth.validSession,
                    guard,
                    local:
                        kDebugMode && config.environment == AppEnvironment.dev,
                  );
                  final flow = AccountDeletionFlow(
                    '${config.environment.name}:${config.apiBaseUrl.origin}:$owner',
                    api,
                    auth.proofs as IdentityLinkProofSource,
                    const SecureDeletionReceiptVault(),
                  );
                  return AccountDeletionScreen(
                    flow: flow,
                    onAccepted: () => auth.deletionAccepted(
                      owner,
                      confirmation: flow.confirmation(owner),
                    ),
                  );
                }
              : null,
          importBuilder: (_) {
            final store = accountStore?.call(), auth = authController;
            if (store == null ||
                auth?.phase != AuthPhase.ready ||
                store.userId != auth?.session?.userId) {
              return const Scaffold(
                body: SafeArea(child: Center(child: Text('로그인이 필요해요.'))),
              );
            }
            final epoch = auth!.accountEpoch;
            void guard() {
              store.requireActive();
              if (auth.phase != AuthPhase.ready ||
                  auth.accountEpoch != epoch ||
                  accountStore?.call() != store ||
                  auth.session?.userId != store.userId) {
                throw StateError('Import account changed');
              }
            }

            return ImportEntryScreen(
              store: store,
              accountChanges: auth,
              synchronize: syncController?.wake,
              requireCurrent: guard,
              session: auth.validSession,
              transport: HttpSnapshotTransport(
                config.apiBaseUrl,
                allowLocalHttp:
                    kDebugMode && config.environment == AppEnvironment.dev,
              ),
            );
          },
          storageBuilder: (_) {
            final store = accountStore?.call(), auth = authController;
            if (store == null ||
                auth?.phase != AuthPhase.ready ||
                store.userId != auth?.session?.userId) {
              return const Scaffold(
                body: SafeArea(child: Center(child: Text('로그인이 필요해요.'))),
              );
            }
            final epoch = auth!.accountEpoch;
            void guard() {
              store.requireActive();
              if (auth.phase != AuthPhase.ready ||
                  auth.accountEpoch != epoch ||
                  accountStore?.call() != store ||
                  auth.session?.userId != store.userId) {
                throw StateError('Storage account changed');
              }
            }

            final api = SettingsApi(
              config.apiBaseUrl,
              auth.validSession,
              guard,
              local: kDebugMode && config.environment == AppEnvironment.dev,
            );
            return StorageScreen(
              requestBuilder: demandScreen,
              requireCurrent: guard,
              accountChanges: auth,
              load: () async {
                final usage =
                    await api.get('/v1/storage') as Map<String, dynamic>;
                final pins = await api.get('/v1/pins') as Map<String, dynamic>;
                final recordings = await store.savedRecordings();
                guard();
                final view = StorageView(
                  usage,
                  (pins['items'] as List).cast<Map<String, dynamic>>(),
                  recordings,
                );
                final confirmed = <String>{
                  for (final slot in view.slots)
                    for (final key in [
                      'current_recording_id',
                      'pending_recording_id',
                    ])
                      if (slot[key] case final String id) id,
                };
                final resumed = await store.resumePinnedUploads(confirmed);
                guard();
                if (resumed > 0) syncController?.wake();
                return view;
              },
              command: (method, path, body, id) async {
                await api.pinCommand(method, path, body, id);
                guard();
                syncController?.wake();
              },
            );
          },
          classificationBuilder: (_) {
            final store = accountStore?.call(), auth = authController;
            if (store == null ||
                auth?.phase != AuthPhase.ready ||
                store.userId != auth?.session?.userId) {
              return const Scaffold(
                body: SafeArea(child: Center(child: Text('로그인이 필요해요.'))),
              );
            }
            final epoch = auth!.accountEpoch;
            void guard() {
              store.requireActive();
              if (auth.phase != AuthPhase.ready ||
                  auth.accountEpoch != epoch ||
                  accountStore?.call() != store ||
                  auth.session?.userId != store.userId) {
                throw StateError('Classification account changed');
              }
            }

            final api = SettingsApi(
              config.apiBaseUrl,
              auth.validSession,
              guard,
              local: kDebugMode && config.environment == AppEnvironment.dev,
            );
            return ClassificationScreen(
              canEdit: syncController != null,
              requireCurrent: guard,
              accountChanges: auth,
              accent: accentChanges,
              saveAccent: saveAccent,
              load: () async {
                final tags = <Map<String, dynamic>>[], cursors = <String>{};
                String? cursor;
                do {
                  final page = await api.tagsPage(
                    cursor: cursor,
                  ) as Map<String, dynamic>;
                  tags.addAll(
                    (page['items'] as List).cast<Map<String, dynamic>>(),
                  );
                  cursor = page['next_cursor'] as String?;
                  if (cursor != null && !cursors.add(cursor)) {
                    throw const FormatException('Repeated tag cursor');
                  }
                } while (cursor != null);
                final conditions =
                    await api.get('/v1/conditions') as Map<String, dynamic>;
                guard();
                return (
                  tags: tags,
                  conditions: (conditions['items'] as List)
                      .cast<Map<String, dynamic>>(),
                );
              },
              command: (method, path, body, op) async {
                final result = await api.tagCommand(
                  method,
                  path,
                  body,
                  op,
                ) as Map<String, dynamic>;
                guard();
                await syncController?.wake();
                guard();
                final copy = await store.readMetadata(
                  LocalEntity.tag,
                  result['id'] as String,
                );
                guard();
                final local = copy?.localJson ?? copy?.serverJson;
                if (local == null) {
                  throw StateError('Tag receipt awaiting local sync');
                }
                final actual = jsonDecode(local) as Map<String, dynamic>;
                if (copy!.revision > (result['revision'] as int)) {
                  // A newer account change superseded this accepted receipt.
                  // Refresh instead of endlessly replaying the old request.
                  throw const SettingsUnavailable(status: 409);
                }
                if (copy.revision < (result['revision'] as int) ||
                    actual['name'] != result['name'] ||
                    (actual['archived_at'] == null) !=
                        (result['archived_at'] == null)) {
                  throw StateError(
                    'Tag receipt awaiting local sync or conflict resolution',
                  );
                }
              },
            );
          },
          backupBuilder: (context) {
            final store = accountStore?.call(), auth = authController;
            if (store == null ||
                auth?.phase != AuthPhase.ready ||
                store.userId != auth?.session?.userId) {
              return const Scaffold(body: Center(child: Text('로그인이 필요해요.')));
            }
            void guard() {
              store.requireActive();
              if (auth!.phase != AuthPhase.ready ||
                  auth.session?.userId != store.userId ||
                  accountStore?.call() != store) {
                throw StateError('The backup account changed');
              }
            }

            final localHttp =
                kDebugMode && config.environment == AppEnvironment.dev;
            return ExportScreen(
              controller: ExportController.forStore(
                store: store,
                recorder: recorderGateway,
                transport: HttpSnapshotTransport(
                  config.apiBaseUrl,
                  allowLocalHttp: localHttp,
                ),
                session: auth!.validSession,
                base: config.apiBaseUrl,
                requireCurrent: guard,
                allowLocalHttp: localHttp,
              ),
            );
          },
          trashBuilder: (context) {
            final actions = trashActions();
            return actions == null
                ? const Scaffold(body: Center(child: Text('로그인이 필요해요.')))
                : TrashScreen(actions: actions, auth: authController);
          },
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
