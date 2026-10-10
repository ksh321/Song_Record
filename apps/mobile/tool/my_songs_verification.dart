import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/songs/my_song.dart';
import 'package:song_record/features/songs/my_song_detail.dart';
import 'package:song_record/features/songs/my_songs_screen.dart';
import 'package:song_record/features/songs/song_representative.dart';

String id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
Map<String, Object?> song(int n, String title, {String state = 'ACTIVE'}) => {
  'id': id(n),
  'title': title,
  'artist': 'Singer',
  'version_code': 'NORMAL',
  'lifecycle_state': state,
  'tier': n == 10
      ? 'S'
      : n == 12
      ? 'A'
      : null,
  'created_at': n == 12 ? '2026-01-02T00:00:00Z' : '2026-01-01T00:00:00Z',
  'note': '곡 메모 · 녹음 메모와 독립',
  if (n == 12) 'tj_number': '00123',
};
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode || appFlavor != 'searchVerification') {
    throw StateError('Isolated verification only');
  }
  final root = await Directory.systemTemp.createTemp('p17-verification-');
  final manager = AccountStoreManager(
    environment: AppEnvironment.dev,
    directory: () async => root,
    temporaryDirectory: () async => root,
  );
  for (final account in [1, 2]) {
    final repo = LocalRepository(await manager.openAccount(id(account)));
    for (final n in account == 1 ? [10, 11, 12, 13] : [20]) {
      final draft = song(
        n,
        n == 10
            ? '밤 산책'
            : n == 11
            ? '휴지통 곡'
            : n == 12
            ? '가벼운 산책'
            : n == 13
            ? '미정 산책'
            : '계정 B 전용곡',
        state: n == 11 ? 'TRASHED' : 'ACTIVE',
      );
      await repo.save(
        repo.prepareCreate(
          entity: LocalEntity.song,
          entityId: id(n),
          draft: draft,
          changes: draft,
        ),
      );
    }
  }
  final repo = LocalRepository(await manager.openAccount(id(1)));
  final record = <String, Object?>{
    'id': id(30),
    'song_id': id(10),
    'title_snapshot': '녹음 당시 제목',
    'artist_snapshot': '녹음 당시 가수',
    'version_code': 'LIVE',
    'key_mode': 'FEMALE',
    'key_shift': -1,
    'tier': 'D',
    'note': '녹음 당시 메모',
    'metadata_state': 'SAVED',
    'lifecycle_state': 'ACTIVE',
    'recorded_at': '2026-01-01T00:00:00Z',
    'timezone_id': 'Asia/Seoul',
    'timezone_offset_minutes': 540,
  };
  for (final n in [30, 31, 32]) {
    final r = {
      ...record,
      'id': id(n),
      'title_snapshot': '역할 녹음 $n',
      'tier': n == 30
          ? 'B'
          : n == 31
          ? 'D'
          : 'A',
      'recorded_at': '2026-01-0${n - 29}T00:00:00Z',
    };
    await repo.save(
      repo.prepareCreate(
        entity: LocalEntity.recording,
        entityId: id(n),
        draft: r,
        changes: r,
      ),
    );
  }
  final unlinked = {
    ...record,
    'id': id(33),
    'song_id': null,
    'title_snapshot': '미연결 원본 제목',
  };
  await repo.save(
    repo.prepareCreate(
      entity: LocalEntity.recording,
      entityId: id(33),
      draft: unlinked,
      changes: unlinked,
    ),
  );
  runApp(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Check(manager: manager, initial: repo),
    ),
  );
}

class Check extends StatefulWidget {
  const Check({required this.manager, required this.initial, super.key});
  final AccountStoreManager manager;
  final LocalRepository initial;
  @override
  State<Check> createState() => _CheckState();
}

class _CheckState extends State<Check> {
  late LocalRepository repo = widget.initial;
  int account = 1;
  bool busy = false;
  Future<void> change() async {
    if (busy) return;
    setState(() => busy = true);
    final next = account == 1 ? 2 : 1;
    final opened = await widget.manager.openAccount(id(next));
    if (!mounted) return;
    setState(() {
      repo = LocalRepository(opened);
      account = next;
      busy = false;
    });
  }

  Future<void> edit() async {
    if (busy || account != 1) return;
    setState(() => busy = true);
    final draft = song(10, '오프라인 수정곡');
    await repo.save(
      repo.preparePatch(
        entity: LocalEntity.song,
        entityId: id(10),
        baseRevision: 0,
        draft: draft,
        changes: {'title': '오프라인 수정곡'},
      ),
    );
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('P17-07 곡 동작 진입 검증')),
    body: SafeArea(
      child: Column(
        children: [
          Text(
            '합성 곡 · 별도 임시 DB · 외부 API 호출 없음 · 계정 ${account == 1 ? 'A' : 'B'}',
          ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: busy ? null : change,
                child: const Text('계정 A/B 전환'),
              ),
              OutlinedButton(
                onPressed: busy || account != 1 ? null : edit,
                child: const Text('오프라인 수정'),
              ),
            ],
          ),
          Expanded(
            child: MySongsScreen(
              prepareEdit: (draft) => draft.prepare(repo),
              prepareRepresentative: (detail, recording) =>
                  prepareRepresentative(repo, detail, recording),
              watchUnlinked: repo.watchUnlinkedRecordings,
              watchDetail: (id) =>
                  () => repo
                      .watchSongDetail(id)
                      .asyncMap(
                        (bundle) => MySongDetail.verified(
                          bundle,
                          repo.recordingFileStatus,
                        ),
                      ),
              watch: () => repo.watchActiveSongs().map(
                (rows) => rows.map(MySong.new).toList(),
              ),
              onFindSong: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('새 곡 찾기는 별도 동작 · 검색 중 외부 호출 없음')),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
