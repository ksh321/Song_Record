import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_database.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/files/recording_file_status.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/features/recorder/recording_list.dart';

Map<String, dynamic> row(
  String id,
  String title,
  String date,
  String? tier, {
  String version = 'NORMAL',
}) => {
  'id': id,
  'title_snapshot': title,
  'artist_snapshot': '가수',
  'recorded_at': date,
  'tier': tier,
  'key_mode': 'ORIGINAL',
  'key_shift': 0,
  'version_code': version,
  'timezone_offset_minutes': -300,
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('four sorts preserve fileless rows, tier ties use actual instant and deterministic id', () {
    final rows = [
      row('b', '밤', '2026-10-10T12:00:00+09:00', 'S'),
      row('a', '아침', '2026-10-10T04:00:00Z', 'S'),
      row('c', '밤', '2026-10-09T04:00:00Z', null),
      row('d', '낮', '2026-10-10T04:00:00Z', 'B'),
    ];
    expect(sortRecordings(rows, RecordingSort.newest).map((r) => r['id']), [
      'a',
      'd',
      'b',
      'c',
    ]);
    expect(sortRecordings(rows, RecordingSort.oldest).map((r) => r['id']), [
      'c',
      'b',
      'a',
      'd',
    ]);
    expect(sortRecordings(rows, RecordingSort.title).map((r) => r['id']), [
      'd',
      'b',
      'c',
      'a',
    ]);
    expect(sortRecordings(rows, RecordingSort.tier).map((r) => r['id']), [
      'a',
      'b',
      'd',
      'c',
    ]);
    expect(rows.first['id'], 'b');
  });
  test(
    'summary uses fixed Korea timezone, all versions and common key display',
    () {
      final r = row('a', '곡', '2026-10-09T20:00:00Z', null);
      expect(recordingSummary(r), contains('2026/10/10 · 일반 반주 · 원키'));
      r['version_code'] = 'MR';
      r['key_mode'] = 'FEMALE';
      r['key_shift'] = 1;
      expect(recordingSummary(r), contains('MR · 여 +1'));
      r['version_code'] = 'LIVE';
      expect(recordingSummary(r), contains('LIVE'));
      expect(recordingSummary(r), contains('파일: 확인 중'));
    },
  );
  testWidgets(
    'small sort button uses checked safe sheet and selected row opens',
    (tester) async {
      final rows = [
        row('b', '밤', '2026-10-09T04:00:00Z', null),
        row('a', '아침', '2026-10-10T04:00:00Z', 'S'),
      ];
      String? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecordingList(
                rows: rows,
                onOpen: (r) => opened = r['id'] as String,
              ),
            ),
          ),
        ),
      );
      expect(find.text('저장 녹음 2개'), findsOneWidget);
      await tester.tap(find.text('최신순'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check), findsOneWidget);
      await tester.tap(find.text('오래된순'));
      await tester.pumpAndSettle();
      final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
      expect((tiles.first.title as Text).data, '밤 · 가수');
      await tester.tap(find.text('밤 · 가수'));
      expect(opened, 'b');
    },
  );
  test('received saved metadata without local file remains visible with missing state', () async {
    final root = await Directory.systemTemp.createTemp('sr-list-');
    const owner = '00000000-0000-4000-8000-000000001801',
        id = '00000000-0000-4000-8000-000000001807';
    final paths = await AccountPaths.create(root, owner, AppEnvironment.dev);
    final db = AccountDatabase(
      NativeDatabase(await paths.databaseFile()),
      userId: owner,
      environment: AppEnvironment.dev,
    );
    await db.verifyReady();
    final raw = jsonEncode({
      ...row(id, '파일 없는 곡', '2026-10-10T04:00:00Z', null),
      'user_id': owner,
      'metadata_state': 'SAVED',
      'lifecycle_state': 'ACTIVE',
    });
    await db.customStatement(
      'INSERT INTO metadata_copies(user_id,entity_type,entity_id,server_revision,server_payload,tombstone,updated_at) VALUES(?,?,?,1,?,0,1)',
      [owner, 'RECORDING', id, raw],
    );
    await db.close();
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    try {
      final repo = LocalRepository(await manager.openAccount(owner));
      final rows = await repo.savedRecordings();
      expect(rows.single['id'], id);
      final status = await repo.recordingFileStatus(id);
      expect(status.device, DeviceAudioState.missing);
      expect(
        recordingSummary({...rows.single, '_file_status': status}),
        contains('재생 가능한 파일 없음'),
      );
    } finally {
      await manager.logout();
      await root.delete(recursive: true);
    }
  });
}
