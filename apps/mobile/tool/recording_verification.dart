import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/recorder/recorder_gateway.dart';
import 'package:song_record/features/recorder/recording_workspace.dart';
import 'package:song_record/features/search/karaoke_search.dart';
import 'package:song_record/features/search/karaoke_search_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode || appFlavor != 'searchVerification') {
    throw StateError('Isolated verification only');
  }
  // Own fixture package and account; never assigns legacy/user recordings.
  await const MethodChannel('song_record/account').invokeMethod<void>(
    'setAccount',
    {'userId': '00000000-0000-4000-8000-000000001801', 'environment': 'dev'},
  );
  final manager = AccountStoreManager(environment: AppEnvironment.dev);
  final repo = LocalRepository(
    await manager.openAccount('00000000-0000-4000-8000-000000001801'),
  );
  const songId = '00000000-0000-4000-8000-000000001803';
  if (await repo.read(LocalEntity.song, songId) == null) {
    await repo.save(
      repo.prepareCreate(
        entity: LocalEntity.song,
        entityId: songId,
        draft: {
          'source_type': 'MANUAL',
          'title': '검증 밤 산책',
          'artist': '검증 가수',
          'version_code': 'LIVE',
          'lifecycle_state': 'ACTIVE',
          'tier': null,
        },
        changes: {
          'source_type': 'MANUAL',
          'manual_reason': 'TJ_NOT_FOUND',
          'title': '검증 밤 산책',
          'artist': '검증 가수',
          'version_code': 'LIVE',
          'note': '',
        },
      ),
    );
  }
  runApp(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        appBar: AppBar(title: const Text('P18-05 녹음 상세 편집 검증')),
        body: SafeArea(
          child: RecordingWorkspace(
            gateway: const MethodChannelRecorderGateway(),
            repository: () => repo,
            discoveryBuilder: (context, destination, prepare) => Scaffold(
              appBar: AppBar(title: const Text('검색 장애 보존 검증')),
              body: SafeArea(
                child: KaraokeSearchScreen(
                  load: (_) async => throw const KaraokeFailure('합성 검색 장애'),
                  prepareRegistration: prepare,
                ),
              ),
            ),
            isCurrent: (current) => current.userId == repo.userId,
          ),
        ),
      ),
    ),
  );
}
