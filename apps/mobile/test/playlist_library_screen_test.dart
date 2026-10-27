import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/mutation_request.dart';
import 'package:song_record/features/playlists/playlist_library.dart';
import 'package:song_record/features/playlists/playlist_library_screen.dart';

import 'auth_session_test.dart' as fixtures;
import 'metadata_dispatcher_test.dart' show FakeTransport;

void main() {
  testWidgets('ACK refresh lets the next icon edit use the current revision', (
    tester,
  ) async {
    late Directory root;
    late AccountStoreManager manager;
    late LocalRepository repo;
    late PlaylistLibrary library;
    final changes = ChangeNotifier();
    final transport = FakeTransport((request) async {
      final body = jsonDecode(request.body) as Map;
      return MutationResponse(
        request.method == 'POST' ? 201 : 200,
        jsonEncode({
          'id': request.mutation.entityId,
          'name': body['name'],
          'icon': body['icon'] ?? 'music',
          'revision': request.mutation.baseRevision + 1,
          'deleted_at': null,
          'updated_at': '2026-10-23T00:00:00Z',
        }),
      );
    });
    Future<void> sync() async {
      await repo.dispatch(
        transport: transport,
        session: () async => fixtures.session(user: repo.userId),
      );
      changes.notifyListeners();
    }

    Future<void> settleReads() async {
      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
          final menus = find.byType(PopupMenuButton<String>);
          if (find.text('시험 목록').evaluate().isNotEmpty &&
              menus.evaluate().length == 1 &&
              tester.widget<PopupMenuButton<String>>(menus).enabled) {
            return;
          }
        }
      });
      await tester.pumpAndSettle();
    }

    Future<void> chooseIcon(String label) => tester.runAsync(() async {
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('아이콘 수정'));
      await tester.pumpAndSettle();
      // The dialog result starts native SQLite work after the exit animation.
      // Keep both the tap and that animation in the real async zone so its
      // transaction can finish before dispatch. Assertions remain unchanged.
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    });

    try {
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('playlist-screen-');
        manager = AccountStoreManager(
          environment: AppEnvironment.dev,
          directory: () async => root,
          temporaryDirectory: () async => root,
        );
        repo = LocalRepository(
          await manager.openAccount('00000000-0000-4000-8000-000000001234'),
        );
        library = PlaylistLibrary(repo);
        await library.create('시험 목록')();
        await sync();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              appBar: AppBar(title: const Text('플레이리스트')),
              body: PlaylistLibraryScreen(
                library: library,
                embedded: true,
                syncChanges: changes,
              ),
            ),
          ),
        );
      });
      await settleReads();
      expect(find.text('플레이리스트'), findsOneWidget);
      await tester.longPress(find.text('시험 목록'));
      await tester.pumpAndSettle();
      expect(find.text('플레이리스트 삭제'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(Dialog), matching: find.text('순서 변경')),
        findsNothing,
      ); // One playlist still has delete.
      await tester.tap(find.text('플레이리스트 삭제'));
      await tester.pumpAndSettle();
      expect(find.text('플레이리스트를 영구 삭제할까요?'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        expect((await library.load()).single['name'], '시험 목록');
        expect(await repo.pendingWork(), isEmpty);
      });

      await chooseIcon('별');
      await tester.runAsync(sync);
      await settleReads();
      await chooseIcon('음표');
      await tester.runAsync(sync);
      await settleReads();
      await tester.runAsync(() async {
        expect((await library.load()).single['icon'], 'music');
        expect(await repo.pendingWork(), isEmpty);
      });
      expect(find.textContaining('저장하지 못했어요'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox());
      changes.dispose();
      await tester.runAsync(() async {
        await manager.logout();
        await root.delete(recursive: true);
      });
    }
  });
}
