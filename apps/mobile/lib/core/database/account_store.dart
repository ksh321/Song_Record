import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as native;

import '../../config/app_config.dart';
import '../domain/identifiers.dart';
import '../sync/canonical_conflict_plan.dart';
import '../sync/change_feed_response.dart';
import '../sync/conflict_resolution_plan.dart';
import '../sync/conflict_review.dart';
import '../sync/dependency_planner.dart';
import '../sync/metadata_response.dart';
import '../sync/mutation_request.dart';
import 'account_database.dart' show AccountDatabase;
import 'account_paths.dart';
import 'asset_deletion_store.dart';
import 'canonical_conflict_store.dart';
import 'canonical_reference_store.dart';
import 'change_feed_store.dart';
import 'conflict_resolution_store.dart';
import 'local_models.dart';
import 'mapping_eligibility.dart';
import 'metadata_followup_store.dart';
import 'retry_controls.dart';
import 'snapshot_business_store.dart';
import 'snapshot_download_store.dart';
import 'upload_queue_store.dart';

export 'change_feed_store.dart' show ChangeFeedPosition;
export 'retry_controls.dart' show RetryClock, RetryStatus;
export 'snapshot_download_store.dart'
    show
        SnapshotDownloadState,
        SnapshotProgress,
        SnapshotBaselinePage,
        SnapshotBaselineRecord,
        SnapshotRecordingBaseline;

export 'upload_queue_store.dart' show UploadWork;

typedef SupportDirectory = Future<Directory> Function();

/// Both sources are captured together; callers must not silently merge conflicts
/// or treat a snapshot read as a queued edit's acknowledged baseline.
final class SnapshotMetadataView {
  const SnapshotMetadataView(this.baseline, this.cached);
  final SnapshotBaselineRecord? baseline;
  final MetadataCopy? cached;
  @override
  String toString() => 'SnapshotMetadataView[REDACTED]';
}

// Keep isolate callbacks outside manager closures: only the temporary path may
// cross the isolate boundary, never the manager's pending Future queue.
QueryExecutor _openNativeDatabase(File file, String tempPath) =>
    NativeDatabase.createInBackground(
      file,
      isolateSetup: () {
        native.sqlite3.tempDirectory = tempPath;
      },
      setup: _configureSqlite,
    );

void _configureSqlite(native.Database database) {
  database.execute('PRAGMA journal_mode = WAL');
}

/// One instance per app session. Authentication must supply the verified UUID;
/// this storage boundary does not authenticate arbitrary caller-supplied IDs.
final class AccountStoreManager {
  AccountStoreManager({
    required this.environment,
    SupportDirectory? directory,
    SupportDirectory? temporaryDirectory,
    RetryClock? clock,
  }) : _directory = directory ?? getApplicationSupportDirectory,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _clock = clock ?? DateTime.now;

  final AppEnvironment environment;
  final SupportDirectory _directory;
  final SupportDirectory _temporaryDirectory;
  final RetryClock _clock;
  Future<void> _tail = Future<void>.value();
  AccountStore? _active;
  int _generation = 0;

  Future<T> _serialize<T>(Future<T> Function() action) {
    final completion = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completion.complete(await action());
      } catch (error, stack) {
        completion.completeError(error, stack);
      }
    });
    return completion.future;
  }

  Future<AccountStore> openAccount(String userId) {
    final canonicalId = UuidValue(userId).value;
    final generation = ++_generation; // Invalidate old handles immediately.
    return _serialize(() async {
      if (generation != _generation) {
        throw StateError('Account opening was superseded');
      }
      final previous = _active;
      _active = null;
      await previous?._database.close();
      final paths = await AccountPaths.create(
        await _directory(),
        canonicalId,
        environment,
      );
      final file = await paths.databaseFile();
      final tempPath = (await _temporaryDirectory()).path;
      final database = AccountDatabase(
        _openNativeDatabase(file, tempPath),
        userId: canonicalId,
        environment: environment,
      );
      final store = AccountStore._(this, database, paths, generation);
      void requireOpening() {
        if (generation != _generation) {
          throw StateError('Account changed while opening storage');
        }
      }

      try {
        await database.verifyReady();
        requireOpening();
        await store._retry.recoverOpening(requireOpening);
        await store._uploads.recover();
        requireOpening();
      } catch (_) {
        await database.close();
        rethrow;
      }
      _active = store;
      return store;
    });
  }

  Future<void> logout() {
    ++_generation;
    return _serialize(() async {
      final previous = _active;
      _active = null;
      await previous?._database.close();
      // Deliberately preserve the DB, pending edits, journals, and audio files.
    });
  }

  void _requireCurrent(AccountStore store) {
    if (!identical(_active, store) || store._generation != _generation) {
      throw StateError('This account storage session has expired');
    }
  }

  Future<T> _run<T>(AccountStore store, Future<T> Function() action) =>
      _serialize(() async {
        _requireCurrent(store);
        final result = await action();
        _requireCurrent(
          store,
        ); // Do not deliver a late account-A result to account-B UI.
        return result;
      });
}

/// Scoped lease, not a global database singleton. No raw database or File escapes
/// this API. Login/logout integration belongs to P06; recorder bridging to P18.
final class AccountStore {
  AccountStore._(this._manager, this._database, this._paths, this._generation);
  final AccountStoreManager _manager;
  final AccountDatabase _database;
  final AccountPaths _paths;
  final int _generation;
  late final RetryControls _retry = RetryControls(
    _database,
    clock: _manager._clock,
  );
  late final UploadQueueStore _uploads = UploadQueueStore(
    _database,
    _manager._clock,
  );
  Future<void> discoverUploads() => _run(_uploads.discover);
  Future<UploadWork?> claimUpload() => _run(_uploads.claim);
  Future<bool> uploadCurrent(UploadWork work) =>
      _run(() => _uploads.current(work));
  Future<bool> saveUploadTicket(UploadWork work, String attempt) =>
      _run(() => _uploads.ticket(work, attempt));
  Future<void> settleUpload(
    UploadWork work,
    String phase,
    String? reason, {
    bool retry = false,
  }) => _run(() => _uploads.settle(work, phase, reason, retry: retry));
  Future<void> cancelUpload(String id) => _run(() => _uploads.cancel(id));
  Future<void> retryUpload(String id) => _run(() => _uploads.retry(id));
  Future<DateTime?> nextUploadAt() => _run(_uploads.next);
  Future<List<Map<String, Object?>>> uploadStatus() => _run(_uploads.status);
  String get userId => _paths.userId;

  Future<T> _run<T>(Future<T> Function() action) => _manager._run(this, action);

  late final SnapshotDownloadStore _snapshots = SnapshotDownloadStore(
    _database,
    clock: _manager._clock,
    requireActive: requireActive,
  );
  Future<void> beginSnapshotDownload(String token, String manifest) =>
      _run(() => _snapshots.begin(token, manifest));
  Future<SnapshotDownloadState> snapshotDownloadState(String token) =>
      _run(() => _snapshots.read(token));
  Future<void> appendSnapshotPage(
    String token,
    String entity,
    int afterOrdinal,
    String body,
  ) => _run(() => _snapshots.append(token, entity, afterOrdinal, body));
  Future<void> verifySnapshotDownload(String token) =>
      _run(() => _snapshots.verify(token));
  Future<void> discardSnapshotDownload(String token) =>
      _run(() => _snapshots.discard(token));

  /// Retire only the observed receive attempt. Staging and its resume pointer
  /// must disappear together, including when a page cursor fails before TTL.
  Future<bool> restartSnapshotDownload(String expected) => _run(
    () => _database.transaction(() async {
      requireActive();
      final state = jsonDecode(expected) as Map<String, dynamic>;
      final token = state['token'] as String;
      if (!{'BUILDING', 'RECEIVING'}.contains(state['phase']) ||
          UuidValue(token).value != token) {
        throw const FormatException('Invalid snapshot restart');
      }
      final changed = await _database.customUpdate(
        '''UPDATE sync_cursors SET snapshot_resume=NULL,updated_at=?
        WHERE singleton=1 AND user_id=? AND baseline_complete=0
          AND snapshot_resume=? AND NOT EXISTS(
            SELECT 1 FROM snapshot_downloads WHERE snapshot_token=? AND state='APPLIED')''',
        variables: [
          Variable(_manager._clock().toUtc().millisecondsSinceEpoch),
          Variable(userId),
          Variable(expected),
          Variable(token),
        ],
      );
      if (changed == 0) return false;
      await _snapshots.discard(token);
      requireActive();
      return true;
    }),
  );
  Future<void> applySnapshotDownload(String token) =>
      _run(() => _applySnapshotDownload(token));

  Future<void> _applySnapshotDownload(String token) => _snapshots.apply(
    token,
    projectBusiness: () async {
      await SnapshotBusinessStore(
        _database,
        requireActive: requireActive,
        clock: _manager._clock,
      ).apply(
        token,
        AssetDeletionStore(_database, requireActive, _manager._clock),
      );
    },
  );

  /// Mutating completion gate for the receiver, separate from read-only status.
  /// Repairs a legacy baseline in the same transaction that pins its token.
  Future<bool> prepareCompletedSnapshot() => _run(
    () => _database.transaction(() async {
      final state = await _database
          .customSelect(
            '''
        SELECT c.baseline_complete,c.snapshot_resume,b.snapshot_token
        FROM sync_cursors c
        LEFT JOIN snapshot_baseline b ON b.singleton=c.singleton AND b.user_id=c.user_id
        WHERE c.singleton=1 AND c.user_id=?
        ''',
            variables: [Variable(userId)],
          )
          .getSingle();
      if (state.read<int>('baseline_complete') != 1 ||
          state.readNullable<String>('snapshot_resume') != null) {
        requireActive();
        return false;
      }
      final token = state.readNullable<String>('snapshot_token');
      if (token == null) {
        throw StateError('Completed snapshot baseline is missing');
      }
      await _applySnapshotDownload(token);
      requireActive();
      return true;
    }),
  );
  Future<SnapshotRecordingBaseline?> snapshotRecordingBaseline(
    String recordingId, {
    String? expectedToken,
  }) => _run(
    () =>
        _snapshots.recordingBaseline(recordingId, expectedToken: expectedToken),
  );
  Future<ChangeFeedPosition?> readChangeFeedPosition() => _run(
    () => ChangeFeedStore(
      _database,
      requireActive: requireActive,
      clock: _manager._clock,
    ).position(),
  );
  Future<void> applyChangeFeed(
    ChangeFeedPage page, {
    required String snapshotToken,
    void Function()? requireCurrent,
  }) => _run(
    () => ChangeFeedStore(
      _database,
      requireActive: () {
        requireActive();
        requireCurrent?.call();
      },
      clock: _manager._clock,
    ).apply(page, snapshotToken: snapshotToken),
  );
  Future<SnapshotBaselinePage> snapshotBaselinePage(
    String entity, {
    String? expectedToken,
    int after = 0,
    int limit = 50,
  }) => _run(
    () => _snapshots.baselinePage(
      entity,
      expectedToken: expectedToken,
      after: after,
      limit: limit,
    ),
  );

  Future<SnapshotBaselineRecord?> snapshotBaselineRecord(
    String entity,
    String resourceId, {
    String? expectedToken,
  }) => _run(
    () => _snapshots.baselineRecord(
      entity,
      resourceId,
      expectedToken: expectedToken,
    ),
  );

  Future<String> recoveryData() => _run(
    () => _database.transaction(() async {
      final tables = <String, Object?>{};
      const orderBy = <String, String>{
        'local_account': 'singleton',
        'metadata_copies': 'entity_type,entity_id',
        'local_mutations': 'rowid',
        'mutation_wire_requests': 'op_id',
        'mutation_retry_controls': 'op_id',
        'song_aliases': 'source_song_id',
        'mutation_supersessions': 'original_op_id',
        'mutation_conflict_resolutions': 'original_op_id',
        'pending_edit_resolutions': 'original_op_id',
        'recording_followups': 'original_op_id',
        'canonical_edit_intents': 'intent_id',
        'mutation_mapping_holds': 'op_id,mapping_source_id,reason',
        'local_recording_files': 'recording_id',
        'local_upload_queue': 'recording_id',
        'local_cleanup_confirmations': 'token',
        'recording_journals': 'recording_id',
        'import_jobs': 'import_job_id',
        'import_items': 'import_job_id,ordinal',
        'sync_cursors': 'singleton',
        'snapshot_downloads': 'snapshot_token',
        'snapshot_download_rows': 'snapshot_token,entity,ordinal',
        'snapshot_download_progress': 'snapshot_token,entity',
        'snapshot_baseline': 'singleton',
      };
      for (final entry in orderBy.entries) {
        final table = entry.key;
        final projection = table == 'local_mutations'
            ? 'rowid AS local_order,*'
            : '*';
        final rows = await _database
            .customSelect(
              'SELECT $projection FROM $table ORDER BY ${entry.value}',
            )
            .get();
        tables[table] = rows.map((row) => row.data).toList();
      }
      return jsonEncode({
        'format': 'song-record-local-recovery',
        'version': 2,
        'schema_version': _database.schemaVersion,
        'source_user_id': userId,
        'environment': _paths.environment.name,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'tables': tables,
      });
    }),
  );

  Future<MetadataCopy?> readMetadata(LocalEntity entity, String entityId) =>
      _run(() => _readMetadata(entity, entityId));

  /// Durable receipt evidence, not an inference from every unlinked recording.
  /// Keep the notice until the current server copy is linked or deleted.
  Future<int> unlinkedOfflineRecordingCount() => _run(() async {
    final row = await _database
        .customSelect(
          '''
      SELECT COUNT(DISTINCT m.entity_id) AS total FROM local_mutations m
      JOIN metadata_copies c ON c.entity_type=m.entity_type AND c.entity_id=m.entity_id
      WHERE m.user_id=? AND c.user_id=? AND m.entity_type='RECORDING'
        AND m.operation='CREATE' AND m.queue_state='ACKED'
        AND json_type(m.payload,'\u0024.song_id')='text'
        AND json_type(m.server_response,'\u0024.song_id')='null'
        AND json_extract(m.server_response,'\u0024.id')=m.entity_id
        AND c.tombstone=0 AND json_type(c.server_payload,'\u0024.song_id')='null'
        AND json_extract(c.server_payload,'\u0024.lifecycle_state')='ACTIVE'
    ''',
          variables: [Variable(userId), Variable(userId)],
        )
        .getSingle();
    requireActive();
    return row.read<int>('total');
  });

  Future<SnapshotMetadataView> snapshotMetadataView(
    LocalEntity entity,
    String entityId, {
    String? expectedToken,
  }) => _run(
    () => _database.transaction(() async {
      final baseline = await _snapshots.baselineRecord(
        entity.code,
        entityId,
        expectedToken: expectedToken,
      );
      final cached = await _readMetadata(entity, entityId);
      requireActive();
      return SnapshotMetadataView(baseline, cached);
    }),
  );

  Future<MetadataCopy?> _readMetadata(
    LocalEntity entity,
    String entityId,
  ) async {
    final row = await _database
        .customSelect(
          'SELECT * FROM metadata_copies WHERE entity_type=? AND entity_id=?',
          variables: [
            Variable(entity.code),
            Variable(UuidValue(entityId).value),
          ],
        )
        .getSingleOrNull();
    return row == null
        ? null
        : MetadataCopy(
            revision: row.read<int>('server_revision'),
            serverJson: row.readNullable<String>('server_payload'),
            localJson: row.readNullable<String>('local_payload'),
            tombstone: row.read<int>('tombstone') == 1,
          );
  }

  Future<void> saveEdit(LocalEdit edit) => _run(() async {
    _validatePayloadOwner(edit.draftJson);
    _validatePayloadOwner(edit.changesJson);
    final fingerprint = sha256
        .convert(
          utf8.encode(
            canonicalJson({
              'entity': edit.entity.code,
              'id': edit.entityId,
              'operation': edit.operation.code,
              'base_revision': edit.baseRevision,
              'draft': jsonDecode(edit.draftJson),
              'changes': jsonDecode(edit.changesJson),
            }),
          ),
        )
        .toString();
    await _database.transaction(() async {
      final oldRequest = await _database
          .customSelect(
            'SELECT request_hash FROM local_mutations WHERE op_id=?',
            variables: [Variable(edit.opId)],
          )
          .getSingleOrNull();
      if (oldRequest != null) {
        if (oldRequest.read<String>('request_hash') != fingerprint) {
          throw StateError('An op_id cannot be reused for a different edit');
        }
        return; // A retry must not overwrite a newer local draft.
      }
      final baseline = await _database
          .customSelect(
            'SELECT server_revision,server_payload,tombstone FROM metadata_copies WHERE entity_type=? AND entity_id=?',
            variables: [Variable(edit.entity.code), Variable(edit.entityId)],
          )
          .getSingleOrNull();
      if ((baseline?.read<int>('server_revision') ?? 0) != edit.baseRevision ||
          baseline?.read<int>('tombstone') == 1) {
        throw StateError(
          'Edit baseline changed or the resource was permanently deleted',
        );
      }
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await _database.customStatement(
        '''INSERT INTO metadata_copies(user_id,entity_type,entity_id,local_payload,updated_at)
        VALUES(?,?,?,?,?) ON CONFLICT(entity_type,entity_id) DO UPDATE SET local_payload=excluded.local_payload,updated_at=excluded.updated_at''',
        [userId, edit.entity.code, edit.entityId, edit.draftJson, now],
      );
      await _database.customStatement(
        '''INSERT INTO local_mutations(op_id,user_id,entity_type,entity_id,operation,base_revision,
        base_payload,payload,request_hash,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)''',
        [
          edit.opId,
          userId,
          edit.entity.code,
          edit.entityId,
          edit.operation.code,
          edit.baseRevision,
          baseline?.readNullable<String>('server_payload'),
          edit.changesJson,
          fingerprint,
          now,
          now,
        ],
      );
      await _database.customStatement(
        '''INSERT INTO mutation_retry_controls(
          op_id,automatic_retries_claimed,retry_mode,last_attempt_kind
        ) VALUES(?,0,'INITIAL','INITIAL')''',
        [edit.opId],
      );
      await materializeCanonicalReferences(_database, _retry.nowMs);
      requireActive();
    });
  });

  void _validatePayloadOwner(String json) {
    final payload = jsonDecode(json) as Map<String, Object?>;
    if (payload.containsKey('user_id') && payload['user_id'] != userId) {
      throw ArgumentError('Payload belongs to another account');
    }
  }

  Future<List<QueuedMutation>> pendingMutations() => _run(_pendingMutations);

  /// Work list excludes only validated, explicitly resolved history. Recovery
  /// and pendingMutations keep the original requests for inspection/export.
  Future<List<QueuedMutation>> pendingWorkMutations() => _run(
    () => _database.transaction(() async {
      final pending = await _pendingMutations();
      final mapping = await readMappingEligibility(_database);
      requireActive();
      return pending
          .where(
            (m) =>
                !mapping.superseded.contains(m.opId) ||
                mapping.blocked.contains(m.opId),
          )
          .toList(growable: false);
    }),
  );

  Future<ConflictReview> readConflictReview(String opId) => _run(
    () => _database.transaction(() async {
      final mapping = await readMappingEligibility(_database);
      final pending = await _pendingMutations();
      final mutation = pending.firstWhere((m) => m.opId == opId);
      final pendingReview =
          mutation.state == 'PENDING' && mutation.attemptCount == 0;
      if (pendingReview) {
        final unrestricted = await readMappingEligibility(
          _database,
          holdDrafts: false,
        );
        final wire = await _database
            .customSelect(
              'SELECT op_id FROM mutation_wire_requests WHERE op_id=?',
              variables: [Variable(opId)],
            )
            .get();
        if (!mapping.blocked.contains(opId) ||
            !unrestricted.allows(opId) ||
            wire.isNotEmpty) {
          throw StateError('Pending draft is not held for explicit review');
        }
      } else if (!mapping.allows(opId)) {
        throw StateError('Conflict is held or resolved');
      }
      final copy = await _readMetadata(mutation.entity, mutation.entityId);
      if (copy == null || copy.tombstone) {
        throw StateError('Conflict target unavailable');
      }
      final original = pendingReview
          ? null
          : ConflictReview(mutation, copy.localJson);
      final serverJson =
          pendingReview || copy.revision > (original!.server['revision'] as int)
          ? copy.serverJson
          : null;
      final queueEvidence = await conflictQueueEvidence(
        _database,
        mutation.entity,
        mutation.entityId,
      );
      final review = ConflictReview(
        mutation,
        copy.localJson,
        serverJson: serverJson,
        queueEvidence: queueEvidence,
        pendingReview: pendingReview,
      );
      final names = <String, String>{};
      if (review.comparison.conflicts.any(
        (group) => group.contains('tag_ids'),
      )) {
        final selected = <String>{};
        for (final values in [review.local, review.server]) {
          if (values['tag_ids'] case final List<dynamic> values) {
            selected.addAll(values.cast<String>());
          }
        }
        for (final id in selected) {
          final tag = await _readMetadata(LocalEntity.tag, id);
          final payload = tag?.localJson ?? tag?.serverJson;
          if (payload != null) {
            final decoded = jsonDecode(payload);
            if (decoded is Map && decoded['name'] is String) {
              names[id] = decoded['name'] as String;
            }
          }
        }
      }
      requireActive();
      return ConflictReview(
        mutation,
        copy.localJson,
        tagNames: names,
        serverJson: serverJson,
        queueEvidence: queueEvidence,
        pendingReview: pendingReview,
      );
    }),
  );

  Future<List<CanonicalConflictReview>> canonicalCandidates() => _run(
    () => _database.transaction(
      () => CanonicalConflictStore(_database, requireActive).list(),
    ),
  );

  Future<CanonicalConflictReview> readCanonicalConflict(String id) => _run(
    () => _database.transaction(
      () => CanonicalConflictStore(_database, requireActive).review(id),
    ),
  );

  Future<void> resolveCanonicalConflict(
    CanonicalConflictReview review,
    ConflictChoice choice,
    String newOpId,
  ) => _run(
    () => _database.transaction(
      () => CanonicalConflictStore(
        _database,
        requireActive,
      ).resolve(review, choice, newOpId, _retry.nowMs),
    ),
  );

  Future<void> resolveMetadataConflict({
    required QueuedMutation expected,
    required String? expectedLocalJson,
    required String? replacementOpId,
    Map<String, ConflictChoice> choices = const {},
    String? expectedServerJson,
    String? expectedQueueEvidence,
    bool pendingReview = false,
  }) {
    final capturedChoices = Map<String, ConflictChoice>.unmodifiable(choices);
    return _run(
      () => _database.transaction(
        () => ConflictResolutionStore(_database, requireActive).resolve(
          expected: expected,
          expectedLocalJson: expectedLocalJson,
          replacementOpId: replacementOpId,
          choices: capturedChoices,
          expectedServerJson: expectedServerJson,
          expectedQueueEvidence: expectedQueueEvidence,
          pendingReview: pendingReview,
          now: _retry.nowMs,
        ),
      ),
    );
  }

  Future<List<QueuedMutation>> _pendingMutations() async {
    final rows = await _database
        .customSelect(
          "SELECT rowid AS local_order,* FROM local_mutations WHERE queue_state<>'ACKED' ORDER BY rowid",
        )
        .get();
    return rows
        .map(
          (row) => QueuedMutation(
            opId: row.read<String>('op_id'),
            localOrder: row.read<int>('local_order'),
            entity: LocalEntity.values.firstWhere(
              (value) => value.code == row.read<String>('entity_type'),
            ),
            entityId: row.read<String>('entity_id'),
            operation: LocalOperation.values.firstWhere(
              (value) => value.code == row.read<String>('operation'),
            ),
            state: row.read<String>('queue_state'),
            baseRevision: row.read<int>('base_revision'),
            payload: row.read<String>('payload'),
            basePayload: row.readNullable<String>('base_payload'),
            serverResponse: row.readNullable<String>('server_response'),
            attemptCount: row.read<int>('attempt_count'),
          ),
        )
        .toList(growable: false);
  }

  Future<DispatchSnapshot> dispatchSnapshot() =>
      _run(() => _database.transaction(_dispatchSnapshot));

  Future<DispatchSnapshot> _dispatchSnapshot() async {
    final pending = await _pendingMutations();
    final rows = await _database
        .customSelect(
          'SELECT entity_type,entity_id,server_revision,tombstone FROM metadata_copies',
        )
        .get();
    return DispatchSnapshot(
      pending: pending,
      mapping: await readMappingEligibility(_database),
      baselines: {
        for (final row in rows)
          LocalTarget(
            LocalEntity.values.firstWhere(
              (value) => value.code == row.read<String>('entity_type'),
            ),
            row.read<String>('entity_id'),
          ): ServerBaseline(
            revision: row.read<int>('server_revision'),
            tombstone: row.read<int>('tombstone') == 1,
          ),
      },
    );
  }

  /// Synchronous fence for the transport before credentials/body leave the process.
  void requireActive() => _manager._requireCurrent(this);

  Future<MutationRequest?> claimMutation() => _run(
    () => _database.transaction(() async {
      await materializeCanonicalReferences(_database, _retry.nowMs);
      await materializeMetadataFollowup(
        _database,
        await readMappingEligibility(_database),
      );
      final snapshot = await _retry.forPlanner(await _dispatchSnapshot());
      final plan = const DependencyPlanner().plan(snapshot);
      for (final candidate in plan.ready) {
        final request = await _retry.claim(candidate);
        if (request == null) continue;
        requireActive();
        return request;
      }
      requireActive();
      return null;
    }),
  );

  Future<RetryStatus?> retryStatus(String opId) => _run(
    () => _database.transaction(() => _retry.status(UuidValue(opId).value)),
  );

  Future<bool> retryMutation(String opId, {required int expectedAttempt}) =>
      _run(
        () => _database.transaction(() async {
          final changed = await _retry.authorizeManual(
            UuidValue(opId).value,
            expectedAttempt: expectedAttempt,
          );
          requireActive();
          return changed;
        }),
      );

  /// Earliest automatic deadline among dependency-ready mutations.
  /// A returned time can already be due. The dispatcher must drain claims
  /// and recompute after queue changes; this API does not send anything.
  Future<DateTime?> nextAutomaticRetryAt() =>
      _nextDispatchAt(includeReady: false);

  /// A bounded foreground pass must also continue ready initial/manual work.
  /// This is a read-only eligibility check; only claimMutation spends a budget.
  Future<DateTime?> nextDispatchAt() => _nextDispatchAt(includeReady: true);

  Future<DateTime?> _nextDispatchAt({required bool includeReady}) => _run(
    () => _database.transaction(() async {
      if (includeReady &&
          await materializeCanonicalReferences(
            _database,
            _retry.nowMs,
            previewOnly: true,
          )) {
        return _retry.now;
      }
      if (includeReady &&
          await materializeMetadataFollowup(
            _database,
            await readMappingEligibility(_database),
            previewOnly: true,
          )) {
        return _retry.now;
      }
      final snapshot = await _retry.forPlanner(
        await _dispatchSnapshot(),
        includeFutureAutomatic: true,
      );
      final plan = const DependencyPlanner().plan(snapshot);
      DateTime? earliest;
      for (final candidate in plan.ready) {
        final control = await _retry.status(candidate.opId);
        if (includeReady &&
            (control?.mode == 'INITIAL' || control?.mode == 'MANUAL_READY')) {
          final sendable = candidate.attemptCount > 0
              ? snapshot.frozenRetries.contains(candidate.opId)
              : MutationRequest.prepare(candidate) != null;
          if (sendable) return _retry.now;
        }
        final due = control?.nextAttemptAt;
        if (control?.mode == 'AUTO' &&
            due != null &&
            (earliest == null || due.isBefore(earliest))) {
          earliest = due;
        }
      }
      return earliest;
    }),
  );

  /// Atomically maps a validated receipt with attempt fencing. Mapping holds
  /// participate in dispatch eligibility before the next mutation is claimed.
  ///
  /// true: committed a new mapping.
  /// false: no longer owns this attempt, including an already applied receipt.
  Future<bool> applyCanonicalSongReceipt(
    MutationRequest request,
    MutationResponse response,
  ) => _run(
    () => _database.transaction(
      () => _applyCanonicalSongReceipt(request, response),
    ),
  );

  /// Requires the caller's transaction and AccountStore serialization.
  Future<bool> _applyCanonicalSongReceipt(
    MutationRequest request,
    MutationResponse response,
  ) async {
    requireActive();

    // Always decode internally; callers cannot supply unchecked snapshot fields.
    final receipt = CanonicalSongReceipt.decode(request, response);
    final mutation = request.mutation;
    final sourceId = receipt.localSongId;
    final canonicalId = receipt.canonicalSongId;

    // The raw receipt must remain byte-for-byte intact. Reject identities
    // requiring normalization rather than rewriting its canonical ID.
    if (UuidValue(sourceId).value != sourceId ||
        UuidValue(canonicalId).value != canonicalId ||
        mutation.baseRevision != 0 ||
        request.attempt < 1) {
      throw const FormatException('Invalid canonical mapping identity');
    }
    _validatePayloadOwner(request.body);

    if (!await _ownsAttempt(request)) {
      requireActive();
      return false;
    }

    // Small supported scope: direct source -> canonical mappings.
    // An incoming alias to canonical is a fan-in, not a chain.
    final chain = await _database
        .customSelect(
          '''
        SELECT source_song_id FROM song_aliases
        WHERE source_song_id IN (?,?) OR canonical_song_id=?
        LIMIT 1
      ''',
          variables: [
            Variable(sourceId),
            Variable(canonicalId),
            Variable(sourceId),
          ],
        )
        .get();
    if (chain.isNotEmpty) {
      throw StateError(
        'Existing source alias or alias chain requires follow-up',
      );
    }

    final superseded = await _database
        .customSelect(
          '''
        SELECT original_op_id FROM mutation_supersessions
        WHERE original_op_id=? OR replacement_op_id=?
        LIMIT 1
      ''',
          variables: [Variable(mutation.opId), Variable(mutation.opId)],
        )
        .get();
    if (superseded.isNotEmpty) {
      throw StateError('Mapping CREATE belongs to a supersession chain');
    }

    Future<QueryRow?> songCopy(String id) => _database
        .customSelect(
          '''
        SELECT * FROM metadata_copies
        WHERE entity_type='SONG' AND entity_id=?
      ''',
          variables: [Variable(id)],
        )
        .getSingleOrNull();

    final source = await songCopy(sourceId);
    final canonicalBefore = await songCopy(canonicalId);
    if (source == null ||
        source.read<String>('user_id') != userId ||
        (canonicalBefore != null &&
            canonicalBefore.read<String>('user_id') != userId)) {
      throw StateError('Canonical mapping metadata ownership mismatch');
    }

    // Capture all evidence before any projection changes.
    final pending = await _database
        .customSelect(
          '''
        SELECT rowid AS local_order,* FROM local_mutations
        WHERE queue_state<>'ACKED' AND op_id<>?
        ORDER BY rowid
      ''',
          variables: [Variable(mutation.opId)],
        )
        .get();

    final references = await _database.customSelect('''
        SELECT * FROM metadata_copies
        WHERE entity_type IN ('RECORDING','PLAYLIST_ITEM')
        ORDER BY entity_type,entity_id
      ''').get();

    final referenceMutations = <String, List<QueryRow>>{};
    for (final row in pending) {
      final entity = row.read<String>('entity_type');
      if (entity == 'RECORDING' || entity == 'PLAYLIST_ITEM') {
        final key = '$entity:${row.read<String>('entity_id')}';
        referenceMutations.putIfAbsent(key, () => <QueryRow>[]).add(row);
      }
    }

    final now = _retry.nowMs;
    final snapshotJson = canonicalJson(receipt.snapshot);
    final revision = receipt.snapshot['revision'] as int;

    if (canonicalBefore == null) {
      await _database.customStatement(
        '''
          INSERT INTO metadata_copies(
            user_id,entity_type,entity_id,server_revision,
            server_payload,local_payload,updated_at
          ) VALUES(?,'SONG',?,?,?,?,?)
        ''',
        [userId, canonicalId, revision, snapshotJson, snapshotJson, now],
      );
    } else if (canonicalBefore.read<int>('tombstone') == 0 &&
        canonicalBefore.read<int>('server_revision') < revision) {
      // Never replace an existing draft, including an explicit SQL NULL.
      // Equal revisions are preserved too; the exact new receipt lives below.
      await _database.customStatement(
        '''
          UPDATE metadata_copies
          SET server_revision=?,server_payload=?,updated_at=?
          WHERE entity_type='SONG' AND entity_id=?
        ''',
        [revision, snapshotJson, now, canonicalId],
      );
    }

    // No OR IGNORE / REPLACE: v4 evidence triggers deliberately reject them.
    await _database.customStatement(
      '''
        INSERT INTO song_aliases(
          source_song_id,canonical_song_id,user_id,mapping_op_id,
          receipt_status,receipt_body,created_at
        ) VALUES(?,?,?,?,?,?,?)
      ''',
      [
        sourceId,
        canonicalId,
        userId,
        mutation.opId,
        receipt.status,
        receipt.envelopeBody,
        now,
      ],
    );

    Future<String> intent({
      required String key,
      required String kind,
      required String entity,
      required String entityId,
      required String? originOpId,
      required Map<String, Object?> evidence,
    }) async {
      // A deterministic UUID-shaped identifier. Uniqueness is still enforced
      // by both the PK and (mapping_source_id,intent_key).
      final hash = sha256
          .convert(
            utf8.encode(
              canonicalJson({
                'namespace': 'song-record-canonical-intent-v1',
                'user_id': userId,
                'mapping_source_id': sourceId,
                'intent_key': key,
              }),
            ),
          )
          .toString();
      final id =
          '${hash.substring(0, 8)}-${hash.substring(8, 12)}-'
          '8${hash.substring(13, 16)}-a${hash.substring(17, 20)}-'
          '${hash.substring(20, 32)}';

      await _database.customStatement(
        '''
          INSERT INTO canonical_edit_intents(
            intent_id,user_id,mapping_source_id,intent_key,kind,
            entity_type,entity_id,origin_op_id,evidence_json,created_at
          ) VALUES(?,?,?,?,?,?,?,?,?,?)
        ''',
        [
          id,
          userId,
          sourceId,
          key,
          kind,
          entity,
          entityId,
          originOpId,
          canonicalJson(evidence),
          now,
        ],
      );
      return id;
    }

    Future<void> hold(QueryRow row, String intentId) =>
        _database.customStatement(
          '''
            INSERT INTO mutation_mapping_holds(
              op_id,mapping_source_id,user_id,reason,
              disposition,intent_id,created_at
            ) VALUES(?,?,?,'CANONICAL_MAPPING','BLOCK',?,?)
          ''',
          [row.read<String>('op_id'), sourceId, userId, intentId, now],
        );

    await intent(
      key: 'song-values',
      kind: 'SONG_VALUES',
      entity: 'SONG',
      entityId: sourceId,
      originOpId: mutation.opId,
      evidence: {
        'version': 1,
        'source_before': source.data,
        'canonical_before': canonicalBefore?.data,
        'mapping_request_body': request.body,
        'canonical_song_id': canonicalId,
      },
    );

    // Preserve every outstanding operation on either song independently.
    // Only the original mapping CREATE is excluded.
    for (final row in pending) {
      final target = row.read<String>('entity_id');
      if (row.read<String>('entity_type') != 'SONG' ||
          (target != sourceId && target != canonicalId)) {
        continue;
      }
      final opId = row.read<String>('op_id');
      final intentId = await intent(
        key: 'song-mutation:$opId',
        kind: 'SONG_MUTATION',
        entity: 'SONG',
        entityId: target,
        originOpId: opId,
        evidence: {'version': 1, 'mutation_before': row.data},
      );
      await hold(row, intentId);
    }

    Map<String, Object?>? object(String? text) =>
        text == null ? null : jsonDecode(text) as Map<String, Object?>;

    bool related(String? text) {
      final id = object(text)?['song_id'];
      return id == sourceId;
    }

    for (final row in references) {
      final entity = row.read<String>('entity_type');
      final entityId = row.read<String>('entity_id');
      final mutations = referenceMutations['$entity:$entityId'] ?? <QueryRow>[];
      final localJson = row.readNullable<String>('local_payload');
      final serverJson = row.readNullable<String>('server_payload');

      // Includes PATCH payloads omitting song_id and frozen requests whose
      // local draft has since selected null or another song.
      final isRelated =
          related(localJson) ||
          related(serverJson) ||
          mutations.any(
            (m) =>
                related(m.read<String>('payload')) ||
                related(m.readNullable<String>('base_payload')),
          );
      if (!isRelated) continue;

      final intentId = await intent(
        key: 'reference:$entity:$entityId',
        kind: 'REFERENCE_RELINK',
        entity: entity,
        entityId: entityId,
        originOpId: null,
        evidence: {
          'version': 1,
          'metadata_before': row.data,
          'mutations_before': mutations.map((m) => m.data).toList(),
          'canonical_song_id': canonicalId,
        },
      );

      // Conservatively hold every outstanding operation on this related
      // entity. Do not modify queue state, frozen wire, budgets or payloads.
      for (final mutation in mutations) {
        await hold(mutation, intentId);
      }

      final local = object(localJson);
      if (row.read<int>('tombstone') == 0 &&
          local != null &&
          local['song_id'] == sourceId) {
        await _database.customStatement(
          '''
            UPDATE metadata_copies SET local_payload=?,updated_at=?
            WHERE entity_type=? AND entity_id=?
          ''',
          [
            canonicalJson({...local, 'song_id': canonicalId}),
            now,
            entity,
            entityId,
          ],
        );
      }
    }

    // A conditional acknowledgement of the actual frozen CREATE only.
    await _database.customStatement(
      '''
        UPDATE local_mutations
        SET queue_state='ACKED',server_response=?,updated_at=?
        WHERE op_id=? AND queue_state='SENDING' AND attempt_count=?
      ''',
      [receipt.envelopeBody, now, mutation.opId, request.attempt],
    );
    final changed = await _database
        .customSelect('SELECT changes() AS affected')
        .getSingle();
    if (changed.read<int>('affected') != 1) {
      throw StateError('Canonical mapping attempt changed before ACK');
    }

    await _retry.finish(mutation.opId);
    await materializeCanonicalReferences(_database, now);
    requireActive();
    return true;
  }

  Future<bool> acknowledgeMutation(
    MutationRequest request,
    Map<String, Object?> snapshot,
  ) => _run(
    () => _database.transaction(() async {
      final m = request.mutation;
      if (snapshot['id'] != m.entityId ||
          snapshot['revision'] is! int ||
          (snapshot['revision'] as int) <= m.baseRevision) {
        throw ArgumentError(
          'Response identity/revision is not an acknowledgement',
        );
      }
      _validatePayloadOwner(canonicalJson(snapshot));
      if (!await _ownsAttempt(request)) return false;
      final current = await _database
          .customSelect(
            'SELECT server_revision,tombstone FROM metadata_copies WHERE entity_type=? AND entity_id=?',
            variables: [Variable(m.entity.code), Variable(m.entityId)],
          )
          .getSingle();
      // A replay receipt acknowledges this operation even when a later pull
      // has already advanced/deleted the entity. Never rewind that newer copy.
      final preserveCurrent =
          current.read<int>('tombstone') == 1 ||
          current.read<int>('server_revision') > (snapshot['revision'] as int);
      final eligibility = await readMappingEligibility(_database);
      final resolved = {
        for (final op in eligibility.superseded)
          if (!eligibility.blocked.contains(op)) op,
      };
      final later = await _database
          .customSelect(
            "SELECT op_id FROM local_mutations WHERE entity_type=? AND entity_id=? AND op_id<>? AND queue_state<>'ACKED'",
            variables: [
              Variable(m.entity.code),
              Variable(m.entityId),
              Variable(m.opId),
            ],
          )
          .get();
      final payload = canonicalJson(snapshot);
      // Accept the receipt without overwriting a mapping-held local draft.
      if (!preserveCurrent) {
        await _database.customStatement(
          '''
      UPDATE metadata_copies
      SET server_revision=?,server_payload=?,
          local_payload=CASE
            WHEN ? OR EXISTS(
              SELECT 1 FROM mutation_mapping_holds
              WHERE op_id=? AND released_at IS NULL
            )
            THEN local_payload ELSE ?
          END,
          updated_at=?
      WHERE entity_type=? AND entity_id=?
    ''',
          [
            snapshot['revision'],
            payload,
            (later.any(
                      (row) => !resolved.contains(row.read<String>('op_id')),
                    ) ||
                    await canonicalKeepsDraft(_database, m.opId))
                ? 1
                : 0,
            m.opId,
            payload,
            DateTime.now().toUtc().millisecondsSinceEpoch,
            m.entity.code,
            m.entityId,
          ],
        );
      }
      await _database.customStatement(
        "UPDATE local_mutations SET queue_state='ACKED',server_response=?,updated_at=? WHERE op_id=? AND queue_state='SENDING' AND attempt_count=?",
        [
          payload,
          DateTime.now().toUtc().millisecondsSinceEpoch,
          m.opId,
          request.attempt,
        ],
      );
      await _retry.finish(m.opId);
      await finishCanonicalChoices(
        _database,
        await readMappingEligibility(_database),
        _retry.nowMs,
      );
      requireActive();
      return true;
    }),
  );

  Future<bool> deferMutation(
    MutationRequest request,
    String state,
    String reason, {
    int? status,
    Map<String, Object?>? serverSnapshot,
  }) => _run(
    () => _database.transaction(() async {
      if (!{'RETRY', 'CONFLICT', 'FAILED'}.contains(state)) {
        throw ArgumentError('Invalid result state');
      }
      if (!RegExp(r'^[A-Z0-9_]{1,64}$').hasMatch(reason)) {
        throw ArgumentError('Invalid result code');
      }
      if (!await _ownsAttempt(request)) return false;
      await _database.customStatement(
        "UPDATE local_mutations SET queue_state=?,server_response=?,updated_at=? WHERE op_id=? AND queue_state='SENDING' AND attempt_count=?",
        [
          state,
          canonicalJson({
            'code': reason,
            'status': ?status,
            'current': ?serverSnapshot,
          }),
          _retry.nowMs,
          request.mutation.opId,
          request.attempt,
        ],
      );
      await _retry.afterFailure(
        request.mutation.opId,
        state: state,
        code: reason,
        status: status,
      );
      requireActive();
      return true;
    }),
  );

  Future<bool> _ownsAttempt(MutationRequest request) async {
    final row = await _database
        .customSelect(
          '''SELECT m.queue_state,m.attempt_count,m.payload,m.entity_type,
            m.entity_id,m.operation,m.base_revision,
            w.contract_version,w.http_method,w.relative_path,w.body_json,w.wire_hash
          FROM local_mutations m
          JOIN mutation_wire_requests w ON w.op_id=m.op_id
          WHERE m.op_id=?''',
          variables: [Variable(request.mutation.opId)],
        )
        .getSingleOrNull();
    return row != null &&
        row.read<String>('queue_state') == 'SENDING' &&
        row.read<int>('attempt_count') == request.attempt &&
        row.read<String>('entity_type') == request.mutation.entity.code &&
        row.read<String>('entity_id') == request.mutation.entityId &&
        row.read<String>('operation') == request.mutation.operation.code &&
        row.read<int>('base_revision') == request.mutation.baseRevision &&
        row.read<String>('payload') == request.body &&
        row.read<String>('contract_version') == MutationRequest.contract &&
        row.read<String>('http_method') == request.method &&
        row.read<String>('relative_path') == request.path &&
        row.read<String>('body_json') == request.body &&
        row.read<String>('wire_hash') == request.hash;
  }

  Future<int?> readCursor() => _run(
    () async =>
        (await _database
                .customSelect(
                  'SELECT last_change_seq FROM sync_cursors WHERE singleton=1',
                )
                .getSingle())
            .readNullable<int>('last_change_seq'),
  );

  Future<void> saveSnapshotResume(Map<String, Object?> resume) {
    final json = canonicalJson(resume);
    return _run(
      () => _database.customStatement(
        'UPDATE sync_cursors SET snapshot_resume=?,updated_at=? WHERE singleton=1',
        [json, DateTime.now().toUtc().millisecondsSinceEpoch],
      ),
    );
  }

  /// Freeze a resync request without deleting the readable old baseline, drafts,
  /// queued commands or files. A stale receiver cannot invalidate a newer head.
  Future<bool> requestSnapshotRefresh({
    required ChangeFeedPosition expected,
    required String operationId,
  }) {
    if (UuidValue(operationId).value != operationId) {
      throw const FormatException('Noncanonical resync operation');
    }
    final encoded = canonicalJson({
      'version': 1,
      'op_id': operationId,
      'phase': 'REQUESTED',
      'token': null,
      'expires_at': null,
    });
    return _run(
      () => _database.transaction(() async {
        requireActive();
        final changed = await _database.customUpdate(
          '''
        UPDATE sync_cursors SET snapshot_resume=?,baseline_complete=0,updated_at=?
        WHERE singleton=1 AND user_id=? AND baseline_complete=1
          AND last_change_seq=? AND snapshot_resume IS NULL
          AND EXISTS(SELECT 1 FROM snapshot_baseline b JOIN snapshot_downloads h
            ON h.snapshot_token=b.snapshot_token
            WHERE b.singleton=1 AND b.user_id=? AND h.user_id=?
              AND b.snapshot_token=? AND h.state='APPLIED')
      ''',
          variables: [
            Variable(encoded),
            Variable(_manager._clock().toUtc().millisecondsSinceEpoch),
            Variable(userId),
            Variable(expected.cursor),
            Variable(userId),
            Variable(userId),
            Variable(expected.snapshotToken),
          ],
        );
        requireActive();
        return changed == 1;
      }),
    );
  }

  Future<bool> hasCompleteBaseline() => _run(
    () async =>
        (await _database
                .customSelect(
                  'SELECT baseline_complete FROM sync_cursors WHERE singleton=1',
                )
                .getSingle())
            .read<int>('baseline_complete') ==
        1,
  );

  Future<String?> readSnapshotResume() => _run(
    () async =>
        (await _database
                .customSelect(
                  'SELECT snapshot_resume FROM sync_cursors WHERE singleton=1',
                )
                .getSingle())
            .readNullable<String>('snapshot_resume'),
  );

  /// Persist the request before sending it, or advance only the observed request.
  /// A late HTTP response cannot replace a newer download (or an applied one).
  Future<bool> compareAndSetSnapshotResume({
    required String? expected,
    required Map<String, Object?>? replacement,
  }) {
    final encoded = replacement == null ? null : canonicalJson(replacement);
    return _run(
      () => _database.transaction(() async {
        requireActive();
        final changed = await _database.customUpdate(
          '''UPDATE sync_cursors SET snapshot_resume=?,updated_at=?
           WHERE singleton=1 AND snapshot_resume IS ?''',
          variables: [
            Variable<String>(encoded),
            Variable(_manager._clock().toUtc().millisecondsSinceEpoch),
            Variable<String>(expected),
          ],
        );
        requireActive();
        return changed == 1;
      }),
    );
  }

  Future<void> recordFileAndJournal({
    required String recordingId,
    required String operationId,
    required FilePresence state,
    required JournalPhase phase,
    required bool pending,
    String? checksum,
    int? sizeBytes,
    required Map<String, Object?> recovery,
  }) {
    final id = UuidValue(recordingId).value;
    final op = UuidValue(operationId).value;
    final json = canonicalJson(recovery);
    return _run(() async {
      final relative = pending ? _paths.pendingPath(id) : _paths.audioPath(id);
      if (pending &&
          (state == FilePresence.inputPending || state == FilePresence.saved)) {
        throw ArgumentError(
          'Completed recordings must use the final audio path',
        );
      }
      final file = await _paths.checkedFile(relative);
      int? verifiedAt;
      if (state == FilePresence.inputPending || state == FilePresence.saved) {
        if (!await file.exists() ||
            await file.length() != sizeBytes ||
            sizeBytes == null ||
            sizeBytes > 6291456 ||
            sizeBytes < 1) {
          throw StateError(
            'Completed local file is missing or has a different size',
          );
        }
        if ((await sha256.bind(file.openRead()).first).toString() != checksum) {
          throw StateError('Completed local file checksum mismatch');
        }
        verifiedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
      }
      await _database.transaction(() async {
        final journal = await _database
            .customSelect(
              'SELECT operation_id FROM recording_journals WHERE recording_id=?',
              variables: [Variable(id)],
            )
            .getSingleOrNull();
        if (journal != null && journal.read<String>('operation_id') != op) {
          throw StateError(
            'A recording journal belongs to its original operation',
          );
        }
        final old = await _database
            .customSelect(
              'SELECT local_state,sha256,size_bytes,cleanup_fence FROM local_recording_files WHERE recording_id=?',
              variables: [Variable(id)],
            )
            .getSingleOrNull();
        if ((old?.read<int>('cleanup_fence') ?? 0) > 0) {
          throw StateError('Local preservation fence is active');
        }
        if (old?.read<String>('local_state') == 'SAVED' &&
            (old?.readNullable<String>('sha256') != checksum ||
                old?.readNullable<int>('size_bytes') != sizeBytes)) {
          throw StateError(
            'Do not replace the content of a saved recording UUID',
          );
        }
        final now = DateTime.now().toUtc().millisecondsSinceEpoch;
        await _database.customStatement(
          '''INSERT INTO local_recording_files(recording_id,user_id,relative_path,sha256,size_bytes,local_state,verified_at,updated_at)
          VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(recording_id) DO UPDATE SET relative_path=excluded.relative_path,sha256=excluded.sha256,
          size_bytes=excluded.size_bytes,local_state=excluded.local_state,verified_at=excluded.verified_at,updated_at=excluded.updated_at''',
          [
            id,
            userId,
            relative,
            checksum,
            sizeBytes,
            state.code,
            verifiedAt,
            now,
          ],
        );
        await _database.customStatement(
          '''INSERT INTO recording_journals(recording_id,user_id,operation_id,pending_path,final_path,phase,recovery_payload,updated_at)
          VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(recording_id) DO UPDATE SET phase=excluded.phase,recovery_payload=excluded.recovery_payload,
          revision=recording_journals.revision+1,updated_at=excluded.updated_at''',
          [
            id,
            userId,
            op,
            _paths.pendingPath(id),
            _paths.audioPath(id),
            phase.code,
            json,
            now,
          ],
        );
      });
    });
  }

  Future<Uint8List> readLocalAudio(String recordingId) =>
      _run(() => _readLocalAudio(recordingId));

  Future<Uint8List> _readLocalAudio(String recordingId) async {
    final id = UuidValue(recordingId).value;
    final row = await _database
        .customSelect(
          'SELECT relative_path,sha256,size_bytes,local_state FROM local_recording_files WHERE recording_id=?',
          variables: [Variable(id)],
        )
        .getSingleOrNull();
    if (row == null ||
        !['INPUT_PENDING', 'SAVED'].contains(row.read<String>('local_state'))) {
      throw StateError('There is no verified readable local file');
    }
    final path = row.read<String>('relative_path');
    if (path != _paths.audioPath(id)) {
      throw StateError('Pending files are not playable');
    }
    final file = await _paths.checkedFile(path);
    final size = await file.length();
    if (size < 1 || size > 6291456 || size != row.read<int>('size_bytes')) {
      throw StateError('Local file size changed');
    }
    final bytes = await file.readAsBytes();
    if (sha256.convert(bytes).toString() != row.read<String>('sha256')) {
      throw StateError('Local file checksum changed');
    }
    return bytes;
  }

  /// Current disk bytes, never a historical device report, prove preservation.
  Future<bool> verifyPreservedAudio(
    String owner,
    String recordingId,
    String checksum,
    int size,
  ) async {
    requireActive();
    if (UuidValue(owner).value != userId ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum) ||
        size < 1 ||
        size > 6291456) {
      throw ArgumentError('Invalid preservation identity');
    }
    try {
      final bytes = await readLocalAudio(recordingId);
      requireActive();
      return bytes.length == size &&
          sha256.convert(bytes).toString() == checksum;
    } on FileSystemException {
      requireActive();
      return false;
    } on StateError {
      requireActive();
      return false;
    }
  }

  /// Persist a verified download without replacing an existing different local original.
  Future<void> preserveDownloadedAudio(
    String owner,
    String recordingId,
    String checksum,
    int size,
    Uint8List data,
  ) => _run(() async {
    final id = UuidValue(recordingId).value;
    if (UuidValue(owner).value != userId ||
        size < 1 ||
        size > 6291456 ||
        data.length != size ||
        sha256.convert(data).toString() != checksum) {
      throw const FormatException('Downloaded preservation identity mismatch');
    }
    final old = await _database
        .customSelect(
          'SELECT sha256,size_bytes,local_state,cleanup_fence FROM local_recording_files WHERE recording_id=?',
          variables: [Variable(id)],
        )
        .getSingleOrNull();
    if (old != null &&
        (old.read<int>('cleanup_fence') > 0 ||
            old.readNullable<String>('sha256') != checksum ||
            old.readNullable<int>('size_bytes') != size)) {
      throw StateError('Existing local original must be preserved');
    }
    final file = await _paths.checkedFile(_paths.audioPath(id));
    if (await file.exists()) {
      if (await file.length() != size ||
          (await sha256.bind(file.openRead()).first).toString() != checksum) {
        throw StateError(
          'Existing local original differs from the server object',
        );
      }
    } else {
      final temp = await _paths.checkedFile(
        _paths.pendingPath(UuidValue.random().value),
      );
      try {
        await temp.writeAsBytes(data, flush: true);
        requireActive();
        final target = await _paths.checkedFile(_paths.audioPath(id));
        if (await target.exists()) {
          throw StateError('Local original appeared during download');
        }
        await temp.rename(target.path);
      } finally {
        if (await temp.exists()) await temp.delete();
      }
    }
    requireActive();
    if (await file.length() != size ||
        (await sha256.bind(file.openRead()).first).toString() != checksum) {
      throw StateError('Persistent preservation check failed');
    }
    requireActive();
    final now = _manager._clock().toUtc().millisecondsSinceEpoch;
    await _database.customStatement(
      """INSERT INTO local_recording_files(recording_id,user_id,relative_path,sha256,size_bytes,local_state,verified_at,updated_at)
      VALUES(?,?,?,?,?,'SAVED',?,?) ON CONFLICT(recording_id) DO UPDATE SET relative_path=excluded.relative_path,
      local_state='SAVED',verified_at=excluded.verified_at,updated_at=excluded.updated_at""",
      [id, userId, _paths.audioPath(id), checksum, size, now, now],
    );
  });

  /// Establish the durable fence before any confirmation request leaves the device.
  Future<void> beginLocalCleanupFence({
    required String token,
    required String owner,
    required String recording,
    required String generation,
    required String checksum,
    required int size,
    required int revision,
    required DateTime expires,
  }) => _run(() async {
    final key = UuidValue(token).value,
        id = UuidValue(recording).value,
        gen = UuidValue(generation).value;
    final now = _manager._clock().toUtc().millisecondsSinceEpoch;
    if (UuidValue(owner).value != userId ||
        revision < 1 ||
        !expires.toUtc().isAfter(_manager._clock().toUtc()) ||
        expires.toUtc().millisecondsSinceEpoch > now + 900000) {
      throw StateError('Invalid or expired cleanup confirmation');
    }
    final bytes = await _readLocalAudio(id);
    requireActive();
    if (bytes.length != size || sha256.convert(bytes).toString() != checksum) {
      throw StateError('No matching persistent local copy');
    }
    await _database.transaction(() async {
      final rows = await _database
          .customSelect(
            "SELECT * FROM local_cleanup_confirmations WHERE recording_id=? AND state IN ('PREPARING','CONFIRMED')",
            variables: [Variable(id)],
          )
          .get();
      if (rows.isNotEmpty) {
        final row = rows.single;
        if (row.read<String>('token') == key &&
            row.read<String>('generation') == gen &&
            row.read<String>('sha256') == checksum &&
            row.read<int>('cloud_revision') == revision &&
            row.read<int>('expires_at') ==
                expires.toUtc().millisecondsSinceEpoch) {
          return;
        }
        throw StateError('A cleanup result is still unresolved');
      }
      await _database.customStatement(
        "INSERT INTO local_cleanup_confirmations(token,user_id,recording_id,generation,sha256,cloud_revision,expires_at,state,created_at,updated_at) VALUES(?,?,?,?,?,?,?,'PREPARING',?,?)",
        [
          key,
          userId,
          id,
          gen,
          checksum,
          revision,
          expires.toUtc().millisecondsSinceEpoch,
          now,
          now,
        ],
      );
      await _database.customStatement(
        'UPDATE local_recording_files SET cleanup_fence=cleanup_fence+1,updated_at=? WHERE recording_id=? AND user_id=?',
        [now, id, userId],
      );
    });
  });
  Future<List<Map<String, Object?>>> pendingLocalCleanup() => _run(
    () async =>
        (await _database
                .customSelect(
                  "SELECT c.*,f.size_bytes FROM local_cleanup_confirmations c JOIN local_recording_files f ON f.user_id=c.user_id AND f.recording_id=c.recording_id WHERE c.user_id=? AND c.state IN ('PREPARING','CONFIRMED') ORDER BY c.created_at,c.token",
                  variables: [Variable(userId)],
                )
                .get())
            .map((r) => Map<String, Object?>.from(r.data))
            .toList(growable: false),
  );

  Future<void> markLocalCleanupConfirmed(String token) => _run(() async {
    final key = UuidValue(token).value;
    final row = await _database
        .customSelect(
          'SELECT state FROM local_cleanup_confirmations WHERE token=? AND user_id=?',
          variables: [Variable(key), Variable(userId)],
        )
        .getSingleOrNull();
    if (row == null ||
        !['PREPARING', 'CONFIRMED'].contains(row.read<String>('state'))) {
      throw StateError('Local cleanup token is not active');
    }
    await _database.customStatement(
      "UPDATE local_cleanup_confirmations SET state='CONFIRMED',updated_at=? WHERE token=? AND user_id=?",
      [_manager._clock().toUtc().millisecondsSinceEpoch, key, userId],
    );
  });

  /// The caller must supply the authenticated server's terminal result, never infer it from expiry.
  Future<void> finishLocalCleanupFence(
    String token,
    String generation,
    String state,
  ) => _run(() async {
    if (!['SUCCEEDED', 'CANCELLED', 'EXPIRED'].contains(state)) {
      throw StateError('Cleanup result is not terminal');
    }
    final key = UuidValue(token).value, gen = UuidValue(generation).value;
    await _database.transaction(() async {
      final row = await _database
          .customSelect(
            'SELECT recording_id,generation,state FROM local_cleanup_confirmations WHERE token=? AND user_id=?',
            variables: [Variable(key), Variable(userId)],
          )
          .getSingleOrNull();
      if (row == null || row.read<String>('generation') != gen) {
        throw StateError('Cleanup result identity mismatch');
      }
      if ([
        'SUCCEEDED',
        'CANCELLED',
        'EXPIRED',
      ].contains(row.read<String>('state'))) {
        if (row.read<String>('state') != state) {
          throw StateError('Terminal cleanup result changed');
        }
        return;
      }
      final now = _manager._clock().toUtc().millisecondsSinceEpoch;
      await _database.customStatement(
        'UPDATE local_cleanup_confirmations SET state=?,updated_at=? WHERE token=? AND user_id=?',
        [state, now, key, userId],
      );
      final changed = await _database.customUpdate(
        'UPDATE local_recording_files SET cleanup_fence=cleanup_fence-1,updated_at=? WHERE user_id=? AND recording_id=? AND cleanup_fence>0',
        variables: [
          Variable(now),
          Variable(userId),
          Variable(row.read<String>('recording_id')),
        ],
      );
      if (changed != 1) throw StateError('Local cleanup fence was lost');
    });
  });

  Future<String?> readJournal(String recordingId) => _run(
    () async =>
        (await _database
                .customSelect(
                  'SELECT recovery_payload FROM recording_journals WHERE recording_id=?',
                  variables: [Variable(UuidValue(recordingId).value)],
                )
                .getSingleOrNull())
            ?.read<String>('recovery_payload'),
  );

  Future<void> createImportJob({
    required String jobId,
    required String sourceUserId,
    required String manifestHash,
    required List<String> resourceIds,
  }) {
    final id = UuidValue(jobId).value;
    final source = UuidValue(sourceUserId).value;
    final resources = resourceIds
        .map((item) => UuidValue(item).value)
        .toList(growable: false);
    return _run(() async {
      if (source != userId) {
        throw ArgumentError('Backup account does not match the active account');
      }
      await _paths.checkedFile(_paths.importPath(id));
      await _database.transaction(() async {
        final now = DateTime.now().toUtc().millisecondsSinceEpoch;
        await _database.customStatement(
          'INSERT INTO import_jobs(import_job_id,user_id,source_user_id,archive_path,manifest_hash,total_items,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?)',
          [
            id,
            userId,
            source,
            _paths.importPath(id),
            manifestHash,
            resources.length,
            now,
            now,
          ],
        );
        for (var index = 0; index < resources.length; index++) {
          await _database.customStatement(
            'INSERT INTO import_items(import_job_id,ordinal,resource_id,updated_at) VALUES(?,?,?,?)',
            [id, index + 1, resources[index], now],
          );
        }
      });
    });
  }

  Future<List<String>> pendingImportJobs() => _run(
    () async =>
        (await _database
                .customSelect(
                  "SELECT import_job_id FROM import_jobs WHERE status<>'COMPLETED' ORDER BY created_at,import_job_id",
                )
                .get())
            .map((row) => row.read<String>('import_job_id'))
            .toList(growable: false),
  );
}
