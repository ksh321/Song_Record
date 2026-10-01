import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_database.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/database/snapshot_download_store.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AccountStoreManager manager;
  late Map<String, dynamic> fixture;
  late AccountStore store;
  late DateTime now;
  const token = '22222222-2222-4222-8222-222222222222',
      owner = '11111111-1111-4111-8111-111111111111';
  setUp(() async {
    now = DateTime.utc(2026, 9, 30);
    directory = await Directory.systemTemp.createTemp('sr-snapshot-store-');
    manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => directory,
      temporaryDirectory: () async => directory,
      clock: () => now,
    );
    fixture = jsonDecode(
      File('../../fixtures/contracts/snapshot-wire.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    store = await manager.openAccount(owner);
    await store.beginSnapshotDownload(token, jsonEncode(fixture['manifest']));
  });
  tearDown(() async {
    await manager.logout();
    expect(
      directory.path.split(Platform.pathSeparator).last,
      startsWith('sr-snapshot-store-'),
    );
    await directory.delete(recursive: true);
  });
  Future<void> pages() async {
    for (final page in fixture['pages'] as List) {
      await store.appendSnapshotPage(
        token,
        page['entity'] as String,
        0,
        jsonEncode(page),
      );
    }
  }

  test('record lookup distinguishes absent baseline from missing resource and pins generation', () async {
    const id = '33333333-3333-4333-8333-333333333333';
    expect(await store.snapshotBaselineRecord('SONG', id), isNull);
    await pages();
    await store.verifySnapshotDownload(token);
    expect(await store.snapshotBaselineRecord('SONG', id), isNull);
    await store.applySnapshotDownload(token);
    final page = await store.snapshotBaselinePage('SONG');
    final record = await store.snapshotBaselineRecord(
      'SONG',
      page.entries.single.resourceId,
      expectedToken: token,
    );
    expect(record!.token, token);
    expect(record.cursor, 7);
    expect(record.entry!.payload, page.entries.single.payload);
    expect(record.toString(), isNot(contains('한글')));
    expect((await store.snapshotBaselineRecord('SONG', owner))!.entry, isNull);
    await expectLater(
      store.snapshotBaselineRecord('SONG', "x' OR 1=1 --"),
      throwsFormatException,
    );
    await expectLater(
      store.snapshotBaselineRecord('RECORDING_TAG', id),
      throwsStateError,
    );
    await expectLater(
      store.snapshotBaselineRecord('SONG', id, expectedToken: owner),
      throwsStateError,
    );
    await expectLater(
      store.snapshotBaselineRecord('UNKNOWN', id),
      throwsStateError,
    );
    now = now.add(const Duration(hours: 1));
    expect(
      (await store.snapshotBaselineRecord(
        'SONG',
        page.entries.single.resourceId,
      ))!.entry,
      isNotNull,
    );
    final old = store;
    store = await manager.openAccount('55555555-5555-4555-8555-555555555555');
    await expectLater(old.snapshotBaselineRecord('SONG', id), throwsStateError);
    expect(await store.snapshotBaselineRecord('SONG', id), isNull);
  });

  test('combined view preserves local draft and pending command beside server baseline', () async {
    const id = '33333333-3333-4333-8333-333333333333';
    final empty = await store.snapshotMetadataView(LocalEntity.song, id);
    expect(empty.baseline, isNull);
    expect(empty.cached, isNull);
    await store.saveEdit(
      LocalEdit(
        opId: '44444444-4444-4444-8444-444444444444',
        entity: LocalEntity.song,
        entityId: id,
        operation: LocalOperation.create,
        baseRevision: 0,
        draft: {'note': 'retained synthetic draft'},
        changes: {'note': 'retained synthetic draft'},
      ),
    );
    final queued = (await store.pendingMutations()).single;
    await pages();
    await store.verifySnapshotDownload(token);
    await store.applySnapshotDownload(token);
    final view = await store.snapshotMetadataView(
      LocalEntity.song,
      id,
      expectedToken: token,
    );
    expect(view.baseline!.entry!.payload['note'], '한글 🎵');
    expect(view.cached!.localJson, contains('retained synthetic draft'));
    expect(view.cached!.revision, 0);
    expect(view.cached!.serverJson, isNull);
    final after = (await store.pendingMutations()).single;
    expect(after.payload, queued.payload);
    expect(after.basePayload, queued.basePayload);
    expect(after.attemptCount, queued.attemptCount);
    expect(after.state, queued.state);
    expect(view.toString(), 'SnapshotMetadataView[REDACTED]');
    await expectLater(
      store.snapshotMetadataView(LocalEntity.song, id, expectedToken: owner),
      throwsStateError,
    );
    final old = store;
    store = await manager.openAccount('55555555-5555-4555-8555-555555555555');
    await expectLater(
      old.snapshotMetadataView(LocalEntity.song, id),
      throwsStateError,
    );
    final other = await store.snapshotMetadataView(LocalEntity.song, id);
    expect(other.baseline, isNull);
    expect(other.cached, isNull);
  });

  test('persistent receive verifies all rows without replacing live edits or cursor', () async {
    await store.saveEdit(
      LocalEdit(
        opId: '44444444-4444-4444-8444-444444444444',
        entity: LocalEntity.song,
        entityId: '33333333-3333-4333-8333-333333333333',
        operation: LocalOperation.create,
        baseRevision: 0,
        draft: {'title': 'private draft'},
        changes: {'title': 'private draft'},
      ),
    );
    await pages();
    await manager.logout();
    store = await manager.openAccount(owner);
    final before = await store.snapshotDownloadState(token);
    expect(before.progress, hasLength(19));
    expect(before.state, 'RECEIVING');
    await store.verifySnapshotDownload(token);
    expect((await store.snapshotDownloadState(token)).state, 'VERIFIED');
    expect(await store.readCursor(), isNull);
    expect(
      (await store.pendingMutations()).single.payload,
      contains('private draft'),
    );
    final backup =
        jsonDecode(await store.recoveryData()) as Map<String, dynamic>;
    expect(
      (backup['tables'] as Map<String, dynamic>)['snapshot_baseline'],
      isEmpty,
    );
    await store.verifySnapshotDownload(
      token,
    ); // Immutable verified state is resumable.
  });
  test(
    'duplicate and stale page cannot replace staged rows or advance twice',
    () async {
      final page = (fixture['pages'] as List).singleWhere(
        (p) => p['entity'] == 'SONG',
      );
      await store.appendSnapshotPage(token, 'SONG', 0, jsonEncode(page));
      await expectLater(
        store.appendSnapshotPage(token, 'SONG', 0, jsonEncode(page)),
        throwsStateError,
      );
      final state = await store.snapshotDownloadState(token);
      expect(state.progress['SONG']!.ordinal, 1);
      expect(state.progress['SONG']!.finished, isTrue);
      await expectLater(store.verifySnapshotDownload(token), throwsStateError);
      expect((await store.snapshotDownloadState(token)).state, 'RECEIVING');
    },
  );
  test(
    'tampered complete download is never promoted or exposed as baseline',
    () async {
      final page = (fixture['pages'] as List).singleWhere(
        (p) => p['entity'] == 'SONG',
      );
      final row = (page['entries'] as List).single as Map<String, dynamic>;
      row['canonical_payload'] = (row['canonical_payload'] as String)
          .replaceFirst('한글', '변조');
      row['payload']['note'] = '변조 🎵';
      await pages();
      await expectLater(
        store.verifySnapshotDownload(token),
        throwsFormatException,
      );
      expect((await store.snapshotDownloadState(token)).state, 'RECEIVING');
      expect(await store.readCursor(), isNull);
    },
  );
  test(
    'expired downloads can be discarded without touching existing edits',
    () async {
      await store.saveEdit(
        LocalEdit(
          opId: '44444444-4444-4444-8444-444444444444',
          entity: LocalEntity.song,
          entityId: '33333333-3333-4333-8333-333333333333',
          operation: LocalOperation.create,
          baseRevision: 0,
          draft: {'title': 'retained edit'},
          changes: {'title': 'retained edit'},
        ),
      );
      await pages();
      now = now.add(const Duration(minutes: 30));
      await expectLater(
        store.verifySnapshotDownload(token),
        throwsFormatException,
      );
      await store.discardSnapshotDownload(token);
      final backup =
          jsonDecode(await store.recoveryData()) as Map<String, dynamic>;
      final tables = backup['tables'] as Map<String, dynamic>;
      for (final table in [
        'snapshot_downloads',
        'snapshot_download_rows',
        'snapshot_download_progress',
      ]) {
        expect(tables[table], isEmpty);
      }
      expect(tables['local_account'], hasLength(1));
      expect(
        (await store.pendingMutations()).single.payload,
        contains('retained edit'),
      );
      expect(await store.readCursor(), isNull);
    },
  );
  test('account switch rejects old handle and cannot read another account download', () async {
    final old = store;
    store = await manager.openAccount('55555555-5555-4555-8555-555555555555');
    await expectLater(old.snapshotDownloadState(token), throwsStateError);
    await expectLater(store.snapshotDownloadState(token), throwsStateError);
    store = await manager.openAccount(owner);
    expect((await store.snapshotDownloadState(token)).state, 'RECEIVING');
  });
  test('only verified snapshot switches baseline and cursor and keeps local drafts', () async {
    await store.saveEdit(
      LocalEdit(
        opId: '44444444-4444-4444-8444-444444444444',
        entity: LocalEntity.song,
        entityId: '33333333-3333-4333-8333-333333333333',
        operation: LocalOperation.create,
        baseRevision: 0,
        draft: {'title': 'unsubmitted'},
        changes: {'title': 'unsubmitted'},
      ),
    );
    await pages();
    await expectLater(store.applySnapshotDownload(token), throwsStateError);
    expect(await store.readCursor(), isNull);
    await store.verifySnapshotDownload(token);
    await store.applySnapshotDownload(token);
    expect(await store.readCursor(), 7);
    final baseline = await store.snapshotBaselinePage('SONG');
    expect(baseline.token, token);
    expect(baseline.cursor, 7);
    expect(baseline.entries.single.payload['note'], '한글 🎵');
    expect(baseline.hasMore, isFalse);
    expect(
      (await store.pendingMutations()).single.payload,
      contains('unsubmitted'),
    );
    expect(
      (await store.readMetadata(
        LocalEntity.song,
        '33333333-3333-4333-8333-333333333333',
      ))!.localJson,
      contains('unsubmitted'),
    );
    await expectLater(
      store.snapshotBaselinePage('SONG', expectedToken: owner),
      throwsStateError,
    );
    await expectLater(
      store.snapshotBaselinePage('SONG', after: 1),
      throwsStateError,
    );
    now = now.add(const Duration(hours: 1));
    await manager.logout();
    store = await manager.openAccount(owner);
    expect(
      (await store.snapshotBaselinePage('SONG', expectedToken: token)).entries,
      hasLength(1),
    );
    await store.applySnapshotDownload(token);
    await store.discardSnapshotDownload(token);
    expect((await store.snapshotBaselinePage('SONG')).token, token);
  });
  test(
    'final apply failure rolls back pointer, state and cursor atomically',
    () async {
      final native = sqlite.sqlite3.openInMemory();
      final db = AccountDatabase(
        NativeDatabase.opened(native),
        userId: owner,
        environment: AppEnvironment.dev,
      );
      var revokeAfterWrite = false;
      final downloads = SnapshotDownloadStore(
        db,
        clock: () => now,
        requireActive: () {
          if (revokeAfterWrite &&
              native
                      .select('SELECT state FROM snapshot_downloads')
                      .single['state'] ==
                  'APPLIED') {
            throw StateError('synthetic account revocation after writes');
          }
        },
      );
      try {
        await db.verifyReady();
        await downloads.begin(token, jsonEncode(fixture['manifest']));
        for (final page in fixture['pages'] as List) {
          await downloads.append(
            token,
            page['entity'] as String,
            0,
            jsonEncode(page),
          );
        }
        await downloads.verify(token);
        revokeAfterWrite = true;
        await expectLater(downloads.apply(token), throwsStateError);
        expect(
          await db.customSelect('SELECT * FROM snapshot_baseline').get(),
          isEmpty,
        );
        expect(
          (await db
                  .customSelect('SELECT state FROM snapshot_downloads')
                  .getSingle())
              .read<String>('state'),
          'VERIFIED',
        );
        expect(
          (await db
                  .customSelect('SELECT last_change_seq FROM sync_cursors')
                  .getSingle())
              .readNullable<int>('last_change_seq'),
          isNull,
        );
        revokeAfterWrite = false;
        await downloads.apply(token);
        expect(
          (await db
                  .customSelect('SELECT last_change_seq FROM sync_cursors')
                  .getSingle())
              .read<int>('last_change_seq'),
          7,
        );
      } finally {
        await db.close();
      }
    },
  );
  test('older baseline never rewinds an already acknowledged cursor', () async {
    final db = AccountDatabase(
      NativeDatabase.memory(),
      userId: owner,
      environment: AppEnvironment.dev,
    );
    final downloads = SnapshotDownloadStore(
      db,
      clock: () => now,
      requireActive: () {},
    );
    try {
      await db.verifyReady();
      await downloads.begin(token, jsonEncode(fixture['manifest']));
      for (final page in fixture['pages'] as List) {
        await downloads.append(
          token,
          page['entity'] as String,
          0,
          jsonEncode(page),
        );
      }
      await downloads.verify(token);
      await db.customStatement(
        'UPDATE sync_cursors SET last_change_seq=8,baseline_complete=1',
      );
      await expectLater(downloads.apply(token), throwsStateError);
      expect(
        await db.customSelect('SELECT * FROM snapshot_baseline').get(),
        isEmpty,
      );
      expect(
        (await db
                .customSelect('SELECT state FROM snapshot_downloads')
                .getSingle())
            .read<String>('state'),
        'VERIFIED',
      );
      expect(
        (await db
                .customSelect('SELECT last_change_seq FROM sync_cursors')
                .getSingle())
            .read<int>('last_change_seq'),
        8,
      );
    } finally {
      await db.close();
    }
  });
  test(
    'lost final account fence rolls back page and progress together',
    () async {
      final db = AccountDatabase(
        NativeDatabase.memory(),
        userId: owner,
        environment: AppEnvironment.dev,
      );
      var active = true, checks = 0;
      final downloads = SnapshotDownloadStore(
        db,
        clock: () => now,
        requireActive: () {
          if (!active && ++checks == 2) {
            throw StateError('synthetic lost account lease');
          }
        },
      );
      try {
        await db.verifyReady();
        await downloads.begin(token, jsonEncode(fixture['manifest']));
        final page = (fixture['pages'] as List).singleWhere(
          (p) => p['entity'] == 'SONG',
        );
        active = false;
        await expectLater(
          downloads.append(token, 'SONG', 0, jsonEncode(page)),
          throwsStateError,
        );
        expect(
          await db.customSelect('SELECT * FROM snapshot_download_rows').get(),
          isEmpty,
        );
        expect(
          await db
              .customSelect('SELECT * FROM snapshot_download_progress')
              .get(),
          isEmpty,
        );
      } finally {
        await db.close();
      }
    },
  );
}
