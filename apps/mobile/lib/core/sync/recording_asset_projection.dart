import '../domain/identifiers.dart';

/// An asset version is cloud_revision, never the recording's revision.
/// This projects metadata only: it grants no download/delete/upload authority.
Map<String, dynamic> projectRecordingAsset(
  Map<String, dynamic> source, {
  required String owner,
  required String recordingId,
  int? revision,
  bool snapshot = false,
}) {
  void require(bool valid) {
    if (!valid) throw const FormatException('Invalid recording asset');
  }

  bool uuid(Object? value) =>
      value is String && UuidValue(value).value == value;
  void time(Object? value, {bool nullable = false}) {
    if (value == null && nullable) return;
    require(
      value is String &&
          RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$')
              .hasMatch(value),
    );
    final parsed = DateTime.tryParse(value as String);
    require(
      parsed != null &&
          parsed.year >= 1000 &&
          parsed.toUtc().toIso8601String().substring(0, 19) ==
              value.substring(0, 19),
    );
  }

  const fields = {
    'recording_id',
    'cloud_state',
    'blocked_reason',
    'generation',
    'verified_size',
    'sha256',
    'stored_at',
    'cloud_revision',
    'created_at',
    'updated_at',
  };
  require(source.keys.toSet().containsAll(fields));
  require(source.keys.every((key) => fields.contains(key) || key == 'user_id'));
  require(uuid(owner) && uuid(recordingId));
  require(source['recording_id'] == recordingId);
  require(!snapshot || source['user_id'] == owner);
  require(!source.containsKey('user_id') || source['user_id'] == owner);
  final version = source['cloud_revision'];
  require(version is int && version > 0 && version <= 9223372036854775807);
  require(revision == null || version == revision);
  final state = source['cloud_state'];
  require(
    {
      'NONE',
      'QUEUED',
      'UPLOADING',
      'VERIFYING',
      'STORED',
      'DELETING',
    }.contains(state),
  );
  require(
    source['blocked_reason'] == null ||
        {
          'FILE_MISSING',
          'QUOTA',
          'PIN_LIMIT',
          'BUDGET',
          'AUTH',
          'NETWORK',
          'FILE_INVALID',
        }.contains(source['blocked_reason']),
  );
  final generation = source['generation'],
      size = source['verified_size'],
      hash = source['sha256'];
  require(
    generation == null ||
        uuid(generation) &&
            generation != '00000000-0000-0000-0000-000000000000',
  );
  require(size == null || size is int && size >= 1 && size <= 6291456);
  require(
    hash == null || hash is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(hash),
  );
  time(source['stored_at'], nullable: true);
  time(source['created_at']);
  time(source['updated_at']);
  if (state == 'STORED' || state == 'DELETING') {
    require(
      generation != null &&
          size != null &&
          hash != null &&
          source['stored_at'] != null,
    );
  }
  return {
    for (final key in fields) key: source[key],
    'id': recordingId,
    'revision': version,
  };
}

/// A new policy/state revision cannot rewrite a previously verified object.
void validateAssetTransition(
  Map<String, dynamic>? previous,
  Map<String, dynamic> incoming,
) {
  if (previous == null ||
      previous['generation'] == null ||
      previous['generation'] != incoming['generation']) {
    return;
  }
  for (final field in ['sha256', 'verified_size']) {
    if (previous[field] != null && incoming[field] != previous[field]) {
      throw const FormatException(
        'Verified object changed within a generation',
      );
    }
  }
}
