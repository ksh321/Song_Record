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
  test('candidate link preserves identity and order through rejection, lost reply and restart', () async {
    final root = await Directory.systemTemp.createTemp('p19-link-');
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    try {
      final repo = LocalRepository(
        await manager.openAccount(playlistFixtureId(1902)),
      );
      final fixture = PlaylistAdditionFixture(repo);
      await fixture.initialize();
      final library = PlaylistLibrary(repo);
      await library.addCandidate(
        (await library.load()).single,
        'isolated-tj-candidate',
      )();
      await fixture.synchronize();
      final original = (await library.items(fixture.playlistId)).single;
      for (final song in [playlistFixtureId(1910), playlistFixtureId(1911)]) {
        // Each rejected head must remain FAILED, so use a separate account
        // store for each rejection rather than erasing it to run a later edit.
        final rejectedRoot = await Directory.systemTemp.createTemp(
          'p19-rejected-link-',
        );
        final rejectedManager = AccountStoreManager(
          environment: AppEnvironment.dev,
          directory: () async => rejectedRoot,
          temporaryDirectory: () async => rejectedRoot,
        );
        try {
          final rejectedRepo = LocalRepository(
            await rejectedManager.openAccount(playlistFixtureId(1902)),
          );
          final fixture = PlaylistAdditionFixture(rejectedRepo);
          await fixture.initialize();
          final library = PlaylistLibrary(rejectedRepo);
          await library.addCandidate(
            (await library.load()).single,
            'isolated-tj-candidate',
          )();
          await fixture.synchronize();
          final original = (await library.items(fixture.playlistId)).single;
          await library.linkCandidate(
            (await library.load()).single,
            original['id'] as String,
            song,
          )();
          await fixture.synchronize();
          expect((await library.items(fixture.playlistId)).single, original);
          expect((await library.load()).single['revision'], 2);
          expect(fixture.requests.last.method, 'PATCH');
          expect((await rejectedRepo.pendingWork()).single.state, 'FAILED');
        } finally {
          await rejectedManager.logout();
          await rejectedRoot.delete(recursive: true);
        }
      }
      final matching = playlistFixtureId(1955);
      fixture.songs[matching] = {
        ...fixture.songs[playlistFixtureId(1910)]!,
        'id': matching,
        'tj_number': '00555',
      };
      await repo.save(
        repo.prepareCreate(
          entity: LocalEntity.song,
          entityId: matching,
          draft: fixture.songs[matching]!,
          changes: {'source_type': 'TJ', 'source_token': 'fixture-matching'},
        ),
      );
      await fixture.synchronize();
      fixture.loseNextAddition = true;
      await library.linkCandidate(
        (await library.load()).single,
        original['id'] as String,
        matching,
      )();
      await fixture.synchronize();
      final lost = fixture.requests.last;
      expect(lost.method, 'PATCH');
      expect(lost.body, isNot(contains('item_id')));
      expect(
        await repo.retryMutation(lost.mutation.opId, expectedAttempt: 1),
        isTrue,
      );
      await fixture.synchronize();
      final linked = (await library.items(fixture.playlistId)).single;
      expect(linked['id'], original['id']);
      expect(linked['position'], original['position']);
      expect(linked['candidate_snapshot'], original['candidate_snapshot']);
      expect(linked['song_id'], matching);
      expect((await library.load()).single['revision'], 3);
      await library.linkCandidate(
        (await library.load()).single,
        linked['id'] as String,
        matching,
      )();
      await fixture.synchronize();
      expect((await library.load()).single['revision'], 3);
      await manager.logout();
      final reopened = PlaylistLibrary(
        LocalRepository(await manager.openAccount(playlistFixtureId(1902))),
      );
      expect(
        (await reopened.items(fixture.playlistId)).single['song_id'],
        matching,
      );
    } finally {
      await manager.logout();
      await root.delete(recursive: true);
    }
  });
  test('offline playlist creation resolves an unsent candidate followup without rewriting its original request', () async {
    final root = await Directory.systemTemp.createTemp(
      'p19-offline-candidate-',
    );
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    try {
      final repo = LocalRepository(
        await manager.openAccount(playlistFixtureId(1902)),
      );
      final fixture = PlaylistAdditionFixture(repo);
      fixture.header = {
        'id': fixture.playlistId,
        'name': '오프라인 후보',
        'revision': 1,
        'deleted_at': null,
        'created_at': playlistFixtureTime,
        'updated_at': playlistFixtureTime,
      };
      await repo.save(
        repo.prepareCreate(
          entity: LocalEntity.playlist,
          entityId: fixture.playlistId,
          draft: {'name': '오프라인 후보', 'deleted_at': null},
          changes: {'name': '오프라인 후보'},
        ),
      );
      final library = PlaylistLibrary(repo);
      final row = (await library.load()).single;
      expect(row['local_base_revision'], 0);
      await library.addCandidate(row, 'isolated-tj-candidate')();
      final original = (await repo.pendingWork()).last;
      expect(original.baseRevision, 0);
      await fixture.synchronize();
      expect(await library.items(fixture.playlistId), hasLength(1));
      expect((await library.load()).single['revision'], 2);
      expect(await repo.pendingWork(), isEmpty);
      expect(fixture.requests.last.mutation.opId, isNot(original.opId));
      expect(original.baseRevision, 0);
      expect(fixture.requests.last.body, contains('"base_revision":1'));
    } finally {
      await manager.logout();
      await root.delete(recursive: true);
    }
  });
  test('verified candidate persists without a song; duplicate and rejected KY preserve IDs/order', () async {
    final root = await Directory.systemTemp.createTemp('p19-candidate-');
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    try {
      final repo = LocalRepository(
        await manager.openAccount(playlistFixtureId(1902)),
      );
      final fixture = PlaylistAdditionFixture(repo);
      await fixture.initialize();
      final library = PlaylistLibrary(repo);
      await library.addCandidate(
        (await library.load()).single,
        'isolated-tj-candidate',
      )();
      await fixture.synchronize();
      final original = (await library.items(fixture.playlistId)).single;
      expect(original['song_id'], isNull);
      expect(original['candidate_number'], '00555');
      expect(original['candidate_snapshot']['title'], '미등록 TJ 후보');
      expect(original['entry_key'], 'tj:00555');
      await library.addCandidate(
        (await library.load()).single,
        'isolated-tj-candidate',
      )();
      await fixture.synchronize();
      expect((await library.items(fixture.playlistId)).single, original);
      expect((await library.load()).single['revision'], 2);
      await library.addCandidate(
        (await library.load()).single,
        'isolated-ky-candidate',
      )();
      await fixture.synchronize();
      expect((await library.items(fixture.playlistId)).single, original);
      expect((await library.load()).single['revision'], 2);
      await manager.logout();
      final restarted = LocalRepository(
        await manager.openAccount(playlistFixtureId(1902)),
      );
      expect(
        (await PlaylistLibrary(restarted).items(fixture.playlistId)).single,
        original,
      );
    } finally {
      await manager.logout();
      await root.delete(recursive: true);
    }
  });
  test(
    'foreign item in addition receipt rolls back parent and items before retry',
    () async {
      final root = await Directory.systemTemp.createTemp('p19-receipt-');
      final manager = AccountStoreManager(
        environment: AppEnvironment.dev,
        directory: () async => root,
        temporaryDirectory: () async => root,
      );
      try {
        final repo = LocalRepository(
          await manager.openAccount(playlistFixtureId(1902)),
        );
        final fixture = PlaylistAdditionFixture(repo);
        await fixture.initialize();
        final library = PlaylistLibrary(repo);
        fixture.corruptNextAdditionOwner = true;
        await library.addRegistered(
          (await library.load()).single,
          playlistFixtureId(1910),
        )();
        await fixture.synchronize();
        expect(await library.items(fixture.playlistId), isEmpty);
        expect((await library.load()).single['revision'], 1);
        final rejected = fixture.requests.last;
        expect(
          await repo.retryMutation(rejected.mutation.opId, expectedAttempt: 1),
          isTrue,
        );
        await fixture.synchronize();
        expect(await library.items(fixture.playlistId), hasLength(1));
        expect((await library.load()).single['revision'], 2);
        expect(fixture.requests.last.hash, rejected.hash);
      } finally {
        await manager.logout();
        await root.delete(recursive: true);
      }
    },
  );
  test('TJ and manual addition, duplicate receipt, lost response and restart keep stable item IDs/positions', () async {
    final root = await Directory.systemTemp.createTemp('p19-addition-');
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    try {
      var repo = LocalRepository(
        await manager.openAccount(playlistFixtureId(1902)),
      );
      final fixture = PlaylistAdditionFixture(repo);
      await fixture.initialize();
      var library = PlaylistLibrary(repo);
      var parent = (await library.load()).single;
      await library.addRegistered(parent, playlistFixtureId(1910))();
      await fixture.synchronize();
      final first = (await library.items(fixture.playlistId)).single;
      expect(first['entry_key'], 'tj:00123');
      expect(first['position'], 0);
      parent = (await library.load()).single;
      await library.addRegistered(parent, playlistFixtureId(1910))();
      await fixture.synchronize();
      expect(
        (await library.items(fixture.playlistId)).single['id'],
        first['id'],
      );
      expect((await library.load()).single['revision'], 2);
      await library.rename((await library.load()).single, '이름 변경 후 추가')();
      await fixture.synchronize();
      await library.addRegistered(
        (await library.load()).single,
        playlistFixtureId(1910),
      )();
      await fixture.synchronize();
      expect(
        (await library.items(fixture.playlistId)).single['id'],
        first['id'],
      );
      expect((await library.load()).single['name'], '이름 변경 후 추가');
      expect((await library.load()).single['revision'], 3);
      parent = (await library.load()).single;
      fixture.loseNextAddition = true;
      await library.addRegistered(parent, playlistFixtureId(1911))();
      await fixture.synchronize();
      final lost = fixture.requests.last;
      await manager.logout();
      repo = LocalRepository(
        await manager.openAccount(playlistFixtureId(1902)),
      );
      library = PlaylistLibrary(repo);
      expect(
        await repo.retryMutation(lost.mutation.opId, expectedAttempt: 1),
        isTrue,
      );
      expect(
        await repo.dispatch(transport: fixture, session: fixture.session),
        1,
      );
      final after = await library.items(fixture.playlistId);
      expect(after, hasLength(2));
      expect(after.first['id'], first['id']);
      expect(after.last['entry_key'], 'manual:${playlistFixtureId(1911)}');
      expect(after.last['position'], 1);
      expect(fixture.requests.last.hash, lost.hash);
      expect(fixture.requests.last.body, lost.body);
      expect(await repo.pendingWork(), isEmpty);
      await manager.logout();
      repo = LocalRepository(
        await manager.openAccount(playlistFixtureId(1902)),
      );
      expect(
        await PlaylistLibrary(repo).items(fixture.playlistId),
        hasLength(2),
      );
      await manager.openAccount(playlistFixtureId(1903));
      await expectLater(library.load(), throwsStateError);
    } finally {
      await manager.logout();
      await root.delete(recursive: true);
    }
  });
}
