import 'dart:convert';

import '../database/local_models.dart';
import 'metadata_response.dart';
import 'mutation_request.dart';

/// A proposal only. The account transaction must verify ordering/ownership,
/// persist a fresh op_id and its evidence, and retire the original atomically.
/// It must never update the original payload or an existing frozen wire.
final class MetadataFollowupPlan {
  MetadataFollowupPlan._(
    this.originalOpId,
    this.predecessorOpId,
    this.revision,
    this.baselineJson,
    this.payloadJson,
  );

  final String originalOpId, predecessorOpId;
  final int revision;
  final String baselineJson, payloadJson;

  static MetadataFollowupPlan? derive({
    required QueuedMutation original,
    required MutationRequest predecessor,
    required MutationResponse receipt,
    required int predecessorLogicalOrder,
    required Map<String, dynamic> current,
    required bool tombstone,
  }) {
    final prior = predecessor.mutation;
    if (!{
          LocalEntity.recording,
          LocalEntity.song,
          LocalEntity.tag,
        }.contains(original.entity) ||
        original.operation != LocalOperation.patch ||
        original.baseRevision != 0 ||
        original.basePayload != null ||
        original.state != 'PENDING' ||
        original.attemptCount != 0 ||
        prior.entity != original.entity ||
        prior.entityId != original.entityId ||
        prior.opId == original.opId ||
        prior.state != 'ACKED' ||
        prior.attemptCount < 1 ||
        predecessor.attempt != prior.attemptCount ||
        predecessorLogicalOrder < 1 ||
        predecessorLogicalOrder >= original.localOrder ||
        tombstone) {
      return null;
    }
    final requested = jsonDecode(original.payload);
    if (requested is! Map<String, dynamic> || requested['base_revision'] != 0) {
      throw const FormatException('Invalid offline followup evidence');
    }
    final snapshot = decodeMetadataSnapshot(predecessor, receipt);
    final revision = snapshot['revision'];
    // A newer pull is a real change, not permission to rebase automatically.
    if (snapshot['id'] != original.entityId ||
        revision is! int ||
        current['id'] != original.entityId ||
        current['revision'] != revision ||
        canonicalJson(current) != canonicalJson(snapshot)) {
      return null;
    }
    final payload = canonicalJson({...requested, 'base_revision': revision});
    final candidate = QueuedMutation(
      opId: original.opId,
      localOrder: original.localOrder,
      entity: original.entity,
      entityId: original.entityId,
      operation: original.operation,
      state: original.state,
      baseRevision: revision,
      payload: payload,
      basePayload: canonicalJson(snapshot),
      attemptCount: 0,
    );
    // Unsupported routes remain intact; never resolve a dependency by dropping
    // request fields. Caller will allocate a different ID when committing.
    if (MutationRequest.prepare(candidate) == null) return null;
    return MetadataFollowupPlan._(
      original.opId,
      prior.opId,
      revision,
      canonicalJson(snapshot),
      payload,
    );
  }

  @override
  String toString() => 'MetadataFollowupPlan[REDACTED]';
}
