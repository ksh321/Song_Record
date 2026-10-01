import 'dart:convert';

import '../database/local_models.dart';
import 'change_payload_validation.dart';
import 'mutation_request.dart';
import 'three_way_merge.dart';

/// Read-only preview for supported revision conflicts. A candidate patch is not
/// permission to mutate/retry the original op_id or discard its retained input.
/// null means this conflict needs another explicit resolution path.
ThreeWayComparison? compareMetadataConflict(QueuedMutation mutation) {
  if (mutation.state != 'CONFLICT' ||
      mutation.operation != LocalOperation.patch ||
      !{LocalEntity.song, LocalEntity.tag}.contains(mutation.entity) ||
      mutation.basePayload == null ||
      mutation.serverResponse == null) {
    return null;
  }
  final response = jsonDecode(mutation.serverResponse!);
  if (response is! Map<String, dynamic> ||
      response['code'] != 'REVISION_CONFLICT' ||
      response['status'] != 409) {
    return null;
  }
  final base = jsonDecode(mutation.basePayload!);
  final server = response['current'];
  final patch = jsonDecode(mutation.payload);
  if (base is! Map<String, dynamic> ||
      server is! Map<String, dynamic> ||
      patch is! Map<String, dynamic> ||
      base['id'] != mutation.entityId ||
      server['id'] != mutation.entityId ||
      base['revision'] != mutation.baseRevision ||
      patch['base_revision'] != mutation.baseRevision ||
      MutationRequest.prepare(mutation) == null) {
    throw const FormatException('Invalid metadata conflict evidence');
  }
  validateChangePayload(mutation.entity, base);
  validateChangePayload(mutation.entity, server);
  if ((server['revision'] as int) <= mutation.baseRevision) {
    throw const FormatException('Revision conflict must have a newer server');
  }
  if (mutation.entity == LocalEntity.song) {
    if (base['lifecycle_state'] != 'ACTIVE' ||
        server['lifecycle_state'] != 'ACTIVE') {
      return null;
    }
    if (base['source_type'] != server['source_type'] ||
        base['tj_number'] != server['tj_number']) {
      throw const FormatException('Immutable song source changed');
    }
  } else if (base['archived_at'] != null || server['archived_at'] != null) {
    return null;
  }
  final changes = Map<String, dynamic>.from(patch)..remove('base_revision');
  // Validate the intended local state as well as the remote evidence. The
  // generic comparer deliberately does not know domain field constraints.
  validateChangePayload(mutation.entity, {...base, ...changes});
  return compareThreeWayPatch(
    base: base,
    localChanges: changes,
    server: server,
    editableFields: mutation.entity == LocalEntity.tag
        ? {'name'}
        : {
            'title',
            'artist',
            'version_code',
            'tier',
            'note',
            'representative_key_mode',
            'representative_key_shift',
          },
    atomicGroups: mutation.entity == LocalEntity.song
        ? [
            {'representative_key_mode', 'representative_key_shift'},
          ]
        : const [],
  );
}
