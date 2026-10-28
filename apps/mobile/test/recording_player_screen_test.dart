import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/audio/audio_player.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/core/widgets/app_icon.dart';
import 'package:song_record/features/recorder/recording_player_screen.dart';

import '../tool/local_preservation_fixture.dart';
import 'audio_player_test.dart' show PlayerFake, UrlFake;

void main() {
  testWidgets('row preview waits for play and exposes the detail menu', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp(
        'player-preview-',
      );
      final manager = AccountStoreManager(
        environment: AppEnvironment.dev,
        directory: () async => directory,
        temporaryDirectory: () async => directory,
      );
      final store = await manager.openAccount(preservationId(1));
      final port = PlayerFake();
      final player = AudioPlayback(
        store,
        UrlFake(store.userId, DateTime.now),
        port,
      );
      var opened = 0;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: RecordingPlayerScreen(
              recordingId: preservationId(2),
              createPlayer: () => player,
              autoplay: false,
              title: '가수 · 곡 원키',
              initialDuration: 12000,
              onDetails: () => opened++,
            ),
          ),
        );
        await tester.pump();
        expect(port.plays, 0);
        expect(find.text('00:12.0'), findsOneWidget);
        expect(find.text('가수 · 곡 원키'), findsOneWidget);
        expect(find.byTooltip('설정'), findsNothing);
        for (final light in [false, true]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.preview(light: light),
              home: RecordingPlayerScreen(
                recordingId: preservationId(2),
                createPlayer: () => player,
                autoplay: false,
                title: '가수 · 곡 원키',
                initialDuration: 12000,
                onDetails: () => opened++,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final expected = light ? Colors.black : Colors.white;
          for (final icon in [Icons.replay_5, Icons.forward_5]) {
            final actual = tester.widget<AppIcon>(
              find.byWidgetPredicate((w) => w is AppIcon && w.icon == icon),
            );
            expect(actual.color, expected);
          }
          for (final tip in ['5초 뒤로', '5초 앞으로']) {
            final button = tester.widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == tip,
              ),
            );
            expect(button.onPressed, isNull);
            expect(
              button.style!.foregroundColor!.resolve({WidgetState.disabled}),
              expected,
            );
            expect(button.style!.foregroundColor!.resolve({}), expected);
          }
          expect(
            AppTheme.preview(light: light).snackBarTheme.backgroundColor,
            light ? const Color(0xFFE8E8E8) : const Color(0xFF303030),
          );
        }

        await tester.tap(find.byTooltip('녹음 상세 메뉴'));
        expect(opened, 1);
        expect(port.plays, 0);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await port.stream.close();
        await manager.logout();
        await directory.delete(recursive: true);
      }
    });
  });

  testWidgets('visible playback pauses, resumes, and stops on leaving', (
    tester,
  ) async {
    late Directory directory;
    late AccountStoreManager manager;
    late AudioPlayback player;
    late PlayerFake port;
    await tester.runAsync(() async {
      port = PlayerFake();
      directory = await Directory.systemTemp.createTemp('player-screen-');
      manager = AccountStoreManager(
        environment: AppEnvironment.dev,
        directory: () async => directory,
        temporaryDirectory: () async => directory,
      );
      final store = await manager.openAccount(preservationId(1));
      player = AudioPlayback(store, UrlFake(store.userId, DateTime.now), port);
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: RecordingPlayerScreen(
              recordingId: preservationId(2),
              createPlayer: () => player,
            ),
          ),
        );
        // Source lookup uses real SQLite/file I/O, so the entire flow uses the real clock.
        final ready = Completer<void>();
        void observe() {
          if (player.phase == PlaybackPhase.playing && !ready.isCompleted) {
            ready.complete();
          }
        }

        player.addListener(observe);
        observe();
        await ready.future.timeout(const Duration(seconds: 5));
        player.removeListener(observe);
        await tester.pump();
        expect(find.byTooltip('일시정지'), findsOneWidget);
        expect(find.byType(Slider), findsNothing);
        // Smooth display advances between native reports, but never runs away
        // past one reporting interval when playback reports stop arriving.
        port.stream.add(
          PlayerEvent(
            port.sources.last['token'] as int,
            PlaybackPhase.playing,
            4000,
            10000,
          ),
        );
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 160));
        await tester.pump();
        expect(find.text('00:04.0'), findsNothing);
        expect(player.position, 4000);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await tester.pump();
        expect(find.text('00:04.5'), findsOneWidget);
        port.stream.add(
          PlayerEvent(
            port.sources.last['token'] as int,
            PlaybackPhase.paused,
            4000,
            10000,
          ),
        );
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await tester.pump();
        expect(find.text('00:04.0'), findsOneWidget);
        port.stream.add(
          PlayerEvent(
            port.sources.last['token'] as int,
            PlaybackPhase.playing,
            0,
            10000,
          ),
        );
        await tester.pump();

        final waveform = find.byKey(const ValueKey('playback-waveform'));
        final box = tester.getRect(waveform);
        port.seekCompletion = Completer<void>();
        await tester.dragFrom(
          Offset(box.right - 10, box.center.dy),
          Offset(-box.width * .7, 0),
        );
        await tester.pump();
        expect(port.seekAt, greaterThan(0));
        final clockText = find.byWidgetPredicate(
          (w) => w is Text && w.style?.fontSize == 52,
        );
        final selectedTime = tester.widget<Text>(clockText).data;
        // Native playback may report the old position after finger release.
        port.stream.add(
          PlayerEvent(
            port.sources.last['token'] as int,
            PlaybackPhase.playing,
            0,
            10000,
          ),
        );
        await tester.pump();
        expect(tester.widget<Text>(clockText).data, selectedTime);
        final firstCompletion = port.seekCompletion!;
        port.seekCompletion = Completer<void>();
        await tester.dragFrom(
          Offset(box.left + 10, box.center.dy),
          Offset(box.width * .2, 0),
        );
        await tester.pump();
        final latestTime = tester.widget<Text>(clockText).data;
        expect(latestTime, isNot(selectedTime));
        firstCompletion.complete();
        await tester.pump();
        expect(tester.widget<Text>(clockText).data, latestTime);
        port.seekCompletion!.complete();
        await tester.pump();
        expect(player.position, port.seekAt);
        expect(tester.widget<Text>(clockText).data, latestTime);
        port.seekCompletion = null;

        port.stream.add(
          PlayerEvent(
            port.sources.last['token'] as int,
            PlaybackPhase.playing,
            5000,
            10000,
          ),
        );
        await tester.pump();
        await tester.dragFrom(
          Offset(box.left + 10, box.center.dy),
          Offset(box.width * .3, 0),
        );
        await tester.pump();
        expect(port.seekAt, inExclusiveRange(0, 5000));
        port.stream.add(
          PlayerEvent(
            port.sources.last['token'] as int,
            PlaybackPhase.playing,
            0,
            10000,
          ),
        );
        await tester.pump();
        await tester.tap(find.byTooltip('5초 뒤로'));
        expect(port.seekAt, 0);
        await tester.tap(find.byTooltip('5초 앞으로'));
        expect(port.seekAt, 5000);
        await tester.tap(find.byTooltip('일시정지'));
        await tester.pump();
        expect(port.pauses, 1);
        expect(find.byTooltip('재생'), findsOneWidget);
        await tester.tap(find.byTooltip('재생'));
        await tester.pump();
        expect(port.plays, 2);
        final loads = port.sources.length;
        port.stream.add(
          PlayerEvent(
            port.sources.last['token'] as int,
            PlaybackPhase.completed,
            2000,
            10000,
          ),
        );
        await tester.pump();
        await tester.tap(find.byTooltip('재생'));
        await tester.pump();
        expect(port.plays, 3);
        expect(port.sources.length, loads);
        expect(player.position, 2000);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(port.stops, greaterThanOrEqualTo(2));
      } finally {
        await tester.pumpWidget(const SizedBox());
        await port.stream.close();
        await manager.logout();
        await directory.delete(recursive: true);
      }
    });
  });
}
