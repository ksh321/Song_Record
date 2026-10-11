import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/domain/identifiers.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/metadata_response.dart';
import 'package:song_record/core/sync/mutation_request.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/songs/my_song_detail.dart';
import 'package:song_record/features/songs/song_detail_screen.dart';
import 'package:song_record/features/songs/song_representative.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'song_detail_test.dart' as fixture;

String id(int n) => fixture.id(n);
MySongDetail roles({String? representative}) => MySongDetail({
  'song': {...fixture.song(), 'representative_recording_id': representative},
  'revision': 1,
  'recordings': [
    {...fixture.recording(30), 'tier': 'B'},
    {
      ...fixture.recording(31),
      'tier': 'D',
      'recorded_at': '2026-01-02T00:00:00Z',
    },
    {
      ...fixture.recording(32),
      'tier': 'A',
      'recorded_at': '2026-01-03T00:00:00Z',
    },
  ],
});
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('three roles stay metadata based and overlap is counted once', () {
    final value = roles(representative: id(30));
    expect(value.roles.representative?.value, id(30));
    expect(value.roles.latest?.value, id(32));
    expect(value.roles.lowestTier?.value, id(31));
    expect(value.roles.uniqueIds, hasLength(3));
    expect(roles(representative: id(32)).roles.uniqueIds, hasLength(2));
    expect(roles(representative: id(99)).roles.representative, isNull);
    final one = fixture.detail();
    expect(one.roles.uniqueIds, hasLength(1));
    final empty = MySongDetail({
      'song': fixture.song(),
      'revision': 0,
      'recordings': <Map<String, Object?>>[],
    });
    expect(empty.roles.uniqueIds, isEmpty);
  });
  test(
    'representative wire uses dedicated PUT, exact fields and explicit clear',
    () {
      QueuedMutation mutation(
        Map<String, Object?> payload, {
        int revision = 1,
      }) => QueuedMutation(
        opId: id(90),
        localOrder: 1,
        entity: LocalEntity.song,
        entityId: id(10),
        operation: LocalOperation.patch,
        state: 'PENDING',
        baseRevision: revision,
        payload: canonicalJson(payload),
        attemptCount: 0,
      );
      final request = MutationRequest.prepare(
        mutation({'base_revision': 1, 'representative_recording_id': id(30)}),
      )!;
      expect(request.method, 'PUT');
      expect(request.path, '/v1/songs/${id(10)}/representative');
      expect(jsonDecode(request.body), {
        'base_revision': 1,
        'recording_id': id(30),
      });
      final clear = MutationRequest.prepare(
        mutation({'base_revision': 1, 'representative_recording_id': null}),
      )!;
      expect(jsonDecode(clear.body), {
        'base_revision': 1,
        'recording_id': null,
      });
      expect(
        MutationRequest.prepare(
          mutation({
            'base_revision': 1,
            'representative_recording_id': id(30),
            'title': 'bad',
          }),
        ),
        isNull,
      );
      expect(
        MutationRequest.prepare(
          mutation({
            'base_revision': 0,
            'representative_recording_id': id(30),
          }, revision: 0),
        ),
        isNull,
      );
    },
  );
  test('real local assignment rejects stale or wrong-song recordings and preserves one command across retries', () async {
    final root = await Directory.systemTemp.createTemp('p17-representative-');
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    try {
      final store = await manager.openAccount(id(1)),
          repo = LocalRepository(store);
      for (final pair in [
        (LocalEntity.song, fixture.song()),
        (LocalEntity.recording, fixture.recording(30)),
        (LocalEntity.recording, {...fixture.recording(31), 'song_id': id(11)}),
      ]) {
        final draft = pair.$2;
        await repo.save(
          repo.prepareCreate(
            entity: pair.$1,
            entityId: draft['id']! as String,
            draft: draft,
            changes: draft,
          ),
        );
      }
      final original = MySongDetail(await store.readSongDetail(id(10)));
      final save = prepareRepresentative(repo, original, RecordingId(id(30)));
      await save();
      await save();
      expect(
        (await store.readSongDetail(
          id(10),
        ))['song']['representative_recording_id'],
        id(30),
      );
      expect(await repo.pending(), hasLength(4));
      final stale = prepareRepresentative(repo, original, RecordingId(id(30)));
      await expectLater(stale(), throwsStateError);
      final current = MySongDetail(await store.readSongDetail(id(10)));
      expect(
        () => prepareRepresentative(repo, current, RecordingId(id(31))),
        throwsArgumentError,
      );
      final wrong = repo.preparePatch(
        entity: LocalEntity.song,
        entityId: id(10),
        baseRevision: 0,
        draft: {
          ...current.song!.payload,
          'representative_recording_id': id(31),
        },
        changes: {'representative_recording_id': id(31)},
      );
      await expectLater(
        repo.saveRepresentative(wrong, current.song!.payload),
        throwsStateError,
      );
      expect(await repo.pending(), hasLength(4));
      await prepareRepresentative(repo, current, null)();
      expect(
        (await store.readSongDetail(
          id(10),
        ))['song']['representative_recording_id'],
        isNull,
      );
      expect(await repo.pending(), hasLength(5));
      final noop = MySongDetail(await store.readSongDetail(id(10)));
      await prepareRepresentative(repo, noop, null)();
      expect(await repo.pending(), hasLength(5));
      final old = prepareRepresentative(repo, noop, RecordingId(id(30)));
      await manager.openAccount(id(2));
      await expectLater(old(), throwsStateError);
    } finally {
      await manager.logout();
      await root.delete(recursive: true);
    }
  });
  test('v11 migration preserves legacy wire and retry budget; frozen PUT survives restart', () async {
    final root = await Directory.systemTemp.createTemp('p17-wire-');
    var now = DateTime.utc(2026, 10, 1);
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
      clock: () => now,
    );
    try {
      var store = await manager.openAccount(id(1));
      var repo = LocalRepository(store);
      await repo.save(
        repo.prepareCreate(
          entity: LocalEntity.tag,
          entityId: id(50),
          draft: {'name': 'keep'},
          changes: {'name': 'keep'},
        ),
      );
      final legacy = (await store.claimMutation())!;
      await store.deferMutation(legacy, 'RETRY', 'NETWORK_UNAVAILABLE');
      await manager.logout();
      final file = await (await AccountPaths.create(
        root,
        id(1),
        AppEnvironment.dev,
      )).databaseFile();
      final db = sqlite.sqlite3.open(file.path);
      final wireBefore = db
          .select('SELECT * FROM mutation_wire_requests')
          .map((r) => Map<String, Object?>.from(r))
          .toList();
      final budgetBefore = db
          .select('SELECT * FROM mutation_retry_controls')
          .map((r) => Map<String, Object?>.from(r))
          .toList();
      final triggers = db
          .select(
            "SELECT name,sql FROM sqlite_master WHERE type='trigger' AND instr(sql,'mutation_wire_requests')>0",
          )
          .map((r) => Map<String, Object?>.from(r))
          .toList();
      try {
        db.execute(
          'CREATE TEMP TABLE legacy_wire_copy AS SELECT * FROM mutation_wire_requests',
        );
        for (final trigger in triggers) {
          db.execute('DROP TRIGGER "${trigger['name']}"');
        }
        db.execute('DROP TABLE mutation_wire_requests');
        db.execute(
          """CREATE TABLE mutation_wire_requests (
          op_id TEXT NOT NULL PRIMARY KEY REFERENCES local_mutations(op_id),
          contract_version TEXT NOT NULL,
          http_method TEXT NOT NULL CHECK(http_method IN ('POST','PATCH')),
          relative_path TEXT NOT NULL,
          body_json TEXT NOT NULL CHECK(json_valid(body_json) AND json_type(body_json)='object'),
          wire_hash TEXT NOT NULL CHECK(length(wire_hash)=64 AND wire_hash NOT GLOB '*[^0-9a-f]*'))""",
        );
        db.execute(
          'INSERT INTO mutation_wire_requests SELECT * FROM legacy_wire_copy',
        );
        db.execute('DROP TABLE legacy_wire_copy');
        for (final trigger in triggers) {
          db.execute(trigger['sql']! as String);
        }
        db.execute('PRAGMA user_version=11');
      } finally {
        db.close();
      }
      store = await manager.openAccount(id(1));
      repo = LocalRepository(store);
      final check = sqlite.sqlite3.open(file.path);
      try {
        expect(check.select('PRAGMA user_version').single.values.single, 13);
        expect(
          check
              .select('SELECT * FROM mutation_wire_requests')
              .map((r) => Map<String, Object?>.from(r))
              .toList(),
          wireBefore,
        );
        expect(
          check
              .select('SELECT * FROM mutation_retry_controls')
              .map((r) => Map<String, Object?>.from(r))
              .toList(),
          budgetBefore,
        );
        expect(
          () => check.execute(
            "UPDATE mutation_wire_requests SET relative_path='/bad'",
          ),
          throwsA(isA<sqlite.SqliteException>()),
        );
        // Isolated fixture: acknowledged baselines, no user database or files.
        for (final pair in [
          (LocalEntity.song, fixture.song()),
          (LocalEntity.recording, fixture.recording(30)),
        ]) {
          check.execute(
            'INSERT INTO metadata_copies(entity_type,entity_id,user_id,server_revision,server_payload,local_payload,updated_at) VALUES(?,?,?,1,?,NULL,0)',
            [pair.$1.code, pair.$2['id'], id(1), canonicalJson(pair.$2)],
          );
        }
      } finally {
        check.close();
      }
      final value = MySongDetail(await store.readSongDetail(id(10)));
      await prepareRepresentative(repo, value, RecordingId(id(30)))();
      // The older tag is not eligible until its retry deadline. PUT can proceed.
      final put = (await store.claimMutation())!;
      expect(put.method, 'PUT');
      expect(
        await store.deferMutation(put, 'RETRY', 'NETWORK_UNAVAILABLE'),
        isTrue,
      );
      await manager.logout();
      now = now.add(const Duration(minutes: 2));
      store = await manager.openAccount(id(1));
      final retryTag = (await store.claimMutation())!;
      expect(retryTag.hash, legacy.hash);
      await store.deferMutation(retryTag, 'FAILED', 'TEST_DONE');
      final retryPut = (await store.claimMutation())!;
      expect(retryPut.method, 'PUT');
      expect(retryPut.path, put.path);
      expect(retryPut.body, put.body);
      expect(retryPut.hash, put.hash);
      expect(retryPut.attempt, put.attempt + 1);
    } finally {
      await manager.logout();
      await root.delete(recursive: true);
    }
  });
  test('offline create then assign and clear follow acknowledged PUT without rewriting original operations', () async {
    final root = await Directory.systemTemp.createTemp('p17-followup-');
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    try {
      final store = await manager.openAccount(id(1)),
          repo = LocalRepository(store);
      final song = {
        ...fixture.song(),
        'source_type': 'MANUAL',
        'tj_number': null,
        'representative_recording_id': null,
        'updated_at': '2026-01-01T00:00:00Z',
      };
      await repo.save(
        repo.prepareCreate(
          entity: LocalEntity.song,
          entityId: id(10),
          draft: song,
          changes: {
            'id': id(10),
            'source_type': 'MANUAL',
            'title': '현재곡',
            'artist': '현재가수',
            'version_code': 'NORMAL',
          },
        ),
      );
      final file = await (await AccountPaths.create(
        root,
        id(1),
        AppEnvironment.dev,
      )).databaseFile();
      final db = sqlite.sqlite3.open(file.path);
      try {
        db.execute(
          'INSERT INTO metadata_copies(entity_type,entity_id,user_id,server_revision,server_payload,updated_at) VALUES(?,?,?,1,?,0)',
          ['RECORDING', id(30), id(1), canonicalJson(fixture.recording(30))],
        );
      } finally {
        db.close();
      }
      await prepareRepresentative(
        repo,
        MySongDetail(await store.readSongDetail(id(10))),
        RecordingId(id(30)),
      )();
      await prepareRepresentative(
        repo,
        MySongDetail(await store.readSongDetail(id(10))),
        null,
      )();
      final original = (await repo.pending()).map((m) => m.payload).toList();
      final create = (await store.claimMutation())!;
      expect(create.method, 'POST');
      expect(
        await store.acknowledgeMutation(create, {...song, 'revision': 1}),
        isTrue,
      );
      final assign = (await store.claimMutation())!;
      expect(assign.method, 'PUT');
      expect(jsonDecode(assign.body), {
        'base_revision': 1,
        'recording_id': id(30),
      });
      final assigned = {
        ...song,
        'revision': 2,
        'representative_recording_id': id(30),
      };
      expect(
        decodeMetadataSnapshot(
          assign,
          MutationResponse(200, jsonEncode(assigned)),
        ),
        assigned,
      );
      expect(
        () => decodeMetadataSnapshot(
          assign,
          MutationResponse(
            200,
            jsonEncode({...assigned, 'representative_recording_id': null}),
          ),
        ),
        throwsFormatException,
      );
      expect(await store.acknowledgeMutation(assign, assigned), isTrue);
      final clear = (await store.claimMutation())!;
      expect(clear.method, 'PUT');
      expect(jsonDecode(clear.body), {
        'base_revision': 2,
        'recording_id': null,
      });
      expect(
        await store.acknowledgeMutation(clear, {...song, 'revision': 3}),
        isTrue,
      );
      expect(
        (await store.readSongDetail(
          id(10),
        ))['song']['representative_recording_id'],
        isNull,
      );
      final history = sqlite.sqlite3.open(file.path);
      try {
        expect(
          history
              .select('SELECT payload FROM local_mutations ORDER BY rowid')
              .take(3)
              .map((r) => r['payload'])
              .toList(),
          original,
        );
        expect(
          history.select('SELECT * FROM recording_followups'),
          hasLength(2),
        );
      } finally {
        history.close();
      }
    } finally {
      await manager.logout();
      await root.delete(recursive: true);
    }
  });
  testWidgets(
    'role rows stay visible while only explanation collapses; cancelled choice does not save',
    (tester) async {
      final stream = StreamController<MySongDetail>.broadcast();
      var prepared = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: SongDetailScreen(
            watch: () => stream.stream,
            prepareRepresentative: (value, recording) {
              prepared++;
              return () async {};
            },
          ),
        ),
      );
      stream.add(roles(representative: id(30)));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('대표 녹음'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('자동 보관 대상 3개'), findsOneWidget);
      expect(find.text('최신 녹음'), findsOneWidget);
      expect(find.text('최저 티어 녹음'), findsOneWidget);
      await tester.tap(find.text('대표 녹음'));
      await tester.pumpAndSettle();
      expect(find.text('대표 녹음 선택'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(prepared, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await stream.close();
    },
  );
}
