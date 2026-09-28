import 'dart:math';
import 'dart:typed_data';

import '../database/account_store.dart';
import '../database/local_models.dart';
import '../domain/identifiers.dart';
import 'dependency_planner.dart';

/// Prepare once, retain the command, then save. A failed save is retried with
/// the same command, never by calling prepare again. Network sending is P10-02.
final class LocalRepository {
  LocalRepository(this._store, {String Function()? newId})
    : _newId = newId ?? _uuid;

  final AccountStore _store;
  final String Function() _newId;

  String get userId => _store.userId;

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

  Future<MetadataCopy?> read(LocalEntity entity, String id) =>
      _store.readMetadata(entity, id);

  /// Includes failed/conflicted work so reopening the app cannot hide it.
  /// This is an inspection list, not the dependency-ordered network send queue.
  Future<List<QueuedMutation>> pending() => _store.pendingMutations();

  Future<DispatchPlan> planDispatch() async =>
      const DependencyPlanner().plan(await _store.dispatchSnapshot());

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
