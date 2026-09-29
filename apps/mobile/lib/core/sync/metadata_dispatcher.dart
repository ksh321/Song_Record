import 'dart:convert';

import '../../features/auth/auth_session.dart';
import '../database/account_store.dart';
import '../database/local_models.dart';
import '../domain/identifiers.dart';
import 'mutation_request.dart';
import 'mutation_transport.dart';

/// One bounded pass; retry scheduling, rebasing and canonical mapping are later steps.
final class MetadataDispatcher {
  MetadataDispatcher(this.store, this.transport, this.session);
  final AccountStore store;
  final MutationTransport transport;
  final Future<AuthSession> Function() session;

  Future<int> dispatch({int limit = 50}) async {
    if (limit < 1 || limit > 500) throw ArgumentError('Invalid dispatch limit');
    var acknowledged = 0;
    for (var i = 0; i < limit; i++) {
      // Acquire credentials before claiming; an unavailable login does not consume an attempt.
      final auth = await session();
      store.requireActive();
      if (auth.userId != store.userId) {
        throw StateError('Session belongs to another account');
      }
      final request = await store.claimMutation();
      if (request == null) break;
      try {
        store.requireActive();
        final response = await transport.send(
          request,
          auth,
          store.requireActive,
        );
        store.requireActive();
        if (response.status == 200 || response.status == 201) {
          final snapshot = _snapshot(request, response);
          if (snapshot['id'] != request.mutation.entityId) {
            await store.deferMutation(
              request,
              'CONFLICT',
              'CANONICAL_MAPPING_REQUIRED',
              status: response.status,
              serverSnapshot: snapshot,
            );
          } else if (request.mutation.operation == LocalOperation.create &&
              response.status == 200) {
            await store.deferMutation(
              request,
              'CONFLICT',
              'EXISTING_RESOURCE_REVIEW_REQUIRED',
              status: response.status,
              serverSnapshot: snapshot,
            );
          } else if (await store.acknowledgeMutation(request, snapshot)) {
            acknowledged++;
          }
        } else {
          final state = response.status == 409
              ? 'CONFLICT'
              : {400, 404, 405, 413, 422}.contains(response.status)
              ? 'FAILED'
              : 'RETRY';
          var reason = 'HTTP_${response.status}';
          Map<String, Object?>? current;
          try {
            final envelope = jsonDecode(response.body);
            final error = envelope is Map ? envelope['error'] : null;
            if (error is Map &&
                error['code'] is String &&
                RegExp(r'^[A-Z0-9_]{1,64}$')
                    .hasMatch(error['code'] as String)) {
              reason = error['code'] as String;
              final details = error['details'];
              if (response.status == 409 &&
                  details is Map &&
                  details['current'] is Map) {
                final parsed = _snapshot(
                  request,
                  MutationResponse(409, jsonEncode(details['current'])),
                  conflict: true,
                );
                if (parsed['revision'] == details['current_revision']) {
                  current = parsed;
                }
              }
            }
          } catch (_) {
            /* Keep status and local input even for a malformed error. */
          }
          await store.deferMutation(
            request,
            state,
            reason,
            status: response.status,
            serverSnapshot: current,
          );
        }
      } catch (_) {
        // No raw exception/body/token in durable diagnostics. An expired lease throws,
        // leaving the old account's SENDING request intact for explicit recovery.
        store.requireActive();
        await store.deferMutation(request, 'RETRY', 'RESPONSE_UNCONFIRMED');
      }
    }
    return acknowledged;
  }

  Map<String, Object?> _snapshot(
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
}
