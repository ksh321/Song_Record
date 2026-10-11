import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/database/account_store.dart';
import '../../../core/domain/identifiers.dart';
import '../../../core/files/preservation_download.dart';
import '../../../core/sync/local_repository.dart';
import '../../../core/sync/snapshot_transport.dart';
import '../../auth/auth_session.dart';
import '../../recorder/recorder_gateway.dart';
import 'export_audio.dart';
import 'export_baseline.dart';
import 'export_data.dart';
import 'export_job.dart';
import 'export_manifest.dart';
import 'export_preparation.dart';
import 'export_zip.dart';

enum BackupPhase {
  ready,
  preparing,
  baseline,
  collecting,
  zip,
  saving,
  completed,
  cancelled,
  failed,
  resumable,
}

final class ExportController extends ChangeNotifier {
  ExportController({
    required this.owner,
    required this.environment,
    required this.requireCurrent,
    required this.prepare,
    required this.freeze,
    required this.createJob,
    required this.createCollector,
    required this.destination,
    required this.availableBytes,
    this.latestJob,
  });

  factory ExportController.forStore({
    required AccountStore store,
    required RecorderGateway recorder,
    required SnapshotTransport transport,
    required Future<AuthSession> Function() session,
    required Uri base,
    required void Function() requireCurrent,
    bool allowLocalHttp = false,
  }) {
    late ExportController controller;
    void fence() {
      requireCurrent();
      if (controller._cancelled || controller._closed) {
        throw const ExportCancelled();
      }
    }

    final preparation = ExportPreparation.forRepository(
      recorder: recorder,
      repository: LocalRepository(store),
      requireCurrent: fence,
    );
    final reader = ExportBaselineReader(
      store: store,
      transport: transport,
      session: session,
      requireCurrent: fence,
    );
    controller = ExportController(
      owner: store.userId,
      environment: store.environment.name,
      requireCurrent: requireCurrent,
      prepare: () => preparation
          .prepare(
            ExportSpacePlan(audioBytes: 0, metadataBytes: 0, fileCount: 0),
          )
          .timeout(const Duration(seconds: 60)),
      freeze: (online, trash) async {
        if (!online) return reader.offline(includeTrash: trash);
        final handle = await reader.request(
          operationId: UuidValue.random().value,
          includeTrash: trash,
        );
        final deadline = DateTime.now().add(const Duration(minutes: 2));
        while (true) {
          fence();
          try {
            return await reader.freezeReady(handle);
          } on ExportNotReady {
            if (DateTime.now().isAfter(deadline)) {
              throw TimeoutException('Export baseline not ready');
            }
            await Future<void>.delayed(const Duration(seconds: 2));
          }
        }
      },
      createJob: (id) => ExportJob(
        owner: store.userId,
        id: id,
        file: (name) => store.privateExportFile(id, name),
        requireCurrent: fence,
      ),
      createCollector: () => ExportAudioCollector.forStore(
        store,
        download: HttpPreservationDownload(
          base,
          session,
          allowLocalHttp: allowLocalHttp,
        ),
      ),
      destination: const AndroidBackupDestination(),
      availableBytes: AndroidBackupSpace.availableBytes,
      latestJob: store.latestExportJob,
    );
    return controller;
  }

  final String owner, environment;
  final void Function() requireCurrent;
  final Future<int> Function() prepare;
  final Future<ExportBaseline> Function(bool online, bool trash) freeze;
  final ExportJob Function(String id) createJob;
  final ExportAudioCollector Function() createCollector;
  final BackupDestination destination;
  final Future<int> Function() availableBytes;
  final Future<String?> Function()? latestJob;
  BackupPhase phase = BackupPhase.ready;
  String? error;
  ExportData? data;
  ExportManifest? manifest;
  ExportJob? job;
  ExportZip? artifact;
  ExportAudioCollector? _collector;
  int done = 0, total = 0;
  bool busy = false, _cancelled = false, _closed = false;
  void _changed() {
    if (!_closed) notifyListeners();
  }

  void _guard() {
    requireCurrent();
    if (_cancelled || _closed) throw const ExportCancelled();
  }

  void _phase(BackupPhase value) {
    phase = value;
    _changed();
  }

  Future<void> restore() async {
    if (busy) return;
    busy = true;
    _changed();
    try {
      _guard();
      final id = await latestJob?.call();
      _guard();
      if (id == null) return;
      final candidate = createJob(id), restored = await candidate.resume();
      _guard();
      job = candidate;
      data = restored.data;
      manifest = restored.manifest;
      artifact = restored.zip;
      phase = restored.externallySaved
          ? BackupPhase.completed
          : BackupPhase.resumable;
    } catch (_) {
      error = '이전 작업을 확인할 수 없어요. 기존 ZIP과 원본을 보존하고 새 백업을 시작해 주세요.';
      phase = BackupPhase.failed;
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void> cancel() async {
    if (!busy) return;
    _cancelled = true;
    _collector?.cancel();
    try {
      await destination.cancel();
    } catch (_) {
      /* Account/source guard still cancels the Dart pipeline. */
    }
    _changed();
  }

  List<ExportAudioEntry> _pending(ExportData source, bool trash) => [
    for (final row in source.records)
      if (row['entity'] == 'RECORDING' &&
          row['tombstone'] != true &&
          (row['payload'] as Map)['lifecycle_state'] != 'PURGED')
        ExportAudioEntry(
          recordingId: row['resource_id'] as String,
          selected:
              trash || (row['payload'] as Map)['lifecycle_state'] != 'TRASHED',
          included: false,
          missingReason:
              !trash && (row['payload'] as Map)['lifecycle_state'] == 'TRASHED'
              ? ExportMissingReason.trashNotSelected
              : ExportMissingReason.notCollected,
        ),
  ];

  Future<void> start({
    required bool online,
    required bool includeTrash,
    bool fresh = false,
  }) async {
    if (busy || _closed) return;
    busy = true;
    _cancelled = false;
    error = null;
    _changed();
    try {
      _guard();
      if (fresh || data == null || job == null || manifest == null) {
        data = null;
        manifest = null;
        job = null;
        artifact = null;
        done = 0;
        total = 0;
        _phase(BackupPhase.preparing);
        await prepare();
        _guard();
        _phase(BackupPhase.baseline);
        final baseline = await freeze(
          online,
          includeTrash,
        ).timeout(const Duration(minutes: 10));
        _guard();
        if (baseline.owner != owner ||
            baseline.online != online ||
            baseline.includeTrash != includeTrash) {
          throw const FormatException('Backup scope mismatch');
        }
        data = ExportData.fromBaseline(baseline);
        manifest = ExportManifest.fromBaseline(
          baseline,
          metadataCount: data!.metadataCount,
          files: _pending(data!, includeTrash),
        );
        job = createJob(baseline.id)
          ..fileStates = baseline.local['file_states'] as List? ?? const [];
        await job!.save(data!, manifest!);
        _guard();
      }
      // Metadata is frozen before estimating the exact planned audio sizes.
      final sizes = <String, int>{};
      for (final row in data!.records) {
        final payload = row['payload'] as Map;
        final spec = row['entity'] == 'RECORDING_FILE_SPEC'
            ? payload
            : payload['file'];
        if (spec is Map && spec['size_bytes'] is int && (spec['size_bytes'] as int) > 0) {
          sizes[row['resource_id'] as String] = spec['size_bytes'] as int;
        }
      }
      for (final row in data!.toJson()['recording_inputs'] as List) {
        final spec = row['file'];
        if (spec is Map && spec['size_bytes'] is int) {
          sizes[row['recording_id'] as String] = spec['size_bytes'] as int;
        }
      }
      final plan = ExportSpacePlan(
        audioBytes: sizes.values.fold(0, (a, b) => a + b),
        metadataBytes:
            utf8.encode(data!.encode()).length +
            utf8.encode(manifest!.encode()).length,
        fileCount: manifest!.files.length,
      );
      if (!plan.fits(await availableBytes())) {
        throw const FileSystemSpaceFailure();
      }
      _guard();
      if (artifact == null) {
        _phase(BackupPhase.collecting);
        _collector = createCollector();
        final pending = manifest!.files;
        final files = await _collector!.collectJob(
          data!,
          manifest!,
          fileStates: job!.fileStates,
          previous: manifest!.files,
          progress: (d, t) {
            done = d;
            total = t;
            _changed();
          },
          checkpoint: (completed) async {
            _guard();
            final ids = completed.map((f) => f.recordingId).toSet();
            manifest = manifest!.withFiles([
              ...completed,
              ...pending.where((f) => !ids.contains(f.recordingId)),
            ]);
            await job!.save(data!, manifest!);
            _guard();
          },
        );
        manifest = manifest!.withFiles(files);
        _guard();
        await job!.save(data!, manifest!);
        _phase(BackupPhase.zip);
        artifact = await ExportZipWriter(
          file: job!.file,
          requireCurrent: _guard,
        ).write(data!, manifest!);
        _guard();
        await job!.save(data!, manifest!, zip: artifact);
      }
      _guard();
      _phase(BackupPhase.saving);
      final saved = await destination.save(
        artifact!,
        owner: owner,
        environment: environment,
        jobId: job!.id,
      );
      _guard();
      await job!.save(data!, manifest!, zip: artifact, externallySaved: saved);
      _guard();
      _phase(saved ? BackupPhase.completed : BackupPhase.cancelled);
    } on ExportCancelled {
      _phase(BackupPhase.cancelled);
    } on FileSystemSpaceFailure {
      error = '기기 공간이 부족해요. 원본과 이전 백업은 그대로 남아 있습니다.';
      _phase(BackupPhase.failed);
    } catch (_) {
      if (_cancelled || _closed) {
        _phase(BackupPhase.cancelled);
      } else {
        error = '백업을 완료하지 못했어요. 원본과 내부 사본은 보존됩니다. 외부 저장 위치에 미완성 사본이 있을 수 있어요. 연결·공간을 확인하고 재시도해 주세요.';
        _phase(BackupPhase.failed);
      }
    } finally {
      _collector = null;
      busy = false;
      _changed();
    }
  }

  @override
  void dispose() {
    _closed = true;
    _cancelled = true;
    _collector?.cancel();
    unawaited(destination.cancel().catchError((Object _) {}));
    super.dispose();
  }
}

final class FileSystemSpaceFailure implements Exception {
  const FileSystemSpaceFailure();
}
