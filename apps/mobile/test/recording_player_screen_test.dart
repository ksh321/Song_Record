import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/audio/audio_player.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/features/recorder/recording_player_screen.dart';

import '../tool/local_preservation_fixture.dart';
import 'audio_player_test.dart' show PlayerFake, UrlFake;

void main() {
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
        expect(find.text('일시정지'), findsOneWidget);
        await tester.tap(find.byTooltip('5초 뒤로'));
        expect(port.seekAt, 0);
        await tester.tap(find.byTooltip('5초 앞으로'));
        expect(port.seekAt, 5000);
        await tester.tap(find.text('일시정지'));
        await tester.pump();
        expect(port.pauses, 1);
        expect(find.text('재생'), findsOneWidget);
        await tester.tap(find.text('재생'));
        await tester.pump();
        expect(port.plays, 2);
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
