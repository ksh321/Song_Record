import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/features/playlists/playlist_library.dart';
import 'package:song_record/features/playlists/playlist_library_screen.dart';

void main() {
  testWidgets('creation survives a facade refresh of the same active store', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp(
        'playlist-create-refresh-',
      );
      final manager = AccountStoreManager(
        environment: AppEnvironment.dev,
        directory: () async => root,
        temporaryDirectory: () async => root,
      );
      final store = await manager.openAccount(
        '00000000-0000-4000-8000-000000001234',
      );
      final refresh = ValueNotifier(0);
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: ValueListenableBuilder<int>(
              valueListenable: refresh,
              builder: (_, value, child) => PlaylistLibraryScreen(
                library: PlaylistLibrary(LocalRepository(store)),
              ),
            ),
          ),
        );
        final readyDeadline = DateTime.now().add(const Duration(seconds: 10));
        while (DateTime.now().isBefore(readyDeadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
          final button = find.widgetWithText(FilledButton, '새 플레이리스트');
          if (button.evaluate().isNotEmpty &&
              tester.widget<FilledButton>(button).onPressed != null) {
            break;
          }
        }
        await tester.pumpAndSettle();
        await tester.tap(find.text('새 플레이리스트'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '새 시험 목록');
        await tester.tap(find.text('별'));
        refresh.value++;
        await tester.pumpAndSettle();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.tap(find.text('만들기'));
        await tester.pumpAndSettle();
        final savedDeadline = DateTime.now().add(const Duration(seconds: 10));
        while ((await PlaylistLibrary(LocalRepository(store)).load()).isEmpty &&
            DateTime.now().isBefore(savedDeadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
        await tester.pumpAndSettle();
        final rows = await PlaylistLibrary(LocalRepository(store)).load();
        expect(rows, hasLength(1));
        expect(rows.single['name'], '새 시험 목록');
        expect(rows.single['icon'], 'star');
      } finally {
        await tester.pumpWidget(const SizedBox());
        refresh.dispose();
        await manager.logout();
        await root.delete(recursive: true);
      }
    });
  });
}
