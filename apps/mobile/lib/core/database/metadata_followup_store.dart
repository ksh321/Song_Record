import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../domain/identifiers.dart';
import '../sync/metadata_followup_plan.dart';
import '../sync/mutation_request.dart';
import 'account_database.dart';
import 'local_models.dart';

QueuedMutation _mutation(QueryRow row) => QueuedMutation(
  opId: row.read<String>('op_id'),
  localOrder: row.read<int>('local_order'),
  entity: LocalEntity.values.firstWhere(
    (e) => e.code == row.read<String>('entity_type'),
  ),
  entityId: row.read<String>('entity_id'),
  operation: LocalOperation.values.firstWhere(
    (o) => o.code == row.read<String>('operation'),
  ),
  state: row.read<String>('queue_state'),
  baseRevision: row.read<int>('base_revision'),
  payload: row.read<String>('payload'),
  basePayload: row.readNullable<String>('base_payload'),
  serverResponse: row.readNullable<String>('server_response'),
  attemptCount: row.read<int>('attempt_count'),
);

/// Must run within the caller's account transaction. Validate history before
/// hiding an original or assigning its logical position to a replacement.
Future<MappingEligibility> metadataFollowupEligibility(
  AccountDatabase db,
  MappingEligibility mapping,
) async {
  final edges = await db
      .customSelect('SELECT * FROM recording_followups')
      .get();
  if (edges.isEmpty) return mapping;
  final rows = await db
      .customSelect('SELECT rowid AS local_order,* FROM local_mutations')
      .get();
  final mutations = {
    for (final row in rows) row.read<String>('op_id'): _mutation(row),
  };
  final blocked = {...mapping.blocked}, superseded = {...mapping.superseded};
  final orders = {...mapping.logicalOrders};
  for (final edge in edges) {
    final id = edge.read<String>('original_op_id'),
        nextId = edge.read<String>('replacement_op_id');
    final original = mutations[id], next = mutations[nextId];
    final prior = mutations[edge.read<String>('predecessor_op_id')];
    var valid =
        original != null &&
        next != null &&
        prior != null &&
        edge.read<String>('user_id') == db.userId &&
        !blocked.contains(id) &&
        !mapping.superseded.contains(id) &&
        !mapping.superseded.contains(nextId);
    if (valid) {
      final intended = jsonDecode(original.payload) as Map<String, dynamic>;
      final baseline = next.basePayload == null
          ? null
          : jsonDecode(next.basePayload!);
      final receipt = prior.serverResponse == null
          ? null
          : jsonDecode(prior.serverResponse!);
      valid =
          {
            LocalEntity.recording,
            LocalEntity.song,
            LocalEntity.tag,
          }.contains(original.entity) &&
          next.entity == original.entity &&
          prior.entity == original.entity &&
          original.entityId == next.entityId &&
          prior.entityId == original.entityId &&
          original.operation == LocalOperation.patch &&
          next.operation == LocalOperation.patch &&
          original.state == 'PENDING' &&
          original.attemptCount == 0 &&
          original.baseRevision == 0 &&
          prior.state == 'ACKED' &&
          prior.attemptCount > 0 &&
          baseline is Map<String, dynamic> &&
          receipt is Map<String, dynamic> &&
          next.baseRevision == receipt['revision'] &&
          next.baseRevision > 0 &&
          canonicalJson(baseline) == canonicalJson(receipt) &&
          edge.read<int>('logical_order') == original.localOrder &&
          next.localOrder > original.localOrder &&
          canonicalJson({...intended, 'base_revision': next.baseRevision}) ==
              canonicalJson(jsonDecode(next.payload) as Map<String, dynamic>);
    }
    if (valid) {
      superseded.add(id);
      // The immutable ledger retains its physical-root contract. Projection
      // additionally inherits a validated canonical reference's earlier order.
      orders[nextId] =
          mapping.logicalOrders[id] ?? edge.read<int>('logical_order');
    } else {
      blocked.addAll([id, nextId]);
    }
  }
  return MappingEligibility(
    blocked: blocked,
    superseded: superseded,
    logicalOrders: orders,
    groups: mapping.groups,
  );
}

/// Add one replacement at a time; the next claim re-evaluates the same ordered
/// account snapshot. Neither local draft nor original request history changes.
Future<bool> materializeMetadataFollowup(
  AccountDatabase db,
  MappingEligibility mapping, {
  bool previewOnly = false,
}) async {
  final rows = await db
      .customSelect(
        'SELECT rowid AS local_order,* FROM local_mutations ORDER BY rowid',
      )
      .get();
  final all = rows.map(_mutation).toList()
    ..sort((a, b) => mapping.orderOf(a).compareTo(mapping.orderOf(b)));
  for (final original in all) {
    if (!{
          LocalEntity.recording,
          LocalEntity.song,
          LocalEntity.tag,
        }.contains(original.entity) ||
        original.operation != LocalOperation.patch ||
        original.baseRevision != 0 ||
        original.state != 'PENDING' ||
        original.attemptCount != 0 ||
        !mapping.allows(original.opId)) {
      continue;
    }
    final previous = all
        .where(
          (m) =>
              m.entity == original.entity &&
              m.entityId == original.entityId &&
              mapping.orderOf(m) < mapping.orderOf(original) &&
              !mapping.superseded.contains(m.opId),
        )
        .toList();
    if (previous.isEmpty ||
        previous.any((m) => m.state != 'ACKED' || !mapping.allows(m.opId))) {
      continue;
    }
    final prior = previous.last;
    final wire = await db
        .customSelect(
          'SELECT * FROM mutation_wire_requests WHERE op_id=?',
          variables: [Variable(prior.opId)],
        )
        .getSingleOrNull();
    final copy = await db
        .customSelect(
          'SELECT * FROM metadata_copies WHERE entity_type=? AND entity_id=?',
          variables: [
            Variable(original.entity.code),
            Variable(original.entityId),
          ],
        )
        .getSingleOrNull();
    if (wire == null ||
        copy == null ||
        prior.serverResponse == null ||
        copy.readNullable<String>('server_payload') == null) {
      continue;
    }
    final request = MutationRequest(
      mutation: prior,
      method: wire.read<String>('http_method'),
      path: wire.read<String>('relative_path'),
      body: wire.read<String>('body_json'),
      attempt: prior.attemptCount,
    );
    if (request.hash != wire.read<String>('wire_hash') ||
        request.body != prior.payload) {
      continue;
    }
    MetadataFollowupPlan? plan;
    try {
      final priorSnapshot = jsonDecode(prior.serverResponse!);
      // Song CREATE ACKs persist the validated resource, not its wire envelope.
      // Rebuild only the envelope shape; the original snapshot stays unchanged.
      final receipt =
          prior.entity == LocalEntity.song &&
              prior.operation == LocalOperation.create
          ? jsonEncode({
              'created': false,
              'canonical_song_id': prior.entityId,
              'song': priorSnapshot,
            })
          : prior.serverResponse!;
      plan = MetadataFollowupPlan.derive(
        original: original,
        predecessor: request,
        receipt: MutationResponse(
          // ACK stores the validated snapshot, not the original HTTP status.
          // Validate as a successful existing-resource snapshot; do not invent
          // 201 or force revision 1 for a recovered CREATE that returned 200.
          200,
          receipt,
        ),
        predecessorLogicalOrder: mapping.orderOf(prior),
        current: jsonDecode(
          copy.read<String>('server_payload'),
        ) as Map<String, dynamic>,
        tombstone: copy.read<int>('tombstone') == 1,
      );
    } on FormatException {
      // Preserve this target's evidence and continue unrelated eligible work.
      continue;
    }
    if (plan == null) continue;
    if (previewOnly) return true;
    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List.generate(16, (_) => random.nextInt(256)),
    );
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final id = UuidValue.fromBytes(bytes).value,
        now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final hash = sha256
        .convert(
          utf8.encode(
            canonicalJson({
              'original': original.opId,
              'predecessor': prior.opId,
              'payload': plan.payloadJson,
              'baseline': plan.baselineJson,
            }),
          ),
        )
        .toString();
    await db.customStatement(
      '''INSERT INTO local_mutations(op_id,user_id,entity_type,entity_id,operation,base_revision,base_payload,payload,request_hash,created_at,updated_at)
      VALUES(?,?,?,?,'PATCH',?,?,?,?,?,?)''',
      [
        id,
        db.userId,
        original.entity.code,
        original.entityId,
        plan.revision,
        plan.baselineJson,
        plan.payloadJson,
        hash,
        now,
        now,
      ],
    );
    await db.customStatement(
      "INSERT INTO mutation_retry_controls(op_id,automatic_retries_claimed,retry_mode,last_attempt_kind) VALUES(?,0,'INITIAL','INITIAL')",
      [id],
    );
    await db.customStatement(
      'INSERT INTO recording_followups(original_op_id,replacement_op_id,predecessor_op_id,user_id,logical_order,created_at) VALUES(?,?,?,?,?,?)',
      [original.opId, id, prior.opId, db.userId, original.localOrder, now],
    );
    return true;
  }
  return false;
}
