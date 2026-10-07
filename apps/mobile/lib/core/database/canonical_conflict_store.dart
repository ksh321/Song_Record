import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../domain/identifiers.dart';
import '../sync/canonical_conflict_plan.dart';
import '../sync/conflict_resolution_plan.dart';
import 'account_database.dart';
import 'local_models.dart';

/// Caller owns the account transaction and lease. All retained evidence is
/// immutable; resolution proof supplements it rather than replacing it.
final class CanonicalConflictStore {
  CanonicalConflictStore(this.db, this.requireActive);
  final AccountDatabase db;
  final void Function() requireActive;

  Future<List<CanonicalConflictReview>> list() async {
    final rows = await db.customSelect(
      "SELECT intent_id FROM canonical_edit_intents WHERE kind IN ('SONG_VALUES','SONG_MUTATION') AND state<>'RESOLVED' ORDER BY created_at,intent_id",
    ).get();
    return [for (final row in rows) await review(row.read<String>('intent_id'))];
  }

  Future<CanonicalConflictReview> review(String id) async {
    requireActive();
    final intent = await db.customSelect(
      'SELECT * FROM canonical_edit_intents WHERE intent_id=? AND user_id=?',
      variables: [Variable(id), Variable(db.userId)],
    ).getSingle();
    final source = intent.read<String>('mapping_source_id');
    final alias = await db.customSelect(
      'SELECT * FROM song_aliases WHERE source_song_id=?',
      variables: [Variable(source)],
    ).getSingle();
    final target = alias.read<String>('canonical_song_id');
    final copies = await db.customSelect(
      "SELECT * FROM metadata_copies WHERE entity_type='SONG' AND entity_id IN (?,?) ORDER BY entity_id",
      variables: [Variable(source), Variable(target)],
    ).get();
    final queue = await db.customSelect(
      "SELECT rowid AS local_order,* FROM local_mutations WHERE entity_type='SONG' AND entity_id IN (?,?) ORDER BY rowid",
      variables: [Variable(source), Variable(target)],
    ).get();
    final holds = await db.customSelect(
      'SELECT * FROM mutation_mapping_holds WHERE mapping_source_id=? ORDER BY op_id,reason',
      variables: [Variable(source)],
    ).get();
    final intents = await db.customSelect(
      'SELECT * FROM canonical_edit_intents WHERE mapping_source_id=? ORDER BY intent_id',
      variables: [Variable(source)],
    ).get();
    final evidence = canonicalJson({
      'intent': intent.data, 'alias': alias.data,
      'copies': [for (final row in copies) row.data],
      'queue': [for (final row in queue) row.data],
      'holds': [for (final row in holds) row.data],
      'intents': [for (final row in intents) row.data],
    });
    String? serverJson, candidateJson, reason;
    try {
      final chained = await db.customSelect(
        'SELECT source_song_id FROM song_aliases WHERE source_song_id=? OR canonical_song_id=?',
        variables: [Variable(target), Variable(source)],
      ).get();
      if (chained.isNotEmpty || alias.read<String>('user_id') != db.userId) {
        throw StateError('Unsupported alias route');
      }
      final copy = copies.singleWhere((r) => r.read<String>('entity_id') == target);
      if (copy.read<int>('tombstone') != 0 || copy.read<int>('server_revision') <= 0) {
        throw StateError('Canonical song unavailable');
      }
      serverJson = copy.read<String>('server_payload');
      final server = jsonDecode(serverJson) as Map<String, dynamic>;
      if (server['id'] != target ||
          server['revision'] != copy.read<int>('server_revision') ||
          (server.containsKey('user_id') && server['user_id'] != db.userId)) {
        throw StateError('Canonical identity differs');
      }
      final saved = jsonDecode(intent.read<String>('evidence_json')) as Map<String, dynamic>;
      if (saved['version'] != 1) throw StateError('Unknown candidate evidence');
      Map<String, dynamic> values;
      if (intent.read<String>('kind') == 'SONG_VALUES') {
        final before = saved['source_before'] as Map<String, dynamic>;
        final mappingRequest = queue.singleWhere((r) =>
            r.read<String>('op_id') == alias.read<String>('mapping_op_id'));
        if (saved['canonical_song_id'] != target || before['entity_id'] != source ||
            before['user_id'] != db.userId ||
            intent.read<String>('origin_op_id') != alias.read<String>('mapping_op_id') ||
            mappingRequest.read<String>('queue_state') != 'ACKED') {
          throw StateError('Candidate source differs');
        }
        values = jsonDecode(before['local_payload'] as String) as Map<String, dynamic>;
      } else if (intent.read<String>('kind') == 'SONG_MUTATION') {
        final before = saved['mutation_before'] as Map<String, dynamic>;
        final origin = queue.singleWhere((r) => r.read<String>('op_id') == intent.read<String>('origin_op_id'));
        if (!_unchangedOrigin(before, origin.data) || !_replaceable(origin.data)) {
          throw StateError('Original request is uncertain or changed');
        }
        final originHolds = await db.customSelect(
          'SELECT * FROM mutation_mapping_holds WHERE op_id=?',
          variables: [Variable(origin.read<String>('op_id'))],
        ).get();
        if (originHolds.isEmpty || originHolds.any((r) =>
            r.readNullable<String>('intent_id') != id ||
            r.read<String>('mapping_source_id') != source ||
            r.read<String>('reason') != 'CANONICAL_MAPPING')) {
          throw StateError('Other mapping evidence still owns this request');
        }
        values = jsonDecode(origin.read<String>('payload')) as Map<String, dynamic>;
        if (values.keys.any((key) => key != 'base_revision' && !canonicalSongFields.contains(key))) {
          throw StateError('Unsupported personal fields');
        }
      } else {
        throw StateError('Reference changes use their existing resolver');
      }
      final candidate = <String, dynamic>{
        for (final key in canonicalSongFields)
          if (values.containsKey(key)) key: values[key],
      };
      prepareCanonicalPatch(server, candidate, ConflictChoice.local);
      candidateJson = canonicalJson(candidate);
    } catch (_) {
      reason = '원본 요청의 전송 결과·곡 상태·매핑 근거를 확인해야 해요. 입력은 보존돼요.';
    }
    requireActive();
    return CanonicalConflictReview(
      intentId: id, state: intent.read<String>('state'), evidence: evidence,
      serverJson: serverJson, candidateJson: candidateJson, blockedReason: reason,
    );
  }

  Future<void> resolve(CanonicalConflictReview expected, ConflictChoice choice,
      String newOpId, int now) async {
    final current = await review(expected.intentId);
    if (!current.canChoose || current.evidence != expected.evidence ||
        current.serverJson != expected.serverJson || current.candidateJson != expected.candidateJson) {
      throw StateError('Canonical choice changed; review again');
    }
    final captured = jsonDecode(current.evidence) as Map<String, dynamic>;
    final intent = captured['intent'] as Map<String, dynamic>;
    final alias = captured['alias'] as Map<String, dynamic>;
    final patch = prepareCanonicalPatch(current.server, current.candidate, choice);
    final target = current.server['id'] as String;
    final origin = (captured['queue'] as List<dynamic>).cast<Map<String, dynamic>>()
        .singleWhere((r) => r['op_id'] == intent['origin_op_id']);
    final targetCopy = (captured['copies'] as List<dynamic>).cast<Map<String, dynamic>>()
        .singleWhere((r) => r['entity_id'] == target);
    final localText = targetCopy['local_payload'] as String?;
    final local = localText == null ? null : jsonDecode(localText) as Map<String, dynamic>;
    // A canonical draft can predate the mapping without having a sendable
    // request. Do not mistake that independently retained input for our choice.
    final preserveLocal = local != null && canonicalSongFields.any((key) =>
        canonicalJson({'v': local[key]}) != canonicalJson({'v': current.server[key]}) &&
        (!current.candidate.containsKey(key) ||
            canonicalJson({'v': local[key]}) != canonicalJson({'v': current.candidate[key]})));
    final opId = patch == null ? null : UuidValue(newOpId).value;
    final proof = canonicalJson({
      'version': 'canonical-choice-v1', 'intent_id': current.intentId,
      'source': intent['mapping_source_id'], 'target': target,
      'intent_evidence': intent['evidence_json'], 'alias': alias,
      'origin': origin, 'server': current.server, 'candidate': current.candidate,
      'choice': choice.name, 'patch': patch, 'op_id': opId,
      'preserved_local': preserveLocal ? localText : null,
    });
    if (opId != null) {
      await db.customStatement('''INSERT INTO local_mutations(
        op_id,user_id,entity_type,entity_id,operation,base_revision,base_payload,
        payload,request_hash,created_at,updated_at) VALUES(?,?,'SONG',?,'PATCH',?,?,?,?,?,?)''', [
        opId, db.userId, target, current.server['revision'], canonicalJson(current.server),
        patch, sha256.convert(utf8.encode(proof)).toString(), now, now,
      ]);
      await db.customStatement(
        "INSERT INTO mutation_retry_controls(op_id,automatic_retries_claimed,retry_mode,last_attempt_kind) VALUES(?,0,'INITIAL','INITIAL')", [opId],
      );
    }
    await db.customStatement('''UPDATE canonical_edit_intents
      SET state=?,resolution_json=?,resolution_op_id=?,resolved_at=? WHERE intent_id=? AND state='OPEN' ''', [
      opId == null ? 'RESOLVED' : 'QUEUED', proof, opId,
      opId == null ? now : null, current.intentId,
    ]);
    if (intent['kind'] == 'SONG_MUTATION') {
      await db.customStatement('''UPDATE mutation_mapping_holds SET released_at=?,release_evidence=?
        WHERE intent_id=? AND op_id=? AND mapping_source_id=? AND reason='CANONICAL_MAPPING' AND released_at IS NULL''',
        [now, proof, current.intentId, origin['op_id'], intent['mapping_source_id']]);
    }
    // Only replace the displayed draft if no other request still owns it.
    // Source copies and their retained pre-mapping values are never overwritten.
    final remaining = await db.customSelect(
      "SELECT op_id FROM local_mutations WHERE entity_type='SONG' AND entity_id=? AND queue_state<>'ACKED' AND op_id<>? AND op_id<>?",
      variables: [Variable(target), Variable(origin['op_id'] as String), Variable(opId ?? '')],
    ).get();
    if (remaining.isEmpty && !preserveLocal) {
      final draft = <String, dynamic>{...current.server};
      if (patch != null) {
        draft.addAll(jsonDecode(patch) as Map<String, dynamic>);
        draft.remove('base_revision');
      }
      await db.customStatement(
        "UPDATE metadata_copies SET local_payload=?,updated_at=? WHERE entity_type='SONG' AND entity_id=?",
        [canonicalJson(draft), now, target],
      );
    }
    requireActive();
  }
}

Future<bool> canonicalKeepsDraft(AccountDatabase db, String opId) async {
  final seen = <String>{};
  String? current = opId;
  while (current != null && seen.add(current)) {
    final intents = await db.customSelect(
      "SELECT resolution_json FROM canonical_edit_intents WHERE resolution_op_id=? AND kind IN ('SONG_VALUES','SONG_MUTATION')",
      variables: [Variable(current)],
    ).get();
    if (intents.any((row) => (jsonDecode(row.read<String>('resolution_json')) as Map)['preserved_local'] != null)) {
      return true;
    }
    final previous = await db.customSelect(
      'SELECT original_op_id FROM mutation_conflict_resolutions WHERE replacement_op_id=? UNION ALL SELECT original_op_id FROM pending_edit_resolutions WHERE replacement_op_id=?',
      variables: [Variable(current), Variable(current)],
    ).getSingleOrNull();
    current = previous?.read<String>('original_op_id');
  }
  return false;
}

bool _replaceable(Map<String, dynamic> row) {
  if (row['operation'] != 'PATCH') return false;
  if (row['queue_state'] == 'PENDING' && row['attempt_count'] == 0) return true;
  if (row['queue_state'] != 'CONFLICT') return false;
  final response = jsonDecode(row['server_response'] as String? ?? '{}');
  return response is Map && response['status'] == 409 && response['code'] == 'REVISION_CONFLICT';
}

bool _unchangedOrigin(Map<String, dynamic> saved, Map<String, dynamic> row) =>
    saved.entries.every((entry) => row[entry.key] == entry.value);

/// Validate proof before retiring held originals or assigning replacement
/// order. A bad proof never removes an existing quarantine.
Future<MappingEligibility> canonicalChoiceEligibility(
  AccountDatabase db, MappingEligibility mapping, Set<LocalTarget> quarantined,
) async {
  final intents = await db.customSelect(
    "SELECT * FROM canonical_edit_intents WHERE kind IN ('SONG_VALUES','SONG_MUTATION') AND state<>'OPEN'",
  ).get();
  final blocked = {...mapping.blocked}, superseded = {...mapping.superseded};
  final orders = {...mapping.logicalOrders};
  for (final intent in intents) {
    final op = intent.readNullable<String>('resolution_op_id');
    final originId = intent.read<String>('origin_op_id');
    try {
      final proof = jsonDecode(intent.read<String>('resolution_json')) as Map<String, dynamic>;
      final source = intent.read<String>('mapping_source_id');
      final alias = await db.customSelect('SELECT * FROM song_aliases WHERE source_song_id=?',
        variables: [Variable(source)]).getSingle();
      final target = alias.read<String>('canonical_song_id');
      final group = mapping.groupOf(LocalTarget(LocalEntity.song, target));
      final chain = await db.customSelect(
        'SELECT source_song_id FROM song_aliases WHERE source_song_id=? OR canonical_song_id=?',
        variables: [Variable(target), Variable(source)],
      ).get();
      final origin = await db.customSelect('SELECT rowid AS local_order,* FROM local_mutations WHERE op_id=?',
        variables: [Variable(originId)]).getSingle();
      if (chain.isNotEmpty || quarantined.contains(group) ||
          intent.read<String>('user_id') != db.userId ||
          alias.read<String>('user_id') != db.userId ||
          origin.read<String>('user_id') != db.userId ||
          proof['version'] != 'canonical-choice-v1' ||
          proof['intent_id'] != intent.read<String>('intent_id') ||
          proof['intent_evidence'] != intent.read<String>('evidence_json') ||
          proof['source'] != source || proof['target'] != target || proof['op_id'] != op ||
          canonicalJson(proof['alias'] as Map<String, dynamic>) != canonicalJson(alias.data) ||
          !_unchangedOrigin(proof['origin'] as Map<String, dynamic>, origin.data)) {
        throw StateError('Invalid canonical choice evidence');
      }
      final server = proof['server'] as Map<String, dynamic>;
      if (server['id'] != target || (server.containsKey('user_id') && server['user_id'] != db.userId)) {
        throw StateError('Wrong canonical owner');
      }
      final retained = jsonDecode(intent.read<String>('evidence_json')) as Map<String, dynamic>;
      Map<String, dynamic> values;
      if (intent.read<String>('kind') == 'SONG_VALUES') {
        final before = retained['source_before'] as Map<String, dynamic>;
        if (retained['canonical_song_id'] != target || before['entity_id'] != source ||
            originId != alias.read<String>('mapping_op_id') ||
            origin.read<String>('queue_state') != 'ACKED') {
          throw StateError('Invalid mapping value origin');
        }
        values = jsonDecode(before['local_payload'] as String) as Map<String, dynamic>;
      } else {
        if (!_unchangedOrigin(retained['mutation_before'] as Map<String, dynamic>, origin.data) ||
            ![source, target].contains(origin.read<String>('entity_id'))) {
          throw StateError('Personal request origin changed');
        }
        values = jsonDecode(origin.read<String>('payload')) as Map<String, dynamic>;
      }
      final candidate = <String, dynamic>{for (final key in canonicalSongFields)
        if (values.containsKey(key)) key: values[key]};
      if (canonicalJson(candidate) != canonicalJson(proof['candidate'] as Map<String, dynamic>)) {
        throw StateError('Candidate differs from retained input');
      }
      final patch = prepareCanonicalPatch(server, proof['candidate'] as Map<String, dynamic>,
        ConflictChoice.values.byName(proof['choice'] as String));
      if (patch != proof['patch'] || (patch == null) != (op == null)) {
        throw StateError('Invalid chosen patch');
      }
      if (op != null) {
        final replacement = await db.customSelect('SELECT rowid AS local_order,* FROM local_mutations WHERE op_id=?',
          variables: [Variable(op)]).getSingle();
        if (replacement.read<String>('user_id') != db.userId ||
            replacement.read<String>('entity_type') != 'SONG' ||
            replacement.read<String>('entity_id') != target ||
            replacement.read<String>('operation') != 'PATCH' ||
            replacement.read<int>('local_order') <= origin.read<int>('local_order') ||
            replacement.read<int>('base_revision') != server['revision'] ||
            replacement.readNullable<String>('base_payload') != canonicalJson(server) ||
            replacement.read<String>('payload') != patch ||
            replacement.read<String>('request_hash') != sha256.convert(utf8.encode(intent.read<String>('resolution_json'))).toString()) {
          throw StateError('Replacement differs from selected request');
        }
        orders[op] = origin.read<int>('local_order');
      }
      if (intent.read<String>('kind') == 'SONG_MUTATION') {
        if (!_replaceable(origin.data)) throw StateError('Uncertain original');
        final holds = await db.customSelect('SELECT * FROM mutation_mapping_holds WHERE op_id=?',
          variables: [Variable(originId)]).get();
        if (holds.isEmpty || holds.any((r) =>
            r.readNullable<int>('released_at') == null ||
            r.readNullable<String>('intent_id') != intent.read<String>('intent_id') ||
            r.readNullable<String>('release_evidence') != intent.read<String>('resolution_json'))) {
          throw StateError('Unresolved original holds');
        }
        blocked.remove(originId);
        superseded.add(originId);
      }
    } catch (_) {
      blocked.add(originId);
      if (op != null) blocked.add(op);
    }
  }
  return MappingEligibility(blocked: blocked, superseded: superseded,
    logicalOrders: orders, groups: mapping.groups);
}

/// Called only after an owned network ACK or an explicit subsequent conflict
/// resolution. Reads alone cannot complete a queued canonical selection.
Future<void> finishCanonicalChoices(AccountDatabase db, MappingEligibility mapping, int now) async {
  final intents = await db.customSelect("SELECT intent_id,resolution_op_id FROM canonical_edit_intents WHERE state='QUEUED' AND kind IN ('SONG_VALUES','SONG_MUTATION')").get();
  for (final intent in intents) {
    var op = intent.read<String>('resolution_op_id');
    final seen = <String>{};
    var complete = false;
    while (seen.add(op) && !mapping.blocked.contains(op)) {
      final row = await db.customSelect('SELECT queue_state FROM local_mutations WHERE op_id=?', variables: [Variable(op)]).getSingle();
      if (row.read<String>('queue_state') == 'ACKED') { complete = true; break; }
      if (!mapping.superseded.contains(op)) break;
      final resolution = await db.customSelect('SELECT replacement_op_id FROM mutation_conflict_resolutions WHERE original_op_id=? UNION ALL SELECT replacement_op_id FROM pending_edit_resolutions WHERE original_op_id=?', variables: [Variable(op), Variable(op)]).getSingleOrNull();
      if (resolution == null) break;
      final next = resolution.readNullable<String>('replacement_op_id');
      if (next == null) { complete = true; break; }
      op = next;
    }
    if (complete) {
      await db.customStatement("UPDATE canonical_edit_intents SET state='RESOLVED',resolved_at=? WHERE intent_id=? AND state='QUEUED'", [now, intent.read<String>('intent_id')]);
    }
  }
}
