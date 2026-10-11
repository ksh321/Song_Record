import 'dart:async';

import 'package:flutter/services.dart';

import '../../../core/sync/local_repository.dart';
import '../../recorder/completed_capture_handoff.dart';
import '../../recorder/recorder_gateway.dart';

final class ExportSpacePlan {
  ExportSpacePlan({
    required int audioBytes,
    required int metadataBytes,
    required int fileCount,
  }) {
    if (audioBytes < 0 ||
        metadataBytes < 0 ||
        fileCount < 0 ||
        audioBytes > 0x1fffffffffffff ||
        metadataBytes > 0x1fffffffffffff ||
        fileCount > 1000000) {
      throw ArgumentError('Invalid backup space estimate');
    }
    // Audio staging + final ZIP, metadata copy, ZIP/deflate overhead and reserve.
    requiredBytes =
        2 * audioBytes +
        2 * metadataBytes +
        ((audioBytes + 16383) ~/ 16384) * 16 +
        fileCount * 1024 +
        16 * 1024 * 1024;
    if (requiredBytes > 0x1fffffffffffff) {
      throw ArgumentError('Backup estimate exceeds supported size');
    }
  }
  late final int requiredBytes;
  bool fits(int available) => available >= requiredBytes;
}

final class AndroidBackupSpace {
  static const channel = MethodChannel(
    'com.ksh321.songrecord/recorder_commands',
  );
  static Future<int> availableBytes() async {
    final bytes = await channel.invokeMethod<int>('availableBackupBytes');
    if (bytes == null || bytes < 0) {
      throw StateError('Backup space unavailable');
    }
    return bytes;
  }
}

/// This gate runs BEFORE ExportBaselineReader fixes any metadata cutoff.
/// Failure/cancel never promotes a capturing file to completed audio.
final class ExportPreparation {
  ExportPreparation({
    required this.recorder,
    required this.preserve,
    required this.requireCurrent,
    Future<int> Function()? availableBytes,
    this.stopTimeout = const Duration(seconds: 30),
  }) : availableBytes = availableBytes ?? AndroidBackupSpace.availableBytes;
  factory ExportPreparation.forRepository({
    required RecorderGateway recorder,
    required LocalRepository repository,
    required void Function() requireCurrent,
  }) => ExportPreparation(
    recorder: recorder,
    requireCurrent: requireCurrent,
    preserve: (status) async {
      requireCurrent();
      final known = await repository.hasRecordingMetadata(status.recordingId!);
      requireCurrent();
      if (known) return;
      if (recorder is! CompletedRecordingGateway) {
        throw StateError('Completed capture handoff unavailable');
      }
      await preserveCompletedCapture(
        status: status,
        gateway: recorder as CompletedRecordingGateway,
        repository: repository,
        requireCurrent: requireCurrent,
      );
    },
  );
  final RecorderGateway recorder;
  final Future<void> Function(RecorderStatus) preserve;
  final void Function() requireCurrent;
  final Future<int> Function() availableBytes;
  final Duration stopTimeout;
  bool _busy = false;

  Future<int> prepare(
    ExportSpacePlan plan, {
    bool Function()? isCancelled,
  }) async {
    if (_busy) throw StateError('Backup preparation already active');
    _busy = true;
    void fence() {
      requireCurrent();
      if (isCancelled?.call() == true) throw StateError('Backup cancelled');
    }

    try {
      fence();
      var status = await recorder.getCurrentStatus();
      fence();
      if (status.isRecording) {
        final captureId = status.recordingId;
        if (captureId == null) throw StateError('Recording start not settled');
        final terminal = Completer<RecorderStatus>();
        final subscription = recorder.watchStatus().listen(
          (value) {
            if (!value.isRecording && !terminal.isCompleted) {
              terminal.complete(value);
            }
          },
          onError: (Object error) {
            if (!terminal.isCompleted) {
              terminal.complete(
                const RecorderStatus(phase: RecorderPhase.error),
              );
            }
          },
          onDone: () {
            if (!terminal.isCompleted) {
              terminal.complete(
                const RecorderStatus(phase: RecorderPhase.error),
              );
            }
          },
        );
        try {
          fence();
          await recorder.stop().timeout(stopTimeout);
          fence();
          status = await recorder.getCurrentStatus();
          if (status.isRecording) {
            status = await terminal.future.timeout(stopTimeout);
          }
          fence();
          if (status.recordingId != captureId ||
              status.phase != RecorderPhase.completed) {
            throw StateError('Recording did not finish safely');
          }
        } finally {
          await subscription.cancel();
        }
      }
      if (status.phase == RecorderPhase.completed) {
        if (status.recordingId == null ||
            !{
              RecorderLocalState.inputPending,
              RecorderLocalState.saved,
            }.contains(status.localState) ||
            status.sizeBytes == null ||
            status.sizeBytes! <= 0 ||
            status.durationMs == null ||
            status.durationMs! <= 0 ||
            status.sha256 == null ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(status.sha256!)) {
          throw StateError('Recording completion is not verified');
        }
        await preserve(status);
        fence();
      } else if (status.phase != RecorderPhase.idle) {
        throw StateError('Recorder requires recovery before backup');
      }
      final available = await availableBytes();
      fence();
      final latest = await recorder.getCurrentStatus();
      fence();
      if (latest.isRecording) {
        throw StateError('New recording started before backup');
      }
      if (!plan.fits(available)) {
        throw StateError('Insufficient backup temporary space');
      }
      return available;
    } finally {
      _busy = false;
    }
  }
}
