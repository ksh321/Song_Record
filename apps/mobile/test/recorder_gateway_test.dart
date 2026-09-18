import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/recorder/recorder_gateway.dart';

void main() {
  test('마이크 권한 재요청 가능 상태를 변환한다', () {
    final denied = RecorderPermissions.fromMap(const {
      'microphoneGranted': false,
      'notificationsGranted': true,
      'microphoneCanAskAgain': true,
    });
    final blocked = RecorderPermissions.fromMap(const {
      'microphoneGranted': false,
      'notificationsGranted': true,
      'microphoneCanAskAgain': false,
    });

    expect(denied.microphoneCanAskAgain, isTrue);
    expect(blocked.microphoneCanAskAgain, isFalse);
  });

  test('실기 검증용 Android 기기 정보를 변환한다', () {
    final info = RecorderDeviceInfo.fromMap(const {
      'manufacturer': 'samsung',
      'model': 'SM-A546S',
      'androidVersion': '16',
      'sdkInt': 36,
    });

    expect(info.manufacturer, 'samsung');
    expect(info.model, 'SM-A546S');
    expect(info.androidVersion, '16');
    expect(info.sdkInt, 36);
  });

  test('네이티브 녹음 중 상태를 변환한다', () {
    final status = RecorderStatus.fromMap(const {
      'phase': 'recording',
      'recordingId': 'recording-1',
      'elapsedMs': 4200,
    });

    expect(status.phase, RecorderPhase.recording);
    expect(status.recordingId, 'recording-1');
    expect(status.elapsedMs, 4200);
    expect(status.isRecording, isTrue);
  });

  test('완료 파일의 실제 오디오 정보를 변환한다', () {
    final status = RecorderStatus.fromMap(const {
      'phase': 'completed',
      'outputPath': '/data/recordings/recording-1.m4a',
      'sizeBytes': 12345,
      'durationMs': 4200,
      'sha256': 'abc123',
      'recovered': true,
      'recoveryState': 'recovered',
      'actualMime': 'audio/mp4a-latm',
      'actualSampleRate': 48000,
      'actualChannels': 1,
      'actualAacProfile': 2,
    });

    expect(status.phase, RecorderPhase.completed);
    expect(status.durationMs, 4200);
    expect(status.sha256, 'abc123');
    expect(status.recovered, isTrue);
    expect(status.recoveryState, 'recovered');
    expect(status.actualMime, 'audio/mp4a-latm');
    expect(status.actualSampleRate, 48000);
    expect(status.actualChannels, 1);
    expect(status.actualAacProfile, 2);
    expect(status.isRecording, isFalse);
  });

  test('6분 제한 안내 상태와 남은 시간을 변환한다', () {
    final thirtySecondWarning = RecorderStatus.fromMap(const {
      'phase': 'recording',
      'elapsedMs': 330000,
      'remainingMs': 30000,
      'limitWarning': 'thirty_seconds',
    });
    final tenSecondWarning = RecorderStatus.fromMap(const {
      'phase': 'recording',
      'elapsedMs': 350000,
      'remainingMs': 10000,
      'limitWarning': 'ten_seconds',
    });

    expect(
      thirtySecondWarning.limitWarning,
      RecorderLimitWarning.thirtySeconds,
    );
    expect(thirtySecondWarning.remainingMs, 30000);
    expect(tenSecondWarning.limitWarning, RecorderLimitWarning.tenSeconds);
    expect(tenSecondWarning.remainingMs, 10000);
  });

  test('6분 자동 종료 원인을 변환한다', () {
    final status = RecorderStatus.fromMap(const {
      'phase': 'completed',
      'elapsedMs': 360000,
      'stopReason': 'time_limit',
    });

    expect(status.phase, RecorderPhase.completed);
    expect(status.stopReason, 'time_limit');
    expect(status.isRecording, isFalse);
  });



  test('복구하지 못한 중단 파일 상태를 변환한다', () {
    final status = RecorderStatus.fromMap(const {
      'phase': 'error',
      'recordingId': 'interrupted-recording',
      'recovered': true,
      'recoveryState': 'interrupted',
      'errorCode': 'RECORDER_RECOVERY_INCOMPLETE',
    });

    expect(status.phase, RecorderPhase.error);
    expect(status.recordingId, 'interrupted-recording');
    expect(status.recovered, isTrue);
    expect(status.recoveryState, 'interrupted');
    expect(status.errorCode, 'RECORDER_RECOVERY_INCOMPLETE');
  });

  test('로컬 녹음 분류와 중단 원인을 변환한다', () {
    final capturing = RecorderStatus.fromMap(const {
      'phase': 'recording',
      'localState': 'CAPTURING',
    });
    final interrupted = RecorderStatus.fromMap(const {
      'phase': 'error',
      'localState': 'INTERRUPTED',
      'interruptionReason': 'other_app',
    });
    final corrupt = RecorderStatus.fromMap(const {
      'phase': 'error',
      'localState': 'CORRUPT',
    });

    expect(capturing.localState, RecorderLocalState.capturing);
    expect(interrupted.localState, RecorderLocalState.interrupted);
    expect(interrupted.interruptionReason, 'other_app');
    expect(corrupt.localState, RecorderLocalState.corrupt);
  });

  test('알 수 없는 상태는 오류로 처리한다', () {
    final status = RecorderStatus.fromMap(const {'phase': 'unexpected'});

    expect(status.phase, RecorderPhase.error);
  });
}
