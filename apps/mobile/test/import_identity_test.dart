import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/backup/export/export_baseline.dart';
import 'package:song_record/features/backup/export/export_data.dart';
import 'package:song_record/features/backup/export/export_manifest.dart';
import 'package:song_record/features/backup/import/import_decision.dart';
import 'package:song_record/features/backup/import/import_identity.dart';
import 'package:song_record/features/backup/import/import_preflight.dart';
import 'package:song_record/features/backup/import/import_validation.dart';
import 'package:song_record/features/backup/import/import_zip.dart';

import 'import_preflight_test.dart' show ImportTransport;
import 'support/business_snapshot_fixture.dart';

String id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
Map<String, dynamic> song(
  int n, {
  String number = '00123',
  String state = 'ACTIVE',
}) => {
  'id': id(n),
  'source_type': 'TJ',
  'tj_number': number,
  'lifecycle_state': state,
  'note': 'server note',
  'version_code': 'NORMAL',
};
void main() {
  late Directory dir;
  late AccountStoreManager manager;
  late AccountStore store;
  late String owner;
  final now = DateTime.utc(2026, 9, 30);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('import-identities-');
    manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => dir,
      temporaryDirectory: () async => dir,
    );
    owner = businessSnapshotFixture()['owner'] as String;
    store = await manager.openAccount(owner);
  });
  tearDown(() async {
    await manager.logout();
    await dir.delete(recursive: true);
  });
  Future<ImportServerBaseline> server(
    List<Map<String, dynamic>> songs, {
    String? purged,
    String entity = 'SONG',
  }) async {
    final f = businessSnapshotFixture();
    replaceBusinessSnapshotRows(f, 'SONG', [
      for (final row in songs) {...row, 'user_id': owner},
    ]);
    replaceBusinessSnapshotRows(
      f,
      'DELETION_LEDGER',
      purged == null
          ? []
          : [
              {
                'id': id(900),
                'user_id': owner,
                'entity_type': entity,
                'entity_id': purged,
                'purged_at': '2026-09-29T00:00:00.000Z',
              },
            ],
    );
    final reader = ImportPreflight(
      store: store,
      transport: ImportTransport(f),
      session: () async => AuthSession(
        userId: owner,
        deviceId: id(901),
        accessToken: 'fixture',
        refreshToken: 'fixture',
        accessExpiresAt: now.add(const Duration(hours: 1)),
        refreshExpiresAt: now.add(const Duration(days: 1)),
      ),
      requireCurrent: () {},
      clock: () => now,
    );
    return reader.readReady(f['manifest']['snapshot_token'] as String);
  }

  Future<ImportConsent> backup({
    String? scope,
    String number = '00123',
    bool includeSong = true,
    bool input = false,
    bool duplicateSong = false,
    bool wrongRecordId = false,
    bool fileRelations = false,
  }) async {
    final user = scope ?? owner;
    final rows = <Map<String, dynamic>>[
      if (includeSong)
        {
          'entity': 'SONG',
          'resource_id': id(501),
          'payload': {
            ...song(501, number: number),
            'note': 'backup note',
            'version_code': 'LIVE',
          },
        },
      if (duplicateSong)
        {
          'entity': 'SONG',
          'resource_id': id(505),
          'payload': song(505, number: number),
        },
      if (fileRelations) ...[
        {
          'entity': 'RECORDING_FILE_SPEC',
          'resource_id': id(502),
          'payload': {
            'recording_id': id(502),
            'sha256': 'a' * 64,
            'size_bytes': 5,
          },
        },
        {
          'entity': 'RECORDING_ASSET',
          'resource_id': id(502),
          'payload': {'recording_id': id(502), 'cloud_state': 'STORED'},
        },
      ],
      if (!input)
        {
          'entity': 'RECORDING',
          'resource_id': id(502),
          'payload': {
            'id': wrongRecordId ? id(599) : id(502),
            'song_id': id(501),
            'title_snapshot': 'original snapshot',
            'artist_snapshot': 'artist',
            'version_code': 'LIVE',
            'key_mode': 'MALE',
            'key_shift': 2,
            'note': 'offline draft',
          },
        },
      {
        'entity': 'PLAYLIST_ITEM',
        'resource_id': id(503),
        'payload': {
          'id': id(503),
          'playlist_id': id(504),
          'song_id': id(501),
          'position': 1,
        },
      },
    ];
    final local = {
      'source_user_id': user,
      'local_cutoff_at': now.toIso8601String(),
      'baseline': [
        {'baseline_complete': 0, 'last_change_seq': null, 'updated_at': null},
      ],
      'copies': [
        for (final row in rows)
          {
            'entity_type': row['entity'],
            'entity_id': row['resource_id'],
            'server_revision': 0,
            'tombstone': 0,
            'server_payload': null,
            'local_payload': jsonEncode(row['payload']),
          },
      ],
      'changes': <Object?>[],
      'recording_inputs': <Object?>[
        if (input)
          {
            'recording_id': id(502),
            'phase': 'INPUT_PENDING',
            'revision': 0,
            'recovery_payload': jsonEncode({
              'draft': {
                'song_id': id(501),
                'title_snapshot': 'original snapshot',
                'version_code': 'LIVE',
                'note': 'offline draft',
              },
              'input_selection': {
                'song_id': id(501),
                'title_snapshot': 'original snapshot',
              },
              'input_form': {
                'song_id': id(501),
                'version_code': 'LIVE',
                'note': 'offline draft',
              },
            }),
          },
      ],
    };
    final baseline = ExportBaseline(
      id: id(800),
      owner: user,
      includeTrash: false,
      manifest: null,
      createdAt: now,
      local: local,
      entries: const [],
    );
    final data = ExportData.fromBaseline(baseline);
    final manifest = ExportManifest.fromBaseline(
      baseline,
      metadataCount: data.metadataCount,
      files: [
        ExportAudioEntry(
          recordingId: id(502),
          selected: true,
          included: true,
          missingReason: null,
          sha256: 'a' * 64,
          sizeBytes: 5,
          durationMs: 12000,
        ),
      ],
    );
    final checked = ValidatedImport(
      ImportZipStaging(dir, const {}),
      manifest,
      ImportData.decode(data.encode(), manifest),
      const [],
    );
    final controller = ImportDecision(
      validate: (_) => Future.value(checked),
      requireCurrent: () {},
    );
    addTearDown(controller.dispose);
    await controller.check();
    return controller.approveWhole();
  }

  test('new UUID with same active TJ maps references but preserves recording snapshots and canonical metadata', () async {
    final consent = await backup(), current = await server([song(601)]);
    final before = jsonEncode(consent.source.data.toJson());
    final result = planImportIdentities(
      consent: consent,
      server: current,
      requireCurrent: () {},
    );
    expect(result.songIds[id(501)], id(601));
    expect(result.records.where((r) => r['entity'] == 'SONG'), isEmpty);
    final recording = result.records.singleWhere(
      (r) => r['entity'] == 'RECORDING',
    );
    expect(recording['resource_id'], id(502));
    expect(recording['payload']['id'], id(502));
    expect(recording['payload']['song_id'], id(601));
    expect(recording['payload']['title_snapshot'], 'original snapshot');
    expect(recording['payload']['version_code'], 'LIVE');
    expect(recording['payload']['note'], 'offline draft');
    expect(recording['payload']['key_shift'], 2);
    expect(
      result.records.singleWhere(
        (r) => r['entity'] == 'PLAYLIST_ITEM',
      )['payload']['song_id'],
      id(601),
    );
    expect(result.fileIds, {id(502)});
    expect(jsonEncode(consent.source.data.toJson()), before);
    expect(
      current.entries.where((e) => e.entity == 'SONG').single.payload['note'],
      'server note',
    );
  });
  test('permanent song UUID is blocked before same-TJ alias and its references held', () async {
    final result = planImportIdentities(
      consent: await backup(),
      server: await server([song(601)], purged: id(501)),
      requireCurrent: () {},
    );
    expect(
      result.blocked.any((e) => e.entity == 'SONG' && e.id == id(501)),
      true,
    );
    expect(result.songIds.containsKey(id(501)), false);
    expect(result.held.any((e) => e.entity == 'RECORDING'), true);
    expect(result.fileIds, isEmpty);
  });
  test(
    'permanent recording UUID cannot regain a file under the mapped song',
    () async {
      final result = planImportIdentities(
        consent: await backup(),
        server: await server([song(601)], purged: id(502), entity: 'RECORDING'),
        requireCurrent: () {},
      );
      expect(result.blocked.any((e) => e.entity == 'RECORDING'), true);
      expect(result.fileIds, isEmpty);
      expect(result.records.where((r) => r['entity'] == 'RECORDING'), isEmpty);
    },
  );
  for (final state in ['TRASHED', 'PURGE_PENDING']) {
    test(
      'same TJ $state holds instead of creating an active duplicate',
      () async {
        final result = planImportIdentities(
          consent: await backup(),
          server: await server([song(601, state: state)]),
          requireCurrent: () {},
        );
        expect(result.songIds, isEmpty);
        expect(
          result.held.any((e) => e.code == 'TJ_RESTORE_OR_PURGE_REQUIRED'),
          true,
        );
        expect(result.records, isEmpty);
      },
    );
  }
  test('leading zeros stay distinct; no active duplicate case retains original UUID', () async {
    final result = planImportIdentities(
      consent: await backup(number: '00123'),
      server: await server([song(601, number: '123')]),
      requireCurrent: () {},
    );
    expect(result.songIds[id(501)], id(501));
    expect(result.records.where((r) => r['entity'] == 'SONG').length, 1);
  });
  test('ambiguous active TJ never chooses an arbitrary row', () async {
    final result = planImportIdentities(
      consent: await backup(),
      server: await server([song(601), song(602)]),
      requireCurrent: () {},
    );
    expect(result.songIds, isEmpty);
    expect(result.held.any((e) => e.code == 'AMBIGUOUS_TJ_IDENTITY'), true);
  });
  test('existing same UUID with changed TJ identity is held', () async {
    final result = planImportIdentities(
      consent: await backup(),
      server: await server([song(501, number: '999')]),
      requireCurrent: () {},
    );
    expect(result.songIds, isEmpty);
    expect(result.held.any((e) => e.code == 'IDENTITY_MISMATCH'), true);
  });
  test('pending input references remap without changing snapshot/version/note or recording UUID', () async {
    final result = planImportIdentities(
      consent: await backup(input: true),
      server: await server([song(601)]),
      requireCurrent: () {},
    );
    final input = result.recoveryInputs.single;
    expect(input['recording_id'], id(502));
    expect(input['draft']['song_id'], id(601));
    expect(input['draft']['note'], 'offline draft');
    expect(input['input_form']['version_code'], 'LIVE');
    expect(result.fileIds, {id(502)});
  });
  test('duplicate incoming TJ without a canonical server row is held instead of duplicated', () async {
    final result = planImportIdentities(
      consent: await backup(duplicateSong: true),
      server: await server([]),
      requireCurrent: () {},
    );
    expect(result.songIds, isEmpty);
    expect(
      result.held.where((e) => e.code == 'AMBIGUOUS_BACKUP_TJ_IDENTITY').length,
      2,
    );
  });
  test('record envelope and payload UUID mismatch cannot produce metadata or a file', () async {
    final result = planImportIdentities(
      consent: await backup(wrongRecordId: true),
      server: await server([song(601)]),
      requireCurrent: () {},
    );
    expect(
      result.held.any(
        (e) => e.entity == 'RECORDING' && e.code == 'IDENTITY_MISMATCH',
      ),
      true,
    );
    expect(result.fileIds, isEmpty);
    expect(result.records.where((r) => r['entity'] == 'RECORDING'), isEmpty);
  });
  test(
    'purged recording also blocks its file-spec and asset relationships',
    () async {
      final result = planImportIdentities(
        consent: await backup(fileRelations: true),
        server: await server([song(601)], purged: id(502), entity: 'RECORDING'),
        requireCurrent: () {},
      );
      expect(
        result.records.where(
          (r) => {
            'RECORDING',
            'RECORDING_FILE_SPEC',
            'RECORDING_ASSET',
          }.contains(r['entity']),
        ),
        isEmpty,
      );
      expect(result.fileIds, isEmpty);
    },
  );
  test(
    'other owner and revoked guard reject the plan before data mutation',
    () async {
      final current = await server([song(601)]),
          foreign = await backup(scope: id(999));
      expect(
        () => planImportIdentities(
          consent: foreign,
          server: current,
          requireCurrent: () {},
        ),
        throwsFormatException,
      );
      final normal = await backup();
      expect(
        () => planImportIdentities(
          consent: normal,
          server: current,
          requireCurrent: () {
            throw StateError('revoked');
          },
        ),
        throwsStateError,
      );
    },
  );
}
