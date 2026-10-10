import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/features/recorder/recording_song_picker.dart';
import 'package:song_record/features/search/karaoke_search.dart';
import 'package:song_record/features/search/karaoke_search_screen.dart';

import 'support/completed_capture_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AccountStoreManager manager;
  late LocalRepository repo;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sr-recording-picker-');
    manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    repo = LocalRepository(await manager.openAccount(owner));
    await capture(repo);
  });
  tearDown(() async {
    await manager.logout();
    await root.delete(recursive: true);
  });

  Future<void> mount(WidgetTester t, {bool outage = false}) async {
    final rows = await t.runAsync(() => repo.watchActiveSongs().first);
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
    });
    await t.pumpWidget(
      MaterialApp(
        home: RecordingSongPicker(
          recordingId: rec,
          repository: repo,
          watchSongs: () => Stream.value(rows!),
          isCurrent: (_) => true,
          discoveryBuilder: (_, destination, prepare) => Scaffold(
            appBar: AppBar(title: const Text('검사 검색')),
            body: KaraokeSearchScreen(
              prepareRegistration: prepare,
              load: (_) async {
                if (outage) throw const KaraokeFailure('외부 장애');
                return [];
              },
            ),
          ),
        ),
      ),
    );
    await t.pump();
  }

  Future<void> song(String id, String title, String artist) => repo.save(
    repo.prepareCreate(
      entity: LocalEntity.song,
      entityId: id,
      draft: {
        'source_type': 'MANUAL',
        'title': title,
        'artist': artist,
        'version_code': 'LIVE',
        'lifecycle_state': 'ACTIVE',
        'tier': null,
      },
      changes: {
        'source_type': 'MANUAL',
        'manual_reason': 'TJ_NOT_FOUND',
        'title': title,
        'artist': artist,
        'version_code': 'LIVE',
        'note': '',
      },
    ),
  );

  testWidgets(
    'many local songs are searchable and selection survives reopen without SAVED/file mutation',
    (t) async {
      await t.runAsync(() async {
        for (var i = 0; i < 80; i++) {
          await song(
            '00000000-0000-4000-8000-${(1900 + i).toString().padLeft(12, '0')}',
            '산책 $i',
            i == 79 ? 'Target Singer' : '가수 $i',
          );
        }
      });
      await mount(t);
      await t.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await t.pump();
      await t.enterText(find.byType(TextField), 'target singer');
      await t.pump();
      expect(find.text('산책 79'), findsOneWidget);
      expect(find.text('산책 0'), findsNothing);
      await t.runAsync(() async {
        await t.tap(find.text('산책 79'));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await t.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await t.pump();
      expect(find.text('선택한 곡: 산책 79'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.runAsync(() async {
        await manager.logout();
        final store = await manager.openAccount(owner);
        repo = LocalRepository(store);
        final row = (await repo.pendingRecordings()).single;
        expect(row['metadata_state'], 'DRAFT');
        expect(row['input_selection']['title_snapshot'], '산책 79');
        expect(row['input_selection']['version_code'], 'LIVE');
        expect(row['input_selection']['key_mode'], 'ORIGINAL');
        expect(await store.readLocalAudio(rec), bytes);
        expect(
          (await repo.pending())
              .where((m) => m.entity == LocalEntity.recording)
              .length,
          1,
        );
      });
    },
  );

  testWidgets(
    'external error never enables manual registration and keeps capture after returning',
    (t) async {
      await mount(t, outage: true);
      await t.tap(find.text('새 곡 찾기'));
      await t.pumpAndSettle();
      await t.tap(find.text('검색'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '없는곡');
      await t.pump(const Duration(milliseconds: 450));
      await t.pump();
      expect(find.text('검색을 완료하지 못했어요.'), findsOneWidget);
      expect(find.text('찾는 곡이 없어요'), findsNothing);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.runAsync(() async {
        expect(
          (await repo.pendingRecordings()).single['input_selection'],
          isNull,
        );
        expect((await repo.pendingRecordings()).single['file'], spec());
      });
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'normal TJ absence alone allows explicit manual registration and captures chosen UUID',
    (t) async {
      await mount(t);
      await t.tap(find.text('새 곡 찾기'));
      await t.pumpAndSettle();
      await t.tap(find.text('검색'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '직접곡');
      await t.pump(const Duration(milliseconds: 450));
      await t.pump();
      await t.tap(find.text('찾는 곡이 없어요'));
      await t.pumpAndSettle();
      await t.tap(find.text('찾는 곡 없음 확인'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('song-artist')), '직접 가수');
      await t.ensureVisible(find.text('이 기기에 저장'));
      await t.runAsync(() async {
        await t.tap(find.text('이 기기에 저장'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await t.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await t.pumpAndSettle();
      await t.runAsync(() async {
        final row = (await repo.pendingRecordings()).single;
        expect(row['input_selection']['title_snapshot'], '직접곡');
        expect(row['input_selection']['artist_snapshot'], '직접 가수');
        expect(row['file'], spec());
        expect(row['metadata_state'], 'DRAFT');
        final linked = await repo.read(
          LocalEntity.song,
          row['input_selection']['song_id'] as String,
        );
        expect(linked, isNotNull);
      });
      await t.pumpWidget(const SizedBox());
    },
  );

  test(
    'unregistered, inactive and stale-account selections write nothing',
    () async {
      await expectLater(
        repo.selectPendingRecordingSong(rec, other),
        throwsStateError,
      );
      await song(other, '휴지통곡', '가수');
      final old = await repo.read(LocalEntity.song, other);
      final local = <String, Object?>{
        'id': other,
        'source_type': 'MANUAL',
        'title': '휴지통곡',
        'artist': '가수',
        'version_code': 'LIVE',
        'lifecycle_state': 'TRASHED',
        'tier': null,
      };
      await repo.save(
        repo.preparePatch(
          entity: LocalEntity.song,
          entityId: other,
          baseRevision: old!.revision,
          draft: local,
          changes: {'title': '휴지통곡'},
        ),
      );
      await expectLater(
        repo.selectPendingRecordingSong(rec, other),
        throwsStateError,
      );
      expect(
        (await repo.pendingRecordings()).single['input_selection'],
        isNull,
      );
      await manager.logout();
      await manager.openAccount(other);
      await expectLater(
        repo.selectPendingRecordingSong(rec, other),
        throwsStateError,
      );
    },
  );
}
