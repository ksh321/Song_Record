import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/features/playlists/playlist_library.dart';

import '../tool/playlist_addition_fixture.dart';

void main() {
  test('batch summaries match visible ordered items and exclude deleted/other owners', () async {
    final root = await Directory.systemTemp.createTemp(
      'playlist-summary-batch-',
    );
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    try {
      final repo = LocalRepository(
        await manager.openAccount(playlistFixtureId(1909)),
      );
      final fixture = PlaylistAdditionFixture(repo);
      await fixture.initialize();
      final library = PlaylistLibrary(repo);
      await library.addRegisteredMany(fixture.playlistId, [
        playlistFixtureId(1910),
        playlistFixtureId(1911),
      ], afterEach: fixture.synchronize);
      final empty = await library.createVisible('empty');
      final batch = await repo.playlistSummaryItems();
      expect(
        batch[fixture.playlistId],
        await library.items(fixture.playlistId),
      );
      expect(batch[fixture.playlistId], isNotEmpty);
      expect(batch[empty['id']], isEmpty);
      final summaries = await library.summaries(await library.load());
      expect(
        summaries[fixture.playlistId]!.count,
        (await library.items(fixture.playlistId)).length,
      );
      await library.delete(empty)();
      expect(
        (await repo.playlistSummaryItems()).containsKey(empty['id']),
        isFalse,
      );
      final other = LocalRepository(
        await manager.openAccount(playlistFixtureId(1919)),
      );
      expect(await other.playlistSummaryItems(), isEmpty);
      await expectLater(repo.playlistSummaryItems(), throwsStateError);
    } finally {
      await manager.logout();
      await root.delete(recursive: true);
    }
  });

  test(
    'preview counts registered and standalone candidates, not missing songs',
    () {
      final summary = PlaylistSummary.fromItems(
        [
          {'song_id': 'active'},
          {
            'candidate_brand': 'TJ',
            'candidate_snapshot': {'title': '후보 곡'},
          },
          {
            'song_id': 'trashed',
            'candidate_brand': 'TJ',
            'candidate_snapshot': {'title': '지운 곡'},
          },
          {
            'candidate_brand': 'KY',
            'candidate_snapshot': {'title': '지원하지 않는 후보'},
          },
          {'song_id': 'third'},
        ],
        {
          'active': {'title': '현재 곡'},
          'third': {'title': '다음 곡'},
        },
      );
      expect(summary.count, 3);
      expect(summary.preview, '현재 곡 · 후보 곡');
      expect(PlaylistSummary.fromItems([], {}).preview, '첫 곡을 담아보세요');
      expect(PlaylistSummary.fromItems([], {}).count, 0);
    },
  );
}
