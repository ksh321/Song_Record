import 'dart:convert';

import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/domain/identifiers.dart';
import 'package:song_record/core/sync/change_feed_response.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/mutation_request.dart';
import 'package:song_record/core/sync/mutation_transport.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/trash/trash_workflow.dart';

import 'sync_verification_fixture.dart';

String trashId(int n) =>
    '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

class MemoryTrashJournal implements TrashJournal {
  Map<String, dynamic>? value;
  @override
  Future<Map<String, dynamic>?> read() async => value == null
      ? null
      : jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  @override
  Future<void> write(Map<String, dynamic> v) async {
    value = jsonDecode(jsonEncode(v)) as Map<String, dynamic>;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

/// Controlled server only; real account store, frozen queue and receive path.
/// Never contacts a production server or touches personal recordings.
class TrashVerificationFixture implements TrashApi, MutationTransport {
  TrashVerificationFixture(this.store) : repository = LocalRepository(store);
  final AccountStore store;
  final LocalRepository repository;
  final songs = <String, Map<String, dynamic>>{},
      records = <String, Map<String, dynamic>>{},
      batches = <String, Map<String, dynamic>>{};
  final receipts = <String, Map<String, dynamic>>{};
  final posts = <Map<String, dynamic>>[];
  final token = trashId(2050);
  int sequence = 7;
  bool fail = false, loseResponse = false;
  Future<void> initialize() async {
    for (final n in [2010, 2011]) {
      songs[trashId(n)] = {
        ...fixtureSong(trashId(n), 1),
        'title': n == 2010 ? '녹음 유지 검사 곡' : '함께 삭제 검사 곡',
        'tj_number': n == 2010 ? '12345' : '54321',
        'artist': '합성 가수',
        'deleted_at': null,
      };
    }
    await installVerificationSnapshot(
      store,
      verificationSnapshot(
        owner: store.userId,
        token: token,
        cursor: sequence,
        now: DateTime.now(),
        rows: {'SONG': songs.values.toList()},
      ),
    );
    final changes = <Map<String, dynamic>>[];
    for (final n in [2020, 2021]) {
      final row = <String, dynamic>{
        'id': trashId(n),
        'metadata_state': 'SAVED',
        'song_id': trashId(n == 2020 ? 2010 : 2011),
        'title_snapshot': '보존 녹음 $n',
        'artist_snapshot': '합성 가수',
        'version_code': 'NORMAL',
        'key_mode': 'ORIGINAL',
        'key_shift': 0,
        'note': '유지해야 하는 메모',
        'recorded_at': '2026-10-11T00:00:00Z',
        'timezone_id': 'UTC',
        'timezone_offset_minutes': 0,
        'origin_device_id': trashId(2090),
        'revision': 1,
        'link_revision': 1,
        'updated_at': '2026-10-11T00:00:00Z',
        'lifecycle_state': 'ACTIVE',
        'tier': 'B',
        'condition_code': null,
        'condition_name_snapshot': null,
        'tag_ids': <String>[],
        'tags': <Object>[],
      };
      records[row['id'] as String] = row;
      changes.add(event('RECORDING', row));
    }
    await receive(changes);
  }

  Map<String, dynamic> event(
    String type,
    Map<String, dynamic> row, {
    bool deleted = false,
  }) => {
    'entity_type': type,
    'entity_id': row['id'],
    'revision': row['revision'],
    'operation': deleted ? 'DELETE' : 'UPSERT',
    'payload': deleted
        ? {
            'id': row['id'],
            'revision': row['revision'],
            'lifecycle_state': 'PURGED',
          }
        : row,
  };
  Future<void> receive(List<Map<String, dynamic>> changes) async {
    final after = sequence;
    for (final row in changes) {
      row['change_seq'] = ++sequence;
    }
    await store.applyChangeFeed(
      ChangeFeedPage.decode(
        jsonEncode({
          'after_seq': after,
          'next_seq': sequence,
          'head_seq': sequence,
          'has_more': false,
          'changes': changes,
        }),
        owner: store.userId,
        expectedAfter: after,
      ),
      snapshotToken: token,
    );
  }

  Future<AuthSession> session() async => AuthSession(
    userId: store.userId,
    deviceId: trashId(2090),
    accessToken: 'synthetic',
    refreshToken: 'synthetic',
    accessExpiresAt: DateTime.now().add(const Duration(hours: 1)),
    refreshExpiresAt: DateTime.now().add(const Duration(days: 1)),
  );
  Future<void> synchronize() async {
    await repository.dispatch(transport: this, session: session);
  }

  @override
  Future<MutationResponse> send(
    MutationRequest request,
    AuthSession session,
    void Function() current,
  ) async {
    current();
    if (fail) return const MutationResponse(503, '{}');
    final body = jsonDecode(request.body) as Map;
    final id = request.mutation.entityId;
    final song = request.mutation.entity == LocalEntity.song;
    final batch = UuidValue.random().value,
        deleted = '2026-10-11T08:00:00Z',
        expires = '2026-10-18T08:00:00Z';
    final mode = song ? body['mode'] as String : 'RECORDING';
    final root = song ? songs[id]! : records[id]!;
    root['revision'] = (root['revision'] as int) + 1;
    root['lifecycle_state'] = 'TRASHED';
    root['deleted_at'] = deleted;
    final related = <Map<String, dynamic>>[];
    if (song) {
      for (final rec in records.values.where(
        (r) => r['song_id'] == id && r['lifecycle_state'] == 'ACTIVE',
      )) {
        rec['song_id'] = null;
        rec['link_revision'] = (rec['link_revision'] as int) + 1;
        rec['revision'] = (rec['revision'] as int) + 1;
        rec['lifecycle_state'] = mode == 'SONG_ONLY' ? 'ACTIVE' : 'TRASHED';
        rec['deleted_at'] = mode == 'SONG_ONLY' ? null : deleted;
        related.add({...rec});
      }
    } else {
      root['song_id'] = null;
      root['link_revision'] = (root['link_revision'] as int) + 1;
    }
    batches[batch] = {
      'batch_id': batch,
      'revision': 1,
      'mode': mode,
      'deleted_at': deleted,
      'purge_after': expires,
      'items': [
        {'entity_type': song ? 'SONG' : 'RECORDING', 'id': id},
        for (final row in related)
          {'entity_type': 'RECORDING', 'id': row['id']},
      ],
    };
    return MutationResponse(
      200,
      jsonEncode({
        'batch_id': batch,
        'deleted_at': deleted,
        'purge_after': expires,
        if (song) ...{
          'mode': mode,
          'song': root,
          'recordings': related,
        } else
          'recording': root,
      }),
    );
  }

  @override
  Future<Map<String, dynamic>> call(
    String method,
    String path,
    Map<String, Object?>? body,
    String? operation,
  ) async {
    if (path.contains('delete-preview')) {
      return {
        'recording_count': 1,
        'server_bytes': 1234,
        'pinned_count': 1,
        'preview_version': 'a' * 64,
        'scope': 'SERVER_CURRENT',
      };
    }
    if (method == 'GET') {
      final result = jsonDecode(
        jsonEncode({'items': batches.values.toList(), 'next_cursor': null}),
      ) as Map<String, dynamic>;
      for (final b in result['items'] as List) {
        for (final item in b['items'] as List) {
          item['lifecycle_state'] = (item['entity_type'] == 'SONG'
              ? songs[item['id']]
              : records[item['id']])!['lifecycle_state'];
        }
      }
      return result;
    }
    posts.add({'path': path, 'body': body, 'operation': operation});
    if (receipts.containsKey(operation)) return receipts[operation]!;
    if (fail) throw const TrashFailure('삭제 실패 · 다시 시도해 주세요. 원본 파일과 용량은 유지돼요.');
    final batchId = path.split('/')[3], batch = batches[batchId]!;
    final selected = (body!['item_ids'] as List?)?.cast<String>();
    final purge = path.endsWith('purge'),
        restored = <Object>[],
        skipped = <Object>[],
        events = <Map<String, dynamic>>[];
    for (final item in batch['items'] as List) {
      if (selected != null && !selected.contains(item['id'])) continue;
      final type = item['entity_type'] as String,
          row = type == 'SONG' ? songs[item['id']]! : records[item['id']]!;
      if (row['lifecycle_state'] != 'TRASHED') {
        skipped.add({
          'id': row['id'],
          'entity_type': type,
          'reason': 'STATE_CHANGED',
        });
        continue;
      }
      row['revision'] = (row['revision'] as int) + 1;
      row['lifecycle_state'] = purge ? 'PURGE_PENDING' : 'ACTIVE';
      if (!purge) row['deleted_at'] = null;
      restored.add({
        'entity_type': type,
        'value': {...row},
      });
      events.add(event(type, row));
    }
    batch['revision'] = (batch['revision'] as int) + 1;
    await receive(events);
    final result = <String, dynamic>{
      'batch_id': batchId,
      'revision': batch['revision'],
      if (purge) ...{
        'state': 'PURGE_PENDING',
        'job_id': UuidValue.random().value,
      } else ...{
        'restored': restored,
        'skipped': skipped,
        'pin_reselection_required': true,
      },
    };
    receipts[operation!] = result;
    if (!purge &&
        (batch['items'] as List).every(
          (v) =>
              (v['entity_type'] == 'SONG'
                  ? songs[v['id']]
                  : records[v['id']])!['lifecycle_state'] ==
              'ACTIVE',
        )) {
      batches.remove(batchId);
    }
    if (loseResponse) {
      loseResponse = false;
      throw const TrashFailure('응답 미확인 · 같은 요청으로 다시 확인해 주세요.');
    }
    return result;
  }

  Future<void> completePurge() async {
    final events = <Map<String, dynamic>>[];
    for (final pair in [('SONG', songs), ('RECORDING', records)]) {
      for (final row in pair.$2.values) {
        if (row['lifecycle_state'] == 'PURGE_PENDING') {
          row['revision'] = (row['revision'] as int) + 1;
          row['lifecycle_state'] = 'PURGED';
          events.add(event(pair.$1, row, deleted: true));
        }
      }
    }
    await receive(events);
    batches.removeWhere(
      (id, b) => (b['items'] as List).every(
        (v) => !{'TRASHED', 'PURGE_PENDING'}.contains(
          (v['entity_type'] == 'SONG'
              ? songs[v['id']]
              : records[v['id']])!['lifecycle_state'],
        ),
      ),
    );
  }
}
