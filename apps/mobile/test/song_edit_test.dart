import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/domain/song_types.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/songs/my_song_detail.dart';
import 'package:song_record/features/songs/song_edit.dart';
import 'package:song_record/features/songs/song_edit_screen.dart';

import 'auth_session_test.dart' as auth_fixtures;

String id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
Map<String, Object?> source() => {
  'id': id(10),
  'title': '원곡',
  'artist': '원가수',
  'note': '원메모',
  'version_code': 'NORMAL',
  'tier': 'A',
  'tj_number': '00123',
  'lifecycle_state': 'ACTIVE',
  'representative_key_mode': 'MALE',
  'representative_key_shift': 2,
};
MySongDetail detail(Map<String, Object?> s) => MySongDetail({
  'song': s,
  'revision': 0,
  'recordings': <Map<String, dynamic>>[],
});
void main() {
  test('separate draft saves only changed allowed fields atomically, retries one op, rejects stale local draft and old account', () async {
    final root = await Directory.systemTemp.createTemp('p17-edit-');
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    try {
      final store = await manager.openAccount(id(1)),
          repo = LocalRepository(store);
      await repo.save(
        repo.prepareCreate(
          entity: LocalEntity.song,
          entityId: id(10),
          draft: source(),
          changes: source(),
        ),
      );
      final before = await store.readSongDetail(id(10));
      final draft = SongEditDraft(MySongDetail(before));
      draft.title = '  새 곡  ';
      draft.artist = '새가수';
      draft.note = '새메모';
      draft.version = VersionCode.live;
      draft.musicalKey = null;
      draft.tier = null;
      expect((await store.readSongDetail(id(10)))['song'], source());
      final stale = SongEditDraft(MySongDetail(before))..note = '지난 초안';
      final save = draft.prepare(repo);
      await save();
      await save();
      final current = (await store.readSongDetail(id(10)))['song'] as Map;
      expect(current['title'], '새 곡');
      expect(current['tj_number'], '00123');
      expect(current['representative_key_mode'], isNull);
      expect(current['representative_key_shift'], isNull);
      expect(current['version_code'], 'LIVE');
      expect(current['tier'], isNull);
      expect(await repo.pending(), hasLength(2));
      final queued = (await repo.pending()).last;
      expect(queued.payload, isNot(contains('tj_number')));
      await expectLater(stale.prepare(repo)(), throwsStateError);
      expect(await repo.pending(), hasLength(2));
      final noChange = SongEditDraft(
        MySongDetail(await store.readSongDetail(id(10))),
      );
      await noChange.prepare(repo)();
      expect(await repo.pending(), hasLength(2));
      final old = SongEditDraft(
        MySongDetail(await store.readSongDetail(id(10))),
      )..note = 'A변경';
      final oldSave = old.prepare(repo);
      await manager.openAccount(id(2));
      await expectLater(oldSave(), throwsStateError);
    } finally {
      await manager.logout();
      await root.delete(recursive: true);
    }
  });
  test('validation keeps original and refuses empty title, oversized note', () {
    final original = source();
    final draft = SongEditDraft(detail(original));
    draft.title = ' ';
    expect(() => draft.changes, throwsArgumentError);
    draft.title = '새곡';
    draft.note = '가' * 2001;
    expect(() => draft.changes, throwsArgumentError);
    expect(original, source());
  });
  testWidgets(
    'cancel returns without preparing save; save commits explicit draft once',
    (tester) async {
      var prepared = 0, saved = 0;
      Future<void> Function() prepare(SongEditDraft draft) {
        prepared++;
        expect(draft.title, '수정 제목');
        return () async {
          saved++;
        };
      }

      final original = source();
      Future<void> open() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => SongEditScreen(
                      draft: SongEditDraft(detail(original)),
                      prepare: prepare,
                    ),
                  ),
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('열기'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).at(0), '수정 제목');
        tester.testTextInput.hide();
        await tester.pump();
      }

      await open();
      await tester.scrollUntilVisible(
        find.text('취소'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(prepared, 0);
      expect(saved, 0);
      expect(original, source());
      await open();
      await tester.scrollUntilVisible(
        find.text('저장'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(prepared, 1);
      expect(saved, 1);
      expect(find.text('열기'), findsOneWidget);
    },
  );
  testWidgets(
    'failed save retries same prepared command and blocks duplicate taps',
    (tester) async {
      var prepared = 0, attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SongEditScreen(
            draft: SongEditDraft(detail(source())),
            prepare: (_) {
              prepared++;
              return () async {
                attempts++;
                if (attempts == 1) throw StateError('temporary');
              };
            },
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('저장'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(find.text('같은 변경 다시 저장'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).enabled,
        isFalse,
      );
      await tester.tap(find.text('같은 변경 다시 저장'));
      await tester.pumpAndSettle();
      expect(prepared, 1);
      expect(attempts, 2);
    },
  );
  testWidgets(
    'account change hides draft fields and prevents saving old account',
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
      var prepared = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SongEditScreen(
            draft: SongEditDraft(detail(source())),
            auth: auth,
            prepare: (_) {
              prepared++;
              return () async {};
            },
          ),
        ),
      );
      api.next = auth_fixtures.session(user: 'account-b');
      await auth.signIn('google');
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('저장'), findsNothing);
      expect(prepared, 0);
      expect(find.text('계정이 변경됐어요. 편집을 닫고 다시 열어 주세요.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
    },
  );
}
