import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_database.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/conflict_resolution_plan.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/metadata_dispatcher.dart';
import 'package:song_record/core/sync/mutation_request.dart';
import 'package:song_record/core/sync/mutation_transport.dart';
import 'package:song_record/features/auth/auth_session.dart';

import 'canonical_song_store_test.dart' show uid, song, ReceiptTransport;
import 'recording_save_dispatch_test.dart' show draft, fileSpec;

final _owner = uid(1), _source = uid(10), _canonical = uid(11), _rec = uid(30);
final _songOp = uid(100),
    _createOp = uid(101),
    _linkOp = uid(102),
    _saveOp = uid(103);
const _bytes = [7, 4, 1, 8];

Map<String, Object?> _fileSpec() => {
  ...fileSpec(),
  'sha256': sha256.convert(_bytes).toString(),
  'size_bytes': _bytes.length,
};

Map<String, Object?> _recording({String? selected}) => {
  ...draft(),
  'id': _rec,
  'song_id': selected ?? _source,
  'key_mode': 'MALE',
  'key_shift': -3,
  'version_code': 'LIVE',
  'note': 'recording private',
  'origin_device_id': _owner,
};

class _Fixture {
  late Directory directory;
  late AccountStoreManager manager;
  late AccountStore store;
  late AccountPaths paths;
  late Map<String, dynamic> fileBefore;
  void Function()? onClock;
  AccountStoreManager newManager() => AccountStoreManager(
    environment: AppEnvironment.dev,
    directory: () async => directory,
    temporaryDirectory: () async => directory,
    clock: () {
      onClock?.call();
      return DateTime.utc(2030);
    },
  );
  Future<void> open() async {
    directory = await Directory.systemTemp.createTemp(
      'sr-canonical-reference-',
    );
    manager = newManager();
    store = await manager.openAccount(_owner);
    paths = await AccountPaths.create(directory, _owner, AppEnvironment.dev);
    final file = await paths.checkedFile(paths.audioPath(_rec));
    await file.writeAsBytes(_bytes, flush: true);
    await store.recordFileAndJournal(
      recordingId: _rec,
      operationId: uid(900),
      state: FilePresence.inputPending,
      phase: JournalPhase.committed,
      pending: false,
      checksum: sha256.convert(_bytes).toString(),
      sizeBytes: _bytes.length,
      recovery: {'song_id': _source, 'note': 'journal private'},
    );
    fileBefore = await tables();
  }

  Future<void> reopen() async {
    await manager.logout();
    manager = newManager();
    store = await manager.openAccount(_owner);
  }

  Future<void> close() async {
    await manager.logout();
    final root = await directory.resolveSymbolicLinks();
    expect(p.basename(root), startsWith('sr-canonical-reference-'));
    expect(
      p.isWithin(await Directory.systemTemp.resolveSymbolicLinks(), root),
      isTrue,
    );
    await Directory(root).delete(recursive: true);
  }

  Future<AuthSession> session() async => AuthSession(
    userId: _owner,
    deviceId: uid(2),
    accessToken: 'synthetic',
    refreshToken: 'unused',
    accessExpiresAt: DateTime.utc(2031),
    refreshExpiresAt: DateTime.utc(2031),
  );
  Future<AccountDatabase> raw() async {
    final db = AccountDatabase(
      NativeDatabase(await paths.databaseFile()),
      userId: _owner,
      environment: AppEnvironment.dev,
    );
    await db.verifyReady();
    return db;
  }

  Future<void> sql(String statement, [List<Object?> args = const []]) async {
    final db = await raw();
    try {
      await db.customStatement(statement, args);
    } finally {
      await db.close();
    }
  }

  Future<Map<String, dynamic>> tables() async =>
      (jsonDecode(await store.recoveryData()) as Map<String, dynamic>)['tables']
          as Map<String, dynamic>;
  Future<void> preserved() async {
    final after = await tables();
    for (final name in ['local_recording_files', 'recording_journals']) {
      expect(after[name], fileBefore[name], reason: name);
    }
    expect(await store.readLocalAudio(_rec), _bytes);
    expect(jsonDecode((await store.readJournal(_rec))!), {
      'song_id': _source,
      'note': 'journal private',
    });
    expect(await store.readCursor(), isNull);
  }

  Future<void> source() => store.saveEdit(
    LocalEdit(
      opId: _songOp,
      entity: LocalEntity.song,
      entityId: _source,
      operation: LocalOperation.create,
      baseRevision: 0,
      draft: {
        ...song(_source),
        'note': 'song private',
        'representative_key_mode': 'MALE',
        'representative_key_shift': 5,
      },
      changes: {
        'id': _source,
        'source_type': 'TJ',
        'source_token': 'opaque-proof',
        'version_code': 'MR',
        'note': 'song private',
      },
    ),
  );
  Future<void> recording() async {
    final value = _recording();
    final fields = {...value}
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
    await store.saveEdit(
      LocalEdit(
        opId: _createOp,
        entity: LocalEntity.recording,
        entityId: _rec,
        operation: LocalOperation.create,
        baseRevision: 0,
        draft: value,
        changes: fields,
      ),
    );
  }

  Future<void> link() => store.saveEdit(
    LocalEdit(
      opId: _linkOp,
      entity: LocalEntity.recording,
      entityId: _rec,
      operation: LocalOperation.patch,
      baseRevision: 0,
      draft: _recording(),
      changes: {'base_revision': 0, 'song_id': _source},
    ),
  );
  Future<void> save() => store.saveEdit(
    LocalEdit(
      opId: _saveOp,
      entity: LocalEntity.recording,
      entityId: _rec,
      operation: LocalOperation.patch,
      baseRevision: 0,
      draft: {..._recording(), 'metadata_state': 'SAVED', 'file': _fileSpec()},
      changes: {
        'base_revision': 0,
        'metadata_state': 'SAVED',
        'file': _fileSpec(),
      },
    ),
  );
  MutationResponse receipt() => MutationResponse(
    200,
    jsonEncode({
      'created': false,
      'canonical_song_id': _canonical,
      'song': song(_canonical),
    }),
  );
}

List<Map<String, dynamic>> _rows(Map<String, dynamic> tables, String name) =>
    (tables[name] as List).cast<Map<String, dynamic>>();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;
  setUp(() async {
    f = _Fixture();
    await f.open();
  });
  tearDown(() async {
    await f.close();
  });

  for (final loseCreate in [false, true]) {
    test(
      'mapping CREATE link and save preserve logical order (lost=$loseCreate)',
      () async {
        await f.source();
        await f.recording();
        await f.link();
        await f.save();
        final before = await f.tables();
        final original = _rows(before, 'local_mutations');
        final sent = <MutationRequest>[];
        var lost = false;
        var confirmed = _recording(selected: _canonical);
        final transport = ReceiptTransport((request) async {
          sent.add(request);
          if (request.mutation.entity == LocalEntity.song) return f.receipt();
          expect(request.mutation.entityId, _rec);
          expect([
            _createOp,
            _linkOp,
            _saveOp,
          ], isNot(contains(request.mutation.opId)));
          if (request.method == 'POST') {
            expect(jsonDecode(request.body)['song_id'], _canonical);
            if (loseCreate && !lost) {
              lost = true;
              throw const MutationNetworkFailure(receivedStatus: 201);
            }
            return MutationResponse(201, jsonEncode(confirmed));
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['base_revision'], confirmed['revision']);
          if (request.path.endsWith('/song')) {
            expect(body, {'base_revision': 1, 'song_id': _canonical});
            // Same-link keeps link_revision; the mutation still advances revision.
            confirmed = {
              ...confirmed,
              'revision': 2,
              'tier': null,
              'tags': <Object>[],
              'tag_ids': <String>[],
            };
            return MutationResponse(200, jsonEncode(confirmed));
          }
          expect(body['metadata_state'], 'SAVED');
          confirmed = {
            ...confirmed,
            'revision': 3,
            'metadata_state': 'SAVED',
            'file': _fileSpec(),
          };
          return MutationResponse(200, jsonEncode(confirmed));
        });
        expect(
          await MetadataDispatcher(
            f.store,
            transport,
            f.session,
          ).dispatch(limit: 1),
          1,
        );
        final mapped = await f.tables();
        expect(_rows(mapped, 'mutation_supersessions'), hasLength(2));
        for (final old in original.where((r) => r['op_id'] != _songOp)) {
          expect(
            _rows(
              mapped,
              'local_mutations',
            ).singleWhere((r) => r['op_id'] == old['op_id']),
            old,
          );
        }
        expect(
          _rows(
            mapped,
            'canonical_edit_intents',
          ).where((r) => r['kind'] == 'SONG_VALUES'),
          hasLength(1),
        );
        final sourceCopy = (await f.store.readMetadata(
          LocalEntity.song,
          _source,
        ))!;
        expect(jsonDecode(sourceCopy.localJson!)['note'], 'song private');
        expect(
          jsonDecode(
            (await f.store.readMetadata(
              LocalEntity.song,
              _canonical,
            ))!.serverJson!,
          )['note'],
          'server note',
        );
        await f.preserved();
        await f.reopen();
        final snapshot = await f.tables();
        expect(await f.store.nextDispatchAt(), isNotNull);
        expect(await f.tables(), snapshot, reason: 'preview is read-only');
        if (loseCreate) {
          expect(
            await MetadataDispatcher(f.store, transport, f.session).dispatch(),
            0,
          );
          final failed = sent.last;
          await f.reopen();
          expect(await f.store.claimMutation(), isNull);
          expect(
            await f.store.retryMutation(
              failed.mutation.opId,
              expectedAttempt: 1,
            ),
            isTrue,
          );
          expect(
            await MetadataDispatcher(f.store, transport, f.session).dispatch(),
            3,
          );
          expect(sent[2].mutation.opId, failed.mutation.opId);
          expect(sent[2].body, failed.body);
          expect(sent[2].hash, failed.hash);
        } else {
          expect(
            await MetadataDispatcher(f.store, transport, f.session).dispatch(),
            3,
          );
        }
        expect(await f.store.pendingWorkMutations(), isEmpty);
        expect(await f.store.nextDispatchAt(), isNull);
        final after = await f.tables();
        expect(_rows(after, 'mutation_supersessions'), hasLength(2));
        expect(_rows(after, 'recording_followups'), hasLength(2));
        for (final old in original.where((r) => r['op_id'] != _songOp)) {
          expect(
            _rows(
              after,
              'local_mutations',
            ).singleWhere((r) => r['op_id'] == old['op_id']),
            old,
          );
        }
        final copy = (await f.store.readMetadata(LocalEntity.recording, _rec))!;
        expect(jsonDecode(copy.localJson!), confirmed);
        expect(jsonDecode(copy.serverJson!), confirmed);
        await f.preserved();
        final expired = f.store;
        final other = await f.manager.openAccount(uid(999));
        expect(await other.readMetadata(LocalEntity.recording, _rec), isNull);
        expect(await other.readJournal(_rec), isNull);
        await expectLater(other.readLocalAudio(_rec), throwsStateError);
        await expectLater(expired.readLocalAudio(_rec), throwsStateError);
        await f.reopen();
        await f.preserved();
        expect(await f.store.nextDispatchAt(), isNull);
      },
    );
  }

  for (final loseResolution in [false, true]) {
    test(
      'canonical save follows resolved note ACK after reopen (lost=$loseResolution)',
      () async {
        await f.source();
        await f.recording();
        final noteOp = uid(104);
        const localNote = 'explicit local note';
        await f.store.saveEdit(
          LocalEdit(
            opId: noteOp,
            entity: LocalEntity.recording,
            entityId: _rec,
            operation: LocalOperation.patch,
            baseRevision: 0,
            draft: {..._recording(), 'note': localNote},
            changes: {'base_revision': 0, 'note': localNote},
          ),
        );
        await f.store.saveEdit(
          LocalEdit(
            opId: _saveOp,
            entity: LocalEntity.recording,
            entityId: _rec,
            operation: LocalOperation.patch,
            baseRevision: 0,
            draft: {
              ..._recording(),
              'note': localNote,
              'metadata_state': 'SAVED',
              'file': _fileSpec(),
            },
            changes: {
              'base_revision': 0,
              'metadata_state': 'SAVED',
              'file': _fileSpec(),
            },
          ),
        );
        final originals = _rows(await f.tables(), 'local_mutations')
            .where((r) => r['op_id'] != _songOp)
            .toList();
        final remote = {
          ..._recording(selected: _canonical),
          'revision': 2,
          'note': 'remote note',
          'tier': null,
          'tags': <Object?>[],
          'tag_ids': <String>[],
        };
        final resolved = {...remote, 'revision': 3, 'note': localNote};
        final saved = {
          ...resolved,
          'revision': 4,
          'metadata_state': 'SAVED',
          'file': _fileSpec(),
        };
        final sent = <MutationRequest>[];
        var lost = false;
        final transport = ReceiptTransport((request) async {
          sent.add(request);
          if (request.mutation.entity == LocalEntity.song) return f.receipt();
          expect(request.mutation.entityId, _rec);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (request.method == 'POST') {
            expect(body['song_id'], _canonical);
            return MutationResponse(
              201,
              jsonEncode(_recording(selected: _canonical)),
            );
          }
          if (body['base_revision'] == 1) {
            expect(body, {'base_revision': 1, 'note': localNote});
            return MutationResponse(
              409,
              jsonEncode({
                'error': {
                  'code': 'REVISION_CONFLICT',
                  'details': {'current': remote, 'current_revision': 2},
                },
              }),
            );
          }
          if (body['metadata_state'] == 'SAVED') {
            expect(body, {
              'base_revision': 3,
              'metadata_state': 'SAVED',
              'file': _fileSpec(),
            });
            return MutationResponse(200, jsonEncode(saved));
          }
          expect(body, {'base_revision': 2, 'note': localNote});
          if (loseResolution && !lost) {
            lost = true;
            throw const MutationNetworkFailure(receivedStatus: 200);
          }
          return MutationResponse(200, jsonEncode(resolved));
        });
        expect(
          await MetadataDispatcher(f.store, transport, f.session).dispatch(),
          2,
        );
        expect(sent, hasLength(3));
        final conflicted = await f.tables();
        final conflict = _rows(conflicted, 'local_mutations')
            .singleWhere((r) => r['queue_state'] == 'CONFLICT');
        final conflictId = conflict['op_id'] as String;
        final conflictWire = _rows(conflicted, 'mutation_wire_requests')
            .singleWhere((r) => r['op_id'] == conflictId);

        Future<void> expectSaveHeld() async {
          final tables = await f.tables();
          final hold = _rows(tables, 'mutation_mapping_holds')
              .singleWhere((r) => r['op_id'] == _saveOp);
          expect(hold['released_at'], isNull);
          expect(
            _rows(tables, 'local_mutations')
                .singleWhere((r) => r['op_id'] == _saveOp),
            originals.singleWhere((r) => r['op_id'] == _saveOp),
          );
          expect(
            _rows(tables, 'recording_followups')
                .where((r) => r['original_op_id'] == _saveOp),
            isEmpty,
          );
          await f.preserved();
        }

        await f.reopen();
        await expectSaveHeld();
        final unresolved = await f.tables();
        expect(await f.store.nextDispatchAt(), isNull);
        expect(await f.tables(), unresolved);
        expect(await f.store.claimMutation(), isNull);
        var serial = 950;
        final repo = LocalRepository(f.store, newId: () => uid(serial++));
        await repo.resolve(
          await repo.review(conflictId),
          {'note': ConflictChoice.local},
        );
        await expectSaveHeld();
        final resolution = _rows(
          await f.tables(),
          'mutation_conflict_resolutions',
        ).single;
        expect(resolution['original_op_id'], conflictId);
        expect(
          resolution['logical_order'],
          originals.singleWhere((r) => r['op_id'] == noteOp)['local_order'],
        );
        await f.reopen();
        await expectSaveHeld();
        final ready = await f.tables();
        expect(await f.store.nextDispatchAt(), isNotNull);
        expect(await f.tables(), ready, reason: 'preview must not release save');
        if (loseResolution) {
          expect(
            await MetadataDispatcher(f.store, transport, f.session)
                .dispatch(limit: 1),
            0,
          );
          final frozen = sent.last;
          await f.reopen();
          await expectSaveHeld();
          final retryWaiting = await f.tables();
          final retryAt = DateTime.utc(2030, 1, 1, 0, 1);
          final retry = (await f.store.retryStatus(frozen.mutation.opId))!;
          expect(retry.queueState, 'RETRY');
          expect(retry.mode, 'AUTO');
          expect(retry.attemptCount, 1);
          expect(retry.automaticRetriesClaimed, 0);
          expect(retry.nextAttemptAt, retryAt);
          expect(retry.canRetryManually, isTrue);
          expect(await f.store.nextDispatchAt(), retryAt);
          expect(await f.store.nextAutomaticRetryAt(), retryAt);
          expect(
            await f.tables(),
            retryWaiting,
            reason: 'retry queries are read-only',
          );
          expect(await f.store.claimMutation(), isNull);
          expect(
            await f.tables(),
            retryWaiting,
            reason: 'no claim before the deadline',
          );
          expect(
            await f.store.retryMutation(
              frozen.mutation.opId,
              expectedAttempt: 1,
            ),
            isTrue,
          );
          final manual = (await f.store.retryStatus(frozen.mutation.opId))!;
          expect(manual.mode, 'MANUAL_READY');
          expect(manual.attemptCount, 1);
          expect(manual.automaticRetriesClaimed, 0);
          expect(manual.nextAttemptAt, isNull);
          expect(await f.store.nextDispatchAt(), DateTime.utc(2030));
          await expectSaveHeld();
        }
        expect(
          await MetadataDispatcher(f.store, transport, f.session)
              .dispatch(limit: 1),
          1,
        );
        final resolutionRequest = sent.last;
        expect(resolutionRequest.mutation.opId, resolution['replacement_op_id']);
        if (loseResolution) {
          expect(resolutionRequest.mutation.opId, sent[3].mutation.opId);
          expect(resolutionRequest.body, sent[3].body);
          expect(resolutionRequest.hash, sent[3].hash);
          expect(resolutionRequest.attempt, 2);
          final acknowledgedRetry = (await f.store.retryStatus(
            resolutionRequest.mutation.opId,
          ))!;
          expect(acknowledgedRetry.queueState, 'ACKED');
          expect(acknowledgedRetry.attemptCount, 2);
          expect(acknowledgedRetry.lastAttemptKind, 'MANUAL');
          expect(acknowledgedRetry.automaticRetriesClaimed, 0);
        }
        await f.reopen();
        final acknowledged = await f.tables();
        expect(await f.store.nextDispatchAt(), isNotNull);
        expect(await f.tables(), acknowledged, reason: 'preview is read-only');
        expect(
          await MetadataDispatcher(f.store, transport, f.session).dispatch(),
          1,
        );
        expect(sent, hasLength(loseResolution ? 6 : 5));
        expect(await f.store.pendingWorkMutations(), isEmpty);
        expect(await f.store.nextDispatchAt(), isNull);
        final after = await f.tables();
        for (final original in originals) {
          expect(
            _rows(after, 'local_mutations')
                .singleWhere((r) => r['op_id'] == original['op_id']),
            original,
          );
        }
        expect(
          _rows(after, 'local_mutations')
              .singleWhere((r) => r['op_id'] == conflictId),
          conflict,
        );
        expect(
          _rows(after, 'mutation_wire_requests')
              .singleWhere((r) => r['op_id'] == conflictId),
          conflictWire,
        );
        expect(_rows(after, 'mutation_conflict_resolutions'), [resolution]);
        final saveEdge = _rows(after, 'recording_followups')
            .singleWhere((r) => r['original_op_id'] == _saveOp);
        expect(saveEdge['predecessor_op_id'], resolutionRequest.mutation.opId);
        expect(saveEdge['replacement_op_id'], sent.last.mutation.opId);
        final copy = (await f.store.readMetadata(LocalEntity.recording, _rec))!;
        expect(jsonDecode(copy.localJson!), saved);
        expect(jsonDecode(copy.serverJson!), saved);
        await f.preserved();
        await f.reopen();
        expect(await f.tables(), after);
        expect(await f.store.nextDispatchAt(), isNull);
        await f.preserved();
      },
    );
  }

  test(
    'playlist identity is remapped once without HTTP or immediate rescheduling',
    () async {
      await f.source();
      final item = uid(50), op = uid(150);
      final value = {
        'id': item,
        'song_id': _source,
        'playlist_id': uid(51),
        'entry_key': 'tj:12345',
        'position': 7,
      };
      await f.store.saveEdit(
        LocalEdit(
          opId: op,
          entity: LocalEntity.playlistItem,
          entityId: item,
          operation: LocalOperation.create,
          baseRevision: 0,
          draft: value,
          changes: value,
        ),
      );
      final request = (await f.store.claimMutation())!;
      expect(
        await f.store.applyCanonicalSongReceipt(request, f.receipt()),
        isTrue,
      );
      final before = await f.tables();
      expect(_rows(before, 'mutation_supersessions'), hasLength(1));
      expect(
        jsonDecode(
          (await f.store.readMetadata(
            LocalEntity.playlistItem,
            item,
          ))!.localJson!,
        ),
        {...value, 'song_id': _canonical},
      );
      expect(
        await f.store.applyCanonicalSongReceipt(request, f.receipt()),
        isFalse,
      );
      expect(await f.store.nextDispatchAt(), isNull);
      expect(await f.store.claimMutation(), isNull);
      await f.reopen();
      expect(await f.store.nextDispatchAt(), isNull);
      expect(await f.store.claimMutation(), isNull);
      expect(await f.tables(), before);
      final pending = await f.store.pendingWorkMutations();
      expect(pending, hasLength(1));
      expect(pending.single.opId, isNot(op));
      expect(pending.single.attemptCount, 0);
      await f.preserved();
    },
  );

  test('edits submitted after alias use the same safe path', () async {
    await f.source();
    final request = (await f.store.claimMutation())!;
    await f.store.applyCanonicalSongReceipt(request, f.receipt());
    await f.recording();
    final next = (await f.store.claimMutation())!;
    expect(next.mutation.opId, isNot(_createOp));
    expect(jsonDecode(next.body)['song_id'], _canonical);
    expect(await f.store.retryMutation(_createOp, expectedAttempt: 0), isFalse);
    await f.preserved();
  });

  test('legacy persisted holds resume after reopening without duplicate materialization', () async {
    await f.source();
    await f.recording();
    // Seed a preserved but currently ineligible queue, as an older mapper did.
    await f.sql(
      "UPDATE mutation_retry_controls SET retry_mode='BLOCKED' WHERE op_id=?",
      [_createOp],
    );
    final request = (await f.store.claimMutation())!;
    await f.store.applyCanonicalSongReceipt(request, f.receipt());
    expect(_rows(await f.tables(), 'mutation_supersessions'), isEmpty);
    await f.sql(
      "UPDATE mutation_retry_controls SET retry_mode='INITIAL' WHERE op_id=?",
      [_createOp],
    );
    await f.reopen();
    final before = await f.tables();
    expect(await f.store.nextDispatchAt(), isNotNull);
    expect(await f.tables(), before);
    final next = (await f.store.claimMutation())!;
    expect(jsonDecode(next.body)['song_id'], _canonical);
    expect(_rows(await f.tables(), 'mutation_supersessions'), hasLength(1));
    expect(await f.store.claimMutation(), isNull);
    await f.preserved();
  });

  for (final baselineState in ['exact', 'newer', 'different-same-revision']) {
    test('confirmed relink requires the exact baseline: $baselineState', () async {
      await f.source();
      final baseline = {
        ..._recording(),
        'revision': 4,
        'tier': null,
        'tags': <Object>[],
        'tag_ids': <String>[],
      };
      await f.sql(
        'INSERT INTO metadata_copies(user_id,entity_type,entity_id,server_revision,server_payload,local_payload,updated_at) VALUES(?,?,?,?,?,?,?)',
        [_owner, 'RECORDING', _rec, 4, canonicalJson(baseline), canonicalJson(baseline), 1],
      );
      await f.store.saveEdit(LocalEdit(
        opId: _linkOp,
        entity: LocalEntity.recording,
        entityId: _rec,
        operation: LocalOperation.patch,
        baseRevision: 4,
        draft: baseline,
        changes: {'base_revision': 4, 'song_id': _source},
      ));
      final original = _rows(await f.tables(), 'local_mutations')
          .singleWhere((row) => row['op_id'] == _linkOp);
      if (baselineState != 'exact') {
        final revision = baselineState == 'newer' ? 5 : 4;
        await f.sql(
          "UPDATE metadata_copies SET server_revision=?,server_payload=? WHERE entity_type='RECORDING' AND entity_id=?",
          [revision, canonicalJson({...baseline, 'revision': revision, 'note': 'received change'}), _rec],
        );
      }
      final mapping = (await f.store.claimMutation())!;
      expect(await f.store.applyCanonicalSongReceipt(mapping, f.receipt()), isTrue);
      await f.reopen();
      final mapped = await f.tables();
      if (baselineState == 'exact') {
        expect(_rows(mapped, 'mutation_supersessions'), hasLength(1));
        final confirmed = {
          ...baseline,
          'song_id': _canonical,
          'revision': 5,
          'link_revision': 2,
        };
        expect(await MetadataDispatcher(f.store, ReceiptTransport((request) async {
          expect(request.method, 'PATCH');
          expect(request.path, '/v1/recordings/$_rec/song');
          expect(request.mutation.opId, isNot(_linkOp));
          expect(request.mutation.basePayload, original['base_payload']);
          expect(jsonDecode(request.body), {'base_revision': 4, 'song_id': _canonical});
          return MutationResponse(200, jsonEncode(confirmed));
        }), f.session).dispatch(), 1);
        expect(await f.store.pendingWorkMutations(), isEmpty);
        final copy = (await f.store.readMetadata(LocalEntity.recording, _rec))!;
        expect(jsonDecode(copy.serverJson!), confirmed);
        expect(jsonDecode(copy.localJson!), confirmed);
      } else {
        expect(_rows(mapped, 'mutation_supersessions'), isEmpty);
        expect(await f.store.claimMutation(), isNull);
        expect(await f.tables(), mapped);
      }
      expect(await f.store.nextDispatchAt(), isNull);
      expect(_rows(await f.tables(), 'local_mutations')
          .singleWhere((row) => row['op_id'] == _linkOp), original);
      await f.preserved();
    });
  }

  test('incomplete reference evidence quarantines the target without scheduling', () async {
    await f.source();
    await f.recording();
    await f.sql("UPDATE mutation_retry_controls SET retry_mode='BLOCKED' WHERE op_id=?", [_createOp]);
    final request = (await f.store.claimMutation())!;
    await f.store.applyCanonicalSongReceipt(request, f.receipt());
    final original = _rows(await f.tables(), 'local_mutations')
        .singleWhere((row) => row['op_id'] == _createOp);
    final replacement = uid(555);
    await f.sql(
      "INSERT INTO local_mutations(op_id,user_id,entity_type,entity_id,operation,base_revision,payload,request_hash,created_at,updated_at) VALUES(?,?,'RECORDING',?,'CREATE',0,?,?,1,1)",
      [replacement, _owner, _rec, canonicalJson({...jsonDecode(original['payload'] as String) as Map<String, dynamic>, 'song_id': _canonical}), List.filled(64, 'a').join()],
    );
    await f.sql(
      "INSERT INTO mutation_retry_controls(op_id,automatic_retries_claimed,retry_mode,last_attempt_kind) VALUES(?,0,'INITIAL','INITIAL')",
      [replacement],
    );
    await f.sql(
      'INSERT INTO mutation_supersessions(original_op_id,replacement_op_id,mapping_source_id,user_id,order_root_op_id,logical_order,created_at) VALUES(?,?,?,?,?,?,1)',
      [_createOp, replacement, _source, _owner, _createOp, original['local_order']],
    );
    await f.sql(
      'UPDATE mutation_mapping_holds SET released_at=2,release_evidence=? WHERE op_id=?',
      [canonicalJson({'contract': 'canonical-reference-v1', 'original_op_id': _createOp, 'replacement_op_id': replacement, 'metadata_before': {'server_revision': 'invalid'}}), _createOp],
    );
    await f.reopen();
    final before = await f.tables();
    expect(await f.store.nextDispatchAt(), isNull);
    expect(await f.store.claimMutation(), isNull);
    expect(await f.tables(), before);
    expect(await f.store.retryMutation(replacement, expectedAttempt: 0), isFalse);
    await f.preserved();
  });

  test('account loss rolls back alias references replacements and holds together', () async {
    await f.source();
    await f.recording();
    await f.link();
    final request = (await f.store.claimMutation())!;
    final before = await f.tables();
    final db = await f.raw();
    Future<void>? closing;
    try {
      f.onClock = () {
        f.onClock = null;
        closing = f.manager.logout();
      };
      await expectLater(f.store.applyCanonicalSongReceipt(request, f.receipt()), throwsStateError);
      await closing!;
      final after = <String, Object?>{};
      for (final table in before.keys) {
        // Match recoveryData's explicit order. SQLite's insertion order is
        // not the exported metadata order; queue rowids remain compared too.
        final query = switch (table) {
          'local_mutations' =>
            'SELECT rowid AS local_order,* FROM local_mutations ORDER BY rowid',
          'metadata_copies' =>
            'SELECT * FROM metadata_copies ORDER BY entity_type,entity_id',
          _ => 'SELECT * FROM $table',
        };
        after[table] = (await db.customSelect(query).get()).map((row) => row.data).toList();
      }
      expect(after, before);
    } finally {
      f.onClock = null;
      await db.close();
    }
    await f.reopen();
    await f.preserved();
  });

  for (final failure in ['mutation', 'control', 'edge', 'release']) {
    test('canonical transaction rolls back replacement failure at $failure', () async {
      await f.source();
      await f.recording();
      final request = (await f.store.claimMutation())!;
      final before = await f.tables();
      final definition = switch (failure) {
        'mutation' => 'BEFORE INSERT ON local_mutations',
        'control' => 'BEFORE INSERT ON mutation_retry_controls',
        'edge' => 'BEFORE INSERT ON mutation_supersessions',
        _ => 'BEFORE UPDATE OF released_at ON mutation_mapping_holds',
      };
      await f.sql(
        "CREATE TRIGGER injected_reference_failure $definition BEGIN SELECT RAISE(ABORT,'injected canonical reference'); END",
      );
      await expectLater(
        f.store.applyCanonicalSongReceipt(request, f.receipt()),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'SQL cause',
            contains('injected canonical reference'),
          ),
        ),
      );
      expect(await f.tables(), before);
      await f.preserved();
      await f.sql('DROP TRIGGER injected_reference_failure');
      expect(
        await f.store.applyCanonicalSongReceipt(request, f.receipt()),
        isTrue,
      );
      expect(_rows(await f.tables(), 'mutation_supersessions'), hasLength(1));
    });
  }

  for (final scenario in [
    'attempted',
    'frozen',
    'different-selection',
    'null-selection',
    'tombstone',
  ]) {
    test('$scenario keeps original held and unrelated tag can send', () async {
      await f.source();
      await f.recording();
      final original = (await f.store.pendingMutations()).singleWhere(
        (m) => m.opId == _createOp,
      );
      if (scenario == 'attempted' || scenario == 'frozen') {
        final wire = MutationRequest.prepare(original)!;
        await f.sql(
          'INSERT INTO mutation_wire_requests(op_id,contract_version,http_method,relative_path,body_json,wire_hash) VALUES(?,?,?,?,?,?)',
          [
            _createOp,
            MutationRequest.contract,
            wire.method,
            wire.path,
            wire.body,
            wire.hash,
          ],
        );
        if (scenario == 'attempted') {
          await f.sql(
            "UPDATE local_mutations SET queue_state='RETRY',attempt_count=1 WHERE op_id=?",
            [_createOp],
          );
          await f.sql(
            "UPDATE mutation_retry_controls SET retry_mode='AUTO',automatic_retries_claimed=1 WHERE op_id=?",
            [_createOp],
          );
        }
      } else if (scenario == 'tombstone') {
        // A received deletion has a positive server revision and snapshot.
        // Keep the unsent CREATE and local input intact while seeding it.
        await f.sql(
          "UPDATE metadata_copies SET tombstone=1,server_revision=2,server_payload=? WHERE entity_type='RECORDING' AND entity_id=?",
          [
            canonicalJson({
              ..._recording(),
              'revision': 2,
              'lifecycle_state': 'PURGED',
            }),
            _rec,
          ],
        );
      } else {
        await f.sql(
          "UPDATE metadata_copies SET local_payload=? WHERE entity_type='RECORDING' AND entity_id=?",
          [
            canonicalJson({
              ..._recording(),
              'song_id': scenario == 'null-selection' ? null : uid(99),
            }),
            _rec,
          ],
        );
      }
      final before = await f.tables();
      await f.store.saveEdit(
        LocalEdit(
          opId: uid(800),
          entity: LocalEntity.tag,
          entityId: uid(80),
          operation: LocalOperation.create,
          baseRevision: 0,
          draft: {'name': 'other'},
          changes: {'id': uid(80), 'name': 'other'},
        ),
      );
      final sent = <String>[];
      expect(
        await MetadataDispatcher(
          f.store,
          ReceiptTransport((request) async {
            sent.add(request.mutation.opId);
            if (request.mutation.entity == LocalEntity.song) return f.receipt();
            expect(request.mutation.entity, LocalEntity.tag);
            return MutationResponse(
              201,
              jsonEncode({
                'id': uid(80),
                'name': 'other',
                'revision': 1,
                'archived_at': null,
                'updated_at': '2026-10-02T00:00:00Z',
              }),
            );
          }),
          f.session,
        ).dispatch(),
        2,
      );
      expect(sent, [_songOp, uid(800)]);
      final after = await f.tables();
      if (scenario == 'tombstone') {
        expect(
          _rows(after, 'metadata_copies').singleWhere(
            (row) => row['entity_type'] == 'RECORDING' && row['entity_id'] == _rec,
          ),
          _rows(before, 'metadata_copies').singleWhere(
            (row) => row['entity_type'] == 'RECORDING' && row['entity_id'] == _rec,
          ),
          reason: 'deletion snapshot and local input must both survive mapping',
        );
      }
      for (final table in [
        'local_mutations',
        'mutation_retry_controls',
        'mutation_wire_requests',
      ]) {
        expect(
          _rows(after, table).where((r) => r['op_id'] == _createOp),
          _rows(before, table).where((r) => r['op_id'] == _createOp),
        );
      }
      expect(_rows(after, 'mutation_supersessions'), isEmpty);
      expect(await f.store.nextDispatchAt(), isNull);
      expect(
        await f.store.retryMutation(
          _createOp,
          expectedAttempt: scenario == 'attempted' ? 1 : original.attemptCount,
        ),
        isFalse,
      );
      await f.reopen();
      expect(await f.store.claimMutation(), isNull);
      await f.preserved();
    });
  }
}
