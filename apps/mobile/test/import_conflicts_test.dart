import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_database.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/backup/export/export_baseline.dart';
import 'package:song_record/features/backup/export/export_data.dart';
import 'package:song_record/features/backup/export/export_manifest.dart';
import 'package:song_record/features/backup/import/import_candidates.dart';
import 'package:song_record/features/backup/import/import_conflict_preview.dart';
import 'package:song_record/features/backup/import/import_conflicts.dart';
import 'package:song_record/features/backup/import/import_decision.dart';
import 'package:song_record/features/backup/import/import_identity.dart';
import 'package:song_record/features/backup/import/import_preflight.dart';
import 'package:song_record/features/backup/import/import_validation.dart';
import 'package:song_record/features/backup/import/import_zip.dart';

import 'import_preflight_test.dart' show ImportTransport;
import 'support/business_snapshot_fixture.dart';

String id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
void main() {
  late Directory dir;
  late AccountStoreManager manager;
  late AccountStore store;
  late String owner;
  late Map<String, dynamic> remoteSong;
  final now = DateTime.utc(2026, 9, 30), bytes = <int>[1, 2, 3, 4, 5];
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('import-conflict-preview-');
    manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => dir,
      temporaryDirectory: () async => dir,
    );
    owner = businessSnapshotFixture()['owner'] as String;
    store = await manager.openAccount(owner);
    remoteSong = {
      'id': id(701),
      'user_id': owner,
      'source_type': 'TJ',
      'tj_number': '00123',
      'lifecycle_state': 'ACTIVE',
      'revision': 2,
      'title': 'server title',
      'artist': 'artist',
      'version_code': 'NORMAL',
      'note': 'server note',
      'tier': null,
      'representative_key_mode': 'ORIGINAL',
      'representative_key_shift': 0,
    };
  });
  tearDown(() async {
    await manager.logout();
    await dir.delete(recursive: true);
  });
  Future<ImportServerBaseline> server({
    bool fileSpec = false,
    bool omitSong = false,
    String? serverSha,
  }) async {
    final f = businessSnapshotFixture();
    replaceBusinessSnapshotRows(f, 'SONG', omitSong ? [] : [remoteSong]);
    replaceBusinessSnapshotRows(f, 'RECORDING', []);
    replaceBusinessSnapshotRows(
      f,
      'RECORDING_FILE_SPEC',
      fileSpec
          ? [
              {
                'recording_id': id(702),
                'user_id': owner,
                'sha256': serverSha ?? sha256.convert(bytes).toString(),
                'size_bytes': bytes.length,
                'duration_ms': 12000,
                'codec': 'AAC_LC',
                'sample_rate': 48000,
                'channels': 1,
              },
            ]
          : [],
    );
    return ImportPreflight(
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
    ).readReady(f['manifest']['snapshot_token'] as String);
  }

  Future<
    ({
      ImportConsent consent,
      ImportCandidatePlan candidates,
      ImportServerBaseline server,
    })
  >
  input({
    String? note,
    String baseNote = 'base note',
    bool fileSpec = false,
    String? serverSha,
    String? backupSha,
    int baseRevision = 1,
    bool omitSong = false,
    bool legacySuitability = false,
  }) async {
    final current = await server(
      fileSpec: fileSpec,
      serverSha: serverSha,
      omitSong: omitSong,
    );
    final base = {...remoteSong, 'revision': baseRevision, 'note': baseNote}
      ..remove('user_id');
    if (legacySuitability) base.remove('is_suitable');
    final local = note == null ? null : {...base, 'note': note};
    final hash = sha256.convert(bytes).toString();
    final baseline = ExportBaseline(
      id: id(800),
      owner: owner,
      includeTrash: false,
      manifest: null,
      createdAt: now,
      entries: const [],
      local: {
        'source_user_id': owner,
        'local_cutoff_at': now.toIso8601String(),
        'baseline': [
          {'baseline_complete': 0, 'last_change_seq': null, 'updated_at': null},
        ],
        'copies': [
          {
            'entity_type': 'SONG',
            'entity_id': id(701),
            'server_revision': baseRevision,
            'server_payload': jsonEncode(base),
            'local_payload': local == null ? null : jsonEncode(local),
            'tombstone': 0,
          },
          {
            'entity_type': 'RECORDING',
            'entity_id': id(702),
            'server_revision': 0,
            'server_payload': null,
            'local_payload': jsonEncode({
              'id': id(702),
              'song_id': id(701),
              'note': 'snapshot note',
              'version_code': 'LIVE',
              'title_snapshot': 'historical title',
              'artist_snapshot': 'artist',
              'file': {
                'sha256': backupSha ?? hash,
                'size_bytes': bytes.length,
                'duration_ms': 12000,
              },
            }),
            'tombstone': 0,
          },
        ],
        'changes': <Object?>[],
        'recording_inputs': <Object?>[],
      },
    );
    final data = ExportData.fromBaseline(baseline),
        manifest = ExportManifest.fromBaseline(
          baseline,
          metadataCount: 2,
          files: [
            ExportAudioEntry(
              recordingId: id(702),
              selected: true,
              included: true,
              missingReason: null,
              sha256: hash,
              sizeBytes: bytes.length,
              durationMs: 12000,
            ),
          ],
        );
    final decision = ImportDecision(
      validate: (_) => Future.value(
        ValidatedImport(
          ImportZipStaging(dir, const {}),
          manifest,
          ImportData.decode(data.encode(), manifest),
          const [],
        ),
      ),
      requireCurrent: () {},
    );
    addTearDown(decision.dispose);
    await decision.check();
    final consent = decision.approveWhole();
    final identity = planImportIdentities(
      consent: consent,
      server: current,
      requireCurrent: () {},
    );
    return (
      consent: consent,
      candidates: planImportCandidates(identity, requireCurrent: () {}),
      server: current,
    );
  }

  Future<ImportConflictPreview> preview(
    ({
      ImportConsent consent,
      ImportCandidatePlan candidates,
      ImportServerBaseline server,
    })
    i,
  ) => previewImportConflicts(
    consent: i.consent,
    candidates: i.candidates,
    server: i.server,
    store: store,
    requireCurrent: () {},
  );
  Future<File> localFile() async => (await AccountPaths.create(
    dir,
    owner,
    AppEnvironment.dev,
  )).checkedFile('audio/${id(702)}.m4a');
  test('historical backup without explicit local edit preserves latest server values', () async {
    final p = await preview(await input());
    expect(
      p.records.singleWhere((r) => r['entity'] == 'SONG')['payload']['note'],
      'server note',
    );
    expect(p.conflicts, isEmpty);
  });
  test('legacy backup without suitability preserves current heart during a note merge', () async {
    remoteSong['is_suitable'] = true;
    final p = await preview(
      await input(
        legacySuitability: true,
        baseNote: 'server note',
        note: 'imported note',
      ),
    );
    final song =
        p.records.singleWhere((r) => r['entity'] == 'SONG')['payload'] as Map;
    expect(p.conflicts, isEmpty);
    expect(song['is_suitable'], isTrue);
    expect(song['note'], 'imported note');
  });
  test('same-field local/server changes stay unresolved without overwrite or DB writes', () async {
    final i = await input(note: 'offline draft');
    final before = await store.captureExportLocal();
    final p = await preview(i), after = await store.captureExportLocal();
    expect(
      p.conflicts.any(
        (c) => c.code == 'REVISION_FIELD_CONFLICT' && c.fields.contains('note'),
      ),
      true,
    );
    expect(
      p.records.singleWhere((r) => r['entity'] == 'SONG')['payload']['note'],
      'server note',
    );
    expect(after['copies'], before['copies']);
    expect(after['changes'], before['changes']);
    expect(p.requiresChoice, true);
  });
  test('different-field changes can be proposed while retaining newer server title/revision', () async {
    remoteSong['note'] = 'base note';
    final p = await preview(await input(note: 'offline draft'));
    final song = p.records.singleWhere((r) => r['entity'] == 'SONG')['payload'];
    expect(song['note'], 'offline draft');
    expect(song['title'], 'server title');
    expect(song['revision'], 2);
    expect(p.conflicts, isEmpty);
  });
  test(
    'newer or incompatible backup baseline cannot produce automatic patches',
    () async {
      final p = await preview(
        await input(note: 'offline draft', baseRevision: 3),
      );
      expect(
        p.conflicts.any((c) => c.code == 'INVALID_OR_NEWER_BASELINE'),
        true,
      );
    },
  );
  test('destination pending local change conflicts with incoming edit rather than being replaced', () async {
    remoteSong['note'] = 'base note';
    final paths = await AccountPaths.create(dir, owner, AppEnvironment.dev);
    final db = AccountDatabase(
      NativeDatabase(await paths.databaseFile()),
      userId: owner,
      environment: AppEnvironment.dev,
    );
    await db.verifyReady();
    await db.customStatement(
      'INSERT INTO metadata_copies(user_id,entity_type,entity_id,server_revision,server_payload,local_payload,updated_at) VALUES(?,?,?,?,?,?,1)',
      [
        owner,
        'SONG',
        id(701),
        2,
        jsonEncode(remoteSong),
        jsonEncode({...remoteSong, 'note': 'destination draft'}),
      ],
    );
    await db.close();
    final p = await preview(await input(note: 'incoming draft'));
    expect(p.conflicts.any((c) => c.code == 'DESTINATION_LOCAL_CHANGE'), true);
    final capture = await store.captureExportLocal();
    expect(
      jsonDecode(
        (capture['copies'] as List).single['local_payload'] as String,
      )['note'],
      'destination draft',
    );
  });
  test(
    'server absence never authorizes overwriting a newer unsent local UUID',
    () async {
      final local = {...remoteSong, 'note': 'newer unsent draft'};
      await store.saveEdit(
        LocalEdit(
          opId: id(990),
          entity: LocalEntity.song,
          entityId: id(701),
          operation: LocalOperation.create,
          baseRevision: 0,
          draft: local,
          changes: {'id': id(701), 'title': local['title']},
        ),
      );
      final p = await preview(
        await input(note: 'older backup draft', omitSong: true),
      );
      expect(
        p.conflicts.any((c) => c.code == 'LOCAL_ONLY_UUID_CONFLICT'),
        true,
      );
      expect(
        p.records.any(
          (r) => r['entity'] == 'SONG' && r['resource_id'] == id(701),
        ),
        false,
      );
      expect(
        jsonDecode(
          (await store.readMetadata(LocalEntity.song, id(701)))!.localJson!,
        )['note'],
        'newer unsent draft',
      );
      expect((await store.pendingMutations()).length, 1);
    },
  );
  test('identical existing file is reusable and never rewritten', () async {
    final file = await localFile();
    await file.writeAsBytes(bytes);
    final p = await preview(await input());
    expect(p.reuseFileIds, {id(702)});
    expect(p.fileIds, {id(702)});
    expect(await file.readAsBytes(), bytes);
  });
  test('different existing checksum is held and old bytes are preserved even without a DB row', () async {
    final file = await localFile();
    await file.writeAsBytes([9, 8, 7]);
    final p = await preview(await input());
    expect(
      p.conflicts.any((c) => c.code == 'LOCAL_FILE_CHECKSUM_CONFLICT'),
      true,
    );
    expect(p.fileIds, isEmpty);
    expect(await file.readAsBytes(), [9, 8, 7]);
  });
  test(
    'record snapshot and server file descriptions are checked independently',
    () async {
      final p = await preview(
        await input(backupSha: 'b' * 64, fileSpec: true, serverSha: 'c' * 64),
      );
      expect(p.fileIds, isEmpty);
      expect(
        p.conflicts.any((c) => c.code == 'SERVER_FILE_DESCRIPTION_MISMATCH'),
        true,
      );
    },
  );
  test('account lease loss aborts preview rather than converting it to a writable conflict', () async {
    final i = await input();
    await manager.logout();
    await expectLater(preview(i), throwsA(anything));
  });
  testWidgets(
    'preview displays base/server/local and no default winner or restore success',
    (tester) async {
      final p = (await tester.runAsync(
        () async => preview(await input(note: 'offline draft')),
      ))!;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SafeArea(child: ImportConflictPreviewList(preview: p)),
          ),
        ),
      );
      expect(find.textContaining('다른 내용 확인'), findsOneWidget);
      expect(find.textContaining('최신 서버:'), findsOneWidget);
      expect(find.textContaining('백업 로컬:'), findsOneWidget);
      expect(find.textContaining('이번에 가져오지 않아요'), findsOneWidget);
      expect(find.text('복원 완료'), findsNothing);
      expect(find.textContaining('REVISION_FIELD_CONFLICT'), findsNothing);
      expect(find.textContaining('user_id'), findsNothing);
      expect(find.textContaining('offline draft'), findsOneWidget);
    },
  );
}
