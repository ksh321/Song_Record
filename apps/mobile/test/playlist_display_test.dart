import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/playlists/playlist_detail_screen.dart';
import 'package:song_record/features/playlists/playlist_library.dart';
import 'package:song_record/features/search/karaoke_search.dart';

import '../tool/playlist_addition_fixture.dart';
import '../tool/playlist_display_fixture.dart';

void main() {
  testWidgets(
    'registered live edits, candidate isolation, item ACK and logout',
    (tester) async {
      late Directory root;
      late AccountStoreManager manager;
      late PlaylistAdditionFixture fixture;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('p19-display-');
        manager = AccountStoreManager(
          environment: AppEnvironment.dev,
          directory: () async => root,
          temporaryDirectory: () async => root,
        );
        fixture = PlaylistAdditionFixture(
          LocalRepository(await manager.openAccount(playlistFixtureId(1905))),
        );
        await preparePlaylistDisplay(fixture);
      });
      final library = PlaylistLibrary(fixture.repository);
      String? openedSong;
      final queries = <KaraokeQuery>[];
      Future<void> settleRead() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 120)),
        );
        await tester.pump();
      }

      try {
        await tester.runAsync(
          () => tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: PlaylistDetailScreen(
                library: library,
                id: fixture.playlistId,
                onOpenSong: (id) => openedSong = id,
                searchLoad: (query) async {
                  queries.add(query);
                  return [
                    KaraokeCandidate(
                      brand: KaraokeBrand.tj,
                      number: '00555',
                      title: '미등록 TJ 후보',
                      artist: '후보 가수',
                      provider: 'synthetic',
                      sourceRef: 'synthetic',
                      sourceToken: 'synthetic-fresh-proof',
                      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
                    ),
                  ];
                },
              ),
            ),
          ),
        );
        await settleRead();
        expect(find.text('TJ 검사 곡'), findsOneWidget);
        expect(find.text('미등록 TJ 후보'), findsOneWidget);
        expect(find.text('후보 가수'), findsOneWidget);
        expect(find.text('내 곡 미등록'), findsNothing);
        expect(find.text('미정'), findsNWidgets(2)); // registered tier + key only
        expect(find.text('TJ 00555'), findsOneWidget);
        await tester.tap(find.text('TJ 검사 곡'));
        expect(openedSong, playlistFixtureId(1910));
        await tester.runAsync(() => tester.tap(find.text('미등록 TJ 후보')));
        await settleRead();
        await tester.pumpAndSettle();
        expect(queries.single.kind, KaraokeKind.number);
        expect(queries.single.text, '00555');
        expect(find.widgetWithText(TextFormField, '곡명'), findsOneWidget);
        await tester.tap(find.text('취소'));
        await tester.pumpAndSettle();
        // Navigator completes after the exit animation; only then does the
        // picker refresh SQLite and release its busy state.
        await settleRead();
        expect(find.text('미등록 TJ 후보'), findsOneWidget);
        expect(find.text('목록에서 제거'), findsNothing);
        await tester.tap(find.byTooltip('곡 메뉴').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('목록에서 제거'));
        await tester.pumpAndSettle();
        expect(find.text('이 목록에서만 제거해요. 내 곡과 녹음은 그대로 유지돼요.'), findsOneWidget);
        await tester.tap(find.text('취소'));
        await tester.pumpAndSettle();
        expect(find.text('TJ 검사 곡'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, '곡 추가'));
        await tester.pumpAndSettle();
        expect(find.text('내 곡에서 선택'), findsOneWidget);
        expect(find.text('직접 등록'), findsOneWidget);
        Navigator.of(tester.element(find.text('직접 등록'))).pop();
        await tester.pumpAndSettle();

        await tester.runAsync(() => editPlaylistDisplaySong(fixture));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1200)),
        );
        await settleRead();
        expect(find.text('수정 반영 곡'), findsOneWidget);
        expect(find.text('수정 가수 · LIVE'), findsOneWidget);
        expect(find.text('A'), findsOneWidget);
        expect(find.text('남 +2'), findsOneWidget);
        expect(find.text('후보 가수'), findsOneWidget);

        // Changes to items without changes to songs also refresh automatically.
        await tester.runAsync(() async {
          await library.addRegistered(
            (await library.load()).single,
            playlistFixtureId(1911),
          )();
          await fixture.synchronize();
        });
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1200)),
        );
        await settleRead();
        expect(find.text('직접 등록 곡'), findsOneWidget);
        await tester.runAsync(manager.logout);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1200)),
        );
        await settleRead();
        expect(find.text('수정 반영 곡'), findsNothing);
        expect(find.text('미등록 TJ 후보'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      } finally {
        await tester.runAsync(() async {
          await manager.logout();
          await root.delete(recursive: true);
        });
      }
    },
  );
}
