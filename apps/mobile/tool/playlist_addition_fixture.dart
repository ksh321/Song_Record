import 'dart:convert';

import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/mutation_request.dart';
import 'package:song_record/core/sync/mutation_transport.dart';
import 'package:song_record/features/auth/auth_session.dart';

String playlistFixtureId(int n) =>
    '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
const playlistFixtureTime = '2026-10-11T00:00:00Z';

/// Isolated synthetic server responses exercise the real durable queue/store.
/// This is not a production server or evidence of provider network access.
class PlaylistAdditionFixture implements MutationTransport {
  PlaylistAdditionFixture(this.repository);
  final LocalRepository repository;
  final String playlistId = playlistFixtureId(1920);
  final Map<String, Map<String, dynamic>> songs = {};
  late Map<String, dynamic> header;
  final List<Map<String, dynamic>> items = [];
  final Map<String, (String, MutationResponse)> receipts = {};
  final List<MutationRequest> requests = [];
  bool loseNextAddition = false;
  bool corruptNextAdditionOwner = false;
  Future<AuthSession> session() async => AuthSession(
    userId: repository.userId,
    deviceId: playlistFixtureId(1990),
    accessToken: 'isolated-fixture',
    refreshToken: 'isolated-fixture',
    accessExpiresAt: DateTime.now().add(const Duration(hours: 1)),
    refreshExpiresAt: DateTime.now().add(const Duration(days: 1)),
  );
  Future<void> initialize() async {
    for (final n in [1910, 1911]) {
      final id = playlistFixtureId(n), manual = n == 1911;
      songs[id] = {
        'id': id,
        'revision': 1,
        'source_type': manual ? 'MANUAL' : 'TJ',
        'tj_number': manual ? null : '00123',
        'title': manual ? '직접 등록 곡' : 'TJ 검사 곡',
        'artist': '검사 가수',
        'version_code': 'NORMAL',
        'tier': null,
        'note': '',
        'lifecycle_state': 'ACTIVE',
        'representative_recording_id': null,
        'representative_key_mode': null,
        'representative_key_shift': null,
        'created_at': playlistFixtureTime,
        'updated_at': playlistFixtureTime,
      };
      if (await repository.read(LocalEntity.song, id) == null) {
        await repository.save(
          repository.prepareCreate(
            entity: LocalEntity.song,
            entityId: id,
            draft: songs[id]!,
            changes: manual
                ? {
                    'source_type': 'MANUAL',
                    'title': '직접 등록 곡',
                    'artist': '검사 가수',
                  }
                : {'source_type': 'TJ', 'source_token': 'isolated-tj-proof'},
          ),
        );
      }
    }
    final stored = await repository.read(LocalEntity.playlist, playlistId);
    header = stored?.serverJson == null
        ? {
            'id': playlistId,
            'name': '등록곡 검증',
            'revision': 1,
            'deleted_at': null,
            'created_at': playlistFixtureTime,
            'updated_at': playlistFixtureTime,
          }
        : jsonDecode(stored!.serverJson!) as Map<String, dynamic>;
    if (stored == null) {
      await repository.save(
        repository.prepareCreate(
          entity: LocalEntity.playlist,
          entityId: playlistId,
          draft: {'name': header['name'], 'deleted_at': null},
          changes: {'name': header['name']},
        ),
      );
    }
    await synchronize();
    for (final value in await repository.playlistItems(playlistId)) {
      items.add({
        for (final key in [
          'id',
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
        ])
          key: value[key],
        'user_id': repository.userId,
      });
    }
  }

  Future<void> synchronize() async {
    await repository.dispatch(transport: this, session: session);
  }

  @override
  Future<MutationResponse> send(
    MutationRequest request,
    AuthSession session,
    void Function() requireCurrent,
  ) async {
    requireCurrent();
    requests.add(request);
    final prior = receipts[request.mutation.opId];
    if (prior != null) {
      if (prior.$1 != request.hash) {
        throw StateError('Fixture immutable request changed');
      }
      return prior.$2;
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    late MutationResponse response;
    if (request.mutation.operation == LocalOperation.create) {
      response = request.mutation.entity == LocalEntity.song
          ? MutationResponse(
              201,
              jsonEncode({
                'created': true,
                'canonical_song_id': request.mutation.entityId,
                'song': songs[request.mutation.entityId],
              }),
            )
          : MutationResponse(201, jsonEncode(header));
    } else if (request.mutation.entity == LocalEntity.song &&
        request.method == 'PATCH') {
      final id = request.mutation.entityId;
      final song = songs[id]!;
      if (body['base_revision'] != song['revision']) {
        throw StateError('Fixture song revision mismatch');
      }
      songs[id] = {...song, ...body}..remove('base_revision');
      songs[id]!['revision'] = (song['revision'] as int) + 1;
      response = MutationResponse(200, jsonEncode(songs[id]));
    } else if (request.path == '/v1/playlists/$playlistId' &&
        request.method == 'PATCH') {
      if (body['base_revision'] != header['revision']) {
        throw StateError('Fixture rename revision mismatch');
      }
      header = {
        ...header,
        'name': body['name'],
        'revision': (header['revision'] as int) + 1,
      };
      final partial = {...header}..remove('created_at');
      response = MutationResponse(200, jsonEncode(partial));
    } else if (request.method == 'PATCH' && request.path.endsWith('/song')) {
      final itemId = request.path.split('/')[5];
      final selected = items.singleWhere((x) => x['id'] == itemId);
      final song = songs[body['song_id']]!;
      if (body['base_revision'] != header['revision']) {
        throw StateError('Fixture link revision mismatch');
      }
      if (song['source_type'] != 'TJ' ||
          song['tj_number'] != selected['candidate_number']) {
        return MutationResponse(
          400,
          jsonEncode({
            'error': {'code': 'VALIDATION_FAILED'},
          }),
        );
      }
      final changed = selected['song_id'] == null;
      selected['song_id'] = song['id'];
      if (changed) {
        header = {...header, 'revision': (header['revision'] as int) + 1};
      }
      response = MutationResponse(
        200,
        jsonEncode({
          'playlist': header,
          'items': items,
          'item_id': itemId,
          'changed': changed,
        }),
      );
    } else {
      if (request.path != '/v1/playlists/$playlistId/items' ||
          body['base_revision'] != header['revision']) {
        throw StateError('Fixture parent revision mismatch');
      }
      final isCandidate = body.containsKey('source_token');
      if (isCandidate && body['source_token'] != 'isolated-tj-candidate') {
        return MutationResponse(
          400,
          jsonEncode({
            'error': {'code': 'PLAYLIST_TJ_REQUIRED'},
          }),
        );
      }
      final song = isCandidate ? null : songs[body['song_id']]!;
      final key = isCandidate
          ? 'tj:00555'
          : song!['source_type'] == 'TJ'
          ? 'tj:${song['tj_number']}'
          : 'manual:${song['id']}';
      var selected = items.where((x) => x['entry_key'] == key).firstOrNull;
      final created = selected == null;
      if (created) {
        selected = {
          'id': request.mutation.opId,
          'user_id': repository.userId,
          'playlist_id': playlistId,
          'song_id': song?['id'],
          'candidate_brand': isCandidate ? 'TJ' : null,
          'candidate_number': isCandidate ? '00555' : null,
          'candidate_snapshot': isCandidate
              ? {
                  'provider': 'FIXTURE',
                  'brand': 'TJ',
                  'number': '00555',
                  'title': '미등록 TJ 후보',
                  'artist': '후보 가수',
                  'verified_at': playlistFixtureTime,
                }
              : null,
          'entry_key': key,
          'position': items.length,
          'hidden_by_batch_id': null,
          'created_at': playlistFixtureTime,
          'updated_at': playlistFixtureTime,
        };
        items.add(selected);
        header = {...header, 'revision': (header['revision'] as int) + 1};
      }
      response = MutationResponse(
        created ? 201 : 200,
        jsonEncode({
          'playlist': header,
          'items': items,
          'item_id': selected['id'],
          'created': created,
        }),
      );
    }
    receipts[request.mutation.opId] = (request.hash, response);
    if (request.mutation.operation != LocalOperation.create &&
        corruptNextAdditionOwner) {
      corruptNextAdditionOwner = false;
      final corrupted = jsonDecode(response.body) as Map<String, dynamic>;
      (corrupted['items'] as List).last['user_id'] = playlistFixtureId(1903);
      return MutationResponse(response.status, jsonEncode(corrupted));
    }
    if (request.mutation.operation != LocalOperation.create &&
        loseNextAddition) {
      loseNextAddition = false;
      throw const MutationNetworkFailure(receivedStatus: 201);
    }
    return response;
  }
}
