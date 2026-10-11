import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/files/local_preservation.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/snapshot_response.dart';
import 'package:song_record/features/backup/export/export_audio.dart';
import 'package:song_record/features/backup/export/export_baseline.dart';
import 'package:song_record/features/backup/export/export_data.dart';
import 'package:song_record/features/backup/export/export_manifest.dart';

import 'support/completed_capture_fixture.dart' as fixture;

const owner = fixture.owner;
const token = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
String id(int n) => 'bbbbbbbb-bbbb-4bbb-8bbb-${n.toString().padLeft(12, '0')}';
final now = DateTime.utc(2026, 10, 11);
Map<String, Object?> row(
  String entity,
  String resource,
  Map<String, Object?> payload,
) => {
  'entity_type': entity,
  'entity_id': resource,
  'server_revision': 1,
  'tombstone': 0,
  'local_payload': jsonEncode(payload),
  'server_payload': null,
};
Map<String, Object?> recording(
  int n, {
  String lifecycle = 'ACTIVE',
  String metadata = 'SAVED',
  bool cloud = false,
}) => row('RECORDING', id(n), {
  'id': id(n),
  'lifecycle_state': lifecycle,
  'metadata_state': metadata,
  'song_id': null,
  'file': fixture.spec(),
});
Map<String, Object?> asset(int n) => row('RECORDING_ASSET', id(n), {
  'recording_id': id(n),
  'cloud_state': 'STORED',
  'generation': token,
  'cloud_revision': 2,
  'sha256': fixture.spec()['sha256'],
  'verified_size': fixture.bytes.length,
});
ExportBaseline baseline(
  List<Map<String, Object?>> copies, {
  bool online = false,
  bool trash = false,
  List<Map<String, Object?>> states = const [],
}) => ExportBaseline(
  id: token,
  owner: owner,
  includeTrash: trash,
  createdAt: now,
  entries: const [],
  manifest: online
      ? SnapshotManifest.decode(
          jsonEncode({
            'snapshot_token': token,
            'status': 'READY',
            'schema_version': 1,
            'snapshot_cursor': 7,
            'captured_at': now.toIso8601String(),
            'ready_at': now.toIso8601String(),
            'expires_at': now
                .add(const Duration(minutes: 30))
                .toIso8601String(),
            'manifest_hash': 'a' * 64,
            'entity_counts': {
              for (final e in snapshotEntities)
                e: e == 'USER_SYNC_STATE' ? 1 : 0,
            },
          }),
          expectedToken: token,
          now: now,
        )
      : null,
  local: {
    'source_user_id': owner,
    'local_cutoff_at': now.toIso8601String(),
    'copies': copies,
    'changes': <Object>[],
    'recording_inputs': <Object>[],
    'file_states': states,
  },
);

class Download implements PreservationDownload {
  int active = 0, maxActive = 0, calls = 0;
  Future<void> Function()? during;
  @override
  Future<Uint8List> download(
    PreservationObject object,
    Future<void> Function() guard,
  ) async {
    active++;
    calls++;
    if (active > maxActive) maxActive = active;
    try {
      await guard();
      await during?.call();
      await guard();
      return fixture.bytes;
    } finally {
      active--;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('active orphan and completed draft are copied; optional trash is not missing', () async {
    final b = baseline([
      recording(1),
      recording(2, metadata: 'DRAFT'),
      recording(3, lifecycle: 'TRASHED'),
    ]);
    final staged = <String>[];
    final collector = ExportAudioCollector(
      requireCurrent: () {},
      state: (_) async => {},
      local: (_) async => fixture.bytes,
      stage: (job, id, hash, size, bytes) async {
        staged.add(id);
      },
    );
    final files = await collector.collect(b, ExportData.fromBaseline(b));
    expect(staged, [id(1), id(2)]);
    expect(files.where((f) => f.included), hasLength(2));
    expect(files.last.selected, false);
    expect(files.last.missingReason, ExportMissingReason.trashNotSelected);
    final selected = baseline([
      recording(3, lifecycle: 'TRASHED'),
    ], trash: true);
    expect(
      (await collector.collect(
        selected,
        ExportData.fromBaseline(selected),
      )).single.included,
      true,
    );
  });
  test('offline server-only and other-device-only audio retain different reasons with no download', () async {
    final b = baseline([recording(1), asset(1), recording(2)]),
        download = Download();
    final c = ExportAudioCollector(
      requireCurrent: () {},
      state: (_) async => {},
      local: (_) async => null,
      stage: (_, _, _, _, _) async => fail('no file'),
      download: download,
    );
    final files = await c.collect(b, ExportData.fromBaseline(b));
    expect(files[0].missingReason, ExportMissingReason.offlineServerOnly);
    expect(files[1].missingReason, ExportMissingReason.fileNotOnDevice);
    expect(download.calls, 0);
  });
  test(
    'server files are sequential and checksum-proved only in export staging',
    () async {
      final b = baseline([
        recording(1),
        asset(1),
        recording(2),
        asset(2),
      ], online: true);
      final download = Download()
        ..during = () async =>
            Future<void>.delayed(const Duration(milliseconds: 5));
      final staged = <String>[];
      final c = ExportAudioCollector(
        requireCurrent: () {},
        state: (_) async => {},
        local: (_) async => null,
        stage: (job, id, hash, size, bytes) async {
          expect(job, token);
          expect(bytes, fixture.bytes);
          staged.add(id);
        },
        download: download,
      );
      expect(
        (await c.collect(
          b,
          ExportData.fromBaseline(b),
        )).every((f) => f.included),
        true,
      );
      expect(staged, [id(1), id(2)]);
      expect(download.calls, 2);
      expect(download.maxActive, 1);
    },
  );
  test('different bytes never become included; permanently unfinished audio is omitted', () async {
    final second = row('RECORDING', id(2), {
      'id': id(2),
      'metadata_state': 'DRAFT',
      'file': {'size_bytes': 5},
    });
    final b = baseline([recording(1), second]);
    final c = ExportAudioCollector(
      requireCurrent: () {},
      state: (_) async => {},
      local: (_) async => Uint8List.fromList([5, 4, 3, 2, 1]),
      stage: (_, _, _, _, _) async => fail('checksum failure'),
    );
    final files = await c.collect(b, ExportData.fromBaseline(b));
    expect(files.first.missingReason, ExportMissingReason.checksumMismatch);
    expect(files.last.missingReason, ExportMissingReason.incompleteRecording);
  });
  test('delete during server download becomes missing without retrying or reinstalling originals', () async {
    final b = baseline([recording(1), asset(1)], online: true);
    var deleted = false;
    final download = Download()
      ..during = () async {
        deleted = true;
      };
    final c = ExportAudioCollector(
      requireCurrent: () {},
      state: (_) async => {'deleted': deleted},
      local: (_) async => null,
      stage: (_, _, _, _, _) async => fail('deleted'),
      download: download,
    );
    final files = await c.collect(b, ExportData.fromBaseline(b));
    expect(files.single.missingReason, ExportMissingReason.fileDeleted);
    expect(download.calls, 1);
  });
  test('bounded download timeout is a missing file; cancellation and account change stop the job', () async {
    final b = baseline([recording(1)], online: true);
    final timeout = ExportAudioCollector(
      requireCurrent: () {},
      state: (_) async => {},
      local: (_) => Completer<Uint8List?>().future,
      timeout: const Duration(milliseconds: 5),
      stage: (_, _, _, _, _) async => fail('timeout'),
    );
    expect(
      (await timeout.collect(
        b,
        ExportData.fromBaseline(b),
      )).single.missingReason,
      ExportMissingReason.downloadFailed,
    );
    final wait = Completer<Uint8List?>();
    final cancel = ExportAudioCollector(
      requireCurrent: () {},
      state: (_) async => {},
      local: (_) => wait.future,
      stage: (_, _, _, _, _) async => fail('cancelled'),
    );
    final running = cancel.collect(b, ExportData.fromBaseline(b));
    cancel.cancel();
    wait.complete(fixture.bytes);
    await expectLater(running, throwsA(isA<ExportCancelled>()));
    var current = true;
    final c = ExportAudioCollector(
      requireCurrent: () {
        if (!current) throw StateError('expired');
      },
      state: (_) async => {},
      local: (_) async {
        current = false;
        return fixture.bytes;
      },
      stage: (_, _, _, _, _) async => fail('account'),
    );
    await expectLater(
      c.collect(b, ExportData.fromBaseline(b)),
      throwsStateError,
    );
  });
  test('disk/staging failure stops rather than claiming a partial successful backup', () async {
    final b = baseline([recording(1)]);
    final c = ExportAudioCollector(
      requireCurrent: () {},
      state: (_) async => {},
      local: (_) async => fixture.bytes,
      stage: (_, _, _, _, _) async {
        throw const FileSystemException('Synthetic no space');
      },
    );
    await expectLater(
      c.collect(b, ExportData.fromBaseline(b)),
      throwsA(isA<FileSystemException>()),
    );
  });
  test('real SQLite stages a detached verified file; explicit cleanup remains possible and is not reversed', () async {
    final root = await Directory.systemTemp.createTemp('sr-export-audio-');
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    try {
      final active = await manager.openAccount(owner);
      await fixture.capture(LocalRepository(active));
      final local = await active.captureExportLocal();
      final b = ExportBaseline(
        id: token,
        owner: owner,
        includeTrash: false,
        manifest: null,
        createdAt: now,
        entries: const [],
        local: local,
      );
      final c = ExportAudioCollector.forStore(active);
      expect(
        (await c.collect(b, ExportData.fromBaseline(b))).single.included,
        true,
      );
      final paths = await AccountPaths.create(root, owner, AppEnvironment.dev);
      expect(
        await (await paths.exportFile(
          token,
          'audio/${fixture.rec}.m4a',
        )).readAsBytes(),
        fixture.bytes,
      );
      expect(await active.readLocalAudio(fixture.rec), fixture.bytes);
      await active.removeConfirmedDeviceAudio(
        recording: fixture.rec,
        checksum: fixture.spec()['sha256'] as String,
        size: fixture.bytes.length,
        confirmed: true,
      );
      final deleted = await c.collect(b, ExportData.fromBaseline(b));
      expect(deleted.single.missingReason, ExportMissingReason.fileDeleted);
      await expectLater(active.readLocalAudio(fixture.rec), throwsStateError);
      // Private stage is independent; original remains deleted and metadata/queue remain.
      expect(
        await (await paths.exportFile(
          token,
          'audio/${fixture.rec}.m4a',
        )).exists(),
        true,
      );
      expect((await active.captureExportLocal())['changes'], hasLength(1));
      await expectLater(
        paths.exportFile(token, '../audio/${fixture.rec}.m4a'),
        throwsArgumentError,
      );
    } finally {
      await manager.logout();
      await root.delete(recursive: true);
    }
  });
}
