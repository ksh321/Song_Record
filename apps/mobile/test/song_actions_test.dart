import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/songs/my_song.dart';
import 'package:song_record/features/songs/my_songs_screen.dart';
import 'package:song_record/features/songs/song_action_entry.dart';
import 'package:song_record/features/songs/song_detail_screen.dart';
import 'package:song_record/features/songs/unlinked_recordings_screen.dart';

import 'auth_session_test.dart' as auth_fixtures;
import 'song_detail_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('unlinked read includes only current account active saved records, preserves snapshots and writes nothing', () async {
    final root = await Directory.systemTemp.createTemp('p17-unlinked-');
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    try {
      final store = await manager.openAccount(fixture.id(1)),
          repo = LocalRepository(store);
      for (final n in [30, 31, 32, 33, 34]) {
        final r = {
          ...fixture.recording(n),
          'song_id': n == 34 ? fixture.id(10) : null,
          if (n == 31) 'metadata_state': 'DRAFT',
          if (n == 32) 'lifecycle_state': 'TRASHED',
          if (n == 33) 'recorded_at': '2026-01-02T00:00:00Z',
        };
        await repo.save(
          repo.prepareCreate(
            entity: LocalEntity.recording,
            entityId: fixture.id(n),
            draft: r,
            changes: r,
          ),
        );
      }
      final before = (await repo.pending()).map((m) => m.payload).toList();
      final rows = await store.readUnlinkedRecordings();
      expect(rows.map((r) => r['id']).toList(), [
        fixture.id(33),
        fixture.id(30),
      ]);
      expect(rows.first['title_snapshot'], '녹음 당시 제목');
      expect((await repo.pending()).map((m) => m.payload).toList(), before);
      final b = await manager.openAccount(fixture.id(2));
      expect(await b.readUnlinkedRecordings(), isEmpty);
      await expectLater(store.readUnlinkedRecordings(), throwsStateError);
    } finally {
      await manager.logout();
      await root.delete(recursive: true);
    }
  });
  testWidgets(
    'registered song uses explicit add button and separate bottom delete entry without executing mutations',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: SongDetailScreen(watch: () => Stream.value(fixture.detail())),
        ),
      );
      await tester.pumpAndSettle();
      final add = find.widgetWithText(FilledButton, '플레이리스트 추가');
      await tester.scrollUntilVisible(
        add,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(
        find.text('플레이리스트 선택·추가 기능을 준비 중이에요. 아직 추가되지 않았어요.'),
        findsOneWidget,
      );
      await tester.tap(find.text('돌아가기'));
      await tester.pumpAndSettle();
      final delete = find.widgetWithText(TextButton, '곡 삭제');
      await tester.scrollUntilVisible(
        delete,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(find.text('현재 기기에 연결된 활성 녹음 1개'), findsOneWidget);
      expect(find.text('삭제 전 서버에서 녹음·파일·고정 수를 다시 확인해야 해요.'), findsOneWidget);
      expect(find.textContaining('아직 삭제되지 않았어요.'), findsOneWidget);
    },
  );
  testWidgets(
    'small unlinked count entry opens saved snapshot list independent of song query and view',
    (tester) async {
      final r = {...fixture.recording(30), 'song_id': null};
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: MySongsScreen(
              watch: () => Stream.value([MySong(fixture.song())]),
              onFindSong: () {},
              watchUnlinked: () => Stream.value([r]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '없는곡');
      await tester.pump();
      expect(find.text('등록된 내 곡이 없습니다'), findsOneWidget);
      final entry = find.text('곡 미연결 녹음 (1)');
      await tester.scrollUntilVisible(
        entry,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.text('곡 미연결 녹음 1개'), findsOneWidget);
      expect(find.textContaining('녹음 당시 제목'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'account-bound action and unlinked routes stay hidden after A to B to A',
    (tester) async {
      final api = auth_fixtures.Api();
      final auth = AuthController(
        api: api,
        vault: auth_fixtures.Vault(),
        proofs: auth_fixtures.Proofs(),
        openAccount: (_) async {},
        closeAccount: () async {},
        now: () => auth_fixtures.time,
      );
      await auth.signIn('google');
      final original = auth.session!.userId;
      await tester.pumpWidget(
        MaterialApp(
          home: SongActionEntry(
            action: SongAction.playlistAdd,
            detail: fixture.detail(),
            auth: auth,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('현재곡'), findsOneWidget);
      api.next = auth_fixtures.session(user: 'account-b');
      await auth.signIn('google');
      await tester.pump();
      expect(find.text('현재곡'), findsNothing);
      api.next = auth_fixtures.session(user: original);
      await auth.signIn('google');
      await tester.pump();
      expect(find.text('현재곡'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: UnlinkedRecordingsScreen(
            watch: () => Stream.value([
              {...fixture.recording(30), 'song_id': null},
            ]),
            auth: auth,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('녹음 당시 제목'), findsOneWidget);
      api.next = auth_fixtures.session(user: 'account-b');
      await auth.signIn('google');
      await tester.pump();
      expect(find.textContaining('녹음 당시 제목'), findsNothing);
      api.next = auth_fixtures.session(user: original);
      await auth.signIn('google');
      await tester.pump();
      expect(find.textContaining('녹음 당시 제목'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
    },
  );
}
