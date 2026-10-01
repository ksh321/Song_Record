import '../sync/change_payload_validation.dart';
import 'local_models.dart';
import 'snapshot_download_store.dart';

/// Projects only the recording's business view. The original snapshot rows,
/// deletion fields and relation history remain untouched in snapshot storage.
Map<String, dynamic>? projectSnapshotRecording(
  SnapshotRecordingBaseline bundle,
) {
  final parent = bundle.recording;
  if (parent == null) return null;
  final source = parent.payload;
  const fields = {
    'id',
    'revision',
    'updated_at',
    'metadata_state',
    'song_id',
    'title_snapshot',
    'artist_snapshot',
    'version_code',
    'key_mode',
    'key_shift',
    'tier',
    'note',
    'recorded_at',
    'timezone_id',
    'timezone_offset_minutes',
    'origin_device_id',
    'link_revision',
    'lifecycle_state',
    'condition_code',
    'condition_name_snapshot',
  };
  final result = <String, dynamic>{
    for (final key in fields)
      if (source.containsKey(key)) key: source[key],
    'tag_ids': [for (final tag in bundle.tags) tag.payload['tag_id']],
    'tags': [
      for (final tag in bundle.tags)
        {
          'id': tag.payload['tag_id'],
          'name_snapshot': tag.payload['name_snapshot'],
        },
    ],
  };
  if (bundle.file case final file?) {
    final payload = file.payload;
    result['file'] = <String, dynamic>{
      for (final key in [
        'sha256',
        'size_bytes',
        'duration_ms',
        'codec',
        'sample_rate',
        'channels',
        'capture_integrity',
      ])
        if (payload.containsKey(key)) key: payload[key],
    };
  }
  validateChangePayload(LocalEntity.recording, result);
  return result;
}
