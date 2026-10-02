import 'dart:convert';

import '../database/local_models.dart';
import '../domain/identifiers.dart';
import 'mutation_request.dart';

/// Only an identity substitution, never a merge or a revision rebase.
final class CanonicalReferencePlan {
  CanonicalReferencePlan._(this.payloadJson);
  final String payloadJson;

  static CanonicalReferencePlan? derive({
    required QueuedMutation original,
    required String sourceId,
    required String canonicalId,
    required MetadataCopy current,
    required bool hasFrozenRequest,
  }) {
    if (sourceId == canonicalId ||
        original.state != 'PENDING' ||
        original.attemptCount != 0 ||
        hasFrozenRequest ||
        current.tombstone ||
        current.localJson == null ||
        !{
          LocalEntity.recording,
          LocalEntity.playlistItem,
        }.contains(original.entity)) {
      return null;
    }
    try {
      if (UuidValue(sourceId).value != sourceId ||
          UuidValue(canonicalId).value != canonicalId) {
        return null;
      }
      final payload = jsonDecode(original.payload);
      final local = jsonDecode(current.localJson!);
      if (payload is! Map<String, dynamic> ||
          local is! Map<String, dynamic> ||
          payload['song_id'] != sourceId ||
          !{sourceId, canonicalId}.contains(local['song_id']) ||
          (local.containsKey('id') && local['id'] != original.entityId)) {
        return null;
      }
      final create = original.operation == LocalOperation.create;
      if (!create && original.operation != LocalOperation.patch) return null;
      if (create || original.baseRevision == 0) {
        if (original.baseRevision != 0 ||
            original.basePayload != null ||
            current.revision != 0 ||
            current.serverJson != null) {
          return null;
        }
      } else {
        final base = original.basePayload == null
            ? null
            : jsonDecode(original.basePayload!);
        final server = current.serverJson == null
            ? null
            : jsonDecode(current.serverJson!);
        if (base is! Map<String, dynamic> ||
            server is! Map<String, dynamic> ||
            current.revision != original.baseRevision ||
            base['revision'] != original.baseRevision ||
            base['id'] != original.entityId ||
            !base.containsKey('song_id') ||
            canonicalJson(base) != canonicalJson(server)) {
          return null;
        }
      }
      // A relink PATCH uses the dedicated /song route. Never mix user edits
      // into it or infer song_id from a historical baseline.
      if (!create &&
          (payload.length != 2 ||
              payload['base_revision'] != original.baseRevision)) {
        return null;
      }
      if (create && payload['id'] != original.entityId) return null;
      if (original.entity == LocalEntity.playlistItem) {
        if (create) {
          final playlist = payload['playlist_id'];
          if (playlist is! String || UuidValue(playlist).value != playlist) {
            return null;
          }
        }
      }
      final changed = canonicalJson({...payload, 'song_id': canonicalId});
      final candidate = QueuedMutation(
        opId: original.opId,
        localOrder: original.localOrder,
        entity: original.entity,
        entityId: original.entityId,
        operation: original.operation,
        state: 'PENDING',
        baseRevision: original.baseRevision,
        basePayload: original.basePayload,
        payload: changed,
        attemptCount: 0,
      );
      // The exact offline link shape is retained until its CREATE ACK provides
      // a revision through the existing metadata followup ledger.
      if (original.entity == LocalEntity.recording &&
          !(original.operation == LocalOperation.patch &&
              original.baseRevision == 0) &&
          MutationRequest.prepare(candidate) == null) {
        return null;
      }
      return CanonicalReferencePlan._(changed);
    } on FormatException {
      return null;
    }
  }
}
