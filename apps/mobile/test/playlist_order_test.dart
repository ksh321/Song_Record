import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/playlist_addition_receipt.dart';
import 'package:song_record/features/playlists/playlist_library.dart';
import 'package:song_record/features/playlists/playlist_order_picker.dart';

import '../tool/playlist_addition_fixture.dart';

void main() {
  testWidgets('order controls move full IDs; cancel is null', (t) async {
    List<String>? result;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showModalBottomSheet<List<String>>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const SizedBox(
                    height: 500,
                    child: PlaylistOrderPicker(
                      items: [
                        {'id': 'a'},
                        {'id': 'b'},
                      ],
                      titles: {'a': '첫 곡', 'b': '둘째 곡'},
                    ),
                  ),
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('2번 위로'));
    await t.pump();
    await t.tap(find.text('취소'));
    await t.pumpAndSettle();
    expect(result, isNull);
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('2번 위로'));
    await t.pump();
    await t.tap(find.text('순서 저장'));
    await t.pumpAndSettle();
    expect(result, ['b', 'a']);
  });
  test('order ACK validates complete positions; immutable retry and restart preserve reversed items', () async {
    final root = await Directory.systemTemp.createTemp('p19-order-');
    var now = DateTime.utc(2026, 10, 11);
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
      clock: () => now,
    );
    try {
      final repo = LocalRepository(
        await manager.openAccount(playlistFixtureId(1908)),
      );
      final fixture = PlaylistAdditionFixture(repo);
      await fixture.initialize();
      final library = PlaylistLibrary(repo);
      await library.addRegisteredMany(fixture.playlistId, [
        playlistFixtureId(1910),
        playlistFixtureId(1911),
      ], afterEach: fixture.synchronize);
      final before = await library.items(fixture.playlistId),
          row = (await library.load()).single;
      final ids = before
          .map((x) => x['id'] as String)
          .toList()
          .reversed
          .toList();
      await expectLater(
        library.reorder(row, [ids.first, ids.first]),
        throwsStateError,
      );
      await expectLater(library.reorder(row, [ids.first]), throwsStateError);
      expect(await repo.pendingWork(), isEmpty);
      await library.reorder(row, ids);
      final queued = (await repo.pendingWork()).single;
      expect(jsonDecode(queued.payload)['item_ids'], ids);
      fixture.corruptNextOrder = true;
      await fixture.synchronize();
      expect(await library.items(fixture.playlistId), before);
      expect(await repo.retryMutation(queued.opId, expectedAttempt: 1), isTrue);
      now = now.add(const Duration(minutes: 2));
      await fixture.synchronize();
      final retried = fixture.requests.last;
      decodePlaylistAddition(
        retried,
        fixture.receipts[retried.mutation.opId]!.$2,
      );
      final after = await library.items(fixture.playlistId);
      expect(
        await repo.pendingWork(),
        isEmpty,
        reason:
            'requests=${fixture.requests.where((r) => r.path.endsWith('/order')).length}; '
            'states=${(await repo.pendingWork()).map((m) => m.state).join(',')}',
      );
      expect(after.map((x) => x['id']).toList(), ids);
      expect(after.map((x) => x['position']).toList(), [0, 1]);
      expect(await repo.pendingWork(), isEmpty);
      final requests = fixture.requests
          .where((r) => r.path.endsWith('/order'))
          .toList();
      expect(requests.length, 2);
      expect(requests.first.hash, requests.last.hash);
      await manager.logout();
      final reopen = PlaylistLibrary(
        LocalRepository(await manager.openAccount(playlistFixtureId(1908))),
      );
      expect(
        (await reopen.items(fixture.playlistId)).map((x) => x['id']).toList(),
        ids,
      );
    } finally {
      await manager.logout();
      await root.delete(recursive: true);
    }
  });
}
