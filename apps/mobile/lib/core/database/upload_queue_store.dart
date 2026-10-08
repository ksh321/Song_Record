import 'package:drift/drift.dart';

import '../domain/identifiers.dart';
import 'account_database.dart';
import 'mapping_eligibility.dart';

final class UploadWork {
  UploadWork(
    this.recordingId,
    this.operationId,
    this.attemptId,
    this.renewOperationId,
    this.claimId,
    this.size,
    this.sha256,
  );
  final String recordingId, operationId, claimId, sha256;
  final String? attemptId, renewOperationId;
  final int size;
}

/// Only called under the account manager's serialized lease. Never deletes audio or metadata.
final class UploadQueueStore {
  UploadQueueStore(this.db, this.clock);
  final AccountDatabase db;
  final DateTime Function() clock;
  int get now => clock().toUtc().millisecondsSinceEpoch;
  Future<void> recover() async {
    await db.customStatement(
      "UPDATE local_upload_queue SET phase='RETRY',claim_id=NULL,next_attempt_at=NULL,reason='INTERRUPTED',updated_at=? WHERE phase='SENDING'",
      [now],
    );
  }

  Future<Set<String>> _blockedRecordings() async {
    final mapping = await readMappingEligibility(db);
    final rows = await db
        .customSelect(
          "SELECT op_id,entity_id FROM local_mutations WHERE entity_type='RECORDING' AND queue_state<>'ACKED'",
        )
        .get();
    return {
      for (final row in rows)
        if (!mapping.superseded.contains(row.read<String>('op_id')) ||
            mapping.blocked.contains(row.read<String>('op_id')))
          row.read<String>('entity_id'),
    };
  }

  // Every literal is a canonical UUID, never arbitrary SQL or user text.
  String _exclude(Set<String> ids) => ids.isEmpty
      ? ''
      : "AND m.entity_id NOT IN (${ids.map((id) => "'${UuidValue(id).value}'").join(',')})";
  Future<void> discover() => db.transaction(() async {
    final blocked = await _blockedRecordings();
    // Only acknowledged SAVED metadata, matching verified original; no local edit is mistaken for approval.
    final rows = await db.customSelect(
      """SELECT f.recording_id,f.size_bytes,f.sha256 FROM local_recording_files f
      JOIN metadata_copies m ON m.entity_type='RECORDING' AND m.entity_id=f.recording_id AND m.user_id=f.user_id
      WHERE f.local_state='SAVED' AND f.verified_at IS NOT NULL AND m.tombstone=0 AND m.server_revision>0
      AND json_extract(m.server_payload,'\$.metadata_state')='SAVED' AND json_extract(m.server_payload,'\$.lifecycle_state')='ACTIVE'
      AND json_extract(m.server_payload,'\$.file.sha256')=f.sha256 AND json_extract(m.server_payload,'\$.file.size_bytes')=f.size_bytes
      AND NOT EXISTS(SELECT 1 FROM local_upload_queue q WHERE q.recording_id=f.recording_id)
      ${_exclude(blocked)}
      ORDER BY f.updated_at,f.recording_id LIMIT 500""",
    ).get();
    for (final r in rows) {
      await db.customStatement(
        "INSERT INTO local_upload_queue(recording_id,user_id,operation_id,phase,expected_size,sha256,created_at,updated_at) VALUES(?,?,?,'PENDING',?,?,?,?)",
        [
          r.read<String>('recording_id'),
          db.userId,
          UuidValue.random().value,
          r.read<int>('size_bytes'),
          r.read<String>('sha256'),
          now,
          now,
        ],
      );
    }
  });

  Future<UploadWork?> claim() => db.transaction(() async {
    final blocked = await _blockedRecordings();
    if ((await db
            .customSelect(
              "SELECT 1 FROM local_upload_queue WHERE phase='SENDING' LIMIT 1",
            )
            .get())
        .isNotEmpty) {
      return null;
    }
    final rows = await db
        .customSelect(
          """SELECT q.* FROM local_upload_queue q
      JOIN metadata_copies m ON m.entity_type='RECORDING' AND m.entity_id=q.recording_id
      WHERE (q.phase='PENDING' OR(q.phase='RETRY' AND q.next_attempt_at IS NOT NULL AND q.next_attempt_at<=? AND q.automatic_retries<3))
      AND m.tombstone=0 AND json_extract(m.server_payload,'\$.metadata_state')='SAVED'
      AND json_extract(m.server_payload,'\$.lifecycle_state')='ACTIVE'
      ${_exclude(blocked)}
      ORDER BY CASE WHEN EXISTS(SELECT 1 FROM metadata_copies p WHERE p.entity_type='PIN_SLOT' AND p.tombstone=0
        AND (json_extract(p.server_payload,'\$.current_recording_id')=q.recording_id OR json_extract(p.server_payload,'\$.pending_recording_id')=q.recording_id))
        OR EXISTS(SELECT 1 FROM snapshot_download_rows p JOIN snapshot_baseline b ON b.snapshot_token=p.snapshot_token
        WHERE p.entity='PIN_SLOT' AND NOT EXISTS(SELECT 1 FROM metadata_copies newer WHERE newer.entity_type='PIN_SLOT' AND newer.entity_id=p.resource_id) AND (json_extract(p.canonical_payload,'\$.current_recording_id')=q.recording_id OR json_extract(p.canonical_payload,'\$.pending_recording_id')=q.recording_id))
        THEN 0 ELSE 1 END,q.created_at,q.rowid LIMIT 1""",
          variables: [Variable(now)],
        )
        .get();
    if (rows.isEmpty) return null;
    final r = rows.single, claim = UuidValue.random().value;
    final renew = r.readNullable<String>('attempt_id') == null
        ? null
        : r.readNullable<String>('renew_operation_id') ??
              UuidValue.random().value;
    await db.customStatement(
      "UPDATE local_upload_queue SET phase='SENDING',claim_id=?,renew_operation_id=?,attempt_count=attempt_count+1,automatic_retries=automatic_retries+?,next_attempt_at=NULL,updated_at=? WHERE recording_id=?",
      [
        claim,
        renew,
        r.read<String>('phase') == 'RETRY' ? 1 : 0,
        now,
        r.read<String>('recording_id'),
      ],
    );
    return UploadWork(
      r.read<String>('recording_id'),
      r.read<String>('operation_id'),
      r.readNullable<String>('attempt_id'),
      renew,
      claim,
      r.read<int>('expected_size'),
      r.read<String>('sha256'),
    );
  });
  Future<bool> current(UploadWork work) async =>
      (await db
              .customSelect(
                "SELECT 1 FROM local_upload_queue WHERE recording_id=? AND phase='SENDING' AND claim_id=?",
                variables: [Variable(work.recordingId), Variable(work.claimId)],
              )
              .get())
          .isNotEmpty;
  Future<bool> ticket(UploadWork work, String attempt) async {
    if (!await current(work)) return false;
    final id = UuidValue(attempt).value;
    await db.customStatement(
      'UPDATE local_upload_queue SET attempt_id=?,renew_operation_id=NULL,updated_at=? WHERE recording_id=?',
      [id, now, work.recordingId],
    );
    return true;
  }

  Future<void> settle(
    UploadWork work,
    String phase,
    String? reason, {
    bool retry = false,
  }) async {
    if (!await current(work)) return;
    final r = await db
        .customSelect(
          'SELECT automatic_retries FROM local_upload_queue WHERE recording_id=?',
          variables: [Variable(work.recordingId)],
        )
        .getSingle();
    final count = r.read<int>('automatic_retries');
    final next = retry && count < 3
        ? now + const [60000, 300000, 900000][count]
        : null;
    await db.customStatement(
      'UPDATE local_upload_queue SET phase=?,claim_id=NULL,reason=?,next_attempt_at=?,updated_at=? WHERE recording_id=?',
      [phase, reason, next, now, work.recordingId],
    );
  }

  Future<void> cancel(String id) async {
    await db.customStatement(
      "UPDATE local_upload_queue SET phase='CANCELLED',claim_id=NULL,next_attempt_at=NULL,reason='USER_CANCELLED',updated_at=? WHERE recording_id=? AND phase NOT IN ('UPLOADED','STORED')",
      [now, UuidValue(id).value],
    );
  }

  Future<void> retry(String id) async {
    await db.customStatement(
      "UPDATE local_upload_queue SET phase='PENDING',claim_id=NULL,next_attempt_at=NULL,reason=NULL,updated_at=? WHERE recording_id=? AND phase IN ('RETRY','BLOCKED','CANCELLED')",
      [now, UuidValue(id).value],
    );
  }

  Future<DateTime?> next() => db.transaction(() async {
    final blocked = await _blockedRecordings();
    // Ineligible PENDING records must not create a busy timer loop.
    final r = await db
        .customSelect(
          """SELECT MIN(CASE WHEN q.phase='PENDING' THEN ? ELSE q.next_attempt_at END) AS value
      FROM local_upload_queue q JOIN metadata_copies m ON m.entity_type='RECORDING' AND m.entity_id=q.recording_id
      WHERE (q.phase='PENDING' OR(q.phase='RETRY' AND q.automatic_retries<3)) AND m.tombstone=0
      AND json_extract(m.server_payload,'\$.lifecycle_state')='ACTIVE' AND json_extract(m.server_payload,'\$.metadata_state')='SAVED'
      ${_exclude(blocked)}""",
          variables: [Variable(now)],
        )
        .getSingle();
    final value = r.readNullable<int>('value');
    return value == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  });

  Future<List<Map<String, Object?>>> status() async =>
      (await db
              .customSelect(
                'SELECT recording_id,phase,reason,attempt_count,automatic_retries FROM local_upload_queue ORDER BY created_at,rowid',
              )
              .get())
          .map((r) => Map<String, Object?>.from(r.data))
          .toList();
}
