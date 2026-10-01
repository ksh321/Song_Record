import 'dart:convert';

import '../database/local_models.dart';
import 'change_payload_validation.dart';
import 'metadata_conflict.dart';
import 'mutation_request.dart';

enum ConflictChoice { local, server }

/// Detached proposal, not a persisted resolution or permission to send. The
/// account transaction must recheck the source, latest baseline and holds.
final class ConflictResolutionPlan {
  ConflictResolutionPlan._(this.serverJson, this.patchJson, this.choicesJson);
  final String serverJson;
  final String? patchJson;
  final String choicesJson;
  bool get needsRequest => patchJson != null;
  @override
  String toString() => 'ConflictResolutionPlan[REDACTED]';
}

ConflictResolutionPlan prepareConflictResolution(
  QueuedMutation mutation, {
  Map<String, ConflictChoice> choices = const {},
}) {
  final comparison = compareMetadataConflict(mutation);
  if (comparison == null) {
    throw StateError('Unsupported metadata conflict');
  }
  final base = jsonDecode(mutation.basePayload!) as Map<String, dynamic>;
  final response = jsonDecode(mutation.serverResponse!) as Map<String, dynamic>;
  final server = response['current'] as Map<String, dynamic>;
  final local = jsonDecode(mutation.payload) as Map<String, dynamic>;
  if (local['base_revision'] is! int) {
    throw const FormatException('Conflict base revision must be an integer');
  }
  final required = comparison.conflicts.expand((g) => g).toSet();
  if (choices.length != required.length ||
      choices.keys.any((key) => !required.contains(key))) {
    throw StateError('Every conflicting field needs an explicit choice');
  }
  final patch = comparison.safePatch;
  for (final group in comparison.conflicts) {
    final choice = choices[group.first]!;
    if (group.any((key) => choices[key] != choice)) {
      throw StateError('Coupled fields require one consistent choice');
    }
    if (choice == ConflictChoice.server) continue;
    for (final key in group) {
      if (!local.containsKey(key) && !base.containsKey(key)) {
        throw StateError('Local conflict value is unknown');
      }
      patch[key] = local.containsKey(key) ? local[key] : base[key];
    }
  }
  // Validate the combination, not just its separately valid inputs. Tag names
  // are server history: do not fabricate name snapshots for selected IDs.
  final merged = <String, dynamic>{...server, ...patch};
  if (mutation.entity == LocalEntity.recording &&
      patch.containsKey('tag_ids')) {
    merged.remove('tags');
    merged.remove('tag_ids');
  }
  validateChangePayload(mutation.entity, merged);
  if (mutation.entity == LocalEntity.recording &&
      merged['metadata_state'] == 'SAVED' &&
      (merged['title_snapshot'] == null ||
          merged['artist_snapshot'] == null ||
          merged['key_mode'] == null)) {
    throw const FormatException('Resolved saved metadata is incomplete');
  }
  final revision = server['revision'] as int;
  final body = patch.isEmpty
      ? null
      : canonicalJson({'base_revision': revision, ...patch});
  if (body != null &&
      MutationRequest.prepare(
            QueuedMutation(
              opId: mutation.opId,
              localOrder: mutation.localOrder,
              entity: mutation.entity,
              entityId: mutation.entityId,
              operation: LocalOperation.patch,
              state: 'PENDING',
              baseRevision: revision,
              payload: body,
              attemptCount: 0,
            ),
          ) ==
          null) {
    throw StateError('Resolved patch has no supported request route');
  }
  return ConflictResolutionPlan._(
    canonicalJson(server),
    body,
    canonicalJson({
      for (final entry in choices.entries)
        entry.key: entry.value.name.toUpperCase(),
    }),
  );
}
