import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/snapshot_response.dart';
import 'package:song_record/features/backup/export/export_baseline.dart';
import 'package:song_record/features/backup/export/export_data.dart';

import 'support/completed_capture_fixture.dart' as capture_fixture;

const owner = '00000000-0000-4000-8000-000000001801';
const id = '00000000-0000-4000-8000-000000002101';
const token = '00000000-0000-4000-8000-000000002102';
const second = '00000000-0000-4000-8000-000000002103';
final now = DateTime.utc(2026, 10, 11);
ExportBaseline baseline(
  Map<String, Object?> local, {
  List<SnapshotEntry> entries = const [],
  SnapshotManifest? manifest,
}) => ExportBaseline(
  id: token,
  owner: owner,
  includeTrash: false,
  manifest: manifest,
  createdAt: now,
  local: {
    'source_user_id': owner,
    'local_cutoff_at': now.toIso8601String(),
    'copies': <Object>[],
    'changes': <Object>[],
    ...local,
  },
  entries: entries,
);
Map<String, Object?> copy(
  String entity,
  String resource,
  Map<String, Object?> payload, {
  bool tombstone = false,
}) => {
  'entity_type': entity,
  'entity_id': resource,
  'server_revision': 7,
  'server_payload': null,
  'local_payload': jsonEncode(payload),
  'tombstone': tombstone ? 1 : 0,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('personal versions, relationships, classifications and deletions retain values', () {
    final data = ExportData.fromBaseline(
      baseline({
        'copies': [
          copy('SONG', id, {
            'id': id,
            'source_type': 'TJ',
            'tj_number': '00123',
            'title': '노래',
            'artist': '가수',
            'version_code': 'LIVE',
            'revision': 7,
            'lifecycle_state': 'TRASHED',
            'deleted_at': now.toIso8601String(),
          }, tombstone: true),
          copy('PLAYLIST_ITEM', second, {
            'id': second,
            'playlist_id': token,
            'song_id': id,
            'position': 5,
            'candidate_snapshot': {
              'provider': 'MANANA',
              'verified_at': now.toIso8601String(),
              'brand': 'TJ',
              'number': '00123',
              'title': '노래',
              'artist': '가수',
            },
          }),
          copy('RECORDING', token, {
            'id': token,
            'song_id': id,
            'tier': 'A',
            'note': '내 메모',
            'condition_code': 'GOOD',
            'tags': [
              {'id': second, 'name_snapshot': '연습'},
            ],
            'tag_ids': [second],
          }),
        ],
      }),
    );
    final records = data.records;
    expect(records.length, 3);
    expect(records.first['tombstone'], true);
    expect(records.first['payload']['tj_number'], '00123');
    expect(records[1]['payload']['playlist_id'], token);
    expect(records[1]['payload']['candidate_snapshot']['provider'], 'MANANA');
    expect(records[2]['payload']['tags'].single['name_snapshot'], '연습');
    final detached = data.toJson();
    detached.clear();
    expect(data.metadataCount, 3);
  });
  test('pending conflict keeps base, draft and remote current separately and drops credentials', () {
    final data = ExportData.fromBaseline(
      baseline({
        'copies': [
          copy('SONG', id, {
            'id': id,
            'title': 'local',
            'local_path': 'C:/private/audio.m4a',
            'access_token': 'secret',
            '_storage_evidence': {'secret_key': 'secret'},
          }),
        ],
        'changes': [
          {
            'op_id': second,
            'entity_type': 'SONG',
            'entity_id': id,
            'operation': 'PATCH',
            'base_revision': 3,
            'base_payload': jsonEncode({
              'id': id,
              'revision': 3,
              'title': 'base',
            }),
            'payload': jsonEncode({
              'base_revision': 3,
              'title': 'local',
              'source_token': 'secret',
            }),
            'queue_state': 'CONFLICT',
            'created_at': 1,
            'server_response': jsonEncode({
              'status': 409,
              'code': 'REVISION_CONFLICT',
              'current': {
                'id': id,
                'revision': 4,
                'title': 'remote',
                'refresh_token': 'secret',
              },
              'message': 'private message',
              'status_token': 'secret',
            }),
          },
        ],
      }),
    );
    final change = (data.toJson()['pending_changes'] as List).single;
    expect(change['base']['title'], 'base');
    expect(change['changes']['title'], 'local');
    expect(change['server_response']['current']['title'], 'remote');
    expect(change['requires_source_refresh'], true);
    for (final excluded in [
      'secret',
      'C:/',
      'private message',
      'access_token',
      'status_token',
      '_storage_evidence',
    ]) {
      expect(data.encode(), isNot(contains(excluded)));
    }
  });
  test(
    'nested file and candidate fields never copy storage paths or tokens',
    () {
      final data = ExportData.fromBaseline(
        baseline({
          'copies': [
            copy('RECORDING', id, {
              'id': id,
              'file': {
                'sha256': 'a' * 64,
                'size_bytes': 12,
                'local_path': 'C:/secret',
                'object_key': 'secret',
                'signed_url': 'secret',
              },
            }),
            copy('PLAYLIST_ITEM', second, {
              'id': second,
              'candidate_snapshot': {
                'title': 'candidate',
                'artist': 'artist',
                'source_token': 'secret',
                'cache_path': 'C:/secret',
              },
            }),
          ],
        }),
      );
      expect(data.encode(), isNot(contains('secret')));
      expect(data.records.first['payload']['file']['sha256'], 'a' * 64);
      expect(
        () => ExportData.fromBaseline(
          baseline({
            'copies': [
              copy('RECORDING', id, {'id': id, 'file': 'C:/private'}),
            ],
          }),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'foreign account and unknown entities fail without exposing payload',
    () {
      expect(
        () => ExportData.fromBaseline(
          baseline({
            'copies': [
              copy('SONG', id, {'user_id': second, 'title': 'private'}),
            ],
          }),
        ),
        throwsFormatException,
      );
      expect(
        () => ExportData.fromBaseline(
          baseline({
            'copies': [
              copy('CHART_CACHE', id, {'title': 'cached'}),
            ],
          }),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'offline snapshot preserves composite tags and historical deletion ledger',
    () {
      final source = [
        for (final tag in [id, second])
          {
            'entity': 'RECORDING_TAG',
            'ordinal': tag == id ? 1 : 2,
            'resource_id': token,
            'canonical_payload': jsonEncode({
              'user_id': owner,
              'recording_id': token,
              'tag_id': tag,
              'name_snapshot': 'tag',
            }),
          },
        {
          'entity': 'DELETION_LEDGER',
          'ordinal': 1,
          'resource_id': second,
          'canonical_payload': jsonEncode({
            'user_id': owner,
            'id': second,
            'entity_id': id,
            'entity_type': 'SONG',
            'revision': 9,
            'purged_at': now.toIso8601String(),
          }),
        },
      ];
      final frozen = baseline({'snapshot_rows': source});
      source.clear(); // ExportBaseline owns a detached frozen value.
      final data = ExportData.fromBaseline(frozen);
      expect(data.records, hasLength(3));
      expect(data.records.last['payload']['purged_at'], now.toIso8601String());
    },
  );
  test('online fresh rows outrank an older local confirmed server copy without losing draft evidence', () {
    final counts = {for (final e in snapshotEntities) e: 0}
      ..['USER_SYNC_STATE'] = 1;
    final manifest = SnapshotManifest.decode(
      jsonEncode({
        'snapshot_token': token,
        'status': 'READY',
        'schema_version': 1,
        'snapshot_cursor': 7,
        'captured_at': now.toIso8601String(),
        'ready_at': now.toIso8601String(),
        'expires_at': now.add(const Duration(minutes: 30)).toIso8601String(),
        'manifest_hash': 'a' * 64,
        'entity_counts': counts,
      }),
      expectedToken: token,
      now: now,
    );
    final entry = SnapshotEntry.fromStored(
      entity: 'SONG',
      ordinal: 1,
      resourceId: id,
      canonicalPayload: jsonEncode({
        'user_id': owner,
        'id': id,
        'title': 'fresh',
        'revision': 7,
      }),
      owner: owner,
      snapshotCursor: 7,
    );
    final old = copy('SONG', id, {})
      ..['local_payload'] = null
      ..['server_payload'] = jsonEncode({
        'id': id,
        'title': 'old',
        'revision': 2,
      });
    final data = ExportData.fromBaseline(
      baseline(
        {
          'copies': [old],
        },
        entries: [entry],
        manifest: manifest,
      ),
    );
    expect(data.records.single['payload']['title'], 'fresh');
    expect(data.toJson()['local_copies'].single['server']['title'], 'old');
  });
  test('real account transaction freezes completed input and queue without paths or ACK', () async {
    final directory = await Directory.systemTemp.createTemp('sr-backup-data-');
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () => Future.value(directory),
      temporaryDirectory: () => Future.value(directory),
    );
    try {
      final store = await manager.openAccount(owner);
      final repo = LocalRepository(store);
      await capture_fixture.capture(repo);
      await store.preserveRecordingInput(capture_fixture.rec, {
        'note': 'first input',
        'tier': 'A',
      });
      final frozen = baseline(await store.captureExportLocal());
      await store.preserveRecordingInput(capture_fixture.rec, {
        'note': 'later input',
      });
      final data = ExportData.fromBaseline(frozen);
      final input = (data.toJson()['recording_inputs'] as List).single;
      expect(input['input_form']['note'], 'first input');
      expect(input['file']['sha256'], capture_fixture.spec()['sha256']);
      expect(data.encode(), isNot(contains(directory.path)));
      expect(data.encode(), isNot(contains('pending/')));
      expect((await store.captureExportLocal())['changes'], hasLength(1));
      expect(
        (await store.captureExportLocal())['recording_inputs'],
        hasLength(1),
      );
    } finally {
      await manager.logout();
      await directory.delete(recursive: true);
    }
  });
}
