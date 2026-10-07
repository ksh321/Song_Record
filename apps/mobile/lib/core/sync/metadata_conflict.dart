import 'dart:convert';

import '../database/local_models.dart';
import '../domain/identifiers.dart';
import 'change_payload_validation.dart';
import 'mutation_request.dart';
import 'three_way_merge.dart';

/// Read-only preview for supported revision conflicts. A candidate patch is not
/// permission to mutate/retry the original op_id or discard its retained input.
/// null means this conflict needs another explicit resolution path.
ThreeWayComparison? compareMetadataConflict(
  QueuedMutation mutation, {
  Map<String, dynamic>? serverSnapshot,
  bool pendingReview = false,
}) {
  if ((pendingReview
          ? mutation.state != 'PENDING' || mutation.attemptCount != 0 ||
              mutation.serverResponse != null || serverSnapshot == null
          : mutation.state != 'CONFLICT') ||
      mutation.operation != LocalOperation.patch ||
      !{
        LocalEntity.song,
        LocalEntity.tag,
        LocalEntity.recording,
      }.contains(mutation.entity) ||
      mutation.basePayload == null ||
      (!pendingReview && mutation.serverResponse == null)) {
    return null;
  }
  final response = pendingReview ? null : jsonDecode(mutation.serverResponse!);
  if (!pendingReview && (response is! Map<String, dynamic> ||
      response['code'] != 'REVISION_CONFLICT' ||
      response['status'] != 409)) {
    return null;
  }
  final base = jsonDecode(mutation.basePayload!);
  final originalServer = pendingReview ? serverSnapshot : (response as Map<String, dynamic>)['current'];
  if (!pendingReview && serverSnapshot != null &&
      (originalServer is! Map<String, dynamic> ||
          originalServer['revision'] is! int ||
          serverSnapshot['revision'] is! int ||
          (serverSnapshot['revision'] as int) <
              (originalServer['revision'] as int))) {
    throw const FormatException('Cannot rewind conflict evidence');
  }
  final server = serverSnapshot ?? originalServer;
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
  } else if (mutation.entity == LocalEntity.tag &&
      (base['archived_at'] != null || server['archived_at'] != null)) {
    return null;
  }
  final changes = Map<String, dynamic>.from(patch)..remove('base_revision');
  if (mutation.entity == LocalEntity.recording) {
    // Relationship moves and DRAFT -> SAVED/file transitions need their own
    // explicit handling, not a metadata-only rebase.
    if (changes.containsKey('song_id') ||
        changes.containsKey('metadata_state') ||
        changes.containsKey('file') ||
        changes.containsKey('tier') && base['metadata_state'] != 'SAVED' ||
        base['metadata_state'] != server['metadata_state'] ||
        base['lifecycle_state'] != 'ACTIVE' ||
        server['lifecycle_state'] != 'ACTIVE') {
      return null;
    }
    if (base['origin_device_id'] != server['origin_device_id']) {
      throw const FormatException('Recording origin changed');
    }
    final intended = <String, dynamic>{...base, ...changes};
    // Names are historical server snapshots, not client-editable tag fields.
    // Validate the selected ID set separately without manufacturing names.
    if (changes.containsKey('tag_ids')) {
      final ids = changes['tag_ids'];
      if (ids is! List) throw const FormatException('Invalid selected tags');
      final seen = <String>{};
      for (final id in ids) {
        if (id is! String || UuidValue(id).value != id || !seen.add(id)) {
          throw const FormatException('Invalid selected tags');
        }
      }
      intended.remove('tag_ids');
      intended.remove('tags');
    }
    validateChangePayload(mutation.entity, intended);
    for (final value in [base, server, intended]) {
      if (value['metadata_state'] == 'SAVED' &&
          (value['title_snapshot'] == null ||
              value['artist_snapshot'] == null ||
              value['key_mode'] == null)) {
        throw const FormatException('Saved recording metadata is incomplete');
      }
    }
    Map<String, dynamic> comparable(Map<String, dynamic> value) {
      final copy = Map<String, dynamic>.from(value);
      if (copy['tag_ids'] case final List<dynamic> ids) {
        copy['tag_ids'] = List<String>.from(ids)..sort();
      }
      return copy;
    }

    return compareThreeWayPatch(
      base: comparable(base),
      localChanges: comparable(changes),
      server: comparable(server),
      editableFields: {
        'title_snapshot',
        'artist_snapshot',
        'version_code',
        'key_mode',
        'key_shift',
        'note',
        'recorded_at',
        'timezone_id',
        'timezone_offset_minutes',
        'condition_code',
        'tag_ids',
        'tier',
      },
      atomicGroups: [
        {'key_mode', 'key_shift'},
        {'recorded_at', 'timezone_id', 'timezone_offset_minutes'},
      ],
    );
  }
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
