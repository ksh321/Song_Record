import 'dart:typed_data';

import '../../core/sync/local_repository.dart';
import 'recorder_gateway.dart';

/// Shared verified recorder-to-account handoff for input screens and backup.
Future<void> preserveCompletedCapture({
  required RecorderStatus status,
  required CompletedRecordingGateway gateway,
  required LocalRepository repository,
  required void Function() requireCurrent,
}) async {
  requireCurrent();
  if (status.phase != RecorderPhase.completed || status.recordingId == null) {
    throw StateError('Completed capture required');
  }
  final source = await gateway.readCompleted(status.recordingId!);
  requireCurrent();
  if (source['recordingId'] != status.recordingId ||
      source['phase'] != 'completed' ||
      source['actualMime'] != 'audio/mp4a-latm' ||
      source['actualAacProfile'] != 2 ||
      source['bytes'] is! Uint8List) {
    throw StateError('Unverified completed capture');
  }
  await repository.importCompletedCapture(
    accountScope: source['accountScope'] as String,
    recordingId: status.recordingId!,
    bytes: source['bytes'] as Uint8List,
    fileSpec: {
      'sha256': source['sha256'],
      'size_bytes': source['sizeBytes'],
      'duration_ms': source['durationMs'],
      'codec': 'AAC_LC',
      'sample_rate': source['actualSampleRate'],
      'channels': source['actualChannels'],
      'capture_integrity': source['recovered'] == true
          ? 'RECOVERED'
          : 'VALIDATED',
    },
    recordedAt: DateTime.fromMillisecondsSinceEpoch(
      (source['startedAtWallClockMs'] as num).toInt(),
      isUtc: true,
    ),
    timezoneId: source['timezoneId'] as String,
    timezoneOffsetMinutes: (source['timezoneOffsetMinutes'] as num).toInt(),
  );
  requireCurrent();
}
