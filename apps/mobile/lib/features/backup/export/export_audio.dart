import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../core/database/account_store.dart';
import '../../../core/files/local_preservation.dart';
import '../../../core/sync/recording_save_contract.dart';
import 'export_baseline.dart';
import 'export_data.dart';
import 'export_manifest.dart';

final class ExportCancelled implements Exception {
  const ExportCancelled();
}

final class _Deleted implements Exception {
  const _Deleted();
}

/// Local reads are bounded to one verified recording. Server downloads go only
/// to private export staging; cleanup/deletion remains free between recordings.
final class ExportAudioCollector {
  ExportAudioCollector({
    required this.requireCurrent,
    required this.state,
    required this.local,
    required this.stage,
    this.download,
    this.owner,
    this.timeout = const Duration(seconds: 35),
  });
  factory ExportAudioCollector.forStore(
    AccountStore store, {
    PreservationDownload? download,
  }) => ExportAudioCollector(
    owner: store.userId,
    requireCurrent: store.requireActive,
    state: store.exportAudioState,
    local: (id) async {
      try {
        return await store.readLocalAudio(id);
      } on StateError {
        store.requireActive();
        return null;
      } on FileSystemException catch (e) {
        store.requireActive();
        if ([2, 3].contains(e.osError?.errorCode)) return null;
        rethrow;
      }
    },
    stage: store.stageExportAudio,
    download: download,
  );
  final void Function() requireCurrent;
  final Future<Map<String, Object?>> Function(String) state;
  final Future<Uint8List?> Function(String) local;
  final Future<void> Function(String, String, String, int, Uint8List) stage;
  final PreservationDownload? download;
  final Duration timeout;
  final String? owner;
  bool _cancelled = false, _busy = false;
  void cancel() => _cancelled = true;
  void _guard() {
    requireCurrent();
    if (_cancelled) throw const ExportCancelled();
  }

  Future<List<ExportAudioEntry>> collect(
    ExportBaseline baseline,
    ExportData data, {
    void Function(int done, int total)? progress,
  }) async {
    if (_busy) throw StateError('Export collection already running');
    if (data.toJson()['export_id'] != baseline.id ||
        data.toJson()['source_user_id'] != baseline.owner ||
        owner != null && owner != baseline.owner) {
      throw const FormatException('Export collection baseline mismatch');
    }
    _busy = true;
    try {
      _guard();
      final rows = data.records,
          files = <String, Map<String, dynamic>>{},
          assets = <String, Map<String, dynamic>>{};
      final inputs = {
        for (final row in data.toJson()['recording_inputs'] as List)
          row['recording_id'] as String: row as Map<String, dynamic>,
      };
      final initial = {
        for (final row in baseline.local['file_states'] as List? ?? const [])
          row['recording_id'] as String: row as Map<String, dynamic>,
      };
      final recordings = <Map<String, dynamic>>[];
      for (final row in rows) {
        final payload = row['payload'] as Map<String, dynamic>;
        final id = row['resource_id'] as String;
        if (row['entity'] == 'RECORDING_FILE_SPEC') files[id] = payload;
        if (row['entity'] == 'RECORDING_ASSET') assets[id] = payload;
        if (row['entity'] == 'RECORDING' &&
            row['tombstone'] != true &&
            payload['lifecycle_state'] != 'PURGED') {
          recordings.add({...payload, 'id': id});
        }
      }
      recordings.sort(
        (a, b) => (a['id'] as String).compareTo(b['id'] as String),
      );
      final result = <ExportAudioEntry>[];
      for (final recording in recordings) {
        _guard();
        final id = recording['id'] as String;
        final file = recording['file'] ?? files[id] ?? inputs[id]?['file'];
        const fields = {
          'sha256',
          'size_bytes',
          'duration_ms',
          'codec',
          'sample_rate',
          'channels',
          'capture_integrity',
        };
        final spec = file is Map<String, dynamic>
            ? <String, dynamic>{
                for (final k in fields)
                  if (file.containsKey(k)) k: file[k],
              }
            : null;
        final valid = validRecordingFileSpec(spec);
        ExportAudioEntry entry(
          ExportMissingReason? reason, {
          bool selected = true,
        }) => ExportAudioEntry(
          recordingId: id,
          selected: selected,
          included: reason == null,
          missingReason: reason,
          sha256: valid ? spec!['sha256'] as String : null,
          sizeBytes: valid ? spec!['size_bytes'] as int : null,
          durationMs: valid ? spec!['duration_ms'] as int : null,
        );
        if (recording['lifecycle_state'] == 'TRASHED' &&
            !baseline.includeTrash) {
          result.add(
            entry(ExportMissingReason.trashNotSelected, selected: false),
          );
        } else if (!valid) {
          result.add(entry(ExportMissingReason.incompleteRecording));
        } else {
          Future<void> guard() async {
            _guard();
            final current = await state(id);
            _guard();
            if (recording['lifecycle_state'] == 'PURGE_PENDING' ||
                current['deleted'] == true ||
                current['lifecycle_state'] == 'TRASHED' &&
                    !baseline.includeTrash ||
                initial[id] != null &&
                    current['local_state'] == 'MISSING' &&
                    current['updated_at'] != initial[id]!['updated_at']) {
              throw const _Deleted();
            }
          }

          Uint8List? bytes;
          ExportMissingReason? reason;
          try {
            await guard();
            bytes = await local(id).timeout(timeout);
            _guard();
            if (bytes == null &&
                {
                  'SAVED',
                  'INPUT_PENDING',
                }.contains(initial[id]?['local_state'])) {
              throw const _Deleted();
            }
            if (bytes == null) {
              final asset = assets[id];
              if (asset?['cloud_state'] == 'STORED') {
                if (!baseline.online) {
                  reason = ExportMissingReason.offlineServerOnly;
                } else if (download == null) {
                  reason = ExportMissingReason.downloadFailed;
                } else {
                  final object = PreservationObject(
                    owner: baseline.owner,
                    recording: id,
                    generation: asset!['generation'] as String,
                    checksum: spec!['sha256'] as String,
                    size: spec['size_bytes'] as int,
                    revision: asset['cloud_revision'] as int,
                  );
                  bytes = await download!
                      .download(object, guard)
                      .timeout(timeout);
                  _guard();
                }
              } else {
                reason = ExportMissingReason.fileNotOnDevice;
              }
            }
          } on _Deleted {
            reason = ExportMissingReason.fileDeleted;
          } on ExportCancelled {
            rethrow;
          } catch (_) {
            _guard();
            try {
              await guard();
              reason = ExportMissingReason.downloadFailed;
            } on _Deleted {
              reason = ExportMissingReason.fileDeleted;
            }
          }
          if (bytes != null && reason == null) {
            if (bytes.length != spec!['size_bytes'] ||
                sha256.convert(bytes).toString() != spec['sha256']) {
              reason = ExportMissingReason.checksumMismatch;
            } else {
              try {
                await guard();
                // Staging/disk failures are fatal, not a partially successful ZIP.
                await stage(
                  baseline.id,
                  id,
                  spec['sha256'] as String,
                  spec['size_bytes'] as int,
                  bytes,
                );
                await guard();
                if ({
                      'SAVED',
                      'INPUT_PENDING',
                    }.contains(initial[id]?['local_state']) &&
                    await local(id).timeout(timeout) == null) {
                  throw const _Deleted();
                }
              } on _Deleted {
                reason = ExportMissingReason.fileDeleted;
              }
            }
          }
          result.add(entry(reason));
        }
        _guard();
        progress?.call(result.length, recordings.length);
      }
      return List.unmodifiable(result);
    } finally {
      _busy = false;
    }
  }
}
