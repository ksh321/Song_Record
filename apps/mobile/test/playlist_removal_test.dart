import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/features/playlists/playlist_library.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../tool/playlist_addition_fixture.dart';
import 'recording_tier_dispatch_test.dart' show snapshot, rec;

void main() {
  test('remove one item rolls back a bad receipt, retries identically and preserves songs and remaining position', () async {
    final root = await Directory.systemTemp.createTemp('p19-remove-');
    var now = DateTime.utc(2026, 10, 11);
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
      clock: () => now,
    );
    final owner = playlistFixtureId(1909);
    try {
      final repo = LocalRepository(await manager.openAccount(owner));
      final fixture = PlaylistAdditionFixture(repo);
      await fixture.initialize();
      final library = PlaylistLibrary(repo);
      await library.addRegisteredMany(fixture.playlistId, [
        playlistFixtureId(1910),
        playlistFixtureId(1911),
      ], afterEach: fixture.synchronize);
      final before = await library.items(fixture.playlistId),
          songs = await library.songs();
      final row = (await library.load()).single,
          target = before.first['id'] as String;
      final hiddenId = playlistFixtureId(2099),
          batchId = playlistFixtureId(2098);
      final paths = await AccountPaths.create(root, owner, AppEnvironment.dev);
      final db = sqlite.sqlite3.open((await paths.databaseFile()).path);
      final hidden = {
        ...before.first,
        'id': hiddenId,
        'song_id': null,
        'candidate_brand': 'TJ',
        'candidate_number': '00999',
        'candidate_snapshot': {'title': '휴지통 연계 후보', 'artist': '합성 자료'},
        'entry_key': 'tj:00999',
        'position': 9,
        'hidden_by_batch_id': batchId,
      };
      final recording = jsonEncode(snapshot(1, null));
      try {
        for (final entry in [
          (
            'PLAYLIST_ITEM',
            hiddenId,
            row['revision'] as int,
            jsonEncode(hidden),
          ),
          ('RECORDING', rec, 1, recording),
        ]) {
          db.execute(
            'INSERT INTO metadata_copies(user_id,entity_type,entity_id,server_revision,server_payload,updated_at) VALUES(?,?,?,?,?,?)',
            [
              owner,
              entry.$1,
              entry.$2,
              entry.$3,
              entry.$4,
              now.millisecondsSinceEpoch,
            ],
          );
        }
      } finally {
        db.close();
      }
      await expectLater(
        library.removeItem(row, playlistFixtureId(9999)),
        throwsStateError,
      );
      expect(await repo.pendingWork(), isEmpty);
      await library.removeItem(row, target);
      final queued = (await repo.pendingWork()).single;
      fixture.corruptNextAdditionOwner = true;
      await fixture.synchronize();
      expect(await library.items(fixture.playlistId), before);
      expect(await repo.retryMutation(queued.opId, expectedAttempt: 1), isTrue);
      now = now.add(const Duration(minutes: 2));
      await fixture.synchronize();
      expect(await repo.pendingWork(), isEmpty);
      final remaining = (await library.items(fixture.playlistId)).single;
      expect(remaining['id'], before.last['id']);
      expect(remaining['position'], before.last['position']);
      expect(
        (await repo.read(LocalEntity.playlistItem, target))!.tombstone,
        isTrue,
      );
      expect(await library.songs(), songs);
      expect(
        (await repo.read(LocalEntity.playlistItem, hiddenId))!.tombstone,
        isFalse,
      );
      expect(
        jsonDecode(
          (await repo.read(LocalEntity.playlistItem, hiddenId))!.serverJson!,
        )['hidden_by_batch_id'],
        batchId,
      );
      expect(
        (await repo.read(LocalEntity.recording, rec))!.serverJson,
        recording,
      );
      final requests = fixture.requests
          .where((r) => r.method == 'DELETE' && r.path.contains('/items/'))
          .toList();
      expect(requests.length, 2);
      expect(requests.first.hash, requests.last.hash);
      expect(requests.first.body, requests.last.body);
      await manager.logout();
      final reopened = PlaylistLibrary(
        LocalRepository(await manager.openAccount(owner)),
      );
      expect(
        (await reopened.items(fixture.playlistId)).single['id'],
        before.last['id'],
      );
      expect(await reopened.songs(), songs);
    } finally {
      await manager.logout();
      await root.delete(recursive: true);
    }
  });
  test('whole playlist deletion hides its members and preserves every song after restart', () async {
    final root = await Directory.systemTemp.createTemp('p19-delete-');
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    final owner = playlistFixtureId(1909);
    try {
      final repo = LocalRepository(await manager.openAccount(owner)),
          fixture = PlaylistAdditionFixture(repo);
      await fixture.initialize();
      final library = PlaylistLibrary(repo);
      await library.addRegisteredMany(fixture.playlistId, [
        playlistFixtureId(1910),
        playlistFixtureId(1911),
      ], afterEach: fixture.synchronize);
      final songs = await library.songs();
      await library.delete((await library.load()).single)();
      expect(await library.load(), isEmpty);
      expect(await library.items(fixture.playlistId), isEmpty);
      await fixture.synchronize();
      expect(await repo.pendingWork(), isEmpty);
      expect(await library.songs(), songs);
      await manager.logout();
      final reopened = PlaylistLibrary(
        LocalRepository(await manager.openAccount(owner)),
      );
      expect(await reopened.load(), isEmpty);
      expect(await reopened.items(fixture.playlistId), isEmpty);
      expect(await reopened.songs(), songs);
    } finally {
      await manager.logout();
      await root.delete(recursive: true);
    }
  });
}
