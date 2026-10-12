import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/backup/export/export_baseline.dart';
import 'package:song_record/features/backup/export/export_data.dart';
import 'package:song_record/features/backup/export/export_manifest.dart';
import 'package:song_record/features/backup/import/import_application.dart';
import 'package:song_record/features/backup/import/import_candidates.dart';
import 'package:song_record/features/backup/import/import_conflicts.dart';
import 'package:song_record/features/backup/import/import_decision.dart';
import 'package:song_record/features/backup/import/import_identity.dart';
import 'package:song_record/features/backup/import/import_preflight.dart';
import 'package:song_record/features/backup/import/import_validation.dart';
import 'package:song_record/features/backup/import/import_zip.dart';

import '../tool/import_transfer_verification.dart' show FixtureTransport;

String id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
void main() {
  test('reviewed manual-song application is durable and same archive is not duplicated', () async {
    final root = await Directory.systemTemp.createTemp(
      'p23-import-application-',
    );
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    final owner = '11111111-1111-4111-8111-111111111111',
        store = await manager.openAccount(owner);
    final transport = FixtureTransport();
    final preflight = ImportPreflight(
      store: store,
      transport: transport,
      session: () async => AuthSession(
        userId: owner,
        deviceId: id(1),
        accessToken: 'synthetic',
        refreshToken: 'synthetic',
        accessExpiresAt: DateTime.now().add(const Duration(hours: 1)),
        refreshExpiresAt: DateTime.now().add(const Duration(days: 1)),
      ),
      requireCurrent: store.requireActive,
      clock: () => DateTime.now().toUtc(),
    );
    Future<ImportServerBaseline> current() => preflight.readReady(
      transport.fixture['manifest']['snapshot_token'] as String,
    );
    final baseline = ExportBaseline(
      id: id(501),
      owner: owner,
      includeTrash: false,
      manifest: null,
      createdAt: DateTime.now().toUtc(),
      entries: const [],
      local: {
        'source_user_id': owner,
        'local_cutoff_at': DateTime.now().toUtc().toIso8601String(),
        'baseline': const [
          {'baseline_complete': 0, 'last_change_seq': null, 'updated_at': null},
        ],
        'changes': const [],
        'recording_inputs': const [],
        'copies': [
          {
            'entity_type': 'SONG',
            'entity_id': id(502),
            'server_revision': 0,
            'server_payload': null,
            'tombstone': 0,
            'local_payload': jsonEncode({
              'id': id(502),
              'source_type': 'MANUAL',
              'title': '복원 제목',
              'artist': '복원 가수',
              'lifecycle_state': 'ACTIVE',
              'version_code': 'LIVE',
              'note': '보존할 메모',
            }),
          },
          {
            'entity_type': 'PLAYLIST',
            'entity_id': id(503),
            'server_revision': 0,
            'server_payload': null,
            'tombstone': 0,
            'local_payload': jsonEncode({'id': id(503), 'name': '복원 목록'}),
          },
          {
            'entity_type': 'PLAYLIST_ITEM',
            'entity_id': id(504),
            'server_revision': 0,
            'server_payload': null,
            'tombstone': 0,
            'local_payload': jsonEncode({
              'id': id(504),
              'playlist_id': id(503),
              'song_id': id(502),
              'position': 0,
            }),
          },
        ],
      },
    );
    final data = ExportData.fromBaseline(baseline),
        manifest = ExportManifest.fromBaseline(
          baseline,
          metadataCount: 3,
          files: const [],
        );
    final decision = ImportDecision(
      requireCurrent: store.requireActive,
      validate: (_) async => ValidatedImport(
        ImportZipStaging(root, const {}),
        manifest,
        ImportData.decode(data.encode(), manifest),
        const [],
      ),
    );
    final archive = File('${root.path}/archive-test')
      ..writeAsStringSync('owned synthetic test archive');
    try {
      await decision.check();
      final consent = decision.approveWhole(), remote = await current();
      final candidate = planImportCandidates(
        planImportIdentities(
          consent: consent,
          server: remote,
          requireCurrent: store.requireActive,
        ),
        requireCurrent: store.requireActive,
      );
      final preview = await previewImportConflicts(
        consent: consent,
        candidates: candidate,
        server: remote,
        store: store,
        requireCurrent: store.requireActive,
      );
      final result = await applyReviewedImport(
        store: store,
        consent: consent,
        preview: preview,
        server: remote,
        archive: archive,
        synchronize: () async {},
        refresh: current,
        requireCurrent: store.requireActive,
        held: 0,
      );
      expect(result.information, 2);
      expect(
        result.pending,
        greaterThan(0),
      ); // A list relation is not counted before its server ACK.
      final queued = await store.pendingMutations();
      expect(
        queued.any(
          (m) =>
              m.entity == LocalEntity.playlist &&
              (jsonDecode(m.payload) as Map).containsKey('song_ids'),
        ),
        true,
      );
      expect(result.files, 0);
      final saved = await store.readMetadata(LocalEntity.song, id(502));
      expect(jsonDecode(saved!.localJson!)['note'], '보존할 메모');
      final count = (await store.pendingMutations()).length;
      await applyReviewedImport(
        store: store,
        consent: consent,
        preview: preview,
        server: remote,
        archive: archive,
        synchronize: () async {},
        refresh: current,
        requireCurrent: store.requireActive,
        held: 0,
      );
      expect((await store.pendingMutations()).length, count);
      await expectLater(
        store.importJobMatches(manifest.exportId, '0' * 64),
        throwsStateError,
      );
    } finally {
      decision.dispose();
      await manager.logout();
      await root.delete(recursive: true);
    }
  });
}
