import 'dart:convert';

import '../database/local_models.dart';
import 'change_payload_validation.dart';
import 'conflict_resolution_plan.dart';
import 'mutation_request.dart';

const canonicalSongFields = <String>{
  'title', 'artist', 'version_code', 'tier', 'note',
  'representative_key_mode', 'representative_key_shift',
};

/// Different song identities have no shared editing baseline. Every differing
/// value requires a choice; this is deliberately not a three-way merge.
final class CanonicalConflictReview {
  const CanonicalConflictReview({
    required this.intentId,
    required this.state,
    required this.evidence,
    this.serverJson,
    this.candidateJson,
    this.blockedReason,
  });
  final String intentId, state, evidence;
  final String? serverJson, candidateJson, blockedReason;
  bool get canChoose => state == 'OPEN' && blockedReason == null;
  Map<String, dynamic> get server =>
      jsonDecode(serverJson!) as Map<String, dynamic>;
  Map<String, dynamic> get candidate =>
      jsonDecode(candidateJson!) as Map<String, dynamic>;
  Map<String, dynamic>? get latestDraft {
    final captured = jsonDecode(evidence);
    if (captured is! Map || captured['copies'] is! List) return null;
    for (final copy in captured['copies'] as List<dynamic>) {
      if (copy is Map && copy['entity_id'] == server['id'] && copy['local_payload'] is String) {
        return jsonDecode(copy['local_payload'] as String) as Map<String, dynamic>;
      }
    }
    return null;
  }
  @override
  String toString() => 'CanonicalConflictReview[REDACTED]';
}

abstract interface class CanonicalConflictActions {
  Future<List<CanonicalConflictReview>> canonicalCandidates();
  Future<CanonicalConflictReview> reviewCanonical(String intentId);
  Future<void> resolveCanonical(
    CanonicalConflictReview review, ConflictChoice choice,
  );
}

String? prepareCanonicalPatch(
  Map<String, dynamic> server,
  Map<String, dynamic> candidate,
  ConflictChoice choice,
) {
  validateChangePayload(LocalEntity.song, server);
  if (server['lifecycle_state'] != 'ACTIVE' ||
      (server['revision'] as int) <= 0 ||
      candidate.isEmpty ||
      candidate.keys.any((key) => !canonicalSongFields.contains(key))) {
    throw StateError('Unsupported canonical personal edit');
  }
  // Validate even a discarded candidate. Corrupt evidence cannot authorize a
  // hold release merely because the server side was selected.
  validateChangePayload(LocalEntity.song, {...server, ...candidate});
  final patch = <String, dynamic>{};
  if (choice == ConflictChoice.local) {
    for (final key in candidate.keys) {
      if (canonicalJson({'v': candidate[key]}) !=
          canonicalJson({'v': server[key]})) {
        patch[key] = candidate[key];
      }
    }
    if (patch.containsKey('representative_key_mode') ||
        patch.containsKey('representative_key_shift')) {
      for (final key in ['representative_key_mode', 'representative_key_shift']) {
        patch[key] = candidate.containsKey(key) ? candidate[key] : server[key];
      }
    }
  }
  if (patch.isEmpty) return null;
  final body = canonicalJson({'base_revision': server['revision'], ...patch});
  if (MutationRequest.prepare(QueuedMutation(
    opId: server['id'] as String,
    localOrder: 0,
    entity: LocalEntity.song,
    entityId: server['id'] as String,
    operation: LocalOperation.patch,
    state: 'PENDING',
    baseRevision: server['revision'] as int,
    payload: body,
    attemptCount: 0,
  )) == null) {
    throw StateError('Canonical selection has no PATCH route');
  }
  return body;
}
