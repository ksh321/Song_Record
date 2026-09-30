import 'dart:convert';

import '../database/local_models.dart';
import '../domain/identifiers.dart';
import 'mutation_request.dart';

/// Shared mutation response validation; no database writes.
Map<String, Object?> decodeMetadataSnapshot(
  MutationRequest request,
  MutationResponse response, {
  bool conflict = false,
}) {
  final m = request.mutation;
  final decoded = jsonDecode(response.body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Expected object');
  }
  Map<String, Object?> value = decoded;
  if (!conflict &&
      m.entity == LocalEntity.song &&
      m.operation == LocalOperation.create) {
    if (decoded.keys.toSet().difference({
          'created',
          'canonical_song_id',
          'song',
        }).isNotEmpty ||
        decoded['created'] is! bool ||
        decoded['song'] is! Map<String, dynamic>) {
      throw const FormatException('Invalid creation envelope');
    }
    if (decoded['created'] != (response.status == 201)) {
      throw const FormatException('Creation status contradicts response');
    }
    value = decoded['song'] as Map<String, dynamic>;
    if (decoded['canonical_song_id'] != value['id']) {
      throw const FormatException('Canonical mismatch');
    }
  }
  void require(bool valid) {
    if (!valid) throw const FormatException('Incomplete metadata response');
  }

  void fields(Set<String> required, Set<String> optional) {
    require(value.keys.toSet().containsAll(required));
    require(
      value.keys.every(
        (key) => required.contains(key) || optional.contains(key),
      ),
    );
  }

  void string(String key, {bool nullable = false}) {
    require(value[key] is String || nullable && value[key] == null);
  }

  void integer(String key, {bool nullable = false}) {
    require(value[key] is int || nullable && value[key] == null);
  }

  void uuid(String key, {bool nullable = false}) {
    if (nullable && value[key] == null) return;
    require(value[key] is String);
    UuidValue(value[key] as String);
  }

  void time(String key, {bool nullable = false}) {
    if (nullable && value[key] == null) return;
    string(key);
    require(DateTime.tryParse(value[key] as String) != null);
  }

  switch (m.entity) {
    case LocalEntity.song:
      fields(
        {
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
        },
        {
          'created_at',
          'latest_recorded_at',
          'representative_recording_id',
          'representative_key_mode',
          'representative_key_shift',
        },
      );
      for (final key in [
        'source_type',
        'title',
        'artist',
        'version_code',
        'lifecycle_state',
      ]) {
        string(key);
      }
      for (final key in ['tj_number', 'tier', 'note']) {
        string(key, nullable: true);
      }
      for (final key in ['created_at', 'latest_recorded_at']) {
        if (value.containsKey(key)) time(key, nullable: true);
      }
      if (value.containsKey('representative_recording_id')) {
        uuid('representative_recording_id', nullable: true);
      }
    case LocalEntity.tag:
      fields({'id', 'name', 'revision', 'archived_at', 'updated_at'}, {});
      string('name');
      time('archived_at', nullable: true);
    case LocalEntity.recording:
      fields(
        {
          'id',
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
          'revision',
          'link_revision',
          'updated_at',
          'lifecycle_state',
        },
        {
          'condition_code',
          'condition_name_snapshot',
          'tag_ids',
          'tags',
          'tier',
        },
      );
      for (final key in [
        'metadata_state',
        'version_code',
        'note',
        'timezone_id',
        'lifecycle_state',
      ]) {
        string(key);
      }
      for (final key in [
        'title_snapshot',
        'artist_snapshot',
        'key_mode',
        'condition_code',
        'condition_name_snapshot',
      ]) {
        string(key, nullable: true);
      }
      if (m.operation == LocalOperation.patch) {
        require(
          value.keys.toSet().containsAll({
            'tags',
            'tag_ids',
            'tier',
            'condition_code',
            'condition_name_snapshot',
          }),
        );
        string('tier', nullable: true);
        if (!conflict && request.path.endsWith('/tier')) {
          final requested = jsonDecode(request.body) as Map<String, dynamic>;
          require(value['tier'] == requested['tier']);
          require(
            value['metadata_state'] == 'SAVED' &&
                value['lifecycle_state'] == 'ACTIVE',
          );
        }
        require(value['tags'] is List);
        for (final entry in value['tags'] as List) {
          require(
            entry is Map &&
                entry.length == 2 &&
                entry['id'] is String &&
                entry['name_snapshot'] is String,
          );
          UuidValue(entry['id'] as String);
        }
      }
      uuid('song_id', nullable: true);
      uuid('origin_device_id');
      integer('link_revision');
      integer('key_shift', nullable: true);
      integer('timezone_offset_minutes');
      time('recorded_at');
      if (value.containsKey('tag_ids')) {
        require(value['tag_ids'] is List);
        for (final tag in value['tag_ids'] as List) {
          require(tag is String);
          UuidValue(tag as String);
        }
      }
    default:
      throw const FormatException('Unsupported acknowledgement');
  }
  // The current server always returns these snapshot fields, including explicit null.
  // A missing field must never turn a locally selected value into an apparent omission.
  if (m.entity == LocalEntity.song) {
    require(
      value.keys.toSet().containsAll({
        'representative_key_mode',
        'representative_key_shift',
        'representative_recording_id',
      }),
    );
    string('representative_key_mode', nullable: true);
    integer('representative_key_shift', nullable: true);
  }
  if (m.entity == LocalEntity.recording) {
    require(
      value.keys.toSet().containsAll({
        'condition_code',
        'condition_name_snapshot',
      }),
    );
  }
  if (m.operation == LocalOperation.create && response.status == 201) {
    require(value['revision'] == 1);
  }
  uuid('id');
  integer('revision');
  time('updated_at');
  require((value['revision'] as int) > 0);
  if (!conflict && m.entity != LocalEntity.tag) {
    require(value['lifecycle_state'] == 'ACTIVE');
  }
  if (!conflict && m.operation == LocalOperation.patch) {
    require(
      response.status == 200 &&
          value['id'] == m.entityId &&
          value['revision'] == m.baseRevision + 1,
    );
  }
  if (conflict) {
    require(value['id'] == m.entityId);
  }
  // Never advance sync cursors here: mutation replies are not a gap-free change stream.
  return value;
}

/// Validated evidence for a future canonical-song store transaction.
/// Decoding alone never acknowledges or maps a mutation.
final class CanonicalSongReceipt {
  CanonicalSongReceipt._(
    this.request,
    MutationResponse response,
    Map<String, Object?> snapshot,
  ) : status = response.status,
      envelopeBody = response.body,
      snapshot = Map<String, Object?>.unmodifiable(snapshot);

  final MutationRequest request;
  final int status;

  /// Exact response text, including whitespace and envelope fields.
  final String envelopeBody;

  /// All accepted SONG fields are validated scalar JSON values or null.
  /// An unmodifiable copy therefore makes the complete snapshot immutable.
  final Map<String, Object?> snapshot;

  String get localSongId => request.mutation.entityId;
  String get canonicalSongId => snapshot['id'] as String;

  static CanonicalSongReceipt decode(
    MutationRequest request,
    MutationResponse response,
  ) {
    final mutation = request.mutation;
    if (mutation.entity != LocalEntity.song ||
        mutation.operation != LocalOperation.create ||
        request.method != 'POST' ||
        request.path != '/v1/songs' ||
        response.status != 200) {
      throw const FormatException('Not a canonical song creation response');
    }

    // Inspect the actual frozen wire body, not a reconstructed queue payload.
    final wire = jsonDecode(request.body);
    if (wire is! Map<String, dynamic> ||
        wire['id'] != mutation.entityId ||
        wire['source_type'] != 'TJ') {
      throw const FormatException('Invalid canonical song request');
    }
    UuidValue(mutation.entityId);

    // Includes envelope validation, created=false for HTTP 200, canonical
    // ID equality, full SONG shape, UUIDs, revision, timestamps and ACTIVE.
    final snapshot = decodeMetadataSnapshot(request, response);
    final canonicalId = snapshot['id'] as String;
    final number = snapshot['tj_number'];
    if (snapshot['source_type'] != 'TJ' ||
        number is! String ||
        number.isEmpty ||
        canonicalId.toLowerCase() == mutation.entityId.toLowerCase()) {
      throw const FormatException('Invalid canonical song snapshot');
    }

    if (TjNumber(number).value != number) {
      throw const FormatException('Noncanonical TJ number');
    }

    // source_token is opaque. Server proof.number establishes TJ identity;
    // the client must not compare the token with tj_number.
    return CanonicalSongReceipt._(request, response, snapshot);
  }

  @override
  String toString() => 'CanonicalSongReceipt[REDACTED]';
}
