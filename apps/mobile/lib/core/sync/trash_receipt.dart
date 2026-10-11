import '../database/local_models.dart';
import '../domain/identifiers.dart';
import 'change_payload_validation.dart';
import 'mutation_request.dart';
import 'wire_json.dart';

/// Validate the whole receipt before acknowledging any member. No file I/O.
Map<String, dynamic> decodeTrashReceipt(
  MutationRequest request,
  MutationResponse response,
) {
  final value = decodeWireJson(response.body);
  if (response.status != 200 || value is! Map<String, dynamic>) {
    throw const FormatException('Invalid trash receipt');
  }
  final song = request.mutation.entity == LocalEntity.song;
  final required = song
      ? {'batch_id', 'mode', 'deleted_at', 'purge_after', 'song', 'recordings'}
      : {'batch_id', 'deleted_at', 'purge_after', 'recording'};
  if (value.length != required.length ||
      !value.keys.every(required.contains) ||
      value['batch_id'] is! String) {
    throw const FormatException('Invalid trash fields');
  }
  UuidValue(value['batch_id'] as String);
  DateTime utc(Object? time) {
    if (time is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$')
            .hasMatch(time)) {
      throw const FormatException('Invalid server trash time');
    }
    final date = DateTime.tryParse(time);
    if (date == null ||
        date.toIso8601String().substring(0, 19) != time.substring(0, 19)) {
      throw const FormatException('Invalid server trash date');
    }
    return date;
  }

  if (utc(value['purge_after']).difference(utc(value['deleted_at'])) !=
      const Duration(days: 7)) {
    throw const FormatException('Invalid trash lifetime');
  }
  final primary = value[song ? 'song' : 'recording'];
  if (primary is! Map<String, dynamic>) {
    throw const FormatException('Missing trash snapshot');
  }
  validateChangePayload(request.mutation.entity, primary);
  if (primary['id'] != request.mutation.entityId ||
      (song
          ? (primary['revision'] as int) <= request.mutation.baseRevision
          : primary['revision'] != request.mutation.baseRevision + 1) ||
      primary['lifecycle_state'] != 'TRASHED' ||
      primary['deleted_at'] != value['deleted_at']) {
    throw const FormatException('Trash identity/revision/time mismatch');
  }
  if (song) {
    final sent = decodeWireJson(request.body) as Map;
    if (value['mode'] != sent['mode'] || value['recordings'] is! List) {
      throw const FormatException('Trash scope mismatch');
    }
    final seen = <String>{};
    for (final row in value['recordings'] as List) {
      if (row is! Map<String, dynamic>) {
        throw const FormatException('Invalid retained recording');
      }
      validateChangePayload(LocalEntity.recording, row);
      if (!seen.add(row['id'] as String) ||
          row['song_id'] != null ||
          row['lifecycle_state'] !=
              (value['mode'] == 'SONG_ONLY' ? 'ACTIVE' : 'TRASHED') ||
          (value['mode'] != 'SONG_ONLY' &&
              row['deleted_at'] != value['deleted_at'])) {
        throw const FormatException('Invalid recording trash scope');
      }
    }
  }
  return value;
}
