import 'dart:convert';

import 'package:drift/drift.dart';

import '../sync/change_feed_response.dart';
import '../sync/change_payload_validation.dart';
import '../sync/recording_asset_projection.dart';
import '../sync/recording_change_projection.dart';
import 'account_database.dart';
import 'asset_deletion_store.dart';
import 'local_models.dart';
import 'playlist_change_store.dart';
import 'snapshot_business_store.dart';
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
    final assetDeletions = AssetDeletionStore(db, requireActive, clock);
    final business = SnapshotBusinessStore(
      db,
      requireActive: requireActive,
      clock: clock,
    );
    // Also covers an app upgrade whose cursor already passed the baseline.
    final permanent = await business.apply(snapshotToken, assetDeletions);
    for (final entry in page.entries) {
      requireActive();
      final markerRevision = permanent['${entry.entity.code}:${entry.id}'];
      if (markerRevision != null) {
        if (entry.revision > markerRevision) {
          throw StateError('Change conflicts with permanent deletion revision');
        }
        // Validated account-lifetime deletion wins over an older ordinary UUID
        // row, including a legacy body no longer editable by this app version.
        continue;
      }
      if (entry.entity == LocalEntity.playlistItem ||
          entry.entity == LocalEntity.playlist &&
              entry.payload.containsKey('items')) {
        await PlaylistChangeStore(db, requireActive, business.writeCopy).apply(entry);
        continue;
      }
      // Only explicitly supported business adapters can advance the cursor.
      // Assets use cloud_revision; playlist operations were handled above.
      if (!{
        LocalEntity.song,
        LocalEntity.recording,
        LocalEntity.playlist,
        LocalEntity.tag,
        LocalEntity.recordingCondition,
        LocalEntity.recordingAsset,
      }.contains(entry.entity)) {
        throw const FormatException('Change entity adapter is not implemented');
      }
      final asset = entry.entity == LocalEntity.recordingAsset;
      // A generation deletion never tombstones the recording/asset UUID.
      if (asset && entry.deleted) {
        final proof = assetDeletions.parse(
          entry.payload,
          recordingId: entry.id,
          revision: entry.revision,
        );
        await assetDeletions.remember(proof);
        await business.applyAssetDeletion(entry.id, assetDeletions);
        continue;
      }
      final payload = asset
          ? assetDeletions.suppress(
              projectRecordingAsset(
                entry.payload,
                owner: db.userId,
                recordingId: entry.id,
                revision: entry.revision,
              ),
            )
          : entry.payload;
      if (!entry.deleted && !asset) {
        validateChangePayload(entry.entity, payload);
      }
      if (!entry.deleted &&
          (payload['id'] != entry.id ||
              (!asset && payload['revision'] != entry.revision))) {
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
      if (current?.read<int>('tombstone') == 1) continue;
      final baseline = await db
          .customSelect(
            '''
            SELECT CASE WHEN entity='RECORDING_ASSET'
              THEN json_extract(canonical_payload,'\$.cloud_revision')
              ELSE json_extract(canonical_payload,'\$.revision') END AS revision
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
      if (!entry.deleted && !asset) {
        validateChangePayload(entry.entity, projected);
      }
      final encoded = canonicalJson(projected);
      if (asset) {
        validateAssetTransition(previous, projected);
        if (currentRevision == entry.revision &&
            canonicalJson(previous!) != encoded) {
          throw StateError('Conflicting asset at the same cloud revision');
        }
      }
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
      await business.writeCopy(
        code,
        entry.id,
        asset ? projected['revision'] as int : entry.revision,
        encoded,
        entry.deleted ||
            entry.entity == LocalEntity.playlist &&
                projected['deleted_at'] != null,
      );
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

}
