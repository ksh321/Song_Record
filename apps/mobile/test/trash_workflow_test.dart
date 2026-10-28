import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/features/songs/my_song.dart';
import 'package:song_record/features/songs/my_songs_screen.dart';
import 'package:song_record/features/trash/trash_screens.dart';
import 'package:song_record/features/trash/trash_workflow.dart';

import '../tool/trash_verification_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AccountStoreManager manager;
  late TrashVerificationFixture fixture;
  late MemoryTrashJournal journal;
  late TrashWorkflow flow;
  late bool current;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('song-record-trash-ui-');
    manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    final store = await manager.openAccount(trashId(2001));
    fixture = TrashVerificationFixture(store);
    await fixture.initialize();
    journal = MemoryTrashJournal();
    current = true;
    flow = TrashWorkflow(
      repository: fixture.repository,
      api: fixture,
      journal: journal,
      requireCurrent: () {
        if (!current) throw const TrashFailure('계정 변경');
      },
      wakeSync: () {},
    );
  });
  tearDown(() async {
    await manager.logout();
    expect(root.path, contains('song-record-trash-ui-'));
    await root.delete(recursive: true);
  });
  Future<TrashBatch> batch() async => TrashBatch.fromJson(
    Map<String, dynamic>.from(
      ((await flow.page(null))['items'] as List).first as Map,
    ),
  );
  Future<void> delete({bool together = false}) async {
    await flow.trashSong(
      trashId(together ? 2011 : 2010),
      together ? 'SONG_AND_RECORDINGS' : 'SONG_ONLY',
      'a' * 64,
    );
    await fixture.synchronize();
  }

  testWidgets('my song long press opens deletion menu without a mutation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MySongsScreen(
            watch: () => Stream.value([MySong(fixture.songs[trashId(2010)]!)]),
            onFindSong: () {},
            trash: flow,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.text('녹음 유지 검사 곡'));
    await tester.pumpAndSettle();
    expect(find.text('선택한 1곡 삭제'), findsOneWidget);
    expect(find.text('전체 1'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      expect(await fixture.repository.pendingWork(), isEmpty);
    });
  });
  test('received equal local/server copy queues frozen song-only request preserving record', () async {
    await delete();
    expect(fixture.records[trashId(2020)]!['lifecycle_state'], 'ACTIVE');
    expect(fixture.records[trashId(2020)]!['note'], '유지해야 하는 메모');
    expect(
      (await fixture.repository.pending()).where((v) => v.state != 'ACKED'),
      isEmpty,
    );
  });
  test('together deletes only connected records and partial restore does not restore song', () async {
    await delete(together: true);
    final b = await batch();
    final response = await flow.mutate(b, [trashId(2021)], false);
    expect(response['pin_reselection_required'], true);
    expect(fixture.records[trashId(2021)]!['lifecycle_state'], 'ACTIVE');
    expect(fixture.songs[trashId(2011)]!['lifecycle_state'], 'TRASHED');
  });
  test('permanent song removal keeps retained active recording', () async {
    await delete();
    await flow.mutate(await batch(), [trashId(2010)], true);
    expect(fixture.songs[trashId(2010)]!['lifecycle_state'], 'PURGE_PENDING');
    await fixture.completePurge();
    expect(fixture.records[trashId(2020)]!['lifecycle_state'], 'ACTIVE');
    expect(
      (await fixture.repository.read(
        LocalEntity.song,
        trashId(2010),
      ))!.tombstone,
      true,
    );
  });
  test('lost response survives workflow recreation and reuses exact operation/body', () async {
    await delete(together: true);
    fixture.loseResponse = true;
    await expectLater(
      flow.mutate(await batch(), [trashId(2021)], false),
      throwsA(isA<TrashFailure>()),
    );
    expect(journal.value, isNotNull);
    final restarted = TrashWorkflow(
      repository: fixture.repository,
      api: fixture,
      journal: journal,
      requireCurrent: () {},
      wakeSync: () {},
    );
    await restarted.retry();
    expect(fixture.posts.length, 2);
    expect(fixture.posts[0], fixture.posts[1]);
    expect(journal.value, isNull);
  });
  test(
    'failure preserves journal and resource until same request retry',
    () async {
      await delete();
      fixture.fail = true;
      await expectLater(
        flow.mutate(await batch(), [trashId(2010)], true),
        throwsA(isA<TrashFailure>()),
      );
      expect(fixture.songs[trashId(2010)]!['lifecycle_state'], 'TRASHED');
      expect(journal.value, isNotNull);
      fixture.fail = false;
      await flow.retry();
      expect(fixture.posts[0], fixture.posts[1]);
    },
  );
  test('account change blocks read and write before network', () async {
    current = false;
    await expectLater(flow.page(null), throwsA(isA<TrashFailure>()));
    await expectLater(
      flow.trashRecording(trashId(2021), true),
      throwsA(isA<TrashFailure>()),
    );
    expect(fixture.posts, isEmpty);
  });
  test('invalid selected member cannot create durable command', () async {
    await delete();
    await expectLater(
      flow.mutate(await batch(), [trashId(9999)], true),
      throwsA(isA<TrashFailure>()),
    );
    expect(journal.value, isNull);
  });
  test('batch dates must be actual UTC seven day server lifetime', () async {
    await delete();
    final raw = Map<String, dynamic>.from(
      (await flow.page(null))['items'][0] as Map,
    );
    expect(
      () =>
          TrashBatch.fromJson({...raw, 'purge_after': '2026-10-19T08:00:00Z'}),
      throwsFormatException,
    );
  });
  testWidgets('cancel delete does not queue and two modes are visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => DeleteScreen(
                  actions: flow,
                  id: trashId(2010),
                  title: '취소 검사',
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
    expect(find.text('녹음 유지'), findsOneWidget);
    expect(find.text('함께 삭제'), findsOneWidget);
    await tester.ensureVisible(find.text('취소'));
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(fixture.repository.pending), isEmpty);
  });
  testWidgets('recording deletion requires explicit pin-release confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DeleteScreen(
          actions: flow,
          id: trashId(2021),
          title: '녹음 검사',
          recording: true,
        ),
      ),
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '휴지통으로 이동'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('고정 해제를 확인했어요'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '휴지통으로 이동'))
          .onPressed,
      isNotNull,
    );
  });
  testWidgets(
    'partial restore presents count and reselection without silently repinning',
    (tester) async {
      // Start SQLite and UI callbacks in real time; keep the actual production
      // workflow, receipt validation, database receive and domain assertions.
      await tester.runAsync(() async {
        await delete(together: true);
        await tester.pumpWidget(MaterialApp(home: TrashScreen(actions: flow)));
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(find.text('함께 삭제 검사 곡'), findsOneWidget);
        expect(find.text('보존 녹음 2021'), findsOneWidget);
        expect(find.textContaining('합성 가수'), findsWidgets);
        await tester.tap(find.text('복원'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(CheckboxListTile),
            matching: find.textContaining('보존 녹음 2021'),
          ),
        );
        await tester.pump();
        await tester.ensureVisible(find.text('선택 항목 복원'));
        await tester.tap(find.text('선택 항목 복원'));
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(find.textContaining('고정은 다시 선택해야 함'), findsOneWidget);
        expect(fixture.songs[trashId(2011)]!['lifecycle_state'], 'TRASHED');
        expect(fixture.records[trashId(2021)]!['lifecycle_state'], 'ACTIVE');
        final actual = await fixture.repository.read(
          LocalEntity.recording,
          trashId(2021),
        );
        expect(jsonDecode(actual!.serverJson!)['lifecycle_state'], 'ACTIVE');
        expect(fixture.posts.single['body'], {
          'base_revision': 1,
          'item_ids': [trashId(2021)],
        });
      });
    },
  );
  test(
    'TJ reservation requires restore and waits for purge tombstone',
    () async {
      await delete();
      await expectLater(
        fixture.repository.ensureTjAvailable('12345'),
        throwsA(isA<TjTrashReservation>()),
      );
      await flow.mutate(await batch(), [trashId(2010)], true);
      await expectLater(
        fixture.repository.ensureTjAvailable('12345'),
        throwsA(isA<TjTrashReservation>()),
      );
      await fixture.completePurge();
      await fixture.repository.ensureTjAvailable('12345');
    },
  );
  testWidgets(
    'partial purge leaves other trashed members selectable for restore',
    (tester) async {
      await tester.runAsync(() async {
        await delete(together: true);
        await flow.mutate(await batch(), [trashId(2011)], true);
        await tester.pumpWidget(MaterialApp(home: TrashScreen(actions: flow)));
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(find.text('영구 삭제 처리 중'), findsOneWidget);
        await tester.tap(find.text('복원'));
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(CheckboxListTile, '곡 · 함께 삭제 검사 곡'),
          findsNothing,
        );
        await tester.tap(
          find.descendant(
            of: find.byType(CheckboxListTile),
            matching: find.textContaining('보존 녹음 2021'),
          ),
        );
        await tester.pump();
        await tester.ensureVisible(find.text('선택 항목 복원'));
        await tester.tap(find.text('선택 항목 복원'));
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(fixture.records[trashId(2021)]!['lifecycle_state'], 'ACTIVE');
        expect(
          fixture.songs[trashId(2011)]!['lifecycle_state'],
          'PURGE_PENDING',
        );
      });
    },
  );
  test(
    'journal contains frozen request only, never authentication or object keys',
    () async {
      await delete();
      fixture.fail = true;
      await expectLater(
        flow.mutate(await batch(), [trashId(2010)], true),
        throwsA(isA<TrashFailure>()),
      );
      expect(journal.value!.keys.toSet(), {'path', 'operation', 'body'});
      expect(jsonEncode(journal.value), isNot(contains('synthetic')));
    },
  );
  testWidgets('failed purge and retry retain error after listing refresh', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await delete();
      fixture.fail = true;
      await tester.pumpWidget(MaterialApp(home: TrashScreen(actions: flow)));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await tester.tap(find.text('영구 삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('곡 · 녹음 유지 검사 곡'));
      await tester.pump();
      await tester.ensureVisible(find.text('선택 항목 영구 삭제'));
      await tester.tap(find.text('선택 항목 영구 삭제'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.textContaining('삭제 실패 · 다시 시도'), findsOneWidget);
      final saved = jsonEncode(journal.value);
      expect(journal.value, isNotNull);
      expect(fixture.songs[trashId(2010)]!['lifecycle_state'], 'TRASHED');
      await tester.tap(find.text('결과 미확인 요청 다시 확인'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.textContaining('삭제 실패 · 다시 시도'), findsOneWidget);
      expect(jsonEncode(journal.value), saved);
      fixture.fail = false;
      await tester.tap(find.text('결과 미확인 요청 다시 확인'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.textContaining('삭제 실패 · 다시 시도'), findsNothing);
      expect(find.textContaining('영구 삭제 처리 중'), findsWidgets);
      expect(journal.value, isNull);
      expect(fixture.records[trashId(2020)]!['lifecycle_state'], 'ACTIVE');
    });
  });
}
