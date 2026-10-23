import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/features/playlists/playlist_discovery_screen.dart';
import 'package:song_record/features/playlists/playlist_library.dart';
import 'package:song_record/features/search/search_intent.dart';

import '../tool/playlist_addition_fixture.dart';
import '../tool/playlist_discovery_fixture.dart';

void main() {
  testWidgets(
    'playlist chart KY to TJ selection returns origin; cancel has no result',
    (t) async {
      const intent = SearchIntent(
        purpose: SearchPurpose.playlist,
        playlistId: 'destination',
        returnRoute: '/playlists/destination',
      );
      KaraokeSelection? result;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.push<KaraokeSelection>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlaylistDiscoveryScreen(
                        intent: intent,
                        searchLoad: playlistSearchFixture,
                        chartLoad: playlistChartFixture,
                      ),
                    ),
                  );
                },
                child: const Text('원래 목록'),
              ),
            ),
          ),
        ),
      );
      Future<void> open() async {
        await t.tap(find.text('원래 목록'));
        await t.pumpAndSettle();
        await t.tap(find.text('인기 차트'));
        await t.pumpAndSettle();
        await t.tap(find.text('금영'));
        await t.pumpAndSettle();
        await t.tap(find.text('미등록 TJ 후보'));
        await t.pumpAndSettle();
        await t.tap(find.text('TJ에서 이 곡 찾기'));
        await t.pumpAndSettle();
      }

      await open();
      expect(find.text('TJ에서 찾기'), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      expect(result, isNull);
      expect(find.text('원래 목록'), findsOneWidget);
      await open();
      await t.tap(find.text('미등록 TJ 후보').last);
      await t.pumpAndSettle();
      await t.tap(find.text('목록에 사용할 TJ 곡 선택'));
      await t.pumpAndSettle();
      expect(result!.intent, same(intent));
      expect(result!.candidate.number, '00555');
      expect(find.text('원래 목록'), findsOneWidget);
    },
  );
  test('selected destination queues exact proof; foreign context and cancel preserve DB', () async {
    final root = await Directory.systemTemp.createTemp('p19-discovery-');
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    try {
      final repo = LocalRepository(
        await manager.openAccount(playlistFixtureId(1907)),
      );
      final fixture = PlaylistAdditionFixture(repo);
      await fixture.initialize();
      final library = PlaylistLibrary(repo), id = fixture.playlistId;
      expect(await library.items(id), isEmpty);
      expect(await repo.pendingWork(), isEmpty);
      final foreign = KaraokeSelection(
        playlistTjCandidate,
        const SearchIntent(
          purpose: SearchPurpose.playlist,
          playlistId: 'other',
          returnRoute: '/playlists/other',
        ),
      );
      await expectLater(library.addSelection(id, foreign), throwsStateError);
      expect(await repo.pendingWork(), isEmpty);
      final selected = KaraokeSelection(
        playlistTjCandidate,
        SearchIntent(
          purpose: SearchPurpose.playlist,
          playlistId: id,
          returnRoute: '/playlists/$id',
        ),
      );
      await library.addSelection(id, selected);
      final queued = (await repo.pendingWork()).single;
      expect(queued.entityId, id);
      expect(
        jsonDecode(queued.payload)['source_token'],
        'isolated-tj-candidate',
      );
      await fixture.synchronize();
      final items = await library.items(id);
      expect(items.single['candidate_number'], '00555');
      await manager.logout();
      final reopened = PlaylistLibrary(
        LocalRepository(await manager.openAccount(playlistFixtureId(1907))),
      );
      expect((await reopened.items(id)).single['id'], items.single['id']);
    } finally {
      await manager.logout();
      await root.delete(recursive: true);
    }
  });
}
