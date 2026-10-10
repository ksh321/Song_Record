import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/songs/my_song.dart';
import 'package:song_record/features/songs/my_songs_screen.dart';

String id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
Map<String, Object?> song(int n, String title, {String lifecycle = 'ACTIVE'}) =>
    {
      'id': id(n),
      'title': title,
      'artist': 'Singer',
      'version_code': 'NORMAL',
      'lifecycle_state': lifecycle,
      'tier': null,
      'note': '',
    };
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real local stream excludes deleted songs and candidates; preserves pending edit', () async {
    final root = await Directory.systemTemp.createTemp('p17-local-');
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    StreamIterator<List<Map<String, dynamic>>>? stream;
    try {
      final store = await manager.openAccount(id(1));
      final repo = LocalRepository(store);
      for (final n in [10, 11]) {
        final draft = song(
          n,
          n == 10 ? 'offline song' : 'trash song',
          lifecycle: n == 10 ? 'ACTIVE' : 'TRASHED',
        );
        await repo.save(
          repo.prepareCreate(
            entity: LocalEntity.song,
            entityId: id(n),
            draft: draft,
            changes: draft,
          ),
        );
      }
      await repo.save(
        repo.prepareCreate(
          entity: LocalEntity.playlistItem,
          entityId: id(12),
          draft: {'title': 'external candidate'},
          changes: {'title': 'external candidate'},
        ),
      );
      stream = StreamIterator(repo.watchActiveSongs());
      expect(await stream.moveNext(), isTrue);
      expect(stream.current.map((p) => p['title']), ['offline song']);
      final change = song(10, 'changed offline');
      await repo.save(
        repo.preparePatch(
          entity: LocalEntity.song,
          entityId: id(10),
          baseRevision: 0,
          draft: change,
          changes: {'title': 'changed offline'},
        ),
      );
      expect(
        await stream.moveNext().timeout(const Duration(seconds: 4)),
        isTrue,
      );
      expect(stream.current.single['title'], 'changed offline');
      expect(await repo.pending(), hasLength(4));
    } finally {
      await stream?.cancel();
      await manager.logout();
      await root.delete(recursive: true);
    }
  });
  test(
    'account switch invalidates old lease and never returns another owner song',
    () async {
      final root = await Directory.systemTemp.createTemp('p17-owner-');
      final manager = AccountStoreManager(
        environment: AppEnvironment.dev,
        directory: () async => root,
        temporaryDirectory: () async => root,
      );
      try {
        final a = await manager.openAccount(id(1));
        final repo = LocalRepository(a);
        final draft = song(10, 'owner A');
        await repo.save(
          repo.prepareCreate(
            entity: LocalEntity.song,
            entityId: id(10),
            draft: draft,
            changes: draft,
          ),
        );
        final b = await manager.openAccount(id(2));
        expect(await b.readActiveSongs(), isEmpty);
        await expectLater(a.readActiveSongs(), throwsStateError);
        final reopened = await manager.openAccount(id(1));
        expect((await reopened.readActiveSongs()).single['title'], 'owner A');
      } finally {
        await manager.logout();
        await root.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'local partial title/artist search trims spaces and ASCII case; explicit discovery',
    (tester) async {
      final data = StreamController<List<MySong>>();
      var finds = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: MySongsScreen(
              watch: () => data.stream,
              onFindSong: () {
                finds++;
              },
            ),
          ),
        ),
      );
      data.add([
        MySong(song(10, '한글 (LIVE)')),
        MySong({...song(11, 'Other'), 'artist': 'Someone'}),
      ]);
      await tester.pump();
      expect(find.text('한글 (LIVE)'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '  sInGeR ');
      await tester.pump();
      expect(find.text('한글 (LIVE)'), findsOneWidget);
      expect(find.text('Other'), findsNothing);
      await tester.enterText(find.byType(TextField), '한글');
      await tester.pump();
      expect(find.text('한글 (LIVE)'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'missing');
      await tester.pump();
      expect(find.text('등록된 내 곡이 없습니다'), findsOneWidget);
      await tester.tap(find.text('새 곡 찾기'));
      expect(finds, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => data.close());
    },
  );
  testWidgets(
    'replaced account stream removes prior rows and late data never reappears',
    (tester) async {
      final a = StreamController<List<MySong>>(),
          b = StreamController<List<MySong>>();
      Future<void> mount(StreamController<List<MySong>> c) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MySongsScreen(watch: () => c.stream, onFindSong: () {}),
          ),
        ),
      );
      await mount(a);
      a.add([MySong(song(10, 'old owner'))]);
      await tester.pump();
      expect(find.text('old owner'), findsOneWidget);
      await mount(b);
      expect(find.text('old owner'), findsNothing);
      a.add([MySong(song(11, 'late old owner'))]);
      b.add([]);
      await tester.pump();
      expect(find.text('late old owner'), findsNothing);
      b.addError(StateError('fixture read failure'));
      await tester.pump();
      expect(find.text('내 곡을 불러오지 못했어요.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await a.close();
        await b.close();
      });
    },
  );
}
