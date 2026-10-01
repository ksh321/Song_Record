import '../sync/change_payload_validation.dart';
import 'local_models.dart';

/// The untouched raw snapshot retains owner, deletion and creation metadata.
/// Supplies SONG/TAG and retained Condition business wire shapes.
Map<String, dynamic> projectSnapshotMetadata(
  LocalEntity entity,
  Map<String, dynamic> source, {
  required String owner,
  required String id,
}) {
  if (source['user_id'] != owner || source['id'] != id) {
    throw const FormatException('Snapshot metadata identity changed');
  }
  final fields = switch (entity) {
    LocalEntity.song => {
      'id',
      'revision',
      'updated_at',
      'source_type',
      'tj_number',
      'title',
      'artist',
      'version_code',
      'tier',
      'note',
      'lifecycle_state',
      'representative_recording_id',
      'representative_key_mode',
      'representative_key_shift',
      'created_at',
      'latest_recorded_at',
    },
    LocalEntity.tag => {'id', 'revision', 'updated_at', 'name', 'archived_at'},
    LocalEntity.recordingCondition => {
      'id',
      'revision',
      'updated_at',
      'name',
      'code',
      'archived_at',
    },
    _ => throw const FormatException(
      'Snapshot metadata adapter not implemented',
    ),
  };
  final result = <String, dynamic>{
    for (final field in fields)
      if (source.containsKey(field)) field: source[field],
  };
  validateChangePayload(entity, result);
  return result;
}
