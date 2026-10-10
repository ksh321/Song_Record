import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/recorder/recorder_gateway.dart';
import 'package:song_record/features/recorder/recorder_panel.dart';

class _Gateway implements RecorderGateway {
  final events = StreamController<RecorderStatus>.broadcast();
  RecorderStatus current = const RecorderStatus.idle();
  RecorderPermissions permissions = const RecorderPermissions(
    microphoneGranted: true,
    notificationsGranted: true,
  );
  Completer<RecorderPermissions>? permissionReply;
  int starts = 0;
  int stops = 0;
  int requests = 0;
  @override
  Stream<RecorderStatus> watchStatus() => events.stream;
  @override
  Future<RecorderStatus> getCurrentStatus() async => current;
  @override
  Future<RecorderDeviceInfo> getDeviceInfo() async => const RecorderDeviceInfo(
    manufacturer: 'private',
    model: 'private',
    androidVersion: '16',
    sdkInt: 36,
  );
  @override
  Future<RecorderPermissions> requestPermissions() {
    requests++;
    return permissionReply?.future ?? Future.value(permissions);
  }

  @override
  Future<void> start() async {
    starts++;
    emit(
      const RecorderStatus(
        phase: RecorderPhase.recording,
        recordingId: 'private-id',
        outputPath: '/private/path',
      ),
    );
  }

  @override
  Future<void> stop() async {
    stops++;
    emit(
      const RecorderStatus(
        phase: RecorderPhase.completed,
        elapsedMs: 12000,
        localState: RecorderLocalState.inputPending,
      ),
    );
  }

  @override
  Future<void> playLatest() async {}
  @override
  Future<void> openAppSettings() async {}
  void emit(RecorderStatus status) {
    current = status;
    events.add(status);
  }
}

Future<void> _open(WidgetTester t, _Gateway g) async {
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: ListView(
          children: [RecorderPanel(gateway: g, diagnostics: false)],
        ),
      ),
    ),
  );
  await t.pump();
}

Future<void> _close(WidgetTester t, _Gateway g) async {
  await t.pumpWidget(const SizedBox());
  await g.events.close();
}

void main() {
  testWidgets(
    'persisting is single-flight; only successful handoff enables another recording',
    (t) async {
      final g = _Gateway()
        ..current = const RecorderStatus(
          phase: RecorderPhase.completed,
          recordingId: 'private-id',
        );
      final done = Completer<void>();
      int calls = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                RecorderPanel(
                  gateway: g,
                  diagnostics: false,
                  onCompleted: (status) {
                    calls++;
                    return done.future;
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(seconds: 2));
      expect(calls, 1);
      expect(find.text('새 녹음 시작'), findsNothing);
      done.complete();
      await t.pump();
      await t.pump();
      expect(find.text('새 녹음 시작'), findsOneWidget);
      await _close(t, g);
    },
  );
  testWidgets(
    'failed handoff preserves completed recording and retries without restarting microphone',
    (t) async {
      final g = _Gateway()
        ..current = const RecorderStatus(
          phase: RecorderPhase.completed,
          recordingId: 'private-id',
        );
      int calls = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                RecorderPanel(
                  gateway: g,
                  diagnostics: false,
                  onCompleted: (status) async {
                    calls++;
                    if (calls == 1) throw StateError('storage unavailable');
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await t.pump();
      await t.pump();
      await t.pump(const Duration(seconds: 2));
      expect(calls, 1);
      expect(g.starts, 0);
      expect(find.text('완료 녹음 듣기'), findsOneWidget);
      expect(find.text('새 녹음 시작'), findsNothing);
      await t.ensureVisible(find.text('입력 대기 저장 다시 시도'));
      await t.tap(find.text('입력 대기 저장 다시 시도'));
      await t.pump();
      await t.pump();
      expect(calls, 2);
      expect(g.starts, 0);
      expect(find.text('새 녹음 시작'), findsOneWidget);
      await _close(t, g);
    },
  );

  testWidgets(
    'elapsed remains native observation; circle becomes square, complete keeps pending file private',
    (t) async {
      final g = _Gateway();
      await _open(t, g);
      expect(g.requests, 0);
      expect(
        find.byKey(const ValueKey('recorder-start-circle')),
        findsOneWidget,
      );
      await t.tap(find.text('녹음 시작'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(g.starts, 1);
      expect(
        find.byKey(const ValueKey('recorder-stop-square')),
        findsOneWidget,
      );
      g.emit(
        const RecorderStatus(
          phase: RecorderPhase.recording,
          recordingId: 'private-id',
          outputPath: '/private/path',
          elapsedMs: 12000,
        ),
      );
      await t.pump();
      await t.pump(const Duration(seconds: 3));
      expect(find.text('00:12'), findsOneWidget);
      expect(find.textContaining('private-id'), findsNothing);
      expect(find.textContaining('/private/path'), findsNothing);
      await t.tap(find.text('녹음 완료'));
      await t.tap(find.text('녹음 완료'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(g.stops, 1);
      expect(find.text('녹음 정보 입력 대기'), findsOneWidget);
      expect(find.text('녹음 시작'), findsNothing);
      await _close(t, g);
    },
  );
  testWidgets(
    'permission awaiting prevents duplicate starts; denial allows retry without starting',
    (t) async {
      final g = _Gateway()..permissionReply = Completer<RecorderPermissions>();
      await _open(t, g);
      await t.tap(find.text('녹음 시작'));
      await t.tap(find.text('녹음 시작'));
      await t.pump();
      expect(g.requests, 1);
      g.permissionReply!.complete(
        const RecorderPermissions(
          microphoneGranted: false,
          notificationsGranted: false,
        ),
      );
      await t.pump();
      expect(g.starts, 0);
      expect(find.text('마이크 권한 다시 요청'), findsOneWidget);
      await _close(t, g);
    },
  );
  testWidgets(
    'permission return in background never starts microphone service',
    (t) async {
      final g = _Gateway()..permissionReply = Completer<RecorderPermissions>();
      await _open(t, g);
      await t.tap(find.text('녹음 시작'));
      await t.pump();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      g.permissionReply!.complete(g.permissions);
      await t.pump();
      expect(g.starts, 0);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      expect(g.starts, 0);
      await _close(t, g);
    },
  );
  testWidgets(
    'native warnings, six minute completion and recovery render without Flutter timer advancement',
    (t) async {
      final g = _Gateway();
      await _open(t, g);
      g.emit(
        const RecorderStatus(
          phase: RecorderPhase.recording,
          elapsedMs: 330000,
          limitWarning: RecorderLimitWarning.thirtySeconds,
        ),
      );
      await t.pump();
      expect(find.text('05:30'), findsOneWidget);
      expect(find.text('30초 뒤 녹음이 자동으로 완료돼요.'), findsOneWidget);
      g.emit(
        const RecorderStatus(
          phase: RecorderPhase.recording,
          elapsedMs: 350000,
          limitWarning: RecorderLimitWarning.tenSeconds,
        ),
      );
      await t.pump();
      expect(find.text('10초 뒤 녹음이 자동으로 완료돼요.'), findsOneWidget);
      g.emit(
        const RecorderStatus(
          phase: RecorderPhase.completed,
          elapsedMs: 360000,
          stopReason: 'time_limit',
          recovered: true,
        ),
      );
      await t.pump();
      expect(find.text('06:00'), findsOneWidget);
      expect(find.text('6분에 도달해 자동으로 완료했어요.'), findsOneWidget);
      expect(find.text('앱을 닫기 전의 녹음을 찾았어요.'), findsOneWidget);
      await _close(t, g);
    },
  );
  testWidgets(
    'small screen large type remains scrollable with visible labelled controls',
    (t) async {
      t.view.physicalSize = const Size(320, 568);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final g = _Gateway();
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: ListView(
                children: [RecorderPanel(gateway: g, diagnostics: false)],
              ),
            ),
          ),
        ),
      );
      await t.pump();
      await t.ensureVisible(find.text('녹음 시작'));
      expect(t.takeException(), isNull);
      await _close(t, g);
    },
  );
}
