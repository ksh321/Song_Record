import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/features/playlists/playlist_library.dart';

import '../tool/playlist_addition_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
