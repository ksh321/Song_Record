import 'dart:convert';

import 'package:drift/drift.dart';

import '../domain/identifiers.dart';
import '../sync/snapshot_response.dart';
import 'account_database.dart';
import 'local_models.dart' show canonicalJson;

final class SnapshotProgress {
  const SnapshotProgress(this.ordinal, this.cursor, this.finished);
  final int ordinal;
  final String? cursor;
  final bool finished;
  @override
  String toString() => 'SnapshotProgress[REDACTED]';
}

final class SnapshotDownloadState {
  SnapshotDownloadState(
    this.manifest,
    this.state,
    Map<String, SnapshotProgress> progress,
  ) : progress = Map.unmodifiable(progress);
  final SnapshotManifest manifest;
  final String state;
  final Map<String, SnapshotProgress> progress;
  @override
  String toString() => 'SnapshotDownloadState[REDACTED]';
}

final class SnapshotBaselineRecord {
  const SnapshotBaselineRecord(this.token, this.cursor, this.entry);
  final String token;
  final int cursor;
  final SnapshotEntry? entry;
  @override
  String toString() => 'SnapshotBaselineRecord[REDACTED]';
}

final class SnapshotBaselinePage {
  SnapshotBaselinePage(
    this.token,
    this.cursor,
    List<SnapshotEntry> entries,
    this.hasMore,
  ) : entries = List.unmodifiable(entries);
  final String token;
  final int cursor;
  final List<SnapshotEntry> entries;
  final bool hasMore;
  @override
  String toString() => 'SnapshotBaselinePage[REDACTED]';
}

final class SnapshotRecordingBaseline {
  SnapshotRecordingBaseline(
    this.token,
    this.cursor,
    this.recording,
    this.file,
    List<SnapshotEntry> tags,
  ) : tags = List.unmodifiable(tags);
  final String token;
  final int cursor;
  final SnapshotEntry? recording, file;
  final List<SnapshotEntry> tags;
  @override
  String toString() => 'SnapshotRecordingBaseline[REDACTED]';
}

/// Internal persistence service. AccountStore serializes calls and supplies the
/// live account fence, including the final check inside every transaction.
final class SnapshotDownloadStore {
  SnapshotDownloadStore(
    this.db, {
    required this.clock,
    required this.requireActive,
  });
  final AccountDatabase db;
  final DateTime Function() clock;
  final void Function() requireActive;
  void _check(bool condition) {
    if (!condition) throw StateError('Snapshot download state changed');
  }

  void _fence(SnapshotManifest manifest) {
    requireActive();
    _check(clock().isBefore(manifest.expiresAt));
  }

  String _token(String token) {
    _check(UuidValue(token).value == token);
    return token;
  }

  Future<void> begin(String token, String body) => db.transaction(() async {
    requireActive();
    _token(token);
    final manifest = SnapshotManifest.decode(
      body,
      expectedToken: token,
      now: clock(),
    );
    final canonical = canonicalJson(jsonDecode(body) as Map<String, dynamic>);
    final old = await db
        .customSelect(
          'SELECT manifest_json FROM snapshot_downloads WHERE snapshot_token=? AND user_id=?',
          variables: [Variable(token), Variable(db.userId)],
        )
        .getSingleOrNull();
    if (old != null) {
      _check(old.read<String>('manifest_json') == canonical);
      _fence(manifest);
      return;
    }
    await db.customStatement(
      'INSERT INTO snapshot_downloads(snapshot_token,user_id,manifest_json,snapshot_cursor,expires_at,created_at) VALUES(?,?,?,?,?,?)',
      [
        token,
        db.userId,
        canonical,
        manifest.cursor,
        manifest.expiresAt.millisecondsSinceEpoch,
        clock().toUtc().millisecondsSinceEpoch,
      ],
    );
    _fence(manifest);
  });

  Future<SnapshotDownloadState> read(String token) => db.transaction(() async {
    final result = await _read(token);
    _fence(result.manifest);
    return result;
  });
  Future<SnapshotDownloadState> _read(String token) async {
    requireActive();
    _token(token);
    final header = await db
        .customSelect(
          'SELECT manifest_json,state FROM snapshot_downloads WHERE snapshot_token=? AND user_id=?',
          variables: [Variable(token), Variable(db.userId)],
        )
        .getSingleOrNull();
    _check(header != null);
    final manifest = SnapshotManifest.decode(
      header!.read<String>('manifest_json'),
      expectedToken: token,
      now: clock(),
    );
    final rows = await db
        .customSelect(
          'SELECT entity,last_ordinal,next_cursor,finished FROM snapshot_download_progress WHERE snapshot_token=?',
          variables: [Variable(token)],
        )
        .get();
    return SnapshotDownloadState(manifest, header.read<String>('state'), {
      for (final row in rows)
        row.read<String>('entity'): SnapshotProgress(
          row.read<int>('last_ordinal'),
          row.readNullable<String>('next_cursor'),
          row.read<int>('finished') == 1,
        ),
    });
  }

  Future<void> append(String token, String entity, int after, String body) =>
      db.transaction(() async {
        final state = await _read(token);
        _check(state.state == 'RECEIVING');
        final prior = state.progress[entity];
        _check((prior?.ordinal ?? 0) == after && !(prior?.finished ?? false));
        final page = SnapshotPage.decode(
          body,
          manifest: state.manifest,
          entity: entity,
          owner: db.userId,
          afterOrdinal: after,
          now: clock(),
        );
        final held =
            (await db
                    .customSelect(
                      'SELECT COALESCE(SUM(length(CAST(canonical_payload AS BLOB))),0) AS bytes FROM snapshot_download_rows WHERE snapshot_token=?',
                      variables: [Variable(token)],
                    )
                    .getSingle())
                .read<int>('bytes');
        _check(
          held +
                  page.entries.fold<int>(
                    0,
                    (sum, e) => sum + utf8.encode(e.canonicalPayload).length,
                  ) <=
              100 * 1024 * 1024,
        );
        for (final entry in page.entries) {
          await db.customStatement(
            'INSERT INTO snapshot_download_rows(snapshot_token,user_id,entity,ordinal,resource_id,canonical_payload) VALUES(?,?,?,?,?,?)',
            [
              token,
              db.userId,
              entity,
              entry.ordinal,
              entry.resourceId,
              entry.canonicalPayload,
            ],
          );
        }
        final last = page.entries.isEmpty ? after : page.entries.last.ordinal,
            finished = page.nextCursor == null ? 1 : 0;
        if (prior == null) {
          await db.customStatement(
            'INSERT INTO snapshot_download_progress VALUES(?,?,?,?,?)',
            [token, entity, last, page.nextCursor, finished],
          );
        } else {
          await db.customStatement(
            'UPDATE snapshot_download_progress SET last_ordinal=?,next_cursor=?,finished=? WHERE snapshot_token=? AND entity=?',
            [last, page.nextCursor, finished, token, entity],
          );
        }
        _fence(state.manifest);
      });

  Future<void> verify(String token) => db.transaction(() async {
    final state = await _read(token);
    if (state.state == 'VERIFIED') {
      _fence(state.manifest);
      return;
    }
    _check(state.state == 'RECEIVING');
    _check(
      snapshotEntities.every(
        (e) =>
            state.progress[e]?.finished == true &&
            state.progress[e]?.ordinal == state.manifest.counts[e],
      ),
    );
    final integrity = SnapshotIntegrity(state.manifest);
    for (final entity in snapshotEntities) {
      var ordinal = 0;
      while (true) {
        _fence(state.manifest);
        final rows = await db
            .customSelect(
              'SELECT ordinal,resource_id,canonical_payload FROM snapshot_download_rows WHERE snapshot_token=? AND entity=? AND ordinal>? ORDER BY ordinal LIMIT 100',
              variables: [Variable(token), Variable(entity), Variable(ordinal)],
            )
            .get();
        if (rows.isEmpty) break;
        for (final row in rows) {
          ordinal = row.read<int>('ordinal');
          integrity.add(
            SnapshotEntry.fromStored(
              entity: entity,
              ordinal: ordinal,
              resourceId: row.read<String>('resource_id'),
              canonicalPayload: row.read<String>('canonical_payload'),
              owner: db.userId,
              snapshotCursor: state.manifest.cursor,
            ),
          );
        }
      }
    }
    integrity.finish(now: clock());
    await db.customStatement(
      "UPDATE snapshot_downloads SET state='VERIFIED' WHERE snapshot_token=?",
      [token],
    );
    _fence(state.manifest);
  });

  /// Swap all 19 entity baselines and the acknowledged cursor together.
  /// Local command/history/file tables remain overlays and are never replaced.
  Future<void> apply(String token) => db.transaction(() async {
    requireActive();
    _token(token);
    final pointer = await db
        .customSelect(
          'SELECT snapshot_token FROM snapshot_baseline WHERE singleton=1 AND user_id=?',
          variables: [Variable(db.userId)],
        )
        .getSingleOrNull();
    if (pointer?.read<String>('snapshot_token') == token) {
      requireActive();
      return;
    }
    final state = await _read(token);
    _check(state.state == 'VERIFIED');
    final cursor =
        (await db
                .customSelect(
                  'SELECT last_change_seq FROM sync_cursors WHERE singleton=1',
                )
                .getSingle())
            .readNullable<int>('last_change_seq');
    _check(cursor == null || state.manifest.cursor >= cursor);
    await db.customStatement(
      "UPDATE snapshot_downloads SET state='APPLIED' WHERE snapshot_token=?",
      [token],
    );
    await db.customStatement(
      'INSERT INTO snapshot_baseline(singleton,snapshot_token,user_id) VALUES(1,?,?) ON CONFLICT(singleton) DO UPDATE SET snapshot_token=excluded.snapshot_token',
      [token, db.userId],
    );
    await db.customStatement(
      'UPDATE sync_cursors SET last_change_seq=?,baseline_complete=1,snapshot_resume=NULL,updated_at=? WHERE singleton=1',
      [state.manifest.cursor, clock().toUtc().millisecondsSinceEpoch],
    );
    _fence(state.manifest);
  });

  /// TTL governs downloading, not the lifetime of an already applied baseline.
  /// Subsequent pages must pin the baseline token to avoid mixing generations.
  Future<SnapshotBaselinePage> baselinePage(
    String entity, {
    String? expectedToken,
    int after = 0,
    int limit = 50,
  }) => db.transaction(() async {
    requireActive();
    _check(
      snapshotEntities.contains(entity) &&
          after >= 0 &&
          limit >= 1 &&
          limit <= 100 &&
          (after == 0 || expectedToken != null),
    );
    final header = await db
        .customSelect(
          "SELECT h.snapshot_token,h.snapshot_cursor FROM snapshot_baseline b JOIN snapshot_downloads h ON h.snapshot_token=b.snapshot_token AND h.user_id=b.user_id WHERE b.singleton=1 AND b.user_id=? AND h.state='APPLIED'",
          variables: [Variable(db.userId)],
        )
        .getSingleOrNull();
    _check(header != null);
    final token = header!.read<String>('snapshot_token'),
        cursor = header.read<int>('snapshot_cursor');
    _check(expectedToken == null || token == expectedToken);
    final rows = await db
        .customSelect(
          'SELECT ordinal,resource_id,canonical_payload FROM snapshot_download_rows WHERE snapshot_token=? AND entity=? AND ordinal>? ORDER BY ordinal LIMIT ?',
          variables: [
            Variable(token),
            Variable(entity),
            Variable(after),
            Variable(limit + 1),
          ],
        )
        .get();
    final entries = [
      for (final row in rows.take(limit))
        SnapshotEntry.fromStored(
          entity: entity,
          ordinal: row.read<int>('ordinal'),
          resourceId: row.read<String>('resource_id'),
          canonicalPayload: row.read<String>('canonical_payload'),
          owner: db.userId,
          snapshotCursor: cursor,
        ),
    ];
    requireActive();
    return SnapshotBaselinePage(token, cursor, entries, rows.length > limit);
  });

  /// Point lookup only for entities whose resource UUID identifies one row.
  /// Relationship/log entities can repeat resource IDs: use baselinePage instead.
  /// Null means no applied baseline; a null entry means absent in that baseline.
  Future<SnapshotBaselineRecord?> baselineRecord(
    String entity,
    String resourceId, {
    String? expectedToken,
  }) => db.transaction(() async {
    requireActive();
    _check(
      const {
        'SONG',
        'RECORDING',
        'PLAYLIST',
        'TAG',
        'RECORDING_CONDITION',
      }.contains(entity),
    );
    _check(UuidValue(resourceId).value == resourceId);
    final header = await db
        .customSelect(
          "SELECT h.snapshot_token,h.snapshot_cursor FROM snapshot_baseline b JOIN snapshot_downloads h ON h.snapshot_token=b.snapshot_token AND h.user_id=b.user_id WHERE b.singleton=1 AND b.user_id=? AND h.state='APPLIED'",
          variables: [Variable(db.userId)],
        )
        .getSingleOrNull();
    if (header == null) {
      _check(expectedToken == null);
      requireActive();
      return null;
    }
    final token = header.read<String>('snapshot_token');
    final cursor = header.read<int>('snapshot_cursor');
    _check(expectedToken == null || token == expectedToken);
    final row = await db
        .customSelect(
          'SELECT ordinal,canonical_payload FROM snapshot_download_rows WHERE snapshot_token=? AND entity=? AND resource_id=?',
          variables: [Variable(token), Variable(entity), Variable(resourceId)],
        )
        .getSingleOrNull();
    final entry = row == null
        ? null
        : SnapshotEntry.fromStored(
            entity: entity,
            ordinal: row.read<int>('ordinal'),
            resourceId: resourceId,
            canonicalPayload: row.read<String>('canonical_payload'),
            owner: db.userId,
            snapshotCursor: cursor,
          );
    requireActive();
    return SnapshotBaselineRecord(token, cursor, entry);
  });

  /// Read parent and repeated recording-tag rows in one baseline generation.
  /// This does not merge local edits, advance a cursor or manufacture revisions.
  Future<SnapshotRecordingBaseline?> recordingBaseline(
    String recordingId, {
    String? expectedToken,
  }) => db.transaction(() async {
    requireActive();
    final parent = await baselineRecord(
      'RECORDING',
      recordingId,
      expectedToken: expectedToken,
    );
    if (parent == null) return null;
    final rows = await db
        .customSelect(
          '''
      SELECT entity,ordinal,canonical_payload FROM snapshot_download_rows
      WHERE snapshot_token=? AND user_id=? AND resource_id=?
        AND entity IN ('RECORDING_FILE_SPEC','RECORDING_TAG') ORDER BY entity,ordinal
    ''',
          variables: [
            Variable(parent.token),
            Variable(db.userId),
            Variable(recordingId),
          ],
        )
        .get();
    _check(parent.entry != null || rows.isEmpty);
    SnapshotEntry? file;
    final tags = <SnapshotEntry>[];
    final tagIds = <String>{};
    for (final row in rows) {
      final entry = SnapshotEntry.fromStored(
        entity: row.read<String>('entity'),
        ordinal: row.read<int>('ordinal'),
        resourceId: recordingId,
        canonicalPayload: row.read<String>('canonical_payload'),
        owner: db.userId,
        snapshotCursor: parent.cursor,
      );
      if (entry.entity == 'RECORDING_FILE_SPEC') {
        _check(file == null);
        file = entry;
      } else {
        final id = entry.payload['tag_id'];
        _check(id is String && UuidValue(id).value == id && tagIds.add(id));
        tags.add(entry);
      }
    }
    requireActive();
    return SnapshotRecordingBaseline(
      parent.token,
      parent.cursor,
      parent.entry,
      file,
      tags,
    );
  });

  /// Discard only an un-applied derived download, including an expired one.
  Future<void> discard(String token) => db.transaction(() async {
    requireActive();
    _token(token);
    await db.customStatement(
      "DELETE FROM snapshot_downloads WHERE snapshot_token=? AND user_id=? AND state<>'APPLIED'",
      [token, db.userId],
    );
    requireActive();
  });
}
