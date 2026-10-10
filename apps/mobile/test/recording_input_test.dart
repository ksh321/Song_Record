import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/mutation_request.dart';
import 'package:song_record/core/sync/mutation_transport.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/recorder/recording_input_screen.dart';

import 'support/completed_capture_fixture.dart';

const song = '00000000-0000-4000-8000-000000001820';
Map<String, Object?> fields() => {
  'song_id': null,
  'title_snapshot': '밤 산책',
  'artist_snapshot': 'Singer',
  'key_mode': 'ORIGINAL',
  'key_shift': 0,
  'version_code': 'NORMAL',
  'note': 'keep',
  'recorded_at': '2026-10-10T01:02:03.000Z',
  'timezone_id': 'Asia/Seoul',
  'timezone_offset_minutes': 540,
  'condition_code': 'GOOD',
  'tag_ids': <String>[],
};
AuthSession session() => AuthSession(
  userId: owner,
  deviceId: owner,
  accessToken: 'synthetic',
  refreshToken: 'unused',
  accessExpiresAt: DateTime.utc(2030),
  refreshExpiresAt: DateTime.utc(2030),
);

/// Strict existing response shapes. No remote service or real credentials.
class Transport implements MutationTransport {
  Map<String, dynamic> state = {};
  final List<MutationRequest> requests = [];
  @override
  Future<MutationResponse> send(
    MutationRequest request,
    AuthSession session,
    void Function() fence,
  ) async {
    fence();
    requests.add(request);
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    if (request.method == 'POST') {
      state = {
        ...body,
        'origin_device_id': owner,
        'revision': 1,
        'link_revision': 1,
        'lifecycle_state': 'ACTIVE',
        'updated_at': '2026-10-10T02:00:00.000Z',
        'tier': null,
        'condition_code': null,
        'condition_name_snapshot': null,
      };
      return MutationResponse(201, jsonEncode(state));
    }
    expect(body['base_revision'], state['revision']);
    final previousSong = state['song_id'];
    state = {...state, ...body, 'revision': (state['revision'] as int) + 1}
      ..remove('base_revision');
    if (body.containsKey('song_id') && body['song_id'] != previousSong) {
      state['link_revision'] = (state['link_revision'] as int) + 1;
    }
    final response = {
      ...state,
      'tags': <Object>[],
      'tag_ids': <Object>[],
      'tier': null,
      'condition_name_snapshot': state['condition_code'] == 'GOOD'
          ? '좋음'
          : null,
    };
    if (!body.containsKey('file')) response.remove('file');
    return MutationResponse(200, jsonEncode(response));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AccountStoreManager manager;
  late AccountStore store;
  late LocalRepository repo;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sr-input-');
    manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    store = await manager.openAccount(owner);
    repo = LocalRepository(store);
    await capture(repo);
  });
  tearDown(() async {
    await manager.logout();
    await root.delete(recursive: true);
  });
  Future<void> seedSong() => repo.save(
    repo.prepareCreate(
      entity: LocalEntity.song,
      entityId: song,
      draft: {
        'source_type': 'MANUAL',
        'title': '새 곡',
        'artist': '가수',
        'version_code': 'LIVE',
        'representative_key_mode': 'FEMALE',
        'representative_key_shift': -2,
        'lifecycle_state': 'ACTIVE',
        'tier': 'A',
      },
      changes: {
        'source_type': 'MANUAL',
        'manual_reason': 'TJ_NOT_FOUND',
        'title': '새 곡',
        'artist': '가수',
        'version_code': 'LIVE',
        'note': '',
      },
    ),
  );

  test('offline input save is atomic, idempotent, retains file, and existing wire steps dispatch in order', () async {
    final values = fields();
    final ids = repo.recordingSaveOperationIds();
    await repo.saveRecordingInput(rec, values, ids);
    await repo.saveRecordingInput(rec, values, ids);
    expect(await repo.pendingRecordings(), isEmpty);
    expect(await store.readLocalAudio(rec), bytes);
    final local = jsonDecode(
      (await repo.read(LocalEntity.recording, rec))!.localJson!,
    );
    expect(local['metadata_state'], 'SAVED');
    expect(local['tier'], null);
    expect(local['link_revision'], 1);
    expect(local['key_shift'], 0);
    expect((await repo.pending()).length, 4);
    final transport = Transport();
    expect(
      await repo.dispatch(transport: transport, session: () async => session()),
      4,
    );
    expect(transport.requests.map((r) => r.path).toList(), [
      '/v1/recordings',
      '/v1/recordings/$rec',
      '/v1/recordings/$rec',
      '/v1/recordings/$rec/song',
    ]);
    expect(jsonDecode(transport.requests[2].body)['metadata_state'], 'SAVED');
    expect(await repo.pendingWork(), isEmpty);
    expect(await store.readLocalAudio(rec), bytes);
    await manager.logout();
    store = await manager.openAccount(owner);
    repo = LocalRepository(store);
    expect(
      jsonDecode(
        (await repo.read(LocalEntity.recording, rec))!.serverJson!,
      )['metadata_state'],
      'SAVED',
    );
    expect(await store.readLocalAudio(rec), bytes);
  });
  test(
    'already ACKed DRAFT uses a positive first baseline then proven followups',
    () async {
      final transport = Transport();
      expect(
        await repo.dispatch(
          transport: transport,
          session: () async => session(),
        ),
        1,
      );
      await repo.saveRecordingInput(
        rec,
        fields(),
        repo.recordingSaveOperationIds(),
      );
      expect(
        await repo.dispatch(
          transport: transport,
          session: () async => session(),
        ),
        3,
      );
      expect(
        transport.requests
            .skip(1)
            .map((r) => jsonDecode(r.body)['base_revision'])
            .toList(),
        [1, 2, 3],
      );
      expect(await repo.pendingWork(), isEmpty);
    },
  );
  test(
    'partial input and edited flags survive song defaults and reopening',
    () async {
      await seedSong();
      await repo.preserveRecordingInput(rec, {
        ...fields(),
        'key_mode': 'MALE',
        'key_shift': 3,
        'version_code': 'MR',
        'key_edited': true,
        'version_edited': true,
      });
      await repo.selectPendingRecordingSong(rec, song);
      await manager.logout();
      store = await manager.openAccount(owner);
      repo = LocalRepository(store);
      final input = (await repo.pendingRecordings()).single['input_form'];
      expect(input['title_snapshot'], '새 곡');
      expect(input['key_mode'], 'MALE');
      expect(input['key_shift'], 3);
      expect(input['version_code'], 'MR');
      expect(await store.readLocalAudio(rec), bytes);
      expect(
        jsonDecode(
          (await repo.read(LocalEntity.song, song))!.localJson!,
        )['tier'],
        'A',
      );
    },
  );
  test('missing input, lost tag, absent song, and operation collision keep original DRAFT and file', () async {
    final ids = repo.recordingSaveOperationIds();
    await expectLater(
      repo.saveRecordingInput(rec, {...fields(), 'title_snapshot': ''}, ids),
      throwsArgumentError,
    );
    await expectLater(
      repo.saveRecordingInput(rec, {
        ...fields(),
        'tag_ids': [song],
      }, ids),
      throwsStateError,
    );
    await expectLater(
      repo.saveRecordingInput(rec, {...fields(), 'song_id': song}, ids),
      throwsStateError,
    );
    await expectLater(
      repo.saveRecordingInput(rec, fields(), [rec, ids[1], ids[2]]),
      throwsStateError,
    );
    expect((await repo.pendingRecordings()).single['metadata_state'], 'DRAFT');
    expect((await repo.pending()).length, 1);
    expect(await store.readLocalAudio(rec), bytes);
  });
  testWidgets(
    'required form has no initial tier, refuses empty input and preserves cancel draft',
    (t) async {
      final row = await t.runAsync(
        () async => (await repo.pendingRecordings()).single,
      );
      await t.pumpWidget(
        MaterialApp(
          home: RecordingInputScreen(
            tagLoader: () async => [],
            recording: row!,
            repository: repo,
            isCurrent: (_) => true,
          ),
        ),
      );
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await t.pump();
      expect(find.textContaining('티어'), findsNothing);
      expect(find.text('키: 원키'), findsOneWidget);
      await t.tap(find.text('녹음 저장'));
      await t.pump();
      expect(find.textContaining('곡명·가수는'), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('recording-title')),
        'input still pending',
      );
      await t.runAsync(() async {
        await t.tap(find.byIcon(Icons.arrow_back));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await t.pump();
      await t.pumpWidget(const SizedBox());
      await t.runAsync(() async {
        expect(
          (await repo.pendingRecordings())
              .single['input_form']['title_snapshot'],
          'input still pending',
        );
        expect(await store.readLocalAudio(rec), bytes);
      });
    },
  );
  test('selected active song and tag save snapshots without changing song defaults', () async {
    await seedSong();
    const tagId = '00000000-0000-4000-8000-000000001830';
    await repo.save(
      repo.prepareCreate(
        entity: LocalEntity.tag,
        entityId: tagId,
        draft: {'name': '연습', 'archived_at': null},
        changes: {'name': '연습'},
      ),
    );
    final before = (await repo.read(LocalEntity.song, song))!.localJson;
    await repo.saveRecordingInput(rec, {
      ...fields(),
      'song_id': song,
      'tag_ids': [tagId],
    }, repo.recordingSaveOperationIds());
    final row = jsonDecode(
      (await repo.read(LocalEntity.recording, rec))!.localJson!,
    );
    expect(row['song_id'], song);
    expect(row['tags'], [
      {'id': tagId, 'name_snapshot': '연습'},
    ]);
    expect((await repo.read(LocalEntity.song, song))!.localJson, before);
    expect(await store.readLocalAudio(rec), bytes);
  });
  test('stale account lease cannot save or preserve pending input', () async {
    final oldRepo = repo;
    await manager.openAccount(other);
    await expectLater(
      oldRepo.preserveRecordingInput(rec, fields()),
      throwsStateError,
    );
    await expectLater(
      oldRepo.saveRecordingInput(
        rec,
        fields(),
        oldRepo.recordingSaveOperationIds(),
      ),
      throwsStateError,
    );
    store = await manager.openAccount(owner);
    repo = LocalRepository(store);
    expect((await repo.pendingRecordings()).single['metadata_state'], 'DRAFT');
    expect(await store.readLocalAudio(rec), bytes);
  });
  testWidgets(
    'one save tap stores normalized required information with original zero and no tier',
    (t) async {
      final row = await t.runAsync(
        () async => (await repo.pendingRecordings()).single,
      );
      await t.pumpWidget(
        MaterialApp(
          home: RecordingInputScreen(
            tagLoader: () async => [],
            recording: row!,
            repository: repo,
            isCurrent: (_) => true,
          ),
        ),
      );
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await t.pump();
      await t.enterText(
        find.byKey(const ValueKey('recording-title')),
        '  노래  ',
      );
      await t.enterText(
        find.byKey(const ValueKey('recording-artist')),
        '  가수  ',
      );
      await t.runAsync(() async {
        await t.tap(find.text('녹음 저장'));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      for (var attempt = 0; attempt < 10; attempt++) {
        await t.pump();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        final pending = await t.runAsync(() => repo.pendingRecordings());
        if (pending!.isEmpty) break;
      }
      await t.pump();
      expect(find.textContaining('저장하지 못했어요'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.runAsync(() async {
        final saved = jsonDecode(
          (await repo.read(LocalEntity.recording, rec))!.localJson!,
        );
        expect(saved['title_snapshot'], '노래');
        expect(saved['artist_snapshot'], '가수');
        expect(saved['key_shift'], 0);
        expect(saved['key_mode'], 'ORIGINAL');
        expect(saved['tier'], null);
        expect(saved['metadata_state'], 'SAVED');
        expect(await repo.pendingRecordings(), isEmpty);
      });
    },
  );
  testWidgets('small screen keeps save above keyboard and system navigation', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetViewInsets);
    final row = await t.runAsync(
      () async => (await repo.pendingRecordings()).single,
    );
    await t.pumpWidget(
      MaterialApp(
        home: RecordingInputScreen(
          tagLoader: () async => [],
          recording: row!,
          repository: repo,
          isCurrent: (_) => true,
        ),
      ),
    );
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await t.pump();
    t.view.viewInsets = const FakeViewPadding(bottom: 300);
    await t.pump();
    expect(
      t.getBottomRight(find.widgetWithText(FilledButton, '녹음 저장')).dy,
      lessThanOrEqualTo(544),
    );
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
