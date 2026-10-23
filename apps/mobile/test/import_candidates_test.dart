import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/backup/export/export_baseline.dart';
import 'package:song_record/features/backup/export/export_data.dart';
import 'package:song_record/features/backup/export/export_manifest.dart';
import 'package:song_record/features/backup/import/import_candidate_holds.dart';
import 'package:song_record/features/backup/import/import_candidates.dart';
import 'package:song_record/features/backup/import/import_decision.dart';
import 'package:song_record/features/backup/import/import_identity.dart';
import 'package:song_record/features/backup/import/import_preflight.dart';
import 'package:song_record/features/backup/import/import_validation.dart';
import 'package:song_record/features/backup/import/import_zip.dart';

import 'export_audio_test.dart' as audio;
import 'import_preflight_test.dart' show ImportTransport;
import 'support/business_snapshot_fixture.dart';

String id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
void main() {
  late Directory dir;
  late AccountStoreManager manager;
  late ImportServerBaseline current;
  late String owner, songId;
  final now = DateTime.utc(2026, 9, 30);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('import-legacy-candidates-');
    manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => dir,
      temporaryDirectory: () async => dir,
    );
    final f = businessSnapshotFixture();
    owner = f['owner'] as String;
    songId =
        ((f['pages'] as List).singleWhere(
                      (dynamic p) => p['entity'] == 'SONG',
                    )['entries']
                    as List)
                .first['resource_id']
            as String;
    final store = await manager.openAccount(owner);
    current = await ImportPreflight(
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
  });
  tearDown(() async {
    await manager.logout();
    await dir.delete(recursive: true);
  });
  Future<ImportIdentityPlan> identity({
    String brand = 'KY',
    String snapshotBrand = 'KY',
    bool linked = false,
    String title = '검사 곡',
    bool absentSnapshot = false,
  }) async {
    final candidate = {
      'id': id(101),
      'playlist_id': id(100),
      'song_id': linked ? songId : null,
      'candidate_brand': brand,
      'candidate_number': '00211',
      'candidate_snapshot': absentSnapshot
          ? null
          : {
              'brand': snapshotBrand,
              'number': '00211',
              'title': title,
              'artist': '가수',
              'version_code': 'NORMAL',
            },
    };
    final normal = {
      'id': id(102),
      'playlist_id': id(100),
      'song_id': null,
      'candidate_brand': 'TJ',
      'candidate_number': '00211',
      'candidate_snapshot': {
        'brand': 'TJ',
        'number': '00211',
        'title': '정상 곡',
        'artist': '가수',
      },
    };
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
          audio.recording(1),
          audio.recording(2),
          for (final p in [candidate, normal])
            {
              'entity_type': 'PLAYLIST_ITEM',
              'entity_id': p['id'],
              'server_revision': 0,
              'tombstone': 0,
              'server_payload': null,
              'local_payload': jsonEncode(p),
            },
        ],
        'changes': <Object?>[],
        'recording_inputs': <Object?>[],
      },
    );
    final data = ExportData.fromBaseline(baseline);
    final manifest = ExportManifest.fromBaseline(
      baseline,
      metadataCount: data.metadataCount,
      files: [
        for (final n in [1, 2])
          ExportAudioEntry(
            recordingId: audio.id(n),
            selected: true,
            included: true,
            missingReason: null,
            sha256: 'a' * 64,
            sizeBytes: 5,
            durationMs: 12000,
          ),
      ],
    );
    final controller = ImportDecision(
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
    addTearDown(controller.dispose);
    await controller.check();
    return planImportIdentities(
      consent: controller.approveWhole(),
      server: current,
      requireCurrent: () {},
    );
  }

  test('only unlinked KY candidate held; same-number TJ and every normal file/info preserved', () async {
    final source = await identity(), before = jsonEncode(source.records);
    final result = planImportCandidates(source, requireCurrent: () {});
    expect(result.held.length, 1);
    expect(result.held.single.code, 'LEGACY_KY_CANDIDATE');
    expect(result.held.single.original['payload']['candidate_brand'], 'KY');
    expect(result.records.any((r) => r['resource_id'] == id(101)), false);
    expect(
      result.records.singleWhere(
        (r) => r['resource_id'] == id(102),
      )['payload']['candidate_number'],
      '00211',
    );
    expect(result.records.where((r) => r['entity'] == 'RECORDING').length, 2);
    expect(result.fileIds, source.fileIds);
    expect(jsonEncode(source.records), before);
    expect(result.held.single.searchQuery, '검사 곡');
  });
  test('KY snapshot cannot sneak through a TJ row brand', () async {
    final result = planImportCandidates(
      await identity(brand: 'TJ'),
      requireCurrent: () {},
    );
    expect(result.held.single.code, 'LEGACY_KY_CANDIDATE');
  });
  test(
    'registered song item is not reinterpreted as an unregistered KY candidate',
    () async {
      final result = planImportCandidates(
        await identity(linked: true),
        requireCurrent: () {},
      );
      expect(result.held, isEmpty);
      expect(result.records.any((r) => r['resource_id'] == id(101)), true);
    },
  );
  test(
    'unsupported candidate held but never converted or causes file discard',
    () async {
      final source = await identity(brand: 'OTHER', snapshotBrand: 'OTHER');
      final result = planImportCandidates(source, requireCurrent: () {});
      expect(result.held.single.code, 'INVALID_CANDIDATE');
      expect(result.fileIds, source.fileIds);
    },
  );
  test('missing candidate snapshot stays held rather than fabricated source evidence', () async {
    final result = planImportCandidates(
      await identity(brand: 'TJ', absentSnapshot: true),
      requireCurrent: () {},
    );
    expect(result.held.single.code, 'INVALID_CANDIDATE');
  });
  test('search title uses Unicode scalar limit and retained original is immutable-by-copy', () async {
    final result = planImportCandidates(
      await identity(title: '🎵' * 201),
      requireCurrent: () {},
    );
    final hold = result.held.single;
    expect(hold.searchQuery.runes.length, 200);
    hold.original['payload']['candidate_brand'] = 'TJ';
    expect(hold.original['payload']['candidate_brand'], 'KY');
    expect(() => result.fileIds.clear(), throwsUnsupportedError);
  });
  test('revoked account guard cannot generate a candidate plan', () async {
    final source = await identity();
    expect(
      () => planImportCandidates(
        source,
        requireCurrent: () {
          throw StateError('revoked');
        },
      ),
      throwsStateError,
    );
  });
  testWidgets(
    'hold reason and explicit TJ navigation do not mutate legacy candidate',
    (tester) async {
      final result = planImportCandidates(
        await identity(),
        requireCurrent: () {},
      );
      ImportCandidateHold? chosen;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SafeArea(
              child: ImportCandidateHolds(
                holds: result.held,
                onTjSearch: (h) {
                  chosen = h;
                },
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('같은 곡을 TJ에서 찾아 다시 선택'), findsOneWidget);
      expect(chosen, isNull);
      await tester.tap(find.text('TJ에서 찾아 다시 선택'));
      await tester.pump();
      expect(chosen!.itemId, id(101));
      expect(chosen!.original['payload']['candidate_brand'], 'KY');
    },
  );
}
