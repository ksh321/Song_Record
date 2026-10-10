import 'dart:convert';
import 'dart:io';

import '../audio/local_audio.dart';
import '../database/account_store.dart';
import '../domain/identifiers.dart';

enum DeviceAudioState { available, missing, unknown }

enum InformationSyncState { synced, pending, unknown, deleted }

final class RecordingFileStatus {
  const RecordingFileStatus({
    required this.recording,
    required this.information,
    required this.device,
    required this.serverState,
    required this.blockedReason,
    required this.pinCurrent,
    required this.pinPending,
  });
  final String recording;
  final InformationSyncState information;
  final DeviceAudioState device;
  final String serverState;
  final String? blockedReason;
  final bool pinCurrent, pinPending;
  bool get serverStored => serverState == 'STORED';
  bool get canPlay =>
      information != InformationSyncState.deleted &&
      (device == DeviceAudioState.available || serverStored);
  bool get filesConfirmedAbsent =>
      device == DeviceAudioState.missing && serverState == 'NONE';
  String get playbackUnavailableLabel =>
      information == InformationSyncState.deleted
      ? '삭제된 녹음입니다. 녹음 정보의 복원 상태를 먼저 확인하세요.'
      : filesConfirmedAbsent
      ? '현재 기기와 서버에 재생할 파일이 없습니다. 녹음 정보는 유지됩니다.'
      : device == DeviceAudioState.unknown || serverState == 'UNKNOWN'
      ? '파일 위치를 확인할 수 없습니다. 상태를 다시 확인하거나 원래 기기·백업을 확인하세요.'
      : '현재 기기에 재생할 파일이 없고 서버 보관은 아직 완료되지 않았습니다.';
  static const restorationGuide =
      '1. 녹음한 원래 기기에서 파일이 남아 있는지 확인하세요.\n'
      '2. 직접 보관한 M4A 사본이나 사용자 백업을 확인하세요.\n'
      '3. 원래 기기·백업에도 파일이 없다면 녹음 정보만 유지됩니다.\n'
      '파일을 복원한 뒤 실제 파일 검증을 마쳐야 재생할 수 있습니다. 보관 대상으로 선택한 것만으로 백업이 완료되지는 않습니다.';

  String get informationLabel => switch (information) {
    InformationSyncState.synced => '정보 동기화 완료',
    InformationSyncState.pending => '정보 동기화 대기',
    InformationSyncState.unknown => '정보 동기화 확인 중',
    InformationSyncState.deleted => '정보 삭제됨',
  };
  String get deviceLabel => switch (device) {
    DeviceAudioState.available => '이 기기 파일: 있음',
    DeviceAudioState.missing => '이 기기 파일: 재생 가능한 파일 없음',
    DeviceAudioState.unknown => '이 기기 파일: 확인 불가',
  };
  String get serverLabel => '서버 파일: $_serverDescription';
  String get _serverDescription => switch (serverState) {
    'STORED' => '보관됨',
    'NONE' => '없음',
    'QUEUED' => '보관 대기',
    'UPLOADING' => '업로드 중',
    'VERIFYING' => '검증 중',
    'DELETING' => '정리 중',
    _ => '확인 불가',
  };
  String? get pinLabel => pinCurrent && serverStored
      ? '고정 보관 중'
      : (pinCurrent || pinPending) && serverState == 'UNKNOWN'
      ? '고정 상태 확인 중'
      : pinCurrent || pinPending
      ? '고정 대기'
      : null;
  String get waitingLabel =>
      blockedReason == null ? '대기 이유: 없음' : '대기 이유: $_waitingDescription';
  String get _waitingDescription => switch (blockedReason) {
    'FILE_MISSING' => '파일 없음',
    'QUOTA' => '용량 부족',
    'PIN_LIMIT' => '고정 한도',
    'BUDGET' => '처리 예산',
    'AUTH' => '로그인 필요',
    'NETWORK' => '네트워크',
    'FILE_INVALID' => '파일 검증 실패',
    _ => '확인 불가',
  };
}

final class RecordingFileStatuses {
  RecordingFileStatuses(this.store);
  final AccountStore store;
  Future<RecordingFileStatus> read(String recording) async {
    final id = UuidValue(recording).value;
    store.requireActive();
    final evidence = await store.recordingStorageEvidence(id);
    store.requireActive();
    var device = DeviceAudioState.unknown;
    try {
      device = await LocalAudioLookup(store).find(id) == null
          ? DeviceAudioState.missing
          : DeviceAudioState.available;
    } on FileSystemException {
      store.requireActive();
      device = DeviceAudioState.unknown;
    }
    store.requireActive();
    return fromEvidence(id, store.userId, evidence, device);
  }

  static RecordingFileStatus fromEvidence(
    String id,
    String userId,
    Map<String, Object?> evidence,
    DeviceAudioState device,
  ) {
    Map<String, dynamic>? decode(Object? value) {
      if (value is! String) return null;
      try {
        final v = jsonDecode(value);
        return v is Map<String, dynamic> ? v : null;
      } catch (_) {
        return null;
      }
    }

    final record = decode(evidence['record']),
        asset = decode(evidence['asset']);
    final information = evidence['deleted'] == true
        ? InformationSyncState.deleted
        : evidence['draft'] == true
        ? InformationSyncState.pending
        : record != null
        ? InformationSyncState.synced
        : InformationSyncState.unknown;
    var cloud = evidence['asset_absent'] == true ? 'NONE' : 'UNKNOWN';
    String? reason;
    if (asset != null &&
        asset['recording_id'] == id &&
        (asset['user_id'] == null || asset['user_id'] == userId)) {
      final candidate = asset['cloud_state'];
      if ({
        'NONE',
        'QUEUED',
        'UPLOADING',
        'VERIFYING',
        'STORED',
        'DELETING',
      }.contains(candidate)) {
        cloud = candidate as String;
      }
      if (cloud == 'STORED' || cloud == 'DELETING') {
        final generation = asset['generation'],
            size = asset['verified_size'],
            hash = asset['sha256'];
        bool validGeneration = false;
        try {
          validGeneration =
              generation is String &&
              UuidValue(generation).value == generation &&
              generation != '00000000-0000-0000-0000-000000000000';
        } catch (_) {
          validGeneration = false;
        }
        if (!validGeneration ||
            size is! int ||
            size < 1 ||
            size > 6291456 ||
            hash is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
            asset['stored_at'] == null) {
          cloud = 'UNKNOWN';
        }
      }
      if (asset['blocked_reason'] is String) {
        reason = asset['blocked_reason'] as String;
      }
    }
    return RecordingFileStatus(
      recording: id,
      information: information,
      device: device,
      serverState: cloud,
      blockedReason: reason,
      pinCurrent: evidence['pin_current'] == true,
      pinPending: evidence['pin_pending'] == true,
    );
  }
}
