import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/songs/my_song_detail.dart';
import 'package:song_record/features/songs/song_detail_screen.dart';
import 'package:song_record/features/songs/song_edit_screen.dart';

import 'auth_session_test.dart' as auth_fixtures;

String id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
Map<String, Object?> song() => {
  'id': id(10),
  'title': '현재곡',
  'artist': '현재가수',
  'version_code': 'NORMAL',
  'tier': 'A',
  'representative_key_mode': 'MALE',
  'representative_key_shift': 2,
  'note': '곡메모',
  'lifecycle_state': 'ACTIVE',
};
Map<String, Object?> recording(int n) => {
  'id': id(n),
  'song_id': id(10),
  'title_snapshot': '녹음 당시 제목',
  'artist_snapshot': '녹음 당시 가수',
  'version_code': 'LIVE',
  'key_mode': 'FEMALE',
  'key_shift': -1,
  'tier': 'D',
  'note': '녹음메모',
  'metadata_state': 'SAVED',
  'lifecycle_state': 'ACTIVE',
  'recorded_at': '2026-01-01T00:00:00Z',
  'timezone_id': 'Asia/Seoul',
  'timezone_offset_minutes': 540,
};
MySongDetail detail({String? tj}) => MySongDetail({
  'song': {...song(), 'tj_number': ?tj},
  'revision': 0,
  'recordings': [recording(30)],
});
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real detail reads only current active linked saved metadata and preserves snapshots', () async {
    final root = await Directory.systemTemp.createTemp('p17-detail-');
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    try {
      final store = await manager.openAccount(id(1)),
          repo = LocalRepository(store);
      final draft = song();
      await repo.save(
        repo.prepareCreate(
          entity: LocalEntity.song,
          entityId: id(10),
          draft: draft,
          changes: draft,
        ),
      );
      for (final n in [30, 31, 32, 33]) {
        final r = {
          ...recording(n),
          if (n == 31) 'lifecycle_state': 'TRASHED',
          if (n == 32) 'metadata_state': 'DRAFT',
          if (n == 33) 'song_id': id(11),
        };
        await repo.save(
          repo.prepareCreate(
            entity: LocalEntity.recording,
            entityId: id(n),
            draft: r,
            changes: r,
          ),
        );
      }
      final value = MySongDetail(await store.readSongDetail(id(10)));
      expect(value.recordings, hasLength(1));
      expect(value.recordings.single.snapshot.title, '녹음 당시 제목');
      expect(value.recordings.single.snapshot.version.name, 'live');
      expect(value.recordings.single.durationLabel, '길이 정보 없음');
      expect(value.recordings.single.snapshot.note, '녹음메모');
      expect(await repo.pending(), hasLength(5));
      await manager.openAccount(id(2));
      await expectLater(store.readSongDetail(id(10)), throwsStateError);
      final b = await manager.openAccount(id(2));
      expect((await b.readSongDetail(id(10)))['song'], isNull);
    } finally {
      await manager.logout();
      await root.delete(recursive: true);
    }
  });
  for (final light in [false, true]) {
    testWidgets(
      'song memo tap edits only memo and preserves other values light=$light',
      (t) async {
        final data = StreamController<MySongDetail>.broadcast();
        var saves = 0;
        await t.pumpWidget(
          MaterialApp(
            theme: AppTheme.preview(light: light),
            home: SongDetailScreen(
              watch: () => data.stream,
              prepareEdit: (draft) {
                expect(draft.title, '현재곡');
                expect(draft.artist, '현재가수');
                expect(draft.note, '수정한 메모');
                expect(draft.tier?.name, 'a');
                return () async {
                  saves++;
                };
              },
            ),
          ),
        );
        data.add(detail());
        await t.pump();
        final memo = find.byKey(const ValueKey('song-note-detail'));
        await t.ensureVisible(memo);
        await t.tap(memo);
        await t.pumpAndSettle();
        expect(
          t.widget<SongEditScreen>(find.byType(SongEditScreen)).noteOnly,
          isTrue,
        );
        expect(find.byType(TextField), findsOneWidget);
        await t.enterText(find.byType(TextField), '수정한 메모');
        t.testTextInput.hide();
        await t.pump();
        await t.ensureVisible(find.text('저장'));
        await t.tap(find.text('저장'));
        await t.pump();
        expect(saves, 1);
        await t.pumpWidget(const SizedBox());
        await t.runAsync(data.close);
      },
    );
  }
  testWidgets('detail settings opens app settings above the tab navigator', (
    t,
  ) async {
    final data = StreamController<MySongDetail>.broadcast();
    addTearDown(data.close);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        routes: {
          '/settings': (_) =>
              Scaffold(appBar: AppBar(title: const Text('앱 설정 도착'))),
        },
        home: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => SongDetailScreen(watch: () => data.stream),
          ),
        ),
      ),
    );
    data.add(detail());
    await t.pump();
    await t.tap(find.byTooltip('설정'));
    await t.pumpAndSettle();
    expect(find.text('앱 설정 도착'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('곡 상세'), findsOneWidget);
  });
  testWidgets(
    'manual detail shows required fields without language and opens recording snapshot',
    (tester) async {
      final data = StreamController<MySongDetail>.broadcast();
      Stream<MySongDetail> watch() => data.stream;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: SongDetailScreen(watch: watch),
        ),
      );
      data.add(detail());
      await tester.pump();
      expect(find.textContaining('직접 등록'), findsOneWidget);
      expect(find.text('일반 반주'), findsOneWidget);
      expect(find.text('남 +2'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('곡메모'), findsOneWidget);
      expect(find.text('언어'), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('linked-recording-${id(30)}')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(
        find.byKey(ValueKey('linked-recording-${id(30)}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('linked-recording-${id(30)}')));
      await tester.pump();
      data.add(detail());
      await tester.pumpAndSettle();
      expect(find.text('녹음 정보'), findsOneWidget);
      expect(find.text('녹음메모'), findsOneWidget);
      expect(find.text('녹음 티어: D'), findsOneWidget);
      expect(find.text('여 -1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(data.close);
    },
  );
  testWidgets(
    'TJ leading zeros remain and revoked/deleted detail removes prior data',
    (tester) async {
      final data = StreamController<MySongDetail>();
      await tester.pumpWidget(
        MaterialApp(home: SongDetailScreen(watch: () => data.stream)),
      );
      data.add(detail(tj: '00123'));
      await tester.pump();
      expect(find.textContaining('TJ 00123'), findsOneWidget);
      data.add(
        MySongDetail({
          'song': null,
          'revision': 1,
          'recordings': <Map<String, dynamic>>[],
        }),
      );
      await tester.pump();
      expect(find.textContaining('TJ 00123'), findsNothing);
      expect(find.text('현재 계정의 활성 곡을 찾을 수 없어요.'), findsOneWidget);
      data.addError(StateError('lease invalid'));
      await tester.pump();
      await tester.pump();
      expect(find.text('곡 정보를 불러오지 못했어요.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(data.close);
    },
  );
  testWidgets(
    'account switch hides old detail and rejects late old-account events',
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
      final data = StreamController<MySongDetail>.broadcast();
      await tester.pumpWidget(
        MaterialApp(
          home: SongDetailScreen(watch: () => data.stream, auth: auth),
        ),
      );
      data.add(detail(tj: '00123'));
      await tester.pump();
      expect(find.textContaining('TJ 00123'), findsOneWidget);
      api.next = auth_fixtures.session(user: 'account-b');
      await auth.signIn('google');
      data.add(detail(tj: '00123'));
      await tester.pump();
      expect(find.textContaining('TJ 00123'), findsNothing);
      expect(find.text('계정이 변경됐어요. 내 곡 목록에서 다시 열어 주세요.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(data.close);
      auth.dispose();
    },
  );
}
