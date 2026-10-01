import 'dart:convert';

import 'package:drift/drift.dart';

import '../sync/change_feed_response.dart';
import '../sync/change_payload_validation.dart';
import '../sync/permanent_deletion.dart';
import '../sync/recording_change_projection.dart';
import 'account_database.dart';
import 'local_models.dart';
import 'snapshot_download_store.dart';
import 'snapshot_recording_projection.dart';

final class ChangeFeedPosition {
  const ChangeFeedPosition(this.snapshotToken, this.cursor);
  final String snapshotToken;
  final int cursor;
  @override
  String toString() => 'ChangeFeedPosition[REDACTED]';
}

/// AccountStore serializes access. No network, file removal or queue mutation.
/// The applied snapshot token fences replacement even at the same cursor.
final class ChangeFeedStore {
  ChangeFeedStore(this.db, {required this.requireActive, required this.clock});
  final AccountDatabase db;
  final void Function() requireActive;
  final DateTime Function() clock;

  Future<ChangeFeedPosition?> position() => db.transaction(() async {
    requireActive();
    final row = await db
        .customSelect(
          '''
      SELECT c.last_change_seq,b.snapshot_token FROM sync_cursors c
      JOIN snapshot_baseline b ON b.singleton=c.singleton
      JOIN snapshot_downloads h ON h.snapshot_token=b.snapshot_token
      WHERE c.singleton=1 AND c.baseline_complete=1 AND c.user_id=?
        AND b.user_id=? AND h.user_id=? AND h.state='APPLIED'
    ''',
          variables: [
            Variable(db.userId),
            Variable(db.userId),
            Variable(db.userId),
          ],
        )
        .getSingleOrNull();
    requireActive();
    return row == null
        ? null
        : ChangeFeedPosition(
            row.read<String>('snapshot_token'),
            row.read<int>('last_change_seq'),
          );
  });

  Future<void> apply(
    ChangeFeedPage page, {
    required String snapshotToken,
  }) => db.transaction(() async {
    requireActive();
    if (page.owner != db.userId) throw StateError('Change feed owner changed');
    final position = await db
        .customSelect(
          '''
          SELECT c.last_change_seq,c.baseline_complete,b.snapshot_token
          FROM sync_cursors c JOIN snapshot_baseline b ON b.singleton=c.singleton
          JOIN snapshot_downloads h ON h.snapshot_token=b.snapshot_token
          WHERE c.singleton=1 AND c.user_id=? AND b.user_id=?
            AND h.user_id=? AND h.state='APPLIED'
        ''',
          variables: [
            Variable(db.userId),
            Variable(db.userId),
            Variable(db.userId),
          ],
        )
        .getSingleOrNull();
    if (position == null ||
        position.read<int>('baseline_complete') != 1 ||
        position.read<int>('last_change_seq') != page.afterSequence ||
        position.read<String>('snapshot_token') != snapshotToken) {
      throw StateError('Change feed baseline changed');
    }
    final permanent = await _initialDeletions(snapshotToken);
    for (final entry in page.entries) {
      requireActive();
      // Relation rows and cloud assets have different revision/generation
      // contracts. Refuse the whole page until their adapters exist.
      if (!{
        LocalEntity.song,
        LocalEntity.recording,
        LocalEntity.playlist,
        LocalEntity.tag,
        LocalEntity.recordingCondition,
      }.contains(entry.entity)) {
        throw const FormatException('Change entity adapter is not implemented');
      }
      final payload = entry.payload;
      if (!entry.deleted) validateChangePayload(entry.entity, payload);
      if (!entry.deleted &&
          (payload['id'] != entry.id ||
              payload['revision'] != entry.revision)) {
        throw const FormatException('Change payload is not an entity snapshot');
      }
      final code = entry.entity.code;
      final current = await db
          .customSelect(
            '''
            SELECT server_revision,server_payload,tombstone FROM metadata_copies
            WHERE entity_type=? AND entity_id=?
          ''',
            variables: [Variable(code), Variable(entry.id)],
          )
          .getSingleOrNull();
      final markerRevision = permanent['$code:${entry.id}'];
      if (markerRevision != null) {
        if (entry.revision > markerRevision) {
          throw StateError('Change conflicts with permanent deletion revision');
        }
        continue;
      }
      if (current?.read<int>('tombstone') == 1) continue;
      final baseline = await db
          .customSelect(
            '''
            SELECT json_extract(canonical_payload,'\$.revision') AS revision
            FROM snapshot_download_rows WHERE snapshot_token=? AND user_id=?
              AND entity=? AND resource_id=?
          ''',
            variables: [
              Variable(snapshotToken),
              Variable(db.userId),
              Variable(code),
              Variable(entry.id),
            ],
          )
          .get();
      if (baseline.length > 1) throw StateError('Ambiguous entity baseline');
      final baselineRevision = baseline.isEmpty
          ? 0
          : baseline.single.readNullable<int>('revision') ?? 0;
      final currentRevision = current?.read<int>('server_revision') ?? 0;
      if (baselineRevision > entry.revision ||
          currentRevision > entry.revision) {
        continue;
      }
      final previousPayload = current?.readNullable<String>('server_payload');
      Map<String, dynamic>? previous = previousPayload == null
          ? null
          : jsonDecode(previousPayload) as Map<String, dynamic>;
      if (entry.entity == LocalEntity.recording &&
          !entry.deleted &&
          baseline.isNotEmpty) {
        final bundle = await SnapshotDownloadStore(
          db,
          requireActive: requireActive,
          clock: clock,
        ).recordingBaseline(entry.id, expectedToken: snapshotToken);
        if (bundle == null) throw StateError('Recording baseline changed');
        final initial = projectSnapshotRecording(bundle);
        previous = previous == null || currentRevision < baselineRevision
            ? initial
            : projectRecordingChange(initial, previous);
      }
      final projected = entry.entity == LocalEntity.recording && !entry.deleted
          ? projectRecordingChange(previous, payload)
          : payload;
      if (!entry.deleted) validateChangePayload(entry.entity, projected);
      final encoded = canonicalJson(projected);
      if (baselineRevision == entry.revision &&
          baselineRevision >= currentRevision) {
        if (entry.deleted) {
          throw StateError('Deletion did not advance baseline revision');
        }
        continue;
      }
      if (currentRevision == entry.revision) {
        final previous = canonicalJson(
          jsonDecode(current!.read<String>('server_payload'))
              as Map<String, dynamic>,
        );
        if (previous != encoded || entry.deleted) {
          throw StateError('Conflicting change at the same revision');
        }
        continue;
      }
      await _writeCopy(code, entry.id, entry.revision, encoded, entry.deleted);
    }
    await db.customStatement(
      '''
          UPDATE sync_cursors SET last_change_seq=?,updated_at=? WHERE singleton=1
        ''',
      [page.nextSequence, clock().toUtc().millisecondsSinceEpoch],
    );
    // A logout while SQLite awaited must roll back both entities and cursor.
    requireActive();
  });

  /// A page may be empty: baseline UUID tombstones must still hide stale
  /// local copies before its cursor is accepted. All writes share apply's TX.
  Future<Map<String, int>> _initialDeletions(String snapshotToken) async {
    final rows = await db
        .customSelect(
          "SELECT canonical_payload FROM snapshot_download_rows WHERE snapshot_token=? AND user_id=? AND entity='DELETION_LEDGER' ORDER BY ordinal",
          variables: [Variable(snapshotToken), Variable(db.userId)],
        )
        .get();
    final result = <String, int>{};
    for (final row in rows) {
      requireActive();
      final raw = jsonDecode(row.read<String>('canonical_payload'));
      if (raw is! Map<String, dynamic> ||
          raw['entity_type'] is! String ||
          raw['entity_id'] is! String) {
        throw const FormatException('Invalid permanent deletion identity');
      }
      final code = raw['entity_type'] as String,
          id = raw['entity_id'] as String;
      final marker = permanentDeletionPayload(
        raw,
        owner: db.userId,
        entity: code,
        id: id,
      );
      final revision = marker['revision'] as int, key = '$code:$id';
      if (result.containsKey(key))
        throw StateError('Ambiguous permanent deletion');
      result[key] = revision;
      final current = await db
          .customSelect(
            'SELECT server_revision FROM metadata_copies WHERE entity_type=? AND entity_id=?',
            variables: [Variable(code), Variable(id)],
          )
          .getSingleOrNull();
      if ((current?.read<int>('server_revision') ?? 0) > revision) {
        throw StateError(
          'Cached state conflicts with permanent deletion revision',
        );
      }
      await _writeCopy(code, id, revision, canonicalJson(marker), true);
    }
    return result;
  }

  Future<void> _writeCopy(
    String code,
    String id,
    int revision,
    String encoded,
    bool deleted,
  ) async {
    await db.customStatement(
      '''
            INSERT INTO metadata_copies(user_id,entity_type,entity_id,server_revision,
              server_payload,local_payload,tombstone,updated_at)
            VALUES(?,?,?,?,?,?,?,?)
            ON CONFLICT(entity_type,entity_id) DO UPDATE SET
              server_revision=excluded.server_revision,server_payload=excluded.server_payload,
              local_payload=CASE WHEN EXISTS(
                SELECT 1 FROM local_mutations m WHERE m.entity_type=excluded.entity_type
                  AND m.entity_id=excluded.entity_id AND m.queue_state<>'ACKED'
              ) OR EXISTS(
                SELECT 1 FROM mutation_mapping_holds h JOIN local_mutations m ON m.op_id=h.op_id
                WHERE m.entity_type=excluded.entity_type AND m.entity_id=excluded.entity_id
                  AND h.released_at IS NULL
              ) OR (metadata_copies.local_payload IS NOT NULL
                AND metadata_copies.local_payload IS NOT metadata_copies.server_payload)
              THEN metadata_copies.local_payload ELSE excluded.local_payload END,
              tombstone=excluded.tombstone,updated_at=excluded.updated_at
          ''',
      [
        db.userId,
        code,
        id,
        revision,
        encoded,
        deleted ? null : encoded,
        deleted ? 1 : 0,
        clock().toUtc().millisecondsSinceEpoch,
      ],
    );
  }
}
