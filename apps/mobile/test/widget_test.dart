import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/app/song_record_app.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/theme/app_tokens.dart';
import 'package:song_record/features/recorder/recorder_gateway.dart';
import 'package:song_record/features/recorder/recorder_panel.dart';
import 'package:song_record/network/health_client.dart';

void main() {
  final config = AppConfig(
    environment: AppEnvironment.dev,
    apiBaseUrl: Uri.parse('http://127.0.0.1:8080'),
  );

  testWidgets('실제 앱에 초기 블루와 어두운 배경을 적용한다', (tester) async {
    await tester.pumpWidget(
      SongRecordApp(
        config: config,
        recorderGateway: const _FakeRecorderGateway(),
        healthLoader: () async =>
            const HealthResponse(status: 'UP', rawBody: '{"status":"UP"}'),
      ),
    );
    await tester.pumpAndSettle();
    final theme = Theme.of(tester.element(find.byType(RecorderPanel)));
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(theme.colorScheme.primary, AppAccent.blue.background);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('강조색을 바꿔도 실제 녹음 시작·종료 버튼은 빨강을 유지한다', (tester) async {
    for (final accent in AppAccent.values) {
      for (final phase in [RecorderPhase.idle, RecorderPhase.recording]) {
        await tester.pumpWidget(
          SongRecordApp(
            config: config,
            accent: accent,
            recorderGateway: _FakeRecorderGateway(
              status: RecorderStatus(phase: phase),
            ),
            healthLoader: () async =>
                const HealthResponse(status: 'UP', rawBody: '{"status":"UP"}'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('녹음 시작'));
        final start = tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('녹음 시작'),
            matching: find.byWidgetPredicate(
              (widget) => widget is FilledButton,
            ),
          ),
        );
        final stop = tester.widget<OutlinedButton>(
          find.ancestor(
            of: find.text('녹음 종료'),
            matching: find.byWidgetPredicate(
              (widget) => widget is OutlinedButton,
            ),
          ),
        );
        if (phase == RecorderPhase.idle) {
          expect(start.onPressed, isNotNull);
          expect(
            start.style!.backgroundColor!.resolve({}),
            AppColors.recording,
          );
          expect(stop.onPressed, isNull);
        } else {
          expect(start.onPressed, isNull);
          expect(stop.onPressed, isNotNull);
          expect(stop.style!.foregroundColor!.resolve({}), AppColors.recording);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });

  testWidgets('서버 health 성공 응답을 표시한다', (tester) async {
    await tester.pumpWidget(
      SongRecordApp(
        config: config,
        recorderGateway: const _FakeRecorderGateway(),
        healthLoader: () async =>
            const HealthResponse(status: 'UP', rawBody: '{"status":"UP"}'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('서버 연결 성공: UP'), findsOneWidget);
    expect(find.text('응답: {"status":"UP"}'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('서버 health 실패와 재시도 버튼을 표시한다', (tester) async {
    await tester.pumpWidget(
      SongRecordApp(
        config: config,
        recorderGateway: const _FakeRecorderGateway(),
        healthLoader: () async {
          throw const HealthCheckException('테스트 연결 실패');
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('서버 연결 실패'), findsOneWidget);
    expect(find.text('테스트 연결 실패'), findsOneWidget);
    expect(find.text('다시 확인'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('권한 거부 후 앱에서 마이크 권한을 다시 요청한다', (tester) async {
    final gateway = _DeniedPermissionGateway();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RecorderPanel(gateway: gateway)),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('녹음 시작'));
    await tester.pump();

    expect(find.text('마이크 권한 다시 요청'), findsOneWidget);
    expect(find.text('마이크 권한이 필요합니다. 아래 버튼으로 다시 요청하세요.'), findsOneWidget);

    await tester.tap(find.text('마이크 권한 다시 요청'));
    await tester.pump();

    expect(gateway.permissionRequestCount, 2);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('재요청이 차단되면 앱 설정을 직접 연다', (tester) async {
    final gateway = _DeniedPermissionGateway(canAskAgain: false);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RecorderPanel(gateway: gateway)),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('녹음 시작'));
    await tester.pump();
    expect(find.text('마이크 권한 설정 열기'), findsOneWidget);

    await tester.tap(find.text('마이크 권한 설정 열기'));
    await tester.pump();
    expect(gateway.settingsOpenCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('실기 검증용 기기 정보를 표시한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RecorderPanel(
            gateway: _FakeRecorderGateway(
              deviceInfo: RecorderDeviceInfo(
                manufacturer: 'samsung',
                model: 'SM-A546S',
                androidVersion: '16',
                sdkInt: 36,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('검증 기기: samsung SM-A546S · Android 16 (SDK 36)'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('화면을 다시 만들어도 서비스의 녹음 상태를 복원한다', (tester) async {
    await tester.pumpWidget(
      SongRecordApp(
        config: config,
        recorderGateway: const _FakeRecorderGateway(
          status: RecorderStatus(
            phase: RecorderPhase.recording,
            recordingId: 'test-recording',
            elapsedMs: 5000,
          ),
        ),
        healthLoader: () async =>
            const HealthResponse(status: 'UP', rawBody: '{"status":"UP"}'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('상태: 녹음 중'), findsOneWidget);
    expect(find.text('경과 시간: 00:05'), findsOneWidget);
    expect(find.text('녹음 ID: test-recording'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('상태 이벤트가 없어도 조회로 녹음 상태를 동기화한다', (tester) async {
    final gateway = _PollingRecorderGateway();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RecorderPanel(gateway: gateway)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('녹음 시작'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('상태: 녹음 중'), findsOneWidget);
    expect(find.text('경과 시간: 00:01'), findsOneWidget);
    expect(find.text('녹음 ID: polled-recording'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('5분 30초와 5분 50초 종료 임박 안내를 표시한다', (tester) async {
    final statuses = [
      const RecorderStatus(
        phase: RecorderPhase.recording,
        elapsedMs: 330000,
        remainingMs: 30000,
        limitWarning: RecorderLimitWarning.thirtySeconds,
      ),
      const RecorderStatus(
        phase: RecorderPhase.recording,
        elapsedMs: 350000,
        remainingMs: 10000,
        limitWarning: RecorderLimitWarning.tenSeconds,
      ),
    ];

    for (final status in statuses) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecorderPanel(
              key: ValueKey(status.elapsedMs),
              gateway: _FakeRecorderGateway(status: status),
            ),
          ),
        ),
      );
      await tester.pump();

      final seconds = status.remainingMs! ~/ 1000;
      expect(find.text('녹음 종료 임박: $seconds초 후 자동 종료됩니다.'), findsOneWidget);
    }

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('복구된 녹음 파일과 검증 정보를 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecorderPanel(
            gateway: const _FakeRecorderGateway(
              status: RecorderStatus(
                phase: RecorderPhase.completed,
                recordingId: 'recovered-recording',
                outputPath: '/data/recordings/recovered-recording.m4a',
                elapsedMs: 4200,
                durationMs: 4200,
                sizeBytes: 12345,
                sha256: 'abc123',
                recovered: true,
                recoveryState: 'recovered',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('이전 실행에서 완료된 녹음 파일을 복구했습니다.'), findsOneWidget);
    expect(find.text('확인된 길이: 00:04'), findsOneWidget);
    expect(find.text('SHA-256: abc123'), findsOneWidget);
    expect(find.text('녹음 파일 재생 확인'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('녹음 실패 분류와 사용자 안내를 표시한다', (tester) async {
    const cases = [
      (
        RecorderStatus(
          phase: RecorderPhase.error,
          localState: RecorderLocalState.interrupted,
          interruptionReason: 'other_app',
        ),
        '로컬 상태: 녹음 중단',
        '다른 앱이 마이크를 사용 중이어서 녹음이 시작되지 않았습니다.',
      ),
      (
        RecorderStatus(
          phase: RecorderPhase.error,
          localState: RecorderLocalState.corrupt,
        ),
        '로컬 상태: 재생 불가',
        '파일 검증에 실패해 재생할 수 없는 녹음으로 분류했습니다.',
      ),
      (
        RecorderStatus(
          phase: RecorderPhase.completed,
          localState: RecorderLocalState.inputPending,
        ),
        '로컬 상태: 곡 정보 입력 대기',
        '녹음 파일 검증이 끝났습니다. 곡 정보 입력을 기다리고 있습니다.',
      ),
    ];

    for (final (status, label, message) in cases) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecorderPanel(
              key: ValueKey(label),
              gateway: _FakeRecorderGateway(status: status),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text(label), findsOneWidget);
      expect(find.text(message), findsOneWidget);
    }

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('6분 제한 자동 종료 결과를 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecorderPanel(
            gateway: const _FakeRecorderGateway(
              status: RecorderStatus(
                phase: RecorderPhase.completed,
                elapsedMs: 360000,
                stopReason: 'time_limit',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('상태: 파일 생성 완료'), findsOneWidget);
    expect(find.text('경과 시간: 06:00'), findsOneWidget);
    expect(find.text('6분 제한에 도달해 자동 종료되었습니다.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _FakeRecorderGateway implements RecorderGateway {
  const _FakeRecorderGateway({
    this.status = const RecorderStatus.idle(),
    this.deviceInfo = const RecorderDeviceInfo(
      manufacturer: 'test',
      model: 'test-device',
      androidVersion: '1',
      sdkInt: 1,
    ),
  });

  final RecorderStatus status;
  final RecorderDeviceInfo deviceInfo;

  @override
  Future<RecorderStatus> getCurrentStatus() async => status;

  @override
  Future<RecorderDeviceInfo> getDeviceInfo() async => deviceInfo;

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<void> playLatest() async {}

  @override
  Future<RecorderPermissions> requestPermissions() async =>
      const RecorderPermissions(
        microphoneGranted: true,
        notificationsGranted: true,
      );

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Stream<RecorderStatus> watchStatus() => const Stream.empty();
}

class _PollingRecorderGateway implements RecorderGateway {
  RecorderStatus _status = const RecorderStatus.idle();

  @override
  Future<RecorderStatus> getCurrentStatus() async => _status;

  @override
  Future<RecorderDeviceInfo> getDeviceInfo() async => const RecorderDeviceInfo(
    manufacturer: 'test',
    model: 'poll-device',
    androidVersion: '1',
    sdkInt: 1,
  );

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<void> playLatest() async {}

  @override
  Future<RecorderPermissions> requestPermissions() async =>
      const RecorderPermissions(
        microphoneGranted: true,
        notificationsGranted: true,
      );

  @override
  Future<void> start() async {
    _status = const RecorderStatus(
      phase: RecorderPhase.recording,
      recordingId: 'polled-recording',
      elapsedMs: 1000,
    );
  }

  @override
  Future<void> stop() async {
    _status = const RecorderStatus(phase: RecorderPhase.completed);
  }

  @override
  Stream<RecorderStatus> watchStatus() => const Stream.empty();
}

class _DeniedPermissionGateway implements RecorderGateway {
  _DeniedPermissionGateway({this.canAskAgain = true});

  final bool canAskAgain;
  int permissionRequestCount = 0;
  int settingsOpenCount = 0;

  @override
  Future<RecorderStatus> getCurrentStatus() async =>
      const RecorderStatus.idle();

  @override
  Future<RecorderDeviceInfo> getDeviceInfo() async => const RecorderDeviceInfo(
    manufacturer: 'test',
    model: 'permission-device',
    androidVersion: '1',
    sdkInt: 1,
  );

  @override
  Future<void> openAppSettings() async {
    settingsOpenCount += 1;
  }

  @override
  Future<void> playLatest() async {}

  @override
  Future<RecorderPermissions> requestPermissions() async {
    permissionRequestCount += 1;
    return RecorderPermissions(
      microphoneGranted: false,
      notificationsGranted: true,
      microphoneCanAskAgain: canAskAgain,
    );
  }

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Stream<RecorderStatus> watchStatus() => const Stream.empty();
}
