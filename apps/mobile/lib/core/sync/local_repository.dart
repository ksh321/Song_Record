import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../features/auth/auth_session.dart';
import '../database/account_store.dart';
import '../database/local_models.dart';
import '../domain/identifiers.dart';
import '../files/recording_catalog.dart';
import '../files/recording_file_status.dart';
import 'canonical_conflict_plan.dart';
import 'conflict_resolution_plan.dart';
import 'conflict_review.dart';
import 'dependency_planner.dart';
import 'metadata_dispatcher.dart';
import 'mutation_transport.dart';

/// Prepare once, retain the command, then save. A failed save is retried with
/// the same command, never by calling prepare again. Network sending is P10-02.
final class LocalRepository
    implements ConflictActions, CanonicalConflictActions {
  LocalRepository(this._store, {String Function()? newId})
    : _newId = newId ?? _uuid;

  final AccountStore _store;
  final String Function() _newId;

  String get userId => _store.userId;
  Future<List<Map<String, dynamic>>> playlistItems(String id) =>
      _store.playlistItems(id);

  Future<void> importCompletedCapture({
    required String accountScope,
    required String recordingId,
    required Uint8List bytes,
    required Map<String, dynamic> fileSpec,
    required DateTime recordedAt,
    required String timezoneId,
    required int timezoneOffsetMinutes,
  }) => _store.importCompletedCapture(
    accountScope: accountScope,
    recordingId: recordingId,
    bytes: bytes,
    fileSpec: fileSpec,
    recordedAt: recordedAt,
    timezoneId: timezoneId,
    timezoneOffsetMinutes: timezoneOffsetMinutes,
  );
  Future<List<Map<String, dynamic>>> pendingRecordings() =>
      _store.readPendingRecordings();

  Future<void> selectPendingRecordingSong(String recordingId, String songId) =>
      _store.selectPendingRecordingSong(recordingId, songId);

  Future<List<Map<String, dynamic>>> selectableRecordingTags() =>
      _store.selectableRecordingTags();
  Future<void> preserveRecordingInput(String id, Map<String, Object?> input) =>
      _store.preserveRecordingInput(id, input);
  List<String> recordingSaveOperationIds() => List.generate(3, (_) => _newId());
  Future<void> saveRecordingInput(
    String id,
    Map<String, Object?> input,
    List<String> operationIds,
  ) => _store.saveRecordingInput(id, input, operationIds);

  Future<void> Function() prepareRecordingRelink(
    Map<String, Object?> expected,
    int revision,
    String? songId,
  ) {
    final snapshot =
        jsonDecode(canonicalJson(expected)) as Map<String, dynamic>;
    final command = LocalEdit(
      opId: _newId(),
      entity: LocalEntity.recording,
      entityId: snapshot['id'] as String,
      operation: LocalOperation.patch,
      baseRevision: revision,
      draft: {
        ...snapshot,
        'song_id': songId,
        'link_revision':
            (snapshot['link_revision'] as int? ?? 1) +
            (songId == snapshot['song_id'] ? 0 : 1),
      },
      changes: {'song_id': songId, 'base_revision': revision},
    );
    return () => _store.saveRecordingRelink(command, snapshot);
  }

  Future<List<Map<String, dynamic>>> savedRecordings() =>
      _store.savedRecordings();
  List<String> recordingEditOperationIds() => List.generate(2, (_) => _newId());
  Future<void> saveRecordingDetails(
    String id,
    Map<String, Object?> fields,
    List<String> operationIds,
    Map<String, Object?> expected,
    int revision,
  ) =>
      _store.saveRecordingDetails(id, fields, operationIds, expected, revision);

  Future<List<Map<String, dynamic>>> activePlaylists() =>
      _store.activePlaylists();

  Stream<List<Map<String, dynamic>>> watchActiveSongs() =>
      _store.watchActiveSongs();

  Stream<Map<String, dynamic>> watchSongDetail(String songId) =>
      _store.watchSongDetail(songId);

  Future<RecordingCatalog> recordingCatalog() async =>
      RecordingCatalog.fromSnapshot(
        '${_store.environment.name}:$userId:${identityHashCode(_store)}',
        userId,
        await _store.recordingCatalogSnapshot(),
      );

  Future<RecordingFileStatus> recordingFileStatus(String id) =>
      RecordingFileStatuses(_store).read(id);

  LocalEdit prepareCreate({
    required LocalEntity entity,
    String? entityId,
    required Map<String, Object?> draft,
    required Map<String, Object?> changes,
  }) {
    final id = UuidValue(entityId ?? _newId()).value;
    _checkIdentity(draft, id);
    _checkIdentity(changes, id);
    if (changes.containsKey('base_revision')) {
      throw ArgumentError('A create request has no base_revision');
    }
    return LocalEdit(
      opId: _newId(),
      entity: entity,
      entityId: id,
      operation: LocalOperation.create,
      baseRevision: 0,
      draft: {...draft, 'id': id},
      changes: {...changes, 'id': id},
    );
  }

  /// draft is the complete intended local view; changes contains only the
  /// request fields. baseRevision is the last server revision, not a local edit
  /// counter. Zero means a local-only target awaiting CREATE acknowledgement;
  /// P10-02 must resolve that dependency before constructing a server PATCH.
  LocalEdit preparePatch({
    required LocalEntity entity,
    required String entityId,
    required int baseRevision,
    required Map<String, Object?> draft,
    required Map<String, Object?> changes,
  }) {
    if (baseRevision < 0) {
      throw ArgumentError('A local baseline cannot be negative');
    }
    final id = UuidValue(entityId).value;
    _checkIdentity(draft, id);
    _checkIdentity(changes, id);
    if (changes.containsKey('id') || changes.containsKey('base_revision')) {
      throw ArgumentError('Target and baseline must use the typed arguments');
    }
    if (changes.isEmpty) {
      throw ArgumentError('A patch must contain a change');
    }
    return LocalEdit(
      opId: _newId(),
      entity: entity,
      entityId: id,
      operation: LocalOperation.patch,
      baseRevision: baseRevision,
      draft: {...draft, 'id': id},
      changes: {...changes, 'base_revision': baseRevision},
    );
  }

  /// AccountStore validates the active lease and baseline, then commits the
  /// metadata copy and immutable queue entry in one SQLite transaction.
  Future<void> save(LocalEdit command) => _store.saveEdit(command);

  Future<void> saveCheckedEdit(
    LocalEdit command,
    Map<String, Object?> expected,
  ) => _store.saveEdit(
    command,
    expectedEffectivePayload: canonicalJson(expected),
  );

  Stream<List<Map<String, dynamic>>> watchUnlinkedRecordings() =>
      _store.watchUnlinkedRecordings();

  Future<void> saveRepresentative(
    LocalEdit command,
    Map<String, Object?> expected,
  ) => _store.saveEdit(
    command,
    expectedEffectivePayload: canonicalJson(expected),
    representativeSelection: true,
  );

  Future<MetadataCopy?> read(LocalEntity entity, String id) =>
      _store.readMetadata(entity, id);

  /// Includes failed/conflicted work so reopening the app cannot hide it.
  /// This is an inspection list, not the dependency-ordered network send queue.
  Future<List<QueuedMutation>> pending() => _store.pendingMutations();

  Future<List<QueuedMutation>> pendingWork() => _store.pendingWorkMutations();

  @override
  Future<List<CanonicalConflictReview>> canonicalCandidates() =>
      _store.canonicalCandidates();
  @override
  Future<CanonicalConflictReview> reviewCanonical(String intentId) =>
      _store.readCanonicalConflict(intentId);
  @override
  Future<void> resolveCanonical(
    CanonicalConflictReview review,
    ConflictChoice choice,
  ) => _store.resolveCanonicalConflict(review, choice, _newId());

  Future<int> unlinkedOfflineRecordingCount() =>
      _store.unlinkedOfflineRecordingCount();

  @override
  Future<ConflictReview> review(String opId) => _store.readConflictReview(opId);

  @override
  Future<void> resolve(
    ConflictReview review,
    Map<String, ConflictChoice> choices,
  ) {
    final plan = prepareConflictResolution(
      review.mutation,
      choices: choices,
      serverSnapshot: review.server,
      pendingReview: review.pendingReview,
    );
    return _store.resolveMetadataConflict(
      expected: review.mutation,
      expectedLocalJson: review.localJson,
      replacementOpId: plan.needsRequest ? _newId() : null,
      choices: choices,
      expectedServerJson: review.serverJson,
      expectedQueueEvidence: review.queueEvidence,
      pendingReview: review.pendingReview,
    );
  }

  Future<RetryStatus?> retryStatus(String opId) => _store.retryStatus(opId);

  Future<bool> retryMutation(String opId, {required int expectedAttempt}) =>
      _store.retryMutation(opId, expectedAttempt: expectedAttempt);

  Future<DateTime?> nextAutomaticRetryAt() => _store.nextAutomaticRetryAt();
  Future<DateTime?> nextDispatchAt() => _store.nextDispatchAt();

  Future<DispatchPlan> planDispatch() async =>
      const DependencyPlanner().plan(await _store.dispatchSnapshot());

  Future<int> dispatch({
    required MutationTransport transport,
    required Future<AuthSession> Function() session,
    int limit = 50,
    void Function()? onAuthenticationBlocked,
  }) => MetadataDispatcher(
    _store,
    transport,
    session,
  ).dispatch(limit: limit, onAuthenticationBlocked: onAuthenticationBlocked);

  static void _checkIdentity(Map<String, Object?> payload, String id) {
    if (payload.containsKey('user_id')) {
      throw ArgumentError('The active account supplies ownership');
    }
    if (payload.containsKey('id')) {
      final value = payload['id'];
      if (value is! String || UuidValue(value).value != id) {
        throw ArgumentError('Payload id differs from its target');
      }
    }
  }

  static String _uuid() {
    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    return UuidValue.fromBytes(bytes).value;
  }
}
