import '../database/local_models.dart';
import '../domain/identifiers.dart';

void _require(bool valid) {
  if (!valid) throw const FormatException('Invalid change entity payload');
}

/// Current change writers emit SONG, RECORDING and TAG snapshots. This validates
/// their wire fields and the legacy Condition response without normalizing
/// historical values or inventing missing
/// relations. Other writers need an explicit adapter before a cursor can pass.
void validateChangePayload(LocalEntity entity, Map<String, dynamic> value) {
  void fields(Set<String> required, Set<String> optional) => _require(
    value.keys.toSet().containsAll(required) &&
        value.keys.every(
          (key) => required.contains(key) || optional.contains(key),
        ),
  );
  void text(String key, int min, int max, {bool nullable = false}) {
    final v = value[key];
    if (v == null && nullable) return;
    _require(v is String && v.runes.length >= min && v.runes.length <= max);
  }

  void choice(String key, Set<String> choices, {bool nullable = false}) =>
      _require(nullable && value[key] == null || choices.contains(value[key]));
  void number(String key, int min, int max, {bool nullable = false}) {
    final v = value[key];
    _require(nullable && v == null || v is int && v >= min && v <= max);
  }

  void uuid(String key, {bool nullable = false}) {
    final v = value[key];
    if (v == null && nullable) return;
    _require(v is String && UuidValue(v).value == v);
  }

  void time(String key, {bool nullable = false}) {
    final v = value[key];
    if (v == null && nullable) return;
    _require(
      v is String &&
          RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$')
              .hasMatch(v),
    );
    final parsed = DateTime.tryParse(v as String);
    _require(
      parsed != null &&
          parsed.year >= 1000 &&
          parsed.toUtc().toIso8601String().substring(0, 19) ==
              v.substring(0, 19),
    );
  }

  void key(String mode, String shift) {
    choice(mode, {'ORIGINAL', 'MALE', 'FEMALE'}, nullable: true);
    number(shift, -12, 12, nullable: true);
    _require((value[mode] == null) == (value[shift] == null));
    _require(value[mode] != 'ORIGINAL' || value[shift] == 0);
  }

  const common = {'id', 'revision', 'updated_at'};
  switch (entity) {
    case LocalEntity.song:
      fields(
        {
          ...common,
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
        },
        {'created_at', 'latest_recorded_at'},
      );
      choice('source_type', {'TJ', 'MANUAL'});
      final tj = value['tj_number'];
      _require(
        value['source_type'] == 'MANUAL'
            ? tj == null
            : tj is String && RegExp(r'^[0-9]{1,20}$').hasMatch(tj),
      );
      text('title', 1, 200);
      text('artist', 1, 200);
      text('note', 0, 2000, nullable: true);
      choice('version_code', {'NORMAL', 'MR', 'LIVE'});
      choice('tier', {'S', 'A', 'B', 'C', 'D'}, nullable: true);
      choice('lifecycle_state', {
        'ACTIVE',
        'TRASHED',
        'PURGE_PENDING',
        'PURGED',
      });
      uuid('representative_recording_id', nullable: true);
      key('representative_key_mode', 'representative_key_shift');
      if (value.containsKey('created_at')) time('created_at');
      if (value.containsKey('latest_recorded_at')) {
        time('latest_recorded_at', nullable: true);
      }
    case LocalEntity.tag:
      fields({...common, 'name', 'archived_at'}, {});
      text('name', 1, 50);
      time('archived_at', nullable: true);
    case LocalEntity.recordingCondition:
      // D06 keeps old definitions readable; this never enables custom writes.
      fields({...common, 'name', 'code', 'archived_at'}, {});
      text('name', 1, 50);
      time('archived_at', nullable: true);
      final code = value['code'];
      _require(
        {'VERY_GOOD', 'GOOD', 'NORMAL', 'BAD'}.contains(code) ||
            code is String &&
                code == value['id'] &&
                UuidValue(code).value == code,
      );
    case LocalEntity.playlist:
      // Header shape from the account snapshot source. Item ordering has its
      // own parent-revision contract and is not inferred from this header.
      fields({...common, 'name', 'deleted_at'}, {'created_at'});
      text('name', 1, 100);
      time('deleted_at', nullable: true);
      if (value.containsKey('created_at')) time('created_at');
    case LocalEntity.recording:
      fields(
        {
          ...common,
          'metadata_state',
          'song_id',
          'title_snapshot',
          'artist_snapshot',
          'version_code',
          'key_mode',
          'key_shift',
          'note',
          'recorded_at',
          'timezone_id',
          'timezone_offset_minutes',
          'origin_device_id',
          'link_revision',
          'lifecycle_state',
        },
        {
          'file',
          'tier',
          'tags',
          'tag_ids',
          'condition_code',
          'condition_name_snapshot',
        },
      );
      choice('metadata_state', {'DRAFT', 'SAVED'});
      choice('lifecycle_state', {
        'ACTIVE',
        'TRASHED',
        'PURGE_PENDING',
        'PURGED',
      });
      choice('version_code', {'NORMAL', 'MR', 'LIVE'});
      uuid('song_id', nullable: true);
      uuid('origin_device_id');
      text('title_snapshot', 1, 200, nullable: true);
      text('artist_snapshot', 1, 200, nullable: true);
      text('note', 0, 2000);
      text('timezone_id', 1, 64);
      number('timezone_offset_minutes', -1080, 1080);
      number('link_revision', 1, 9223372036854775807);
      time('recorded_at');
      key('key_mode', 'key_shift');
      final condition = value['condition_code'];
      _require(
        value.containsKey('condition_code') ==
            value.containsKey('condition_name_snapshot'),
      );
      if (condition != null &&
          !{'VERY_GOOD', 'GOOD', 'NORMAL', 'BAD'}.contains(condition)) {
        uuid('condition_code');
      }
      text('condition_name_snapshot', 1, 50, nullable: true);
      if (value.containsKey('tier')) {
        choice('tier', {'S', 'A', 'B', 'C', 'D'}, nullable: true);
      }
      _require(value.containsKey('tags') == value.containsKey('tag_ids'));
      if (value.containsKey('tags')) {
        final ids = value['tag_ids'], tags = value['tags'];
        _require(ids is List && tags is List);
        final seen = <String>{};
        for (final id in ids as List) {
          _require(id is String && UuidValue(id).value == id && seen.add(id));
        }
        final names = <String>{};
        for (final tag in tags as List) {
          _require(
            tag is Map<String, dynamic> &&
                tag.length == 2 &&
                tag['id'] is String &&
                seen.contains(tag['id']) &&
                names.add(tag['id'] as String) &&
                tag['name_snapshot'] is String &&
                (tag['name_snapshot'] as String).runes.isNotEmpty &&
                (tag['name_snapshot'] as String).runes.length <= 50,
          );
        }
        _require(seen.length == names.length);
      }
      if (value.containsKey('file')) {
        final file = value['file'];
        const keys = {
          'size_bytes',
          'duration_ms',
          'sha256',
          'codec',
          'sample_rate',
          'channels',
          'capture_integrity',
        };
        _require(
          file is Map<String, dynamic> &&
              file.length == keys.length &&
              file.keys.every(keys.contains),
        );
        final f = file as Map<String, dynamic>;
        final Object? size = f['size_bytes'],
            duration = f['duration_ms'],
            hash = f['sha256'];
        _require(size is int && size >= 1 && size <= 6291456);
        _require(duration is int && duration >= 1 && duration <= 361000);
        _require(hash is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(hash));
        _require(
          f['codec'] == 'AAC_LC' &&
              f['sample_rate'] is int &&
              f['sample_rate'] == 48000 &&
              f['channels'] is int &&
              f['channels'] == 1 &&
              {'VALIDATED', 'RECOVERED'}.contains(f['capture_integrity']),
        );
      }
    default:
      throw const FormatException(
        'Change entity wire adapter is not implemented',
      );
  }
  uuid('id');
  number('revision', 1, 9223372036854775807);
  time('updated_at');
}
