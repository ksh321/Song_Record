import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/dependency_planner.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/mutation_request.dart';
import 'package:song_record/features/auth/auth_session.dart';

import 'metadata_dispatcher_test.dart' show FakeTransport;
import 'metadata_followup_dispatch_test.dart' show baseline, id;
import 'recording_save_dispatch_test.dart' show draft;
import 'recording_tier_dispatch_test.dart' show owner, rec;

const _audio = [4, 3, 2, 1];
const _recovery = {'input': 'preserved', 'native_phase': 'completed'};

AccountStoreManager _manager(Directory dir) => AccountStoreManager(
  environment: AppEnvironment.dev,
  directory: () async => dir,
  temporaryDirectory: () async => dir,
  // Reopening never makes a 503 retry due just because the test ran slowly.
  clock: () => DateTime.utc(2030),
);

Future<AuthSession> _session() async => AuthSession(
  userId: owner,
  deviceId: owner,
  accessToken: 'synthetic',
  refreshToken: 'unused',
  accessExpiresAt: DateTime.utc(2031),
  refreshExpiresAt: DateTime.utc(2031),
);

Future<Map<String, dynamic>> _tables(AccountStore store) async {
  final exported =
      jsonDecode(await store.recoveryData()) as Map<String, dynamic>;
  return exported['tables'] as Map<String, dynamic>;
}

List<Map<String, dynamic>> _rows(Map<String, dynamic> tables, String name) =>
    (tables[name] as List<dynamic>).cast<Map<String, dynamic>>();

Future<Map<String, dynamic>> _registerFile(
  Directory dir,
  AccountStore store,
) async {
  final paths = await AccountPaths.create(dir, owner, AppEnvironment.dev);
  final audio = await paths.checkedFile(paths.audioPath(rec));
  await audio.writeAsBytes(_audio, flush: true);
  await store.recordFileAndJournal(
    recordingId: rec,
    operationId: id(900),
    state: FilePresence.inputPending,
    phase: JournalPhase.committed,
    pending: false,
    checksum: sha256.convert(_audio).toString(),
    sizeBytes: _audio.length,
    recovery: _recovery,
  );
  final tables = await _tables(store);
  final file = _rows(tables, 'local_recording_files').single;
  expect(file['recording_id'], rec);
  expect(file['user_id'], owner);
  expect(file['relative_path'], paths.audioPath(rec));
  expect(file['sha256'], sha256.convert(_audio).toString());
  expect(file['size_bytes'], _audio.length);
  final journal = _rows(tables, 'recording_journals').single;
  expect(journal['recording_id'], rec);
  expect(journal['operation_id'], id(900));
  return tables;
}

Future<void> _expectFilePreserved(
  AccountStore store,
  Map<String, dynamic> before,
) async {
  expect(await store.readLocalAudio(rec), _audio);
  expect(jsonDecode((await store.readJournal(rec))!), _recovery);
  final after = await _tables(store);
  for (final table in ['local_recording_files', 'recording_journals']) {
    expect(_rows(after, table), _rows(before, table), reason: table);
  }
  expect(await store.readCursor(), isNull);
}

Future<void> _dispose(Directory dir, AccountStoreManager manager) async {
  await manager.logout();
  // Only the unique synthetic fixture directory may be removed.
  final root = await dir.resolveSymbolicLinks();
  final temporaryRoot = await Directory.systemTemp.resolveSymbolicLinks();
  expect(p.basename(root), startsWith('sr-dependency-flow-'));
  expect(p.isWithin(temporaryRoot, root), isTrue);
  await Directory(root).delete(recursive: true);
}

LocalEdit _recordingCreate(LocalRepository repo, Map<String, Object?> value) {
  final fields = Map<String, Object?>.from(value)
    ..removeWhere(
      (key, _) => {
        'revision',
        'updated_at',
        'origin_device_id',
        'link_revision',
        'lifecycle_state',
        'condition_name_snapshot',
      }.contains(key),
    );
  return repo.prepareCreate(
    entity: LocalEntity.recording,
    entityId: rec,
    draft: value,
    changes: fields,
  );
}

LocalEdit _songCreate(LocalRepository repo) => repo.prepareCreate(
  entity: LocalEntity.song,
  entityId: id(10),
  draft: baseline(LocalEntity.song, id(10)),
  changes: {
    'source_type': 'MANUAL',
    'title': 'before',
    'artist': 'artist',
    'manual_reason': 'TJ_NOT_FOUND',
    'version_code': 'NORMAL',
    'note': '',
  },
);

MutationResponse _created(
  MutationRequest request,
  Map<String, Object?> recording,
) {
  expect(request.method, 'POST');
  final entity = request.mutation.entity;
  if (entity == LocalEntity.song) {
    expect(request.path, '/v1/songs');
    return MutationResponse(
      201,
      jsonEncode({
        'created': true,
        'canonical_song_id': request.mutation.entityId,
        'song': baseline(entity, request.mutation.entityId),
      }),
    );
  }
  if (entity == LocalEntity.tag) {
    expect(request.path, '/v1/tags');
    return MutationResponse(
      201,
      jsonEncode(baseline(entity, request.mutation.entityId)),
    );
  }
  expect(
    entity,
    LocalEntity.recording,
    reason: 'Unsupported work must never reach transport',
  );
  expect(request.path, '/v1/recordings');
  return MutationResponse(201, jsonEncode(recording));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'failed song holds recording across restart while independent tag sends',
    () async {
      final dir = await Directory.systemTemp.createTemp('sr-dependency-flow-');
      var manager = _manager(dir);
      try {
        var store = await manager.openAccount(owner);
        var repo = LocalRepository(store);
        final fileBefore = await _registerFile(dir, store);
        final song = repo.prepareCreate(
          entity: LocalEntity.song,
          entityId: id(10),
          draft: baseline(LocalEntity.song, id(10)),
          changes: {
            'source_type': 'MANUAL',
            'title': 'before',
            'artist': 'artist',
            'manual_reason': 'TJ_NOT_FOUND',
            'version_code': 'NORMAL',
            'note': '',
          },
        );
        await repo.save(song);
        final value = {...draft(), 'song_id': id(10)};
        final fields = Map<String, Object?>.from(value)
          ..removeWhere(
            (key, _) => {
              'revision',
              'updated_at',
              'origin_device_id',
              'link_revision',
              'lifecycle_state',
              'condition_name_snapshot',
            }.contains(key),
          );
        final recording = repo.prepareCreate(
          entity: LocalEntity.recording,
          entityId: rec,
          draft: value,
          changes: fields,
        );
        await repo.save(recording);
        final recordingBefore = (await repo.read(LocalEntity.recording, rec))!;
        final queueBefore = _rows(
          await _tables(store),
          'local_mutations',
        ).singleWhere((row) => row['op_id'] == recording.opId);
        await repo.save(
          repo.prepareCreate(
            entity: LocalEntity.tag,
            entityId: id(40),
            draft: {'name': 'before'},
            changes: {'name': 'before'},
          ),
        );
        final sent = <LocalEntity>[];
        var failSong = true;
        final transport = FakeTransport((request) async {
          sent.add(request.mutation.entity);
          if (request.mutation.entity == LocalEntity.song) {
            if (failSong) {
              return const MutationResponse(
                503,
                '{"error":{"code":"TEMPORARY"}}',
              );
            }
            return MutationResponse(
              201,
              jsonEncode({
                'created': true,
                'canonical_song_id': id(10),
                'song': baseline(LocalEntity.song, id(10)),
              }),
            );
          }
          return MutationResponse(
            201,
            jsonEncode(
              request.mutation.entity == LocalEntity.tag
                  ? baseline(LocalEntity.tag, id(40))
                  : value,
            ),
          );
        });
        Future<AuthSession> session() async => AuthSession(
          userId: owner,
          deviceId: owner,
          accessToken: 'synthetic',
          refreshToken: 'unused',
          accessExpiresAt: DateTime.utc(2030),
          refreshExpiresAt: DateTime.utc(2030),
        );
        expect(await repo.dispatch(transport: transport, session: session), 1);
        expect(sent, [LocalEntity.song, LocalEntity.tag]);
        final original = (await repo.pending()).singleWhere(
          (m) => m.opId == recording.opId,
        );
        expect(original.attemptCount, 0);
        expect(original.state, 'PENDING');
        expect(
          (await repo.read(LocalEntity.recording, rec))!.localJson,
          recordingBefore.localJson,
        );
        expect(
          _rows(
            await _tables(store),
            'local_mutations',
          ).singleWhere((row) => row['op_id'] == recording.opId),
          queueBefore,
        );
        await _expectFilePreserved(store, fileBefore);

        final expiredStore = store;
        final other = await manager.openAccount(id(999));
        expect(await other.readMetadata(LocalEntity.recording, rec), isNull);
        expect(await other.pendingMutations(), isEmpty);
        expect(await other.readJournal(rec), isNull);
        await expectLater(other.readLocalAudio(rec), throwsStateError);
        await expectLater(expiredStore.readLocalAudio(rec), throwsStateError);
        expect(_rows(await _tables(other), 'local_recording_files'), isEmpty);
        await manager.logout();
        manager = _manager(dir);
        store = await manager.openAccount(owner);
        repo = LocalRepository(store);
        expect(await store.claimMutation(), isNull);
        expect(
          _rows(
            await _tables(store),
            'local_mutations',
          ).singleWhere((row) => row['op_id'] == recording.opId),
          queueBefore,
        );
        expect(
          (await repo.read(LocalEntity.recording, rec))!.localJson,
          recordingBefore.localJson,
        );
        await _expectFilePreserved(store, fileBefore);
        failSong = false;
        expect(await repo.retryMutation(song.opId, expectedAttempt: 1), isTrue);
        expect(await repo.dispatch(transport: transport, session: session), 2);
        expect(sent, [
          LocalEntity.song,
          LocalEntity.tag,
          LocalEntity.song,
          LocalEntity.recording,
        ]);
        final after = _rows(
          await _tables(store),
          'local_mutations',
        ).singleWhere((m) => m['op_id'] == recording.opId);
        expect(after['payload'], original.payload);
        expect(after['entity_id'], rec);
        expect(after['queue_state'], 'ACKED');
        for (final field in [
          'op_id',
          'entity_id',
          'user_id',
          'payload',
          'base_revision',
          'base_payload',
          'request_hash',
          'local_order',
        ]) {
          expect(after[field], queueBefore[field], reason: field);
        }
        final confirmed = (await repo.read(LocalEntity.recording, rec))!;
        expect(jsonDecode(confirmed.localJson!), value);
        expect(jsonDecode(confirmed.serverJson!), value);
        await _expectFilePreserved(store, fileBefore);
        expect(await repo.pendingWork(), isEmpty);
        await manager.logout();
        manager = _manager(dir);
        store = await manager.openAccount(owner);
        expect(
          (await store.readMetadata(LocalEntity.recording, rec))!.revision,
          1,
        );
        await _expectFilePreserved(store, fileBefore);
      } finally {
        await _dispose(dir, manager);
      }
    },
  );
  test('failed tag holds recording tag PATCH until its ACK commits', () async {
    final dir = await Directory.systemTemp.createTemp('sr-dependency-flow-');
    var manager = _manager(dir);
    try {
      var store = await manager.openAccount(owner);
      var repo = LocalRepository(store);
      final fileBefore = await _registerFile(dir, store);
      final value = draft();
      final recording = _recordingCreate(repo, value);
      await repo.save(recording);
      expect(
        await repo.dispatch(
          transport: FakeTransport((request) async => _created(request, value)),
          session: _session,
        ),
        1,
      );
      final tag = repo.prepareCreate(
        entity: LocalEntity.tag,
        entityId: id(40),
        draft: {'name': 'before'},
        changes: {'name': 'before'},
      );
      await repo.save(tag);
      final patch = repo.preparePatch(
        entity: LocalEntity.recording,
        entityId: rec,
        baseRevision: 1,
        draft: {
          ...value,
          'tag_ids': [id(40)],
        },
        changes: {
          'tag_ids': [id(40)],
        },
      );
      await repo.save(patch);
      final song = _songCreate(repo);
      await repo.save(song);
      final patchBefore = _rows(
        await _tables(store),
        'local_mutations',
      ).singleWhere((row) => row['op_id'] == patch.opId);
      final localBefore = (await repo.read(
        LocalEntity.recording,
        rec,
      ))!.localJson;
      final sent = <MutationRequest>[];
      var failTag = true;
      final tagged = {
        ...value,
        'revision': 2,
        'tier': null,
        'tag_ids': [id(40)],
        'tags': [
          {'id': id(40), 'name_snapshot': 'before'},
        ],
      };
      final transport = FakeTransport((request) async {
        sent.add(request);
        if (request.mutation.entity == LocalEntity.tag && failTag) {
          return const MutationResponse(503, '{"error":{"code":"TEMPORARY"}}');
        }
        if (request.mutation.entity == LocalEntity.recording) {
          // The transport sees the committed tag receipt, not merely a ready parent.
          expect((await repo.read(LocalEntity.tag, id(40)))!.revision, 1);
          expect(request.mutation.opId, patch.opId);
          expect(request.method, 'PATCH');
          expect(request.path, '/v1/recordings/$rec');
          expect(request.body, patch.changesJson);
          expect(jsonDecode(request.body), {
            'base_revision': 1,
            'tag_ids': [id(40)],
          });
          return MutationResponse(200, jsonEncode(tagged));
        }
        return _created(request, value);
      });
      expect(await repo.dispatch(transport: transport, session: _session), 1);
      expect(sent.map((r) => r.mutation.opId), [tag.opId, song.opId]);
      expect((await repo.retryStatus(patch.opId))!.attemptCount, 0);
      expect((await repo.retryStatus(patch.opId))!.automaticRetriesClaimed, 0);
      expect(
        _rows(
          await _tables(store),
          'local_mutations',
        ).singleWhere((row) => row['op_id'] == patch.opId),
        patchBefore,
      );
      expect(
        (await repo.read(LocalEntity.recording, rec))!.localJson,
        localBefore,
      );
      await _expectFilePreserved(store, fileBefore);

      await manager.logout();
      manager = _manager(dir);
      store = await manager.openAccount(owner);
      repo = LocalRepository(store);
      expect(await store.claimMutation(), isNull);
      expect((await repo.retryStatus(patch.opId))!.attemptCount, 0);
      expect(
        (await repo.read(LocalEntity.recording, rec))!.localJson,
        localBefore,
      );
      await _expectFilePreserved(store, fileBefore);
      failTag = false;
      expect(await repo.retryMutation(tag.opId, expectedAttempt: 1), isTrue);
      expect(await repo.dispatch(transport: transport, session: _session), 2);
      expect(sent.map((r) => r.mutation.opId), [
        tag.opId,
        song.opId,
        tag.opId,
        patch.opId,
      ]);
      // Retrying the failed parent keeps its previously frozen identity.
      expect(sent[2].body, sent[0].body);
      expect(sent[2].hash, sent[0].hash);
      final after = _rows(
        await _tables(store),
        'local_mutations',
      ).singleWhere((row) => row['op_id'] == patch.opId);
      expect(after['payload'], patchBefore['payload']);
      expect(after['base_payload'], patchBefore['base_payload']);
      expect(after['request_hash'], patchBefore['request_hash']);
      expect(after['queue_state'], 'ACKED');
      expect(after['attempt_count'], 1);
      final copy = (await repo.read(LocalEntity.recording, rec))!;
      expect(copy.revision, 2);
      expect(jsonDecode(copy.localJson!), tagged);
      expect(jsonDecode(copy.serverJson!), tagged);
      expect(await repo.pendingWork(), isEmpty);
      expect(await repo.nextDispatchAt(), isNull);
      await _expectFilePreserved(store, fileBefore);
    } finally {
      await _dispose(dir, manager);
    }
  });

  test('unsupported relations and file work survive mixed queue dispatch and restart', () async {
    final dir = await Directory.systemTemp.createTemp('sr-dependency-flow-');
    var manager = _manager(dir);
    try {
      var store = await manager.openAccount(owner);
      var repo = LocalRepository(store);
      final fileBefore = await _registerFile(dir, store);
      final held = <LocalEdit>[];
      for (final item in [
        (
          entity: LocalEntity.recordingTag,
          target: id(60),
          body: <String, Object?>{'recording_id': rec, 'tag_id': id(40)},
        ),
        (
          entity: LocalEntity.playlistItem,
          target: id(61),
          body: <String, Object?>{'playlist_id': id(60), 'song_id': id(10)},
        ),
        (
          entity: LocalEntity.recordingTag,
          target: id(62),
          body: <String, Object?>{'recording_id': rec, 'tag_id': id(40)},
        ),
        (
          entity: LocalEntity.recordingFileSpec,
          target: rec,
          body: <String, Object?>{
            'recording_id': rec,
            'sha256': sha256.convert(_audio).toString(),
            'size_bytes': _audio.length,
          },
        ),
        (
          entity: LocalEntity.recordingAsset,
          target: rec,
          body: <String, Object?>{'recording_id': rec, 'cloud_state': 'QUEUED'},
        ),
      ]) {
        final edit = repo.prepareCreate(
          entity: item.entity,
          entityId: item.target,
          draft: item.body,
          changes: item.body,
        );
        await repo.save(edit);
        held.add(edit);
      }
      final heldIds = held.map((edit) => edit.opId).toSet();
      final before = await _tables(store);
      // These earlier, unsupported entries must not starve later supported work.
      final value = {...draft(), 'song_id': id(10)};
      final recording = _recordingCreate(repo, value);
      await repo.save(recording);
      final song = _songCreate(repo);
      await repo.save(song);
      final tag = repo.prepareCreate(
        entity: LocalEntity.tag,
        entityId: id(40),
        draft: {'name': 'before'},
        changes: {'name': 'before'},
      );
      await repo.save(tag);
      final sent = <String>[];
      final transport = FakeTransport((request) async {
        expect(heldIds, isNot(contains(request.mutation.opId)));
        sent.add(request.mutation.opId);
        if (request.mutation.entity == LocalEntity.recording) {
          expect((await repo.read(LocalEntity.song, id(10)))!.revision, 1);
        }
        return _created(request, value);
      });
      // Bound each pass to force planning from freshly committed ACKs.
      for (final expected in [song.opId, tag.opId, recording.opId]) {
        expect(await repo.nextDispatchAt(), isNotNull);
        expect(
          await repo.dispatch(
            transport: transport,
            session: _session,
            limit: 1,
          ),
          1,
        );
        expect(sent.last, expected);
      }
      expect(sent, [song.opId, tag.opId, recording.opId]);
      final plan = await repo.planDispatch();
      expect(
        plan.ready.map((m) => m.opId),
        unorderedEquals([held[0].opId, held[2].opId]),
      );
      expect(
        plan.waiting[held[1].opId]!.reason,
        DispatchWaitReason.missingDependency,
      );
      for (final file in held.skip(3)) {
        expect(plan.waiting[file.opId]!.reason, DispatchWaitReason.unsupported);
      }
      for (final candidate in plan.ready) {
        expect(MutationRequest.prepare(candidate), isNull);
      }

      Future<void> expectHeld() async {
        expect(await repo.nextDispatchAt(), isNull);
        expect(await repo.nextAutomaticRetryAt(), isNull);
        expect(await store.claimMutation(), isNull);
        expect(await repo.dispatch(transport: transport, session: _session), 0);
        expect(sent, [song.opId, tag.opId, recording.opId]);
        expect(
          (await repo.pendingWork()).map((m) => m.opId),
          unorderedEquals(heldIds),
        );
        final after = await _tables(store);
        for (final table in ['local_mutations', 'mutation_retry_controls']) {
          expect(
            _rows(after, table).where((row) => heldIds.contains(row['op_id'])),
            _rows(before, table),
            reason: '$table must retain every unsupported request unchanged',
          );
        }
        expect(
          _rows(
            after,
            'mutation_wire_requests',
          ).where((row) => heldIds.contains(row['op_id'])),
          isEmpty,
        );
        for (final edit in held) {
          final copy = (await repo.read(edit.entity, edit.entityId))!;
          expect(copy.localJson, edit.draftJson);
          expect(copy.serverJson, isNull);
          expect(copy.revision, 0);
          final status = (await repo.retryStatus(edit.opId))!;
          expect(status.queueState, 'PENDING');
          expect(status.attemptCount, 0);
          expect(status.automaticRetriesClaimed, 0);
          expect(status.mode, 'INITIAL');
        }
        await _expectFilePreserved(store, fileBefore);
      }

      await expectHeld();
      await manager.logout();
      manager = _manager(dir);
      store = await manager.openAccount(owner);
      repo = LocalRepository(store);
      await expectHeld();
    } finally {
      await _dispose(dir, manager);
    }
  });
}
