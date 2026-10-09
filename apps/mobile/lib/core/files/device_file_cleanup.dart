import 'dart:convert';

import '../audio/local_audio.dart';
import '../database/account_store.dart';
import 'recording_file_status.dart';

final class DeviceFileCleanupPreview {
  DeviceFileCleanupPreview._(
    this.owner,
    this.recording,
    this.source,
    this.status,
    this.assetEvidence,
    this.matchingServerCopy,
  );
  final String owner, recording;
  final LocalAudioSource source;
  final RecordingFileStatus status;
  final Object? assetEvidence;
  final bool matchingServerCopy;
  bool get requiresLossAcknowledgement => !matchingServerCopy;
  String get warning =>
      '${status.serverLabel} (최근 동기화 정보). '
      '${requiresLossAcknowledgement ? "현재 파일과 같은 서버 사본이 없거나 확인되지 않아 이 파일을 정리하면 복구하지 못할 수 있습니다. " : "서버 상태는 바뀔 수 있습니다. 필요한 파일은 먼저 별도로 내보내세요. "}'
      '이 기기 파일만 제거하며 녹음 정보·서버 파일·외부 내보내기 사본은 유지합니다.';
}

final class DeviceFileCleanup {
  DeviceFileCleanup(this.store);
  final AccountStore store;
  Future<DeviceFileCleanupPreview> preview(String recording) async {
    final source = await LocalAudioLookup(store).find(recording);
    if (source == null) throw StateError('No verified current-device file');
    final status = await RecordingFileStatuses(store).read(recording);
    store.requireActive();
    final evidence = await store.recordingStorageEvidence(recording);
    store.requireActive();
    final asset = evidence['asset'];
    Map<String, dynamic>? row;
    try {
      final decoded = asset is String ? jsonDecode(asset) : null;
      if (decoded is Map<String, dynamic>) row = decoded;
    } catch (_) {
      row = null;
    }
    final matches =
        status.serverStored &&
        row?['cloud_state'] == 'STORED' &&
        row?['sha256'] == source.checksum &&
        row?['verified_size'] == source.size;
    return DeviceFileCleanupPreview._(
      store.userId,
      recording,
      source,
      status,
      asset,
      matches,
    );
  }

  Future<void> confirm(
    DeviceFileCleanupPreview preview, {
    required bool confirmed,
    required bool lossAcknowledged,
  }) async {
    store.requireActive();
    if (preview.owner != store.userId || !confirmed) {
      throw StateError('Explicit confirmation required');
    }
    // If evidence changed while the dialog was open, require a new preview/confirmation.
    final current = await this.preview(preview.recording);
    if (current.status.serverState != preview.status.serverState ||
        current.assetEvidence != preview.assetEvidence ||
        current.source.checksum != preview.source.checksum ||
        current.source.size != preview.source.size ||
        (current.requiresLossAcknowledgement && !lossAcknowledged)) {
      throw StateError('Cleanup evidence or acknowledgement changed');
    }
    await store.removeConfirmedDeviceAudio(
      recording: preview.recording,
      checksum: preview.source.checksum,
      size: preview.source.size,
      confirmed: confirmed,
    );
  }
}
