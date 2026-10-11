import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/features/playlists/playlist_library.dart';

import '../tool/playlist_addition_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('offline multi selection survives restart and duplicate selection preserves existing IDs and order', () async {
    final root = await Directory.systemTemp.createTemp('p19-multiple-');
    var now = DateTime.now().toUtc();
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
      clock: () => now,
    );
    try {
      var repo = LocalRepository(
        await manager.openAccount(playlistFixtureId(1906)),
      );
      var fixture = PlaylistAdditionFixture(repo);
      await fixture.initialize();
      var library = PlaylistLibrary(repo);
      final ids = [playlistFixtureId(1910), playlistFixtureId(1911)];
      await library.addRegisteredMany(fixture.playlistId, [...ids, ids.first]);
      expect((await repo.pendingWork()).length, 1); // one atomic list mutation
      await expectLater(
        () => library.addRegisteredMany(fixture.playlistId, ids),
        throwsStateError,
      );
      fixture.reverseNextBatchIds = true;
      await fixture.synchronize();
      expect(await library.items(fixture.playlistId), isEmpty);
      expect((await library.load()).single['revision'], 1);
      expect((await repo.pendingWork()).length, 1);
      final rejected = fixture.requests.last;
      expect(
        await repo.retryMutation(rejected.mutation.opId, expectedAttempt: 1),
        isTrue,
      );
      now = now.add(const Duration(minutes: 2)); // retry becomes eligible
      await manager.logout();
      repo = LocalRepository(
        await manager.openAccount(playlistFixtureId(1906)),
      );
      fixture = PlaylistAdditionFixture(repo);
      await fixture.initialize();
      library = PlaylistLibrary(repo);
      final before = await library.items(fixture.playlistId);
      expect(before.map((x) => x['song_id']), ids);
      expect(before.map((x) => x['position']), [0, 1]);
      expect(await repo.pendingWork(), isEmpty);
      expect(fixture.requests.last.hash, rejected.hash);
      await library.addRegisteredMany(
        fixture.playlistId,
        ids,
        afterEach: fixture.synchronize,
      );
      expect(await library.items(fixture.playlistId), before);
      expect(await repo.pendingWork(), isEmpty);
      await expectLater(
        () => library.addRegisteredMany(fixture.playlistId, [
          playlistFixtureId(1999),
        ]),
        throwsStateError,
      );
      final seed = fixture.songs;
      await manager.logout();
      repo = LocalRepository(
        await manager.openAccount(playlistFixtureId(1907)),
      );
      fixture = PlaylistAdditionFixture(repo)..songs.addAll(seed);
      fixture.header = {
        'id': fixture.playlistId,
        'name': '오프라인 다중',
        'revision': 1,
        'deleted_at': null,
        'created_at': playlistFixtureTime,
        'updated_at': playlistFixtureTime,
      };
      for (final id in ids) {
        await repo.save(
          repo.prepareCreate(
            entity: LocalEntity.song,
            entityId: id,
            draft: seed[id]!,
            changes: seed[id]!['source_type'] == 'TJ'
                ? {'source_type': 'TJ', 'source_token': 'isolated-proof'}
                : {
                    'source_type': 'MANUAL',
                    'title': '직접 등록 곡',
                    'artist': '검사 가수',
                  },
          ),
        );
      }
      await repo.save(
        repo.prepareCreate(
          entity: LocalEntity.playlist,
          entityId: fixture.playlistId,
          draft: {'name': '오프라인 다중', 'deleted_at': null},
          changes: {'name': '오프라인 다중'},
        ),
      );
      library = PlaylistLibrary(repo);
      await library.addRegisteredMany(fixture.playlistId, ids);
      final original = (await repo.pendingWork()).last;
      expect(original.baseRevision, 0);
      await fixture.synchronize();
      expect(await library.items(fixture.playlistId), hasLength(2));
      expect(await repo.pendingWork(), isEmpty);
      expect(fixture.requests.last.mutation.opId, isNot(original.opId));
      expect(original.baseRevision, 0);
    } finally {
      await manager.logout();
      await root.delete(recursive: true);
    }
  });
}
