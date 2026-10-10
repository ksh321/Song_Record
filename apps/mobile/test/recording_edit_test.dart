import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/mutation_request.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/recorder/recording_input_screen.dart';

import 'recording_input_test.dart' as input;
import 'support/completed_capture_fixture.dart';

class EditTransport extends input.Transport {
  @override
  Future<MutationResponse> send(
    MutationRequest request,
    AuthSession session,
    void Function() fence,
  ) async {
    final response = await super.send(request, session, fence);
    if (request.path.endsWith('/tier')) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      body['tier'] = state['tier'];
      return MutationResponse(response.status, jsonEncode(body));
    }
    return response;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AccountStoreManager manager;
  late AccountStore store;
  late LocalRepository repo;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sr-edit-');
    manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    store = await manager.openAccount(owner);
    repo = LocalRepository(store);
    await capture(repo);
    await repo.saveRecordingInput(
      rec,
      input.fields(),
      repo.recordingSaveOperationIds(),
    );
  });
  tearDown(() async {
    await manager.logout();
    await root.delete(recursive: true);
  });
  Future<Map<String, dynamic>> row() async {
    final c = (await repo.read(LocalEntity.recording, rec))!;
    return jsonDecode(c.localJson ?? c.serverJson!) as Map<String, dynamic>;
  }

  Map<String, Object?> values() => Map<String, Object?>.from(input.fields())
    ..remove('song_id')
    ..['tier'] = 'S'
    ..['note'] = 'edited'
    ..['key_mode'] = 'FEMALE'
    ..['key_shift'] = -2
    ..['version_code'] = 'MR'
    ..['condition_code'] = 'GOOD';
  test('saved edit queues metadata then dedicated tier, dispatches and keeps audio', () async {
    final transport = EditTransport();
    expect(
      await repo.dispatch(
        transport: transport,
        session: () async => input.session(),
      ),
      4,
    );
    final copy = (await repo.read(LocalEntity.recording, rec))!;
    final old = await row();
    final ids = repo.recordingEditOperationIds();
    await repo.saveRecordingDetails(rec, values(), ids, old, copy.revision);
    await repo.saveRecordingDetails(rec, values(), ids, old, copy.revision);
    expect((await repo.pendingWork()).length, 2);
    expect(
      await repo.dispatch(
        transport: transport,
        session: () async => input.session(),
      ),
      2,
    );
    expect(transport.requests.skip(4).map((r) => r.path), [
      '/v1/recordings/$rec',
      '/v1/recordings/$rec/tier',
    ]);
    expect(jsonDecode(transport.requests.last.body).keys.toSet(), {
      'base_revision',
      'tier',
    });
    final saved = await row();
    expect(saved['tier'], 'S');
    expect(saved['note'], 'edited');
    expect(saved['key_shift'], -2);
    expect(saved['condition_code'], 'GOOD');
    expect(saved['song_id'], old['song_id']);
    expect(saved['link_revision'], old['link_revision']);
    expect(await store.readLocalAudio(rec), bytes);
    await manager.logout();
    store = await manager.openAccount(owner);
    repo = LocalRepository(store);
    expect((await row())['tier'], 'S');
  });
  test(
    'offline edit leaves Song unchanged and preserves initial save queue',
    () async {
      await repo.save(
        repo.prepareCreate(
          entity: LocalEntity.song,
          entityId: input.song,
          draft: {
            'title': 'same',
            'artist': 'Singer',
            'tier': 'A',
            'representative_key_mode': 'MALE',
            'representative_key_shift': 1,
            'version_code': 'LIVE',
            'lifecycle_state': 'ACTIVE',
          },
          changes: {
            'title': 'same',
            'artist': 'Singer',
            'source_type': 'MANUAL',
            'manual_reason': 'TJ_NOT_FOUND',
            'version_code': 'LIVE',
          },
        ),
      );
      final before = (await repo.read(LocalEntity.song, input.song))!.localJson;
      final old = await row();
      await repo.saveRecordingDetails(
        rec,
        values(),
        repo.recordingEditOperationIds(),
        old,
        0,
      );
      expect(
        (await repo.read(LocalEntity.song, input.song))!.localJson,
        before,
      );
      expect((await repo.pendingWork()).length, 7);
      expect(await store.readLocalAudio(rec), bytes);
    },
  );
  test(
    'stale editor rejected and transaction preserves newest metadata',
    () async {
      final old = await row();
      await repo.saveRecordingDetails(
        rec,
        values(),
        repo.recordingEditOperationIds(),
        old,
        0,
      );
      final count = (await repo.pending()).length;
      await expectLater(
        repo.saveRecordingDetails(
          rec,
          {...values(), 'note': 'stale'},
          repo.recordingEditOperationIds(),
          old,
          0,
        ),
        throwsStateError,
      );
      expect((await row())['note'], 'edited');
      expect((await repo.pending()).length, count);
    },
  );
  test(
    'bad key, unavailable new tag and identity changes cannot partially queue',
    () async {
      final old = await row();
      final count = (await repo.pending()).length;
      for (final fields in [
        {...values(), 'key_mode': 'ORIGINAL', 'key_shift': 1},
        {
          ...values(),
          'tag_ids': [other],
        },
        {...values(), 'song_id': input.song},
        {...values(), 'tier': 'Z'},
      ]) {
        await expectLater(
          repo.saveRecordingDetails(
            rec,
            fields,
            repo.recordingEditOperationIds(),
            old,
            0,
          ),
          throwsA(anyOf(isA<ArgumentError>(), isA<StateError>())),
        );
        expect(await row(), old);
        expect((await repo.pending()).length, count);
      }
    },
  );
  test('account change fences saved editor and list', () async {
    final old = await row();
    await manager.openAccount(other);
    await expectLater(
      repo.saveRecordingDetails(
        rec,
        values(),
        repo.recordingEditOperationIds(),
        old,
        0,
      ),
      throwsStateError,
    );
    await expectLater(repo.savedRecordings(), throwsStateError);
  });
  test(
    'renamed and archived existing tags retain their saved name snapshots',
    () async {
      await repo.save(
        repo.prepareCreate(
          entity: LocalEntity.tag,
          entityId: other,
          draft: {'name': 'old name', 'archived_at': null},
          changes: {'name': 'old name'},
        ),
      );
      var old = await row();
      await repo.saveRecordingDetails(
        rec,
        {
          ...values(),
          'tag_ids': [other],
        },
        repo.recordingEditOperationIds(),
        old,
        0,
      );
      final tag = (await repo.read(LocalEntity.tag, other))!;
      await repo.save(
        repo.preparePatch(
          entity: LocalEntity.tag,
          entityId: other,
          baseRevision: tag.revision,
          draft: {'name': 'renamed', 'archived_at': null},
          changes: {'name': 'renamed'},
        ),
      );
      old = await row();
      await repo.saveRecordingDetails(
        rec,
        {
          ...values(),
          'tag_ids': [other],
          'note': 'name change elsewhere',
        },
        repo.recordingEditOperationIds(),
        old,
        0,
      );
      expect((await row())['tags'], [
        {'id': other, 'name_snapshot': 'old name'},
      ]);
      await repo.save(
        repo.preparePatch(
          entity: LocalEntity.tag,
          entityId: other,
          baseRevision: tag.revision,
          draft: {'name': 'renamed', 'archived_at': '2026-10-10T01:00:00Z'},
          changes: {'name': 'renamed'},
        ),
      );
      old = await row();
      await repo.saveRecordingDetails(
        rec,
        {
          ...values(),
          'tag_ids': [other],
          'note': 'another edit',
        },
        repo.recordingEditOperationIds(),
        old,
        0,
      );
      expect((await row())['tags'], [
        {'id': other, 'name_snapshot': 'old name'},
      ]);
      expect(await repo.selectableRecordingTags(), isEmpty);
    },
  );
  testWidgets(
    'saved editor displays tier and cancel discards all unsaved edits',
    (t) async {
      final old = (await t.runAsync(row))!;
      final count = (await t.runAsync(repo.pending))!.length;
      await t.pumpWidget(
        MaterialApp(
          home: RecordingInputScreen(
            recording: old,
            repository: repo,
            isCurrent: (_) => true,
            editing: true,
            tagLoader: () async => [],
          ),
        ),
      );
      await t.pump();
      expect(find.text('녹음 티어'), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('recording-title')),
        'cancelled',
      );
      await t.tap(find.text('취소'));
      await t.pump();
      await t.pumpWidget(const SizedBox());
      expect(await t.runAsync(row), old);
      expect((await t.runAsync(repo.pending))!.length, count);
    },
  );
}
