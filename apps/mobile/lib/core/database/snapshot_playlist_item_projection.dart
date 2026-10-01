import 'dart:convert';

import '../domain/identifiers.dart';
import 'local_models.dart';
import 'snapshot_metadata_projection.dart';

/// All three rows must come from the same immutable account snapshot token.
/// PlaylistItem has no independent revision: its version belongs to Playlist.
Map<String, dynamic> projectSnapshotPlaylistItem(
  Map<String, dynamic> source, {
  required String owner,
  required String id,
  required Map<String, dynamic> playlist,
  Map<String, dynamic>? song,
}) {
  void require(bool valid) {
    if (!valid) throw const FormatException('Invalid snapshot playlist item');
  }

  bool uuid(Object? value) =>
      value is String && UuidValue(value).value == value;
  const fields = {
    'id',
    'user_id',
    'playlist_id',
    'song_id',
    'candidate_brand',
    'candidate_number',
    'candidate_snapshot',
    'entry_key',
    'position',
    'hidden_by_batch_id',
    'created_at',
    'updated_at',
  };
  require(source.length == fields.length && source.keys.every(fields.contains));
  require(source['user_id'] == owner && source['id'] == id && uuid(id));
  require(uuid(source['playlist_id']));
  final parent = projectSnapshotMetadata(
    LocalEntity.playlist,
    playlist,
    owner: owner,
    id: source['playlist_id'] as String,
  );
  final position = source['position'];
  require(position is int && position >= 0 && position <= 9223372036854775807);
  require(
    source['hidden_by_batch_id'] == null || uuid(source['hidden_by_batch_id']),
  );
  for (final field in ['created_at', 'updated_at']) {
    final value = source[field];
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
  final brand = source['candidate_brand'],
      number = source['candidate_number'],
      candidate = source['candidate_snapshot'];
  final hasCandidate = brand != null || number != null || candidate != null;
  require(
    !hasCandidate ||
        brand == 'TJ' &&
            number is String &&
            RegExp(r'^\d{1,20}$').hasMatch(number) &&
            candidate is Map<String, dynamic>,
  );
  final songId = source['song_id'];
  final String expectedKey;
  if (songId == null) {
    require(song == null && hasCandidate);
    expectedKey = 'tj:$number';
  } else {
    require(
      uuid(songId) &&
          song != null &&
          song['id'] == songId &&
          song['user_id'] == owner,
    );
    final type = song!['source_type'];
    require(type == 'TJ' || type == 'MANUAL');
    if (type == 'TJ') {
      final songNumber = song['tj_number'];
      require(
        songNumber is String && RegExp(r'^\d{1,20}$').hasMatch(songNumber),
      );
      require(!hasCandidate || number == songNumber);
      expectedKey = 'tj:$songNumber';
    } else {
      require(!hasCandidate && song['tj_number'] == null);
      expectedKey = 'manual:$songId';
    }
  }
  require(source['entry_key'] == expectedKey);
  return jsonDecode(
    jsonEncode({
      for (final field in fields)
        if (field != 'user_id') field: source[field],
      'revision': parent['revision'],
      'playlist_revision': parent['revision'],
      'playlist_deleted_at': parent['deleted_at'],
    }),
  ) as Map<String, dynamic>;
}
