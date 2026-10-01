import '../domain/input_validation.dart';

/// File metadata is independent of uploading a verified server audio copy.
bool validRecordingFileSpec(Object? value) {
  if (value is! Map<String, dynamic>) return false;
  const keys = {
    'sha256',
    'size_bytes',
    'duration_ms',
    'codec',
    'sample_rate',
    'channels',
    'capture_integrity',
  };
  if (value.length != keys.length || !value.keys.every(keys.contains)) {
    return false;
  }
  final size = value['size_bytes'], duration = value['duration_ms'];
  final hash = value['sha256'];
  return hash is String &&
      RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) &&
      size is int &&
      size >= 1 &&
      size <= 6291456 &&
      duration is int &&
      duration >= 1 &&
      duration <= 361000 &&
      value['codec'] == 'AAC_LC' &&
      value['sample_rate'] is int &&
      value['sample_rate'] == 48000 &&
      value['channels'] is int &&
      value['channels'] == 1 &&
      {'VALIDATED', 'RECOVERED'}.contains(value['capture_integrity']);
}

bool validRecordingSaveRequest(Map<String, dynamic> value, int revision) {
  const allowed = {
    'base_revision',
    'metadata_state',
    'file',
    'title_snapshot',
    'artist_snapshot',
    'version_code',
    'key_mode',
    'key_shift',
    'note',
  };
  for (final entry in {
    'title_snapshot': InputField.title,
    'artist_snapshot': InputField.artist,
    'note': InputField.note,
  }.entries) {
    if (!value.containsKey(entry.key)) continue;
    final raw = value[entry.key];
    if (raw == null && entry.key == 'note') continue;
    if (raw is! String || !validateInput(entry.value, raw).isValid) {
      return false;
    }
  }
  if (value.containsKey('version_code') &&
      !{'NORMAL', 'MR', 'LIVE'}.contains(value['version_code'])) {
    return false;
  }
  if (value.containsKey('key_mode') &&
      !{'ORIGINAL', 'MALE', 'FEMALE'}.contains(value['key_mode'])) {
    return false;
  }
  final shift = value['key_shift'];
  if (value.containsKey('key_shift') &&
      (shift is! int || shift < -12 || shift > 12)) {
    return false;
  }
  return revision > 0 &&
      value['base_revision'] == revision &&
      value['metadata_state'] == 'SAVED' &&
      value.keys.every(allowed.contains) &&
      validRecordingFileSpec(value['file']);
}
