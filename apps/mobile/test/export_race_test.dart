import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/features/backup/export/export_audio.dart';
import 'package:song_record/features/backup/export/export_baseline.dart';
import 'package:song_record/features/backup/export/export_controller.dart';
import 'package:song_record/features/backup/export/export_job.dart';
import 'package:song_record/features/backup/export/export_manifest.dart';
import 'package:song_record/features/backup/export/export_zip.dart';

import 'support/completed_capture_fixture.dart' as capture;

class Output implements BackupDestination {
  Future<bool> Function()? during;
  int calls = 0;
  @override
  Future<void> cancel() async {}
  @override
  Future<bool> save(
    ExportZip zip, {
    required String owner,
    required String environment,
    required String jobId,
  }) async {
    calls++;
    expect(await zip.file.exists(), isTrue);
    return await during?.call() ?? true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AccountStoreManager manager;
  late AccountStore store;
  late LocalRepository repo;
  late Output output;
  int freezes = 0;
  const jobId = '21212121-2121-4121-8121-212121212209';
  Future<void> deleteOriginal() => store.removeConfirmedDeviceAudio(
    recording: capture.rec,
    checksum: capture.spec()['sha256'] as String,
    size: capture.bytes.length,
    confirmed: true,
  );
  ExportController create({int space = 100000000}) => ExportController(
    owner: capture.owner,
    environment: 'dev',
    requireCurrent: store.requireActive,
    prepare: () async => space,
    freeze: (online, trash) async {
      freezes++;
      return ExportBaseline(
        id: jobId,
        owner: capture.owner,
        includeTrash: false,
        manifest: null,
        createdAt: DateTime.now().toUtc(),
        entries: const [],
        local: await store.captureExportLocal(),
      );
    },
    createJob: (id) => ExportJob(
      owner: capture.owner,
      id: id,
      file: (name) => store.privateExportFile(id, name),
      requireCurrent: store.requireActive,
    ),
    createCollector: () => ExportAudioCollector.forStore(store),
    destination: output,
    availableBytes: () async => space,
    latestJob: store.latestExportJob,
  );
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sr-export-race-');
    manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    store = await manager.openAccount(capture.owner);
    repo = LocalRepository(store);
    await capture.capture(repo);
    await repo.preserveRecordingInput(capture.rec, {'note': 'before cutoff'});
    output = Output();
    freezes = 0;
  });
  tearDown(() async {
    await manager.logout();
    await root.delete(recursive: true);
  });

  test('edit after cutoff stays local; cached retry omits explicitly deleted audio without revival', () async {
    final controller = create();
    output.during = () async {
      await repo.preserveRecordingInput(capture.rec, {'note': 'after cutoff'});
      return false;
    };
    await controller.start(online: false, includeTrash: false);
    expect(controller.phase, BackupPhase.cancelled);
    final oldZip = await controller.artifact!.file.readAsBytes();
    expect(controller.data!.encode(), contains('before cutoff'));
    expect(controller.data!.encode(), isNot(contains('after cutoff')));
    await deleteOriginal();
    output.during = null;
    await controller.start(online: false, includeTrash: false);
    expect(controller.phase, BackupPhase.completed);
    expect(
      controller.manifest!.files.single.missingReason,
      ExportMissingReason.fileDeleted,
    );
    expect(controller.manifest!.includedAudioCount, 0);
    expect(freezes, 1);
    expect(await controller.artifact!.file.readAsBytes(), isNot(oldZip));
    expect(
      (await store.captureExportLocal())['recording_inputs'].toString(),
      contains('after cutoff'),
    );
    expect((await store.captureExportLocal())['changes'], hasLength(1));
    await expectLater(store.readLocalAudio(capture.rec), throwsStateError);
    controller.dispose();
  });

  test('deletion during external output is not claimed complete; resume does not restore original', () async {
    final controller = create();
    output.during = () async {
      await deleteOriginal();
      return true;
    };
    await controller.start(online: false, includeTrash: false);
    expect(controller.phase, BackupPhase.failed);
    expect(controller.artifact, isNull);
    expect(controller.manifest!.missingAudioCount, 1);
    await controller.job!.resume();
    final restarted = create();
    await restarted.restore();
    expect(restarted.phase, BackupPhase.resumable);
    expect(restarted.manifest!.includedAudioCount, 0);
    output.during = null;
    await restarted.start(online: false, includeTrash: false);
    expect(restarted.phase, BackupPhase.completed);
    expect(restarted.manifest!.includedAudioCount, 0);
    await expectLater(store.readLocalAudio(capture.rec), throwsStateError);
    expect(freezes, 1);
    controller.dispose();
    restarted.dispose();
  });

  test(
    'space loss on retry preserves old ZIP, source audio and pending changes',
    () async {
      final controller = create();
      output.during = () async => false;
      await controller.start(online: false, includeTrash: false);
      final oldZip = await controller.artifact!.file.readAsBytes();
      final noSpace = create(space: 0);
      await noSpace.restore();
      await noSpace.start(online: false, includeTrash: false);
      expect(noSpace.phase, BackupPhase.failed);
      expect(noSpace.error, contains('공간'));
      expect(output.calls, 1);
      expect(await controller.artifact!.file.readAsBytes(), oldZip);
      expect(await store.readLocalAudio(capture.rec), capture.bytes);
      expect((await store.captureExportLocal())['changes'], hasLength(1));
      controller.dispose();
      noSpace.dispose();
    },
  );
  test('external output failure retains verified internal ZIP and original for bounded retry', () async {
    final controller = create();
    output.during = () async {
      throw const FileSystemException('Synthetic output space loss');
    };
    await controller.start(online: false, includeTrash: false);
    expect(controller.phase, BackupPhase.failed);
    final bytes = await controller.artifact!.file.readAsBytes();
    expect(await store.readLocalAudio(capture.rec), capture.bytes);
    output.during = null;
    await controller.start(online: false, includeTrash: false);
    expect(controller.phase, BackupPhase.completed);
    expect(await controller.artifact!.file.readAsBytes(), bytes);
    expect(freezes, 1);
    controller.dispose();
  });
}
