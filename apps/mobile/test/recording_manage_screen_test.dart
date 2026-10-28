import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/recorder/recording_audio_panel.dart';
import 'package:song_record/features/recorder/recording_manage_screen.dart';

import 'support/completed_capture_fixture.dart';

void main() {
  for (final light in [false, true]) {
    testWidgets(
      'recording management cancellation preserves audio in light=$light',
      (t) async {
        await t.runAsync(() async {
          final root = await Directory.systemTemp.createTemp('sr-manage-');
          final manager = AccountStoreManager(
            environment: AppEnvironment.dev,
            directory: () async => root,
            temporaryDirectory: () async => root,
          );
          final store = await manager.openAccount(owner);
          final repo = LocalRepository(store);
          await capture(repo);
          final changes = ChangeNotifier();
          try {
            await t.pumpWidget(
              MaterialApp(
                theme: AppTheme.preview(light: light),
                builder: (context, child) => RecordingAudioAccess(
                  store: () => store,
                  createPlayer: (_) =>
                      throw StateError('No playback requested'),
                  changes: changes,
                  refresh: () {},
                  storageBuilder: (_, id) =>
                      Scaffold(appBar: AppBar(), body: Text('pin:$id')),
                  child: child!,
                ),
                home: RecordingManageScreen(
                  id: rec,
                  title: '시험 녹음',
                  artist: '시험 가수',
                  isCurrent: () => true,
                  deleteBuilder: (_) => Scaffold(
                    appBar: AppBar(),
                    body: const Text('delete preview'),
                  ),
                ),
              ),
            );
            await Future<void>.delayed(const Duration(milliseconds: 120));
            await t.pumpAndSettle();
            await t.tap(find.text('M4A 내보내기'));
            await t.pumpAndSettle();
            expect(find.text('저장 위치 선택'), findsOneWidget);
            await t.tap(find.text('취소'));
            await t.pumpAndSettle();
            await t.tap(find.text('이 기기 파일 정리'));
            final deadline = DateTime.now().add(const Duration(seconds: 10));
            while (find.text('파일을 복구하지 못할 수 있음을 이해했습니다').evaluate().isEmpty &&
                DateTime.now().isBefore(deadline)) {
              await Future<void>.delayed(const Duration(milliseconds: 20));
              await t.pump();
            }
            await t.pumpAndSettle();
            expect(find.text('파일을 복구하지 못할 수 있음을 이해했습니다'), findsOneWidget);
            await t.tap(find.text('취소'));
            await t.pumpAndSettle();
            expect(await store.readLocalAudio(rec), bytes);
            await t.tap(find.text('고정 보관'));
            await t.pumpAndSettle();
            expect(find.text('pin:$rec'), findsOneWidget);
            await t.pageBack();
            await t.pumpAndSettle();
            await t.tap(find.text('녹음 삭제'));
            await t.pumpAndSettle();
            expect(find.text('delete preview'), findsOneWidget);
            await t.pageBack();
            await t.pumpAndSettle();
            expect(await store.readLocalAudio(rec), bytes);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            changes.dispose();
            await manager.logout();
            await root.delete(recursive: true);
          }
        });
      },
    );
  }
}
