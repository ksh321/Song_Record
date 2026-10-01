import 'dart:convert';

import 'package:drift/drift.dart';

import 'account_database.dart';
import 'conflict_eligibility.dart';
import 'local_models.dart';
import 'recording_followup_store.dart';

/// Requires the caller's account transaction.
///
/// Supported supersession:
/// - one edge only;
/// - original is an unattempted PENDING PATCH;
/// - replacement is a PATCH on the same logical target;
/// - target is SONG, RECORDING or PLAYLIST_ITEM;
/// - root and logical order match the original physical row.
///
/// Unsupported components remain visible but cannot dispatch. Graph grouping
/// below reserves ordering only; it does not resolve or flatten alias routes.
Future<MappingEligibility> readMappingEligibility(
  AccountDatabase database,
) async {
  final aliases = await database.customSelect('''
    SELECT source_song_id,canonical_song_id FROM song_aliases
  ''').get();
  final supersessions = await database.customSelect('''
    SELECT * FROM mutation_supersessions
  ''').get();
  final holds = await database.customSelect('''
    SELECT op_id FROM mutation_mapping_holds WHERE released_at IS NULL
  ''').get();

  // Preserve the common no-mapping path without scanning historical payloads.
  if (aliases.isEmpty && supersessions.isEmpty && holds.isEmpty) {
    return applyConflictEligibility(
      database,
      await recordingFollowupEligibility(
        database,
        const MappingEligibility.empty(),
      ),
    );
  }
  final mutations = await database.customSelect('''
    SELECT rowid AS local_order,op_id,entity_type,entity_id,operation,queue_state,attempt_count,payload,base_payload FROM local_mutations
  ''').get();

  final byOp = {for (final row in mutations) row.read<String>('op_id'): row};

  LocalTarget targetOf(QueryRow row) => LocalTarget(
    LocalEntity.values.firstWhere(
      (entity) => entity.code == row.read<String>('entity_type'),
    ),
    row.read<String>('entity_id'),
  );

  final parent = <LocalTarget, LocalTarget>{};

  LocalTarget root(LocalTarget target) {
    parent.putIfAbsent(target, () => target);
    var current = target;
    while (parent[current] != current) {
      current = parent[current]!;
    }
    return current;
  }

  void join(LocalTarget a, LocalTarget b) {
    final left = root(a);
    final right = root(b);
    if (left != right) parent[right] = left;
  }

  for (final row in mutations) {
    root(targetOf(row));
  }

  final sources = <String>{
    for (final row in aliases) row.read<String>('source_song_id'),
  };

  for (final alias in aliases) {
    join(
      LocalTarget(LocalEntity.song, alias.read<String>('source_song_id')),
      LocalTarget(LocalEntity.song, alias.read<String>('canonical_song_id')),
    );
  }

  // Preserve the alias-only equivalence relation for validating replacements.
  // Supersession edges must not manufacture target equivalence.
  final aliasGroups = {
    for (final target in parent.keys.toList()) target: root(target),
  };

  final quarantinedTargets = <LocalTarget>{};
  for (final alias in aliases) {
    final destination = alias.read<String>('canonical_song_id');
    if (sources.contains(destination)) {
      // Includes the entire connected chain, without selecting a final route.
      quarantinedTargets.add(LocalTarget(LocalEntity.song, destination));
    }
  }

  // Even an unsupported cross-target edge reserves both affected targets.
  // Unrelated connected components remain eligible.
  for (final edge in supersessions) {
    final original = byOp[edge.read<String>('original_op_id')];
    final replacement = byOp[edge.read<String>('replacement_op_id')];
    if (original != null && replacement != null) {
      join(targetOf(original), targetOf(replacement));
    }
  }

  final originals = {
    for (final edge in supersessions) edge.read<String>('original_op_id'),
  };
  final replacements = {
    for (final edge in supersessions) edge.read<String>('replacement_op_id'),
  };
  final activeHolds = {for (final hold in holds) hold.read<String>('op_id')};

  final blocked = <String>{...activeHolds};
  final superseded = <String>{};
  final logicalOrders = <String, int>{};

  for (final edge in supersessions) {
    final originalId = edge.read<String>('original_op_id');
    final replacementId = edge.read<String>('replacement_op_id');
    final original = byOp[originalId];
    final replacement = byOp[replacementId];

    if (original == null || replacement == null) {
      // Foreign keys normally exclude this, but never dispatch the known side
      // of an incomplete imported history.
      blocked.addAll([originalId, replacementId]);
      if (original != null) quarantinedTargets.add(targetOf(original));
      if (replacement != null) quarantinedTargets.add(targetOf(replacement));
      continue;
    }

    final originalTarget = targetOf(original);
    final replacementTarget = targetOf(replacement);
    final sameLogicalTarget =
        aliasGroups[originalTarget] == aliasGroups[replacementTarget];
    final supported =
        !replacements.contains(originalId) &&
        !originals.contains(replacementId) &&
        {
          LocalEntity.song,
          LocalEntity.recording,
          LocalEntity.playlistItem,
        }.contains(originalTarget.entity) &&
        sameLogicalTarget &&
        original.read<String>('operation') == 'PATCH' &&
        replacement.read<String>('operation') == 'PATCH' &&
        original.read<String>('queue_state') == 'PENDING' &&
        original.read<int>('attempt_count') == 0 &&
        replacement.read<int>('local_order') >
            original.read<int>('local_order') &&
        edge.read<String>('order_root_op_id') == originalId &&
        edge.read<int>('logical_order') == original.read<int>('local_order');

    if (!supported) {
      quarantinedTargets.addAll([originalTarget, replacementTarget]);
      continue;
    }

    superseded.add(originalId);
    logicalOrders[replacementId] = edge.read<int>('logical_order');

    if (activeHolds.contains(originalId)) {
      // Retiring the original must not discard its unresolved hold, including
      // when its replacement has already left the pending queue.
      quarantinedTargets.add(originalTarget);
    }
  }

  bool referencesSource(String? text) {
    if (text == null) return false;
    try {
      final value = jsonDecode(text);
      return value is Map<String, dynamic> &&
          sources.contains(value['song_id']);
    } on FormatException {
      return true; // Cannot safely establish reference eligibility.
    }
  }

  for (final row in mutations) {
    final opId = row.read<String>('op_id');
    final target = targetOf(row);

    if (activeHolds.contains(opId) &&
        row.read<String>('queue_state') == 'ACKED') {
      // An unresolved hold must not silently disappear through ACK filtering.
      quarantinedTargets.add(target);
    }

    if (sources.isEmpty) continue;

    if (target.entity == LocalEntity.song && sources.contains(target.id)) {
      blocked.add(opId);
    }

    if ((target.entity == LocalEntity.recording ||
            target.entity == LocalEntity.playlistItem) &&
        (referencesSource(row.read<String>('payload')) ||
            referencesSource(row.readNullable<String>('base_payload')))) {
      // Covers PATCH bodies omitting song_id and immutable frozen requests.
      // An explicit null/new reference is conservatively held if its baseline
      // still references a source; resolution belongs to the later mapper work.
      blocked.add(opId);
    }
  }

  final quarantinedGroups = {
    for (final target in quarantinedTargets) root(target),
  };
  for (final row in mutations) {
    if (quarantinedGroups.contains(root(targetOf(row)))) {
      blocked.add(row.read<String>('op_id'));
    }
  }

  return applyConflictEligibility(
    database,
    await recordingFollowupEligibility(
      database,
      MappingEligibility(
        blocked: blocked,
        superseded: superseded,
        logicalOrders: logicalOrders,
        groups: {
          for (final target in parent.keys.toList()) target: root(target),
        },
      ),
    ),
  );
}
