import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../database/local_models.dart';
import '../domain/identifiers.dart';
import 'recording_save_contract.dart';

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
    if (m.entity == LocalEntity.playlist &&
        m.operation == LocalOperation.patch) {
      final decoded = jsonDecode(m.payload);
      if (decoded is Map<String, dynamic> && decoded.containsKey('song_ids')) {
        final ids = decoded['song_ids'];
        if (decoded.length != 2 ||
            decoded['base_revision'] != m.baseRevision ||
            m.baseRevision < 1 ||
            ids is! List ||
            ids.isEmpty ||
            ids.length > 100 ||
            ids.any((id) => id is! String) ||
            ids.toSet().length != ids.length) {
          return null;
        }
        for (final id in ids) {
          UuidValue(id as String);
        }
        return MutationRequest(
          mutation: m,
          method: 'POST',
          path: '/v1/playlists/${m.entityId}/items',
          body: m.payload,
          attempt: m.attemptCount + 1,
        );
      }
      if (decoded is Map<String, dynamic> && decoded.containsKey('item_id')) {
        if (decoded.length != 3 ||
            decoded['base_revision'] != m.baseRevision ||
            m.baseRevision < 1 ||
            decoded['item_id'] is! String ||
            decoded['song_id'] is! String) {
          return null;
        }
        UuidValue(decoded['item_id'] as String);
        UuidValue(decoded['song_id'] as String);
        return MutationRequest(
          mutation: m,
          method: 'PATCH',
          path: '/v1/playlists/${m.entityId}/items/${decoded['item_id']}/song',
          body: canonicalJson({...decoded}..remove('item_id')),
          attempt: m.attemptCount + 1,
        );
      }
      if (decoded is Map<String, dynamic> &&
          (decoded.containsKey('song_id') ||
              decoded.containsKey('source_token'))) {
        if (decoded.length != 2 ||
            decoded['base_revision'] != m.baseRevision ||
            m.baseRevision < 1 ||
            !(decoded['song_id'] is String ||
                decoded['source_token'] is String)) {
          return null;
        }
        if (decoded.containsKey('song_id')) {
          UuidValue(decoded['song_id'] as String);
        } else if ((decoded['source_token'] as String).trim().isEmpty ||
            (decoded['source_token'] as String).length > 8192) {
          return null;
        }
        return MutationRequest(
          mutation: m,
          method: 'POST',
          path: '/v1/playlists/${m.entityId}/items',
          body: m.payload,
          attempt: m.attemptCount + 1,
        );
      }
    }
    if (m.entity == LocalEntity.playlist &&
        m.operation == LocalOperation.purge) {
      final value = jsonDecode(m.payload);
      if (value is! Map<String, dynamic> ||
          value.length != 1 ||
          value['base_revision'] != m.baseRevision ||
          m.baseRevision < 1) {
        return null;
      }
      return MutationRequest(
        mutation: m,
        method: 'DELETE',
        path: '/v1/playlists/${m.entityId}',
        body: m.payload,
        attempt: m.attemptCount + 1,
      );
    }
    final route = switch (m.entity) {
      LocalEntity.song => 'songs',
      LocalEntity.recording => 'recordings',
      LocalEntity.tag => 'tags',
      LocalEntity.playlist => 'playlists',
      _ => null,
    };
    if (route == null ||
        !{LocalOperation.create, LocalOperation.patch}.contains(m.operation)) {
      return null;
    }
    final decoded = jsonDecode(m.payload);
    if (decoded is! Map<String, dynamic>) return null;
    final create = m.operation == LocalOperation.create;
    if (m.entity == LocalEntity.song &&
        !create &&
        decoded.containsKey('representative_recording_id')) {
      final target = decoded['representative_recording_id'];
      if (decoded.length != 2 ||
          decoded['base_revision'] != m.baseRevision ||
          m.baseRevision < 1) {
        return null;
      }
      if (target != null) {
        if (target is! String) return null;
        try {
          if (UuidValue(target).value != target) return null;
        } on FormatException {
          return null;
        }
      }
      return MutationRequest(
        mutation: m,
        method: 'PUT',
        path: '/v1/songs/${m.entityId}/representative',
        body: canonicalJson({
          'base_revision': m.baseRevision,
          'recording_id': target,
        }),
        attempt: m.attemptCount + 1,
      );
    }
    if (m.entity == LocalEntity.recording &&
        !create &&
        decoded.containsKey('metadata_state')) {
      if (!validRecordingSaveRequest(decoded, m.baseRevision)) return null;
      return MutationRequest(
        mutation: m,
        method: 'PATCH',
        path: '/v1/recordings/${m.entityId}',
        body: m.payload,
        attempt: m.attemptCount + 1,
      );
    }
    if (m.entity == LocalEntity.recording &&
        !create &&
        decoded.containsKey('song_id')) {
      if (decoded.length != 2 ||
          decoded['base_revision'] != m.baseRevision ||
          m.baseRevision < 1) {
        return null;
      }
      final target = decoded['song_id'];
      if (target != null) {
        if (target is! String) return null;
        try {
          if (UuidValue(target).value != target) return null;
        } on FormatException {
          return null;
        }
      }
      return MutationRequest(
        mutation: m,
        method: 'PATCH',
        path: '/v1/recordings/${m.entityId}/song',
        body: m.payload,
        attempt: m.attemptCount + 1,
      );
    }
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
      (LocalEntity.playlist, true) => {'id', 'name'},
      (LocalEntity.playlist, false) => {'base_revision', 'name'},
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
