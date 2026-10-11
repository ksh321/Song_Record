import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/playlists/playlist_detail_screen.dart';
import 'package:song_record/features/playlists/playlist_library.dart';

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
              ),
            ),
          ),
        );
        await settleRead();
        expect(find.text('TJ 검사 곡'), findsOneWidget);
        expect(find.text('미등록 TJ 후보'), findsOneWidget);
        expect(find.text('후보 가수'), findsOneWidget);
        expect(find.text('내 곡 미등록'), findsOneWidget);
        expect(find.text('미정'), findsNWidgets(2)); // registered tier + key only
        expect(find.text('00555'), findsNothing);

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
