import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/backup/export/export_baseline.dart';
import 'package:song_record/features/backup/export/export_data.dart';
import 'package:song_record/features/backup/export/export_manifest.dart';
import 'package:song_record/features/backup/import/import_decision.dart';
import 'package:song_record/features/backup/import/import_outcome.dart';
import 'package:song_record/features/backup/import/import_outcome_view.dart';
import 'package:song_record/features/backup/import/import_preflight.dart';
import 'package:song_record/features/backup/import/import_validation.dart';
import 'package:song_record/features/backup/import/import_zip.dart';

import 'import_preflight_test.dart' show ImportTransport;
import 'support/business_snapshot_fixture.dart';

String id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
void main() {
  final owner = id(1), a = id(2), b = id(3), c = id(4);
  Map<String, dynamic> row(String entity, String key, Map<String, dynamic> p) =>
      {
        'entity': entity,
        'resource_id': key,
        'payload': {'user_id': owner, ...p},
      };
  List<Map<String, dynamic>> records() => [
    for (final r in [a, b, c])
      row('RECORDING', r, {
        'metadata_state': 'SAVED',
        'lifecycle_state': 'ACTIVE',
      }),
  ];
  test('latest roles and pins select only verified active files, not all restored files', () {
    final r = [
      ...records(),
      row('SONG_CLOUD_SELECTION', id(9), {
        'representative_id': a,
        'latest_id': a,
        'lowest_tier_id': null,
      }),
      row('PIN_SLOT', owner, {
        'current_recording_id': b,
        'pending_recording_id': null,
      }),
    ];
    expect(
      importUploadTargets(
        owner: owner,
        currentRows: r,
        verifiedFiles: {a, b, c},
      ),
      {a, b},
    );
  });
  test('missing current roles grant no blanket upload', () {
    expect(
      importUploadTargets(
        owner: owner,
        currentRows: records(),
        verifiedFiles: {a, b, c},
      ),
      isEmpty,
    );
  });
  test(
    'unacknowledged, trashed, stored and missing-file records are excluded',
    () {
      final r = [
        row('SONG_CLOUD_SELECTION', id(9), {
          'representative_id': a,
          'latest_id': b,
          'lowest_tier_id': c,
        }),
        row('RECORDING', a, {
          'metadata_state': 'DRAFT',
          'lifecycle_state': 'ACTIVE',
        }),
        row('RECORDING', b, {
          'metadata_state': 'SAVED',
          'lifecycle_state': 'TRASHED',
        }),
        row('RECORDING', c, {
          'metadata_state': 'SAVED',
          'lifecycle_state': 'ACTIVE',
        }),
        row('RECORDING_ASSET', c, {'cloud_state': 'STORED'}),
      ];
      expect(
        importUploadTargets(
          owner: owner,
          currentRows: r,
          verifiedFiles: {a, b, c},
        ),
        isEmpty,
      );
      expect(
        importUploadTargets(
          owner: owner,
          currentRows: [...records(), r.first],
          verifiedFiles: {},
        ),
        isEmpty,
      );
    },
  );
  test('foreign policy owner is rejected', () {
    expect(
      () => importUploadTargets(
        owner: owner,
        currentRows: [
          row('PIN_SLOT', owner, {'user_id': id(99)}),
        ],
        verifiedFiles: {},
      ),
      throwsFormatException,
    );
  });
  test(
    'actual server/local presence is distinguished from missing information',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'import-outcome-actual-',
      );
      final manager = AccountStoreManager(
        environment: AppEnvironment.dev,
        directory: () async => dir,
        temporaryDirectory: () async => dir,
      );
      final fixture = businessSnapshotFixture(),
          now = DateTime.utc(2026, 9, 30);
      final owner = fixture['owner'] as String;
      final store = await manager.openAccount(owner);
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
            {
              'baseline_complete': 0,
              'last_change_seq': null,
              'updated_at': null,
            },
          ],
          'copies': <Object?>[],
          'changes': <Object?>[],
          'recording_inputs': <Object?>[],
        },
      );
      final data = ExportData.fromBaseline(baseline),
          manifest = ExportManifest.fromBaseline(
            baseline,
            metadataCount: 0,
            files: const [],
          );
      final decision = ImportDecision(
        requireCurrent: () {},
        validate: (_) async => ValidatedImport(
          ImportZipStaging(dir, const {}),
          manifest,
          ImportData.decode(data.encode(), manifest),
          const [],
        ),
      );
      try {
        await decision.check();
        final consent = decision.approveWhole();
        await store.prepareImportApply(
          jobId: id(801),
          manifestHash: 'a' * 64,
          items: [],
        );
        final current = await ImportPreflight(
          store: store,
          transport: ImportTransport(fixture),
          session: () async => AuthSession(
            userId: owner,
            deviceId: id(802),
            accessToken: 'fixture',
            refreshToken: 'fixture',
            accessExpiresAt: now.add(const Duration(hours: 1)),
            refreshExpiresAt: now.add(const Duration(days: 1)),
          ),
          requireCurrent: () {},
          clock: () => now,
        ).readReady(fixture['manifest']['snapshot_token'] as String);
        final song = current.entries
            .firstWhere((e) => e.entity == 'SONG')
            .resourceId;
        final report = await readImportOutcome(
          store: store,
          consent: consent,
          jobId: id(801),
          plannedRecords: [
            {'entity': 'SONG', 'resource_id': song},
            {'entity': 'SONG', 'resource_id': id(999)},
          ],
          held: 0,
          conflicts: 0,
          refreshPolicy: () async => current,
          requireCurrent: () {},
        );
        expect(report.information, 1);
        expect(report.pending, 1);
        expect(report.complete, false);
        expect(report.files, 0);
        expect(report.uploadCandidates, isEmpty);
      } finally {
        decision.dispose();
        await manager.logout();
        await dir.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'separate information/files/holds/conflicts and no blanket success',
    (tester) async {
      final result = ImportOutcome(
        information: 100,
        files: 25,
        missingFiles: 75,
        held: 2,
        conflicts: 1,
        pending: 3,
        uploadCandidates: {a},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ImportOutcomeView(result: result)),
        ),
      );
      expect(result.complete, false);
      expect(find.text('가져오기 확인 완료'), findsNothing);
      expect(find.text('확인된 정보'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      expect(find.text('검증된 이 기기 파일'), findsOneWidget);
      expect(find.text('25'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -450));
      await tester.pump();
      expect(find.text('충돌'), findsOneWidget);
    },
  );
}
