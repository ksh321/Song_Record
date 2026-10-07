import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../sync/canonical_reference_plan.dart';
import '../sync/metadata_followup_plan.dart';
import '../sync/metadata_response.dart';
import '../sync/mutation_request.dart';
import 'account_database.dart' show AccountDatabase;
import 'conflict_eligibility.dart';
import 'local_models.dart';
import 'metadata_followup_store.dart';

const _contract = 'canonical-reference-v1';

QueuedMutation _mutation(QueryRow row) => QueuedMutation(
  opId: row.read<String>('op_id'),
  localOrder: row.read<int>('local_order'),
  entity: LocalEntity.values.firstWhere(
    (e) => e.code == row.read<String>('entity_type'),
  ),
  entityId: row.read<String>('entity_id'),
  operation: LocalOperation.values.firstWhere(
    (e) => e.code == row.read<String>('operation'),
  ),
  state: row.read<String>('queue_state'),
  baseRevision: row.read<int>('base_revision'),
  basePayload: row.readNullable<String>('base_payload'),
  payload: row.read<String>('payload'),
  serverResponse: row.readNullable<String>('server_response'),
  attemptCount: row.read<int>('attempt_count'),
);

MetadataCopy _copy(Map<String, dynamic> row) => MetadataCopy(
  revision: row['server_revision'] as int,
  serverJson: row['server_payload'] as String?,
  localJson: row['local_payload'] as String?,
  tombstone: row['tombstone'] == 1,
);

String _identity(String value) {
  final h = sha256.convert(utf8.encode(value)).toString();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
      '8${h.substring(13, 16)}-a${h.substring(17, 20)}-${h.substring(20, 32)}';
}

Future<List<QueryRow>> _select(
  AccountDatabase db,
  String sql, [
  List<String> args = const [],
]) => db
    .customSelect(sql, variables: args.map((v) => Variable(v)).toList())
    .get();

/// Revalidate immutable receipt provenance, including the frozen operation.
Future<CanonicalSongReceipt?> _receipt(
  AccountDatabase db,
  QueryRow alias,
) async {
  if (alias.read<String>('user_id') != db.userId) return null;
  final source = alias.read<String>('source_song_id');
  final target = alias.read<String>('canonical_song_id');
  if ((await _select(
    db,
    'SELECT source_song_id FROM song_aliases WHERE source_song_id=? OR canonical_song_id=?',
    [target, source],
  )).isNotEmpty) {
    return null;
  }
  final rows = await _select(
    db,
    'SELECT rowid AS local_order,* FROM local_mutations WHERE op_id=?',
    [alias.read<String>('mapping_op_id')],
  );
  final wires = await _select(
    db,
    'SELECT * FROM mutation_wire_requests WHERE op_id=?',
    [alias.read<String>('mapping_op_id')],
  );
  if (rows.length != 1 || wires.length != 1) return null;
  final row = rows.single, wire = wires.single;
  final m = _mutation(row);
  if (row.read<String>('user_id') != db.userId ||
      m.state != 'ACKED' ||
      m.attemptCount < 1 ||
      m.entityId != source ||
      m.serverResponse != alias.read<String>('receipt_body') ||
      wire.read<String>('contract_version') != MutationRequest.contract) {
    return null;
  }
  final request = MutationRequest(
    mutation: m,
    method: wire.read<String>('http_method'),
    path: wire.read<String>('relative_path'),
    body: wire.read<String>('body_json'),
    attempt: m.attemptCount,
  );
  if (request.body != m.payload ||
      request.hash != wire.read<String>('wire_hash')) {
    return null;
  }
  try {
    final receipt = CanonicalSongReceipt.decode(
      request,
      MutationResponse(
        alias.read<int>('receipt_status'),
        alias.read<String>('receipt_body'),
      ),
    );
    return receipt.canonicalSongId == target ? receipt : null;
  } on FormatException {
    return null;
  }
}

/// Immutable release evidence distinguishes new verified reference edges from
/// legacy PATCH edges. Null means legacy; false means invalid new evidence.
Future<bool?> canonicalReferenceEdge(
  AccountDatabase db,
  QueryRow edge,
  QueryRow original,
  QueryRow replacement,
) async {
  final holds = await _select(
    db,
    'SELECT * FROM mutation_mapping_holds WHERE op_id=?',
    [edge.read<String>('original_op_id')],
  );
  Map<String, dynamic>? evidence;
  for (final hold in holds) {
    final raw = hold.readNullable<String>('release_evidence');
    if (raw == null) continue;
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic> && decoded['contract'] == _contract) {
      if (evidence != null ||
          hold.readNullable<int>('released_at') == null ||
          hold.read<String>('mapping_source_id') !=
              edge.read<String>('mapping_source_id') ||
          hold.read<String>('reason') != 'CANONICAL_MAPPING' ||
          hold.read<String>('disposition') != 'BLOCK' ||
          hold.read<String>('user_id') != db.userId) {
        return false;
      }
      evidence = decoded;
    }
  }
  if (evidence == null) return null;
  final source = edge.read<String>('mapping_source_id');
  final aliases = await _select(
    db,
    'SELECT * FROM song_aliases WHERE source_song_id=?',
    [source],
  );
  if (aliases.length != 1 ||
      await _receipt(db, aliases.single) == null ||
      evidence['original_op_id'] != original.read<String>('op_id') ||
      evidence['replacement_op_id'] != replacement.read<String>('op_id') ||
      original.read<String>('user_id') != db.userId ||
      replacement.read<String>('user_id') != db.userId ||
      edge.read<String>('user_id') != db.userId ||
      evidence['metadata_before'] is! Map<String, dynamic>) {
    return false;
  }
  final before = evidence['metadata_before'] as Map<String, dynamic>;
  if (before['user_id'] != db.userId ||
      before['entity_type'] != original.read<String>('entity_type') ||
      before['entity_id'] != original.read<String>('entity_id') ||
      before['server_revision'] is! int ||
      (before['server_payload'] != null && before['server_payload'] is! String) ||
      before['local_payload'] is! String ||
      before['tombstone'] != 0 ||
      edge.read<String>('order_root_op_id') != original.read<String>('op_id') ||
      edge.read<int>('logical_order') != original.read<int>('local_order') ||
      replacement.read<int>('local_order') <= original.read<int>('local_order')) {
    return false;
  }
  final frozen = await _select(
    db,
    'SELECT op_id FROM mutation_wire_requests WHERE op_id=?',
    [original.read<String>('op_id')],
  );
  final plan = CanonicalReferencePlan.derive(
    original: _mutation(original),
    sourceId: source,
    canonicalId: aliases.single.read<String>('canonical_song_id'),
    current: _copy(before),
    hasFrozenRequest: frozen.isNotEmpty,
  );
  return plan != null &&
      replacement.read<String>('op_id') == _identity(canonicalJson({
        'contract': _contract,
        'user_id': db.userId,
        'original_op_id': original.read<String>('op_id'),
        'mapping_op_id': aliases.single.read<String>('mapping_op_id'),
        'payload': plan.payloadJson,
      })) &&
      replacement.read<String>('payload') == plan.payloadJson &&
      original.read<String>('entity_type') ==
          replacement.read<String>('entity_type') &&
      original.read<String>('entity_id') ==
          replacement.read<String>('entity_id') &&
      original.read<String>('operation') ==
          replacement.read<String>('operation') &&
      original.read<int>('base_revision') ==
          replacement.read<int>('base_revision') &&
      original.readNullable<String>('base_payload') ==
          replacement.readNullable<String>('base_payload');
}

/// Caller owns the account transaction. Preview does not write, consume an
/// attempt, or schedule work solely for an unsupported playlist route.
Future<bool> materializeCanonicalReferences(
  AccountDatabase db,
  int now, {
  bool previewOnly = false,
}) async {
  final aliases = await _select(
    db,
    'SELECT * FROM song_aliases ORDER BY source_song_id',
  );
  if (aliases.isEmpty) return false;
  var changed = false;
  for (final alias in aliases) {
    final receipt = await _receipt(db, alias);
    if (receipt == null) continue;
    final source = receipt.localSongId, target = receipt.canonicalSongId;
    final canonical = await _select(
      db,
      "SELECT * FROM metadata_copies WHERE entity_type='SONG' AND entity_id=?",
      [target],
    );
    if (canonical.length != 1 ||
        canonical.single.read<int>('tombstone') != 0 ||
        canonical.single.read<String>('user_id') != db.userId ||
        canonical.single.read<int>('server_revision') <
            (receipt.snapshot['revision'] as int)) {
      continue;
    }
    final serverText = canonical.single.readNullable<String>('server_payload');
    if (serverText == null) continue;
    final serverSong = jsonDecode(serverText);
    if (serverSong is! Map<String, dynamic> ||
        serverSong['id'] != target ||
        serverSong['source_type'] != 'TJ' ||
        serverSong['lifecycle_state'] != 'ACTIVE' ||
        serverSong['tj_number'] != receipt.snapshot['tj_number'] ||
        serverSong['revision'] != canonical.single.read<int>('server_revision')) {
      continue;
    }

    final rows = await _select(
      db,
      "SELECT rowid AS local_order,* FROM local_mutations WHERE queue_state='PENDING' AND attempt_count=0 AND entity_type IN ('RECORDING','PLAYLIST_ITEM') ORDER BY rowid",
    );
    for (final row in rows) {
      final original = _mutation(row);
      if (row.read<String>('user_id') != db.userId) continue;
      if ((await _select(
        db,
        'SELECT original_op_id FROM mutation_supersessions WHERE original_op_id=? OR replacement_op_id=? UNION SELECT original_op_id FROM recording_followups WHERE original_op_id=? OR replacement_op_id=? UNION SELECT original_op_id FROM mutation_conflict_resolutions WHERE original_op_id=? OR replacement_op_id=? UNION SELECT original_op_id FROM pending_edit_resolutions WHERE original_op_id=? OR replacement_op_id=?',
        List.filled(8, original.opId),
      )).isNotEmpty) {
        continue;
      }
      final frozen = await _select(
        db,
        'SELECT op_id FROM mutation_wire_requests WHERE op_id=?',
        [original.opId],
      );
      if (frozen.isNotEmpty) continue;
      final controls = await _select(
        db,
        'SELECT * FROM mutation_retry_controls WHERE op_id=?',
        [original.opId],
      );
      if (controls.length != 1 ||
          controls.single.readNullable<int>('automatic_retries_claimed') != 0 ||
          controls.single.read<String>('retry_mode') != 'INITIAL') {
        continue;
      }
      final copies = await _select(
        db,
        'SELECT * FROM metadata_copies WHERE entity_type=? AND entity_id=?',
        [original.entity.code, original.entityId],
      );
      if (copies.length != 1 ||
          copies.single.read<String>('user_id') != db.userId) {
        continue;
      }
      final copy = _copy(copies.single.data);
      final holds = await _select(
        db,
        'SELECT * FROM mutation_mapping_holds WHERE op_id=? AND released_at IS NULL',
        [original.opId],
      );
      if (holds.any(
        (h) =>
            h.read<String>('mapping_source_id') != source ||
            h.read<String>('reason') != 'CANONICAL_MAPPING' ||
            h.read<String>('disposition') != 'BLOCK' ||
            h.read<String>('user_id') != db.userId,
      )) {
        continue;
      }
      final plan = CanonicalReferencePlan.derive(
        original: original,
        sourceId: source,
        canonicalId: target,
        current: copy,
        hasFrozenRequest: false,
      );
      if (plan == null) {
        // A no-song_id offline edit/save can follow a verified remapped CREATE.
        // It needs no identity rewrite. Release only after the real ACK, with
        // the exact existing followup derivation as the authority.
        if (holds.length == 1 &&
            await _canFollow(db, original, copy, source, target)) {
          if (previewOnly) return true;
          await _release(
            db,
            original.opId,
            source,
            now,
            canonicalJson({
              'contract': 'canonical-followup-v1',
              'mapping_op_id': alias.read<String>('mapping_op_id'),
              'original_op_id': original.opId,
              'canonical_song_id': target,
            }),
          );
          changed = true;
        }
        continue;
      }
      if (holds.isEmpty &&
          (await _select(
            db,
            'SELECT op_id FROM mutation_mapping_holds WHERE op_id=?',
            [original.opId],
          )).isNotEmpty) {
        continue;
      }
      if (previewOnly) {
        if (original.entity == LocalEntity.recording &&
            (original.operation == LocalOperation.create ||
                original.baseRevision > 0)) {
          return true;
        }
        continue;
      }
      // Deterministic per immutable original + alias. Insert conflicts roll
      // back; they never silently accept an unrelated existing operation.
      final replacement = _identity(
        canonicalJson({
          'contract': _contract,
          'user_id': db.userId,
          'original_op_id': original.opId,
          'mapping_op_id': alias.read<String>('mapping_op_id'),
          'payload': plan.payloadJson,
        }),
      );
      if (holds.isEmpty) {
        // New edits created after mapping also need durable release evidence.
        final existing = await _select(
          db,
          'SELECT op_id FROM mutation_mapping_holds WHERE op_id=?',
          [original.opId],
        );
        if (existing.isNotEmpty) continue;
        await db.customStatement(
          "INSERT INTO mutation_mapping_holds(op_id,mapping_source_id,user_id,reason,disposition,created_at) VALUES(?,?,?,'CANONICAL_MAPPING','BLOCK',?)",
          [original.opId, source, db.userId, now],
        );
      }
      await db.customStatement(
        'INSERT INTO local_mutations(op_id,user_id,entity_type,entity_id,operation,base_revision,base_payload,payload,request_hash,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)',
        [
          replacement,
          db.userId,
          original.entity.code,
          original.entityId,
          original.operation.code,
          original.baseRevision,
          original.basePayload,
          plan.payloadJson,
          sha256
              .convert(
                utf8.encode(
                  canonicalJson({
                    'original': original.opId,
                    'payload': plan.payloadJson,
                    'mapping': source,
                  }),
                ),
              )
              .toString(),
          now,
          now,
        ],
      );
      await db.customStatement(
        "INSERT INTO mutation_retry_controls(op_id,automatic_retries_claimed,retry_mode,last_attempt_kind) VALUES(?,0,'INITIAL','INITIAL')",
        [replacement],
      );
      await db.customStatement(
        'INSERT INTO mutation_supersessions(original_op_id,replacement_op_id,mapping_source_id,user_id,order_root_op_id,logical_order,created_at) VALUES(?,?,?,?,?,?,?)',
        [
          original.opId,
          replacement,
          source,
          db.userId,
          original.opId,
          original.localOrder,
          now,
        ],
      );
      await _release(
        db,
        original.opId,
        source,
        now,
        canonicalJson({
          'contract': _contract,
          'original_op_id': original.opId,
          'replacement_op_id': replacement,
          'metadata_before': copies.single.data,
        }),
      );
      if (copy.localJson != null) {
        final local = jsonDecode(copy.localJson!) as Map<String, dynamic>;
        if (local['song_id'] == source) {
          await db.customStatement(
            'UPDATE metadata_copies SET local_payload=?,updated_at=? WHERE entity_type=? AND entity_id=?',
            [
              canonicalJson({...local, 'song_id': target}),
              now,
              original.entity.code,
              original.entityId,
            ],
          );
        }
      }
      changed = true;
    }
  }
  return changed;
}

Future<void> _release(
  AccountDatabase db,
  String op,
  String source,
  int now,
  String evidence,
) => db.customStatement(
  'UPDATE mutation_mapping_holds SET released_at=?,release_evidence=? WHERE op_id=? AND mapping_source_id=? AND released_at IS NULL',
  [now, evidence, op, source],
);

Future<bool> _canFollow(
  AccountDatabase db,
  QueuedMutation original,
  MetadataCopy copy,
  String source,
  String target,
) async {
  if (original.entity != LocalEntity.recording ||
      original.baseRevision != 0 ||
      original.operation != LocalOperation.patch ||
      original.basePayload != null ||
      copy.localJson == null ||
      copy.serverJson == null ||
      copy.tombstone) {
    return false;
  }
  final requested = jsonDecode(original.payload);
  final local = jsonDecode(copy.localJson!);
  final server = jsonDecode(copy.serverJson!);
  if (requested is! Map<String, dynamic> ||
      requested.containsKey('song_id') ||
      local is! Map<String, dynamic> ||
      local['song_id'] != target ||
      server is! Map<String, dynamic> ||
      server['song_id'] != target ||
      server['revision'] != copy.revision) {
    return false;
  }
  final edges = await _select(
    db,
    'SELECT * FROM mutation_supersessions',
  );
  final rows = await _select(
    db,
    'SELECT rowid AS local_order,* FROM local_mutations WHERE entity_type=? AND entity_id=? ORDER BY rowid',
    [original.entity.code, original.entityId],
  );
  final byId = {for (final row in rows) row.read<String>('op_id'): row};
  final retired = <String>{};
  final orders = <String, int>{};
  var mappedCreate = false;
  for (final edge in edges) {
    final old = byId[edge.read<String>('original_op_id')];
    final next = byId[edge.read<String>('replacement_op_id')];
    if (old == null && next == null) continue;
    if (old == null || next == null ||
        edge.read<String>('mapping_source_id') != source) {
      return false;
    }
    if (await canonicalReferenceEdge(db, edge, old, next) != true) return false;
    retired.add(old.read<String>('op_id'));
    orders[next.read<String>('op_id')] = edge.read<int>('logical_order');
    if (old.read<String>('operation') == 'CREATE') mappedCreate = true;
  }
  if (!mappedCreate) return false;
  // Compose the same validated followup and conflict-resolution projections
  // as dispatch, so a resolved conflict inherits its original logical position.
  final active = await _select(
    db,
    'SELECT op_id FROM mutation_mapping_holds WHERE released_at IS NULL',
  );
  final followups = await metadataFollowupEligibility(
    db,
    MappingEligibility(
      blocked: {
        for (final hold in active)
          if (hold.read<String>('op_id') != original.opId)
            hold.read<String>('op_id'),
      },
      superseded: retired,
      logicalOrders: orders,
      groups: const {},
    ),
  );
  final eligibility = await applyConflictEligibility(db, followups);
  if (!eligibility.allows(original.opId)) return false;
  retired.addAll(eligibility.superseded);
  orders.addAll(eligibility.logicalOrders);
  final previous =
      rows
          .where(
            (r) =>
                !retired.contains(r.read<String>('op_id')) &&
                (orders[r.read<String>('op_id')] ??
                        r.read<int>('local_order')) <
                    original.localOrder,
          )
          .toList()
        ..sort(
          (a, b) =>
              (orders[a.read<String>('op_id')] ?? a.read<int>('local_order'))
                  .compareTo(
                    orders[b.read<String>('op_id')] ??
                        b.read<int>('local_order'),
                  ),
        );
  if (previous.isEmpty ||
      previous.any((r) =>
          r.read<String>('queue_state') != 'ACKED' ||
          !eligibility.allows(r.read<String>('op_id')))) {
    return false;
  }
  final prior = _mutation(previous.last);
  final wires = await _select(
    db,
    'SELECT * FROM mutation_wire_requests WHERE op_id=?',
    [prior.opId],
  );
  if (wires.length != 1 || prior.serverResponse == null) return false;
  final wire = wires.single;
  final request = MutationRequest(
    mutation: prior,
    method: wire.read<String>('http_method'),
    path: wire.read<String>('relative_path'),
    body: wire.read<String>('body_json'),
    attempt: prior.attemptCount,
  );
  if (wire.read<String>('contract_version') != MutationRequest.contract ||
      wire.read<String>('wire_hash') != request.hash ||
      request.body != prior.payload) {
    return false;
  }
  try {
    return MetadataFollowupPlan.derive(
          original: original,
          predecessor: request,
          receipt: MutationResponse(200, prior.serverResponse!),
          predecessorLogicalOrder: orders[prior.opId] ?? prior.localOrder,
          current: server,
          tombstone: false,
        ) !=
        null;
  } on FormatException {
    return false;
  }
}
