import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../database/local_models.dart';

/// Durable wire identity. Credentials are deliberately supplied only at send time.
final class MutationRequest {
  MutationRequest({
    required this.mutation,
    required this.method,
    required this.path,
    required this.body,
    required this.attempt,
  });
  static const contract = 'metadata-v1';
  final QueuedMutation mutation;
  final String method, path, body;
  final int attempt;
  String get hash => sha256
      .convert(
        utf8.encode(
          canonicalJson({
            'contract': contract,
            'method': method,
            'path': path,
            'body': body,
          }),
        ),
      )
      .toString();

  /// Only implemented server routes. Unsupported legacy queues remain intact.
  static MutationRequest? prepare(QueuedMutation m) {
    final route = switch (m.entity) {
      LocalEntity.song => 'songs',
      LocalEntity.recording => 'recordings',
      LocalEntity.tag => 'tags',
      _ => null,
    };
    if (route == null ||
        !{LocalOperation.create, LocalOperation.patch}.contains(m.operation)) {
      return null;
    }
    final decoded = jsonDecode(m.payload);
    if (decoded is! Map<String, dynamic>) return null;
    final create = m.operation == LocalOperation.create;
    if (m.entity == LocalEntity.recording &&
        !create &&
        decoded.containsKey('tier')) {
      if (decoded.length != 2 ||
          decoded['base_revision'] != m.baseRevision ||
          m.baseRevision < 1 ||
          (decoded['tier'] != null &&
              !{'S', 'A', 'B', 'C', 'D'}.contains(decoded['tier']))) {
        return null;
      }
      return MutationRequest(
        mutation: m,
        method: 'PATCH',
        path: '/v1/recordings/${m.entityId}/tier',
        body: m.payload,
        attempt: m.attemptCount + 1,
      );
    }
    final allowed = switch ((m.entity, create)) {
      (LocalEntity.song, true) => {
        'id',
        'source_type',
        'source_token',
        'title',
        'artist',
        'manual_reason',
        'version_code',
        'tier',
        'note',
      },
      (LocalEntity.song, false) => {
        'base_revision',
        'title',
        'artist',
        'version_code',
        'tier',
        'note',
        'representative_key_mode',
        'representative_key_shift',
      },
      (LocalEntity.recording, true) => {
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
        'condition_code',
      },
      (LocalEntity.recording, false) => {
        'base_revision',
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
      },
      (LocalEntity.tag, true) => {'id', 'name'},
      (LocalEntity.tag, false) => {'base_revision', 'name'},
      _ => <String>{},
    };
    if (decoded.keys.any((key) => !allowed.contains(key))) return null;
    if (create && decoded['id'] != m.entityId ||
        !create && decoded['base_revision'] != m.baseRevision) {
      return null;
    }
    if (m.entity == LocalEntity.recording &&
        create &&
        decoded['metadata_state'] != 'DRAFT') {
      return null;
    }
    final condition = decoded['condition_code'];
    if (condition != null &&
        !{'VERY_GOOD', 'GOOD', 'NORMAL', 'BAD'}.contains(condition)) {
      return null;
    }
    return MutationRequest(
      mutation: m,
      method: create ? 'POST' : 'PATCH',
      path: '/v1/$route${create ? '' : '/${m.entityId}'}',
      body: m.payload,
      attempt: m.attemptCount + 1,
    );
  }

  @override
  String toString() => 'MutationRequest[REDACTED]';
}

final class MutationResponse {
  const MutationResponse(this.status, this.body);
  final int status;
  final String body;
  @override
  String toString() => 'MutationResponse[REDACTED]';
}
