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
import 'package:song_record/features/recorder/recording_filter.dart';
import 'package:song_record/features/recorder/recording_list.dart';
import 'package:song_record/features/recorder/recording_pages.dart';

import 'recording_filter_test.dart' as filters;
import 'recording_input_test.dart' as input;
import 'support/completed_capture_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('filter whole catalog before 50-row keyset paging and invalidate every changed generation/scope/condition', () {
    final rows = List.generate(
      110,
      (i) =>
          filters.record(
              i.toString().padLeft(4, '0'),
              DateTime.utc(
                2026,
                1,
                1,
              ).add(Duration(seconds: i)).toIso8601String(),
            )
            ..['_file_status'] = filters.status(
              i < 50 ? DeviceAudioState.available : DeviceAudioState.missing,
              'STORED',
            ),
    );
    final pages = RecordingPages()
      ..replace(rows, 'dev/A')
      ..select(RecordingFilter({'file': 'serverOnly'}), RecordingSort.oldest);
    expect(pages.total, 60);
    expect(pages.visible.length, 50);
    expect(pages.visible.first['id'], '0050');
    final first = pages.cursor!;
    pages.next(first);
    expect(pages.visible.length, 60);
    expect(pages.cursor, isNull);
    pages.select(RecordingFilter(), RecordingSort.newest);
    final stale = pages.cursor!;
    pages.replace([...rows.where((r) => r['id'] != '0100')], 'dev/A');
    expect(pages.total, 109);
    expect(pages.visible.length, 50);
    expect(() => pages.next(stale), throwsStateError);
    final before = pages.cursor!;
    pages.select(RecordingFilter({'key_shift': '0'}), RecordingSort.oldest);
    expect(() => pages.next(before), throwsStateError);
    final account = pages.cursor!;
    pages.replace(rows, 'dev/B');
    expect(() => pages.next(account), throwsStateError);
    expect(() => RecordingPages(limit: 0), throwsRangeError);
    expect(() => RecordingPages(limit: 101), throwsRangeError);
  });
  test(
    'file index change resets paging and count; unknown is never absent',
    () {
      final rows = List.generate(
        70,
        (i) => filters.record('$i', '2026-10-10T00:00:00Z'),
      );
      final pages = RecordingPages()
        ..replace(rows, 'A')
        ..select(RecordingFilter({'file': 'localOnly'}), RecordingSort.newest);
      expect(pages.total, 70);
      final old = pages.cursor!;
      final changed = rows.map((r) => {...r}).toList();
      changed[60]['_file_status'] = filters.status(
        DeviceAudioState.unknown,
        'NONE',
      );
      pages.replace(changed, 'A');
      expect(pages.total, 69);
      expect(pages.unknownFiles, 1);
      expect(() => pages.next(old), throwsStateError);
      final current = pages.cursor!;
      pages.replace(changed, 'A');
      expect(pages.cursor!.generation, current.generation);
    },
  );
  test('full account catalog reads >one page, preserves missing-file metadata, detects bytes and lease changes', () async {
    final root = await Directory.systemTemp.createTemp('sr-catalog-');
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    try {
      var repo = LocalRepository(await manager.openAccount(owner));
      await capture(repo);
      await repo.saveRecordingInput(
        rec,
        input.fields(),
        repo.recordingSaveOperationIds(),
      );
      await manager.logout();
      final paths = await AccountPaths.create(root, owner, AppEnvironment.dev);
      final db = AccountDatabase(
        NativeDatabase(await paths.databaseFile()),
        userId: owner,
        environment: AppEnvironment.dev,
      );
      await db.verifyReady();
      for (var i = 0; i < 110; i++) {
        final id =
            '00000000-0000-4000-8000-${(2000 + i).toString().padLeft(12, '0')}';
        final raw = jsonEncode({
          ...filters.record(id, '2026-10-10T00:00:00Z')..remove('_file_status'),
          'user_id': owner,
          'metadata_state': 'SAVED',
          'tags': <Map<String, dynamic>>[],
          'song_id': null,
          'lifecycle_state': 'ACTIVE',
        });
        await db.customStatement(
          'INSERT INTO metadata_copies(user_id,entity_type,entity_id,server_revision,server_payload,tombstone,updated_at) VALUES(?,?,?,1,?,0,1)',
          [owner, 'RECORDING', id, raw],
        );
        await db.customStatement(
          'INSERT INTO metadata_copies(user_id,entity_type,entity_id,server_revision,server_payload,tombstone,updated_at) VALUES(?,?,?,1,?,0,1)',
          [
            owner,
            'RECORDING_ASSET',
            id,
            jsonEncode({
              'recording_id': id,
              'user_id': owner,
              'cloud_state': 'NONE',
            }),
          ],
        );
      }
      await db.close();
      repo = LocalRepository(await manager.openAccount(owner));
      final all = await repo.recordingCatalog();
      expect(all.rows.length, 111);
      expect(all.complete, isFalse);
      expect(all.lastSync, isNull);
      expect(
        (all.rows.singleWhere((r) => r['id'] == rec)['_file_status']
                as RecordingFileStatus)
            .device,
        DeviceAudioState.available,
      );
      expect(
        all.rows
            .where(
              (r) =>
                  (r['_file_status'] as RecordingFileStatus).device ==
                  DeviceAudioState.missing,
            )
            .length,
        110,
      );
      final again = await repo.recordingCatalog();
      expect(again.rows.length, 111);
      final file = await paths.checkedFile(paths.audioPath(rec));
      await file.writeAsBytes([6, 7, 8, 9, 0]);
      final corrupted = await repo.recordingCatalog();
      expect(
        (corrupted.rows.singleWhere((r) => r['id'] == rec)['_file_status']
                as RecordingFileStatus)
            .device,
        DeviceAudioState.missing,
      );
      await file.writeAsBytes(bytes);
      final restored = await repo.recordingCatalog();
      expect(
        (restored.rows.singleWhere((r) => r['id'] == rec)['_file_status']
                as RecordingFileStatus)
            .device,
        DeviceAudioState.available,
      );
      await file.delete();
      final missing = await repo.recordingCatalog();
      expect(missing.rows.length, 111);
      expect(
        (missing.rows.singleWhere((r) => r['id'] == rec)['_file_status']
                as RecordingFileStatus)
            .device,
        DeviceAudioState.missing,
      );
      await manager.logout();
      final otherRepo = LocalRepository(await manager.openAccount(other));
      expect((await otherRepo.recordingCatalog()).rows, isEmpty);
      await expectLater(repo.recordingCatalog(), throwsStateError);
    } finally {
      await manager.logout();
      await root.delete(recursive: true);
    }
  });
  testWidgets(
    'incomplete zero is provisional; data change resets visible pages',
    (tester) async {
      Widget app(List<Map<String, dynamic>> rows, {bool complete = true}) =>
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RecordingList(
                  rows: rows,
                  metadataComplete: complete,
                  onOpen: (_) {},
                ),
              ),
            ),
          );
      await tester.pumpWidget(app([], complete: false));
      expect(find.text('현재 확인된 0개'), findsOneWidget);
      expect(find.text('저장된 녹음이 없습니다'), findsNothing);
      final rows = List.generate(
        55,
        (i) => filters.record('$i', '2026-10-10T00:00:00Z'),
      );
      await tester.pumpWidget(app(rows));
      expect(find.text('저장 녹음 55개'), findsOneWidget);
      await tester.ensureVisible(find.text('다음 50개'));
      await tester.tap(find.text('다음 50개'));
      await tester.pumpAndSettle();
      expect(find.text('다음 50개'), findsNothing);
      await tester.pumpWidget(app(rows.take(54).toList()));
      expect(find.text('저장 녹음 54개'), findsOneWidget);
      expect(find.text('다음 50개'), findsOneWidget);
    },
  );
}
