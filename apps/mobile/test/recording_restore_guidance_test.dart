import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/files/recording_file_status.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/core/widgets/recording_playback_actions.dart';

void main() {
  RecordingFileStatus status({
    DeviceAudioState device = DeviceAudioState.missing,
    String server = 'NONE',
    bool selected = false,
    InformationSyncState information = InformationSyncState.synced,
  }) => RecordingFileStatus(
    recording: '00000000-0000-4000-8000-000000000001',
    information: information,
    device: device,
    serverState: server,
    blockedReason: server == 'QUEUED' ? 'QUOTA' : null,
    pinCurrent: selected,
    pinPending: selected,
  );
  test('only verified local or actual STORED enables playback; selected/queued/deleting/unknown do not', () {
    expect(status().canPlay, isFalse);
    for (final cloud in [
      'NONE',
      'QUEUED',
      'UPLOADING',
      'VERIFYING',
      'DELETING',
      'UNKNOWN',
    ]) {
      expect(status(server: cloud, selected: true).canPlay, isFalse);
    }
    expect(
      status(device: DeviceAudioState.available, server: 'UNKNOWN').canPlay,
      isTrue,
    );
    expect(status(server: 'STORED').canPlay, isTrue);
    expect(
      status(
        device: DeviceAudioState.available,
        information: InformationSyncState.deleted,
      ).canPlay,
      isFalse,
    );
    expect(
      status(device: DeviceAudioState.unknown).filesConfirmedAbsent,
      isFalse,
    );
    expect(
      status(server: 'UNKNOWN').playbackUnavailableLabel,
      contains('확인할 수 없습니다'),
    );
  });
  testWidgets(
    'missing source disables play, retains information and opens original-device/backup guide',
    (tester) async {
      var played = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: RecordingPlaybackActions(
              status: status(selected: true),
              onPlay: () => played++,
            ),
          ),
        ),
      );
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '재생'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('재생'));
      expect(played, 0);
      expect(find.textContaining('녹음 정보는 유지'), findsOneWidget);
      await tester.tap(find.text('파일 복원 안내'));
      await tester.pumpAndSettle();
      expect(find.textContaining('원래 기기에서 파일'), findsOneWidget);
      expect(find.textContaining('M4A 사본이나 사용자 백업'), findsOneWidget);
      expect(find.textContaining('선택한 것만으로 백업이 완료되지는'), findsOneWidget);
    },
  );
  testWidgets(
    'queued selection never becomes backup completion or enabled play; actual source enables',
    (tester) async {
      var played = 0;
      Future<void> render(RecordingFileStatus value) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecordingPlaybackActions(
              status: value,
              onPlay: () => played++,
            ),
          ),
        ),
      );
      await render(status(server: 'QUEUED', selected: true));
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '재생'))
            .onPressed,
        isNull,
      );
      expect(find.textContaining('서버 보관은 아직 완료되지'), findsOneWidget);
      await render(status(server: 'STORED'));
      await tester.tap(find.text('재생'));
      expect(played, 1);
      await render(
        status(device: DeviceAudioState.available, server: 'UNKNOWN'),
      );
      await tester.tap(find.text('재생'));
      expect(played, 2);
      expect(find.text('파일 복원 안내'), findsNothing);
    },
  );
}
