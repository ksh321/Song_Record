import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/recorder/recorder_gateway.dart';

void main() {
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
      'actualMime': 'audio/mp4a-latm',
      'actualSampleRate': 48000,
      'actualChannels': 1,
      'actualAacProfile': 2,
    });

    expect(status.phase, RecorderPhase.completed);
    expect(status.actualMime, 'audio/mp4a-latm');
    expect(status.actualSampleRate, 48000);
    expect(status.actualChannels, 1);
    expect(status.actualAacProfile, 2);
    expect(status.isRecording, isFalse);
  });

  test('알 수 없는 상태는 오류로 처리한다', () {
    final status = RecorderStatus.fromMap(const {'phase': 'unexpected'});

    expect(status.phase, RecorderPhase.error);
  });
}
