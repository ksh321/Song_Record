import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/app/song_record_app.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/features/recorder/recorder_gateway.dart';
import 'package:song_record/features/recorder/recorder_panel.dart';
import 'package:song_record/features/settings/settings_screen.dart';
import 'package:song_record/network/health_client.dart';

void main() {
  AppConfig config(AppEnvironment environment) => AppConfig(
    environment: environment,
    apiBaseUrl: Uri.parse('http://127.0.0.1:8080'),
  );

  testWidgets('5개 탭 순서와 설정 복귀를 지키며 이동만으로 녹음하지 않는다', (tester) async {
    final gateway = _ShellRecorderGateway();
    var healthCalls = 0;
    await tester.pumpWidget(
      SongRecordApp(
        config: config(AppEnvironment.dev),
        recorderGateway: gateway,
        healthLoader: () async {
          healthCalls++;
          return const HealthResponse(status: 'UP', rawBody: '{"status":"UP"}');
        },
      ),
    );
    await tester.pumpAndSettle();

    const labels = ['내 곡', '인기 차트', '녹음', '플레이리스트', '검색'];
    expect(
      tester
          .widgetList<NavigationDestination>(find.byType(NavigationDestination))
          .map((destination) => destination.label),
      labels,
    );
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    expect(gateway.watchCalls, 0);

    for (var index = 0; index < labels.length; index++) {
      await _selectTab(tester, labels[index]);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text(labels[index]),
        ),
        findsOneWidget,
      );
      expect(find.text('녹음 시작'), index == 2 ? findsOneWidget : findsNothing);

      await tester.tap(find.byTooltip('설정'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text('녹음 시작'), findsNothing);

      // Exercise both the app-bar back action and Android's back dispatch.
      if (index.isEven) {
        await tester.tap(find.byTooltip('뒤로가기'));
      } else {
        await tester.binding.handlePopRoute();
      }
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        index,
      );
    }
    expect(healthCalls, 0);
    expect(gateway.permissionCalls, 0);
    expect(gateway.startCalls, 0);
    expect(gateway.stopCalls, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await gateway.dispose();
  });

  testWidgets('녹음 중 탭과 설정을 다녀와도 같은 세션에서 상태를 받고 종료한다', (tester) async {
    final gateway = _ShellRecorderGateway();
    await tester.pumpWidget(
      SongRecordApp(
        config: config(AppEnvironment.dev),
        recorderGateway: gateway,
      ),
    );
    await tester.pumpAndSettle();
    await _selectTab(tester, '녹음');
    final recorderState = tester.state(find.byType(RecorderPanel));
    await tester.ensureVisible(find.text('녹음 시작'));
    await tester.tap(find.text('녹음 시작'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(gateway.startCalls, 1);

    await _selectTab(tester, '검색');
    gateway.reportElapsed(12000);
    await tester.pump();
    expect(find.byType(RecorderPanel), findsNothing);
    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('뒤로가기'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      4,
    );
    await _selectTab(tester, '녹음');

    expect(tester.state(find.byType(RecorderPanel)), same(recorderState));
    expect(gateway.watchCalls, 1);
    expect(gateway.permissionCalls, 1);
    expect(gateway.startCalls, 1);
    expect(gateway.stopCalls, 0);
    expect(find.text('상태: 녹음 중'), findsOneWidget);
    expect(find.text('경과 시간: 00:12'), findsOneWidget);
    expect(find.text('녹음 ID: shell-recording'), findsOneWidget);

    await tester.ensureVisible(find.text('녹음 종료'));
    await tester.tap(find.text('녹음 종료'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(gateway.stopCalls, 1);
    expect(find.text('상태: 파일 생성 완료'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await gateway.dispose();
  });

  testWidgets('서버 확인은 dev 설정에서만 열고 녹음 조작을 포함하지 않는다', (tester) async {
    for (final environment in AppEnvironment.values) {
      final gateway = _ShellRecorderGateway();
      var healthCalls = 0;
      await tester.pumpWidget(
        SongRecordApp(
          config: config(environment),
          recorderGateway: gateway,
          healthLoader: () async {
            healthCalls++;
            return const HealthResponse(
              status: 'UP',
              rawBody: '{"status":"UP"}',
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('설정'));
      await tester.pumpAndSettle();
      expect(healthCalls, 0);
      if (environment == AppEnvironment.dev) {
        await tester.tap(find.text('서버 연결 확인'));
        await tester.pumpAndSettle();
        expect(healthCalls, 1);
        expect(find.text('서버 연결 성공: UP'), findsOneWidget);
      } else {
        expect(find.text('개발 도구'), findsNothing);
        expect(find.text('서버 연결 확인'), findsNothing);
      }
      expect(find.byType(RecorderPanel), findsNothing);
      expect(find.text('녹음 시작'), findsNothing);
      expect(gateway.watchCalls, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await gateway.dispose();
    }
  });
}

Future<void> _selectTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

class _ShellRecorderGateway implements RecorderGateway {
  final StreamController<RecorderStatus> _events =
      StreamController<RecorderStatus>.broadcast();
  RecorderStatus _status = const RecorderStatus.idle();
  int watchCalls = 0;
  int permissionCalls = 0;
  int startCalls = 0;
  int stopCalls = 0;

  void reportElapsed(int milliseconds) {
    _status = RecorderStatus(
      phase: RecorderPhase.recording,
      recordingId: 'shell-recording',
      elapsedMs: milliseconds,
    );
    _events.add(_status);
  }

  Future<void> dispose() => _events.close();

  @override
  Stream<RecorderStatus> watchStatus() {
    watchCalls++;
    return _events.stream;
  }

  @override
  Future<RecorderStatus> getCurrentStatus() async => _status;

  @override
  Future<RecorderDeviceInfo> getDeviceInfo() async => const RecorderDeviceInfo(
    manufacturer: 'test',
    model: 'shell-device',
    androidVersion: '1',
    sdkInt: 1,
  );

  @override
  Future<RecorderPermissions> requestPermissions() async {
    permissionCalls++;
    return const RecorderPermissions(
      microphoneGranted: true,
      notificationsGranted: true,
    );
  }

  @override
  Future<void> start() async {
    startCalls++;
    reportElapsed(0);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _status = const RecorderStatus(
      phase: RecorderPhase.completed,
      recordingId: 'shell-recording',
      elapsedMs: 12000,
    );
    _events.add(_status);
  }

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<void> playLatest() async {}
}
