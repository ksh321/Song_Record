import 'dart:convert';

import 'package:drift/drift.dart';

import '../sync/conflict_resolution_plan.dart';
import 'account_database.dart';
import 'local_models.dart';

/// Read within the caller's account transaction. Resolution history never
/// rewrites queue state; it only retires original requests from dispatch and
/// gives replacement requests the original logical position.
Future<MappingEligibility> applyConflictEligibility(
  AccountDatabase db,
  MappingEligibility mapping,
  {bool holdDrafts = true}
) async {
  mapping = await pendingEditEligibility(db, mapping);
  final resolutions = await db
      .customSelect('SELECT * FROM mutation_conflict_resolutions')
      .get();
  if (resolutions.isEmpty) return mapping;
  final rows = await db
      .customSelect('SELECT rowid AS local_order,* FROM local_mutations')
      .get();
  final byId = {for (final row in rows) row.read<String>('op_id'): row};
  final followupRows = await db.customSelect(
    'SELECT replacement_op_id,logical_order FROM recording_followups',
  ).get();
  final followupOrders = {
    for (final row in followupRows)
      row.read<String>('replacement_op_id'): row.read<int>('logical_order'),
  };
  final predecessor = {
    for (final row in resolutions)
      if (row.readNullable<String>('replacement_op_id') case final String id)
        id: row,
  };
  final blocked = {...mapping.blocked};
  final superseded = {...mapping.superseded};
  final orders = {...mapping.logicalOrders};
  final quarantine = <LocalTarget>{};
  LocalTarget target(QueryRow row) => LocalTarget(
    LocalEntity.values.firstWhere(
      (e) => e.code == row.read<String>('entity_type'),
    ),
    row.read<String>('entity_id'),
  );
  void reject(QueryRow? original, QueryRow? replacement) {
    for (final row in [original, replacement]) {
      if (row != null) quarantine.add(mapping.groupOf(target(row)));
    }
  }

  for (final resolution in resolutions) {
    final id = resolution.read<String>('original_op_id');
    final replacementId = resolution.readNullable<String>('replacement_op_id');
    final original = byId[id], replacement = byId[replacementId];
    var valid =
        original != null && (replacementId == null || replacement != null);
    if (valid) {
      final proof = jsonDecode(resolution.read<String>('server_snapshot'));
      final response = jsonDecode(
        original.readNullable<String>('server_response') ?? '{}',
      );
      final revision = resolution.read<int>('resolved_revision');
      final previous = predecessor[id];
      valid =
          original.read<String>('user_id') == db.userId &&
          resolution.read<String>('user_id') == db.userId &&
          {
            'SONG',
            'RECORDING',
            'TAG',
          }.contains(original.read<String>('entity_type')) &&
          original.read<String>('operation') == 'PATCH' &&
          original.read<String>('queue_state') == 'CONFLICT' &&
          original.read<int>('attempt_count') ==
              resolution.read<int>('original_attempt_count') &&
          response is Map<String, dynamic> &&
          response['status'] == 409 &&
          response['code'] == 'REVISION_CONFLICT' &&
          response['current'] is Map<String, dynamic> &&
          (response['current'] as Map<String, dynamic>)['revision'] is int &&
          revision >=
              ((response['current'] as Map<String, dynamic>)['revision']
                  as int) &&
          proof is Map<String, dynamic> &&
          proof['id'] == original.read<String>('entity_id') &&
          proof['revision'] is int &&
          proof['revision'] == revision &&
          (!proof.containsKey('user_id') || proof['user_id'] == db.userId) &&
          revision > original.read<int>('base_revision') &&
          resolution.read<String>('order_root_op_id') ==
              (previous?.read<String>('order_root_op_id') ?? id) &&
          resolution.read<int>('logical_order') ==
              (previous?.read<int>('logical_order') ??
                  followupOrders[id] ??
                  original.read<int>('local_order')) &&
          !mapping.blocked.contains(id) &&
          !mapping.superseded.contains(id);
      if (replacement != null) {
        final payload = jsonDecode(replacement.read<String>('payload'));
        valid =
            valid &&
            replacement.read<String>('user_id') == db.userId &&
            target(replacement) == target(original) &&
            replacement.read<String>('operation') == 'PATCH' &&
            replacement.read<int>('local_order') >
                original.read<int>('local_order') &&
            replacement.read<int>('base_revision') == revision &&
            replacement.readNullable<String>('base_payload') ==
                resolution.read<String>('server_snapshot') &&
            payload is Map<String, dynamic> &&
            payload['base_revision'] is int &&
            payload['base_revision'] == revision &&
            !mapping.blocked.contains(replacementId) &&
            !mapping.superseded.contains(replacementId);
      }
    }
    if (!valid) {
      reject(original, replacement);
      blocked.add(id);
      if (replacementId != null) blocked.add(replacementId);
      continue;
    }
    // A draft queued behind the user's resolved conflict is not itself an
    // approved replay of that older baseline. Preserve the existing hold even
    // when an unrelated received revision now permits initial conflict probes.
    final effectiveOrder =
        mapping.logicalOrders[resolution.read<String>('order_root_op_id')] ??
        resolution.read<int>('logical_order');
    for (final candidate in rows) {
      final candidateId = candidate.read<String>('op_id');
      final base = candidate.read<int>('base_revision');
      final order = orders[candidateId] ?? candidate.read<int>('local_order');
      if (holdDrafts && !superseded.contains(candidateId) &&
          candidate.read<String>('queue_state') == 'PENDING' &&
          candidate.read<String>('operation') == 'PATCH' &&
          candidate.read<int>('attempt_count') == 0 &&
          mapping.groupOf(target(candidate)) ==
              mapping.groupOf(target(original!)) &&
          order > effectiveOrder &&
          base > 0 &&
          base < resolution.read<int>('resolved_revision')) {
        blocked.add(candidateId);
      }
    }
    superseded.add(id);
    if (replacementId != null) {
      orders[replacementId] = effectiveOrder;
    }
  }
  for (final row in rows) {
    if (quarantine.contains(mapping.groupOf(target(row)))) {
      blocked.add(row.read<String>('op_id'));
    }
  }
  return MappingEligibility(
    blocked: blocked,
    superseded: superseded,
    logicalOrders: orders,
    groups: mapping.groups,
  );
}

/// Validate explicit pending-edit decisions before projecting retirement/order.
/// The original stays PENDING with zero attempts and no synthetic response.
Future<MappingEligibility> pendingEditEligibility(
  AccountDatabase db, MappingEligibility mapping,
) async {
  final edges = await db.customSelect('SELECT e.* FROM pending_edit_resolutions e JOIN local_mutations m ON m.op_id=e.original_op_id ORDER BY m.rowid').get();
  final blocked = {...mapping.blocked}, superseded = {...mapping.superseded};
  final orders = {...mapping.logicalOrders};
  for (final edge in edges) {
    final id = edge.read<String>('original_op_id');
    final nextId = edge.readNullable<String>('replacement_op_id');
    try {
      final row = await db.customSelect('SELECT rowid AS local_order,* FROM local_mutations WHERE op_id=?', variables: [Variable(id)]).getSingle();
      if (mapping.blocked.contains(id) || mapping.superseded.contains(id) ||
          row.read<String>('user_id') != db.userId || edge.read<String>('user_id') != db.userId ||
          canonicalJson(row.data) != edge.read<String>('original_evidence') ||
          edge.read<int>('logical_order') != row.read<int>('local_order')) {
        throw StateError('Pending review source changed');
      }
      final wire = await db.customSelect('SELECT op_id FROM mutation_wire_requests WHERE op_id=?', variables: [Variable(id)]).get();
      if (wire.isNotEmpty) throw StateError('Pending review source was frozen');
      final mutation = QueuedMutation(
        opId: id, localOrder: row.read<int>('local_order'),
        entity: LocalEntity.values.firstWhere((e) => e.code == row.read<String>('entity_type')),
        entityId: row.read<String>('entity_id'), operation: LocalOperation.patch,
        state: row.read<String>('queue_state'), baseRevision: row.read<int>('base_revision'),
        payload: row.read<String>('payload'), basePayload: row.readNullable<String>('base_payload'),
        serverResponse: row.readNullable<String>('server_response'), attemptCount: row.read<int>('attempt_count'),
      );
      if (row.read<String>('operation') != 'PATCH') throw StateError('Invalid pending operation');
      final rawChoices = jsonDecode(edge.read<String>('choices')) as Map<String, dynamic>;
      final choices = <String, ConflictChoice>{};
      for (final entry in rawChoices.entries) {
        choices[entry.key] = ConflictChoice.values.singleWhere((c) => c.name.toUpperCase() == entry.value);
      }
      final server = jsonDecode(edge.read<String>('server_snapshot')) as Map<String, dynamic>;
      if (server.containsKey('user_id') && server['user_id'] != db.userId) throw StateError('Pending review owner mismatch');
      final plan = prepareConflictResolution(mutation, pendingReview: true, serverSnapshot: server, choices: choices);
      if (plan.needsRequest != (nextId != null)) throw StateError('Invalid pending result');
      if (nextId != null) {
        final next = await db.customSelect('SELECT rowid AS local_order,* FROM local_mutations WHERE op_id=?', variables: [Variable(nextId)]).getSingle();
        if (mapping.blocked.contains(nextId) || mapping.superseded.contains(nextId) ||
            next.read<String>('user_id') != db.userId || next.read<String>('entity_type') != mutation.entity.code ||
            next.read<String>('entity_id') != mutation.entityId || next.read<String>('operation') != 'PATCH' ||
            next.read<int>('local_order') <= mutation.localOrder ||
            next.read<int>('base_revision') != server['revision'] ||
            next.readNullable<String>('base_payload') != plan.serverJson ||
            next.read<String>('payload') != plan.patchJson) {
          throw StateError('Invalid pending replacement');
        }
        orders[nextId] = orders[id] ?? mutation.localOrder;
      }
      superseded.add(id);
    } catch (_) {
      blocked.add(id);
      if (nextId != null) blocked.add(nextId);
    }
  }
  return MappingEligibility(blocked: blocked, superseded: superseded, logicalOrders: orders, groups: mapping.groups);
}
