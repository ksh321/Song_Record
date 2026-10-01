import 'dart:convert';

import 'package:drift/drift.dart';

import 'account_database.dart';
import 'local_models.dart';

/// Read within the caller's account transaction. Resolution history never
/// rewrites queue state; it only retires original requests from dispatch and
/// gives replacement requests the original logical position.
Future<MappingEligibility> applyConflictEligibility(
  AccountDatabase db,
  MappingEligibility mapping,
) async {
  final resolutions = await db
      .customSelect('SELECT * FROM mutation_conflict_resolutions')
      .get();
  if (resolutions.isEmpty) return mapping;
  final rows = await db
      .customSelect('SELECT rowid AS local_order,* FROM local_mutations')
      .get();
  final byId = {for (final row in rows) row.read<String>('op_id'): row};
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
                  mapping.logicalOrders[id] ??
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
    for (final candidate in rows) {
      final candidateId = candidate.read<String>('op_id');
      final base = candidate.read<int>('base_revision');
      final order = orders[candidateId] ?? candidate.read<int>('local_order');
      if (candidate.read<String>('queue_state') == 'PENDING' &&
          candidate.read<String>('operation') == 'PATCH' &&
          candidate.read<int>('attempt_count') == 0 &&
          mapping.groupOf(target(candidate)) ==
              mapping.groupOf(target(original!)) &&
          order > resolution.read<int>('logical_order') &&
          base > 0 &&
          base < resolution.read<int>('resolved_revision')) {
        blocked.add(candidateId);
      }
    }
    superseded.add(id);
    if (replacementId != null) {
      orders[replacementId] = resolution.read<int>('logical_order');
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
