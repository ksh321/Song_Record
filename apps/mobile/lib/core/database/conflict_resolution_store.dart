import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../domain/identifiers.dart';
import '../sync/conflict_resolution_plan.dart';
import 'account_database.dart';
import 'local_models.dart';
import 'mapping_eligibility.dart';

/// Internal helper. Caller owns serialization, transaction and account fence.
final class ConflictResolutionStore {
  ConflictResolutionStore(this.db, this.requireActive);
  final AccountDatabase db;
  final void Function() requireActive;

  Future<void> resolve({
    required QueuedMutation expected,
    required String? expectedLocalJson,
    required String? replacementOpId,
    required Map<String, ConflictChoice> choices,
    required int now,
  }) async {
    requireActive();
    final row = await db
        .customSelect(
          'SELECT rowid AS local_order,* FROM local_mutations WHERE op_id=?',
          variables: [Variable(expected.opId)],
        )
        .getSingleOrNull();
    if (row == null ||
        row.read<String>('user_id') != db.userId ||
        row.read<String>('entity_type') != expected.entity.code ||
        row.read<String>('entity_id') != expected.entityId ||
        row.read<String>('operation') != expected.operation.code ||
        row.read<String>('queue_state') != expected.state ||
        row.read<int>('local_order') != expected.localOrder ||
        row.read<int>('attempt_count') != expected.attemptCount ||
        row.read<int>('base_revision') != expected.baseRevision ||
        row.read<String>('payload') != expected.payload ||
        row.readNullable<String>('base_payload') != expected.basePayload ||
        row.readNullable<String>('server_response') !=
            expected.serverResponse) {
      throw StateError('Conflict source changed');
    }
    final mapping = await readMappingEligibility(db);
    if (!mapping.allows(expected.opId)) {
      throw StateError('Conflict is held or already resolved');
    }
    final plan = prepareConflictResolution(expected, choices: choices);
    final server = jsonDecode(plan.serverJson) as Map<String, dynamic>;
    if (server.containsKey('user_id') && server['user_id'] != db.userId) {
      throw StateError('Conflict owner mismatch');
    }
    final revision = server['revision'] as int;
    final copy = await db
        .customSelect(
          'SELECT * FROM metadata_copies WHERE entity_type=? AND entity_id=?',
          variables: [
            Variable(expected.entity.code),
            Variable(expected.entityId),
          ],
        )
        .getSingleOrNull();
    if (copy == null ||
        copy.read<String>('user_id') != db.userId ||
        copy.read<int>('tombstone') != 0 ||
        copy.readNullable<String>('local_payload') != expectedLocalJson ||
        copy.read<int>('server_revision') > revision) {
      throw StateError('Conflict copy changed or target was deleted');
    }
    if (copy.read<int>('server_revision') == revision &&
        canonicalJson(
              jsonDecode(copy.read<String>('server_payload'))
                  as Map<String, dynamic>,
            ) !=
            plan.serverJson) {
      throw StateError('Equal revision has different server evidence');
    }
    if (plan.needsRequest != (replacementOpId != null) ||
        replacementOpId == expected.opId) {
      throw ArgumentError('A new request needs a distinct new operation ID');
    }
    if (replacementOpId != null &&
        UuidValue(replacementOpId).value != replacementOpId) {
      throw ArgumentError('Operation ID must be canonical');
    }
    final related = await db
        .customSelect(
          "SELECT op_id FROM local_mutations WHERE entity_type=? AND entity_id=? AND op_id<>? AND queue_state<>'ACKED'",
          variables: [
            Variable(expected.entity.code),
            Variable(expected.entityId),
            Variable(expected.opId),
          ],
        )
        .get();
    final preserveDraft = related.any(
      (r) =>
          !mapping.superseded.contains(r.read<String>('op_id')) ||
          mapping.blocked.contains(r.read<String>('op_id')),
    );
    final merged = <String, dynamic>{...server};
    if (plan.patchJson != null) {
      merged.addAll(jsonDecode(plan.patchJson!) as Map<String, dynamic>);
      merged.remove('base_revision');
      if (expected.entity == LocalEntity.recording &&
          (jsonDecode(plan.patchJson!) as Map).containsKey('tag_ids')) {
        // Do not fabricate historical names for new IDs.
        merged.remove('tags');
      }
    }
    final draft = canonicalJson(merged);
    if (replacementOpId != null) {
      final fingerprint = sha256
          .convert(
            utf8.encode(
              canonicalJson({
                'entity': expected.entity.code,
                'id': expected.entityId,
                'operation': 'PATCH',
                'base_revision': revision,
                'draft': merged,
                'changes': jsonDecode(plan.patchJson!),
              }),
            ),
          )
          .toString();
      await db.customStatement(
        '''INSERT INTO local_mutations(op_id,user_id,entity_type,entity_id,operation,
        base_revision,base_payload,payload,request_hash,created_at,updated_at)
        VALUES(?,?,?,?,'PATCH',?,?,?,?,?,?)''',
        [
          replacementOpId,
          db.userId,
          expected.entity.code,
          expected.entityId,
          revision,
          plan.serverJson,
          plan.patchJson,
          fingerprint,
          now,
          now,
        ],
      );
      await db.customStatement(
        "INSERT INTO mutation_retry_controls(op_id,automatic_retries_claimed,retry_mode,last_attempt_kind) VALUES(?,0,'INITIAL','INITIAL')",
        [replacementOpId],
      );
    }
    final previous = await db
        .customSelect(
          'SELECT order_root_op_id,logical_order FROM mutation_conflict_resolutions WHERE replacement_op_id=?',
          variables: [Variable(expected.opId)],
        )
        .getSingleOrNull();
    await db.customStatement(
      'INSERT INTO mutation_conflict_resolutions VALUES(?,?,?,?,?,?,?,?,?,?)',
      [
        expected.opId,
        db.userId,
        replacementOpId,
        expected.attemptCount,
        revision,
        plan.serverJson,
        plan.choicesJson,
        previous?.read<String>('order_root_op_id') ?? expected.opId,
        previous?.read<int>('logical_order') ?? expected.localOrder,
        now,
      ],
    );
    await db.customStatement(
      '''UPDATE metadata_copies SET server_revision=?,server_payload=?,
      local_payload=CASE WHEN ? THEN local_payload ELSE ? END,updated_at=? WHERE entity_type=? AND entity_id=?''',
      [
        revision,
        plan.serverJson,
        preserveDraft ? 1 : 0,
        draft,
        now,
        expected.entity.code,
        expected.entityId,
      ],
    );
    requireActive();
  }
}
