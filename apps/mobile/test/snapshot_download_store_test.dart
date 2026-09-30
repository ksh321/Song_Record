import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_database.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/database/snapshot_download_store.dart';

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
