import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/core/widgets/detail_information_card.dart';
import 'package:song_record/features/recorder/recording_audio_panel.dart';
import 'package:song_record/features/recorder/recording_detail_screen.dart';
import 'package:song_record/features/recorder/recording_input_screen.dart';
import 'package:song_record/features/recorder/recording_manage_screen.dart';
import 'package:song_record/features/trash/trash_screens.dart';

import 'recording_input_test.dart' as input;
import 'restore_candidate_song_test.dart' as trash_fixture;
import 'support/completed_capture_fixture.dart';

class _Trash extends trash_fixture.FakeTrash {
  @override
  Future<void> trashRecording(String recording, bool confirmed) async {
    writes++;
  }
}

void main() {
  for (final light in [false, true]) {
    testWidgets(
      'detail menu keeps edit/manage/delete reachable without playback or writes light=$light',
      (t) async {
        await t.runAsync(() async {
          final root = await Directory.systemTemp.createTemp('sr-detail-menu-');
          final manager = AccountStoreManager(
            environment: AppEnvironment.dev,
            directory: () async => root,
            temporaryDirectory: () async => root,
          );
          final changes = ChangeNotifier();
          final trash = _Trash();
          try {
            final store = await manager.openAccount(owner);
            final repo = LocalRepository(store);
            await capture(repo);
            await repo.saveRecordingInput(
              rec,
              input.fields(),
              repo.recordingSaveOperationIds(),
            );
            final count = (await repo.pending()).length;
            await t.pumpWidget(
              MaterialApp(
                theme: AppTheme.preview(light: light),
                builder: (context, child) => RecordingAudioAccess(
                  store: () => store,
                  createPlayer: (_) =>
                      throw StateError('No playback requested'),
                  changes: changes,
                  refresh: () {},
                  child: child!,
                ),
                home: RecordingDetailScreen(
                  id: rec,
                  repository: repo,
                  isCurrent: (_) => true,
                  trash: trash,
                ),
              ),
            );
            Future<void> settle() async {
              await Future<void>.delayed(const Duration(milliseconds: 120));
              await t.pumpAndSettle();
            }

            await settle();
            expect(find.byType(DetailInformationCard), findsOneWidget);
            expect(find.text('재생'), findsNothing);
            expect(find.text('녹음 정보 수정'), findsNothing);
            for (final action in ['정보 수정', '보관 관리', '삭제']) {
              await t.ensureVisible(find.byTooltip('녹음 메뉴'));
              await t.tap(find.byTooltip('녹음 메뉴'));
              await t.pumpAndSettle();
              expect(find.text('정보 수정'), findsOneWidget);
              expect(find.text('보관 관리'), findsOneWidget);
              expect(find.text('삭제'), findsOneWidget);
              await t.tap(find.text(action));
              await settle();
              if (action == '정보 수정') {
                expect(find.byType(RecordingInputScreen), findsOneWidget);
              }
              if (action == '보관 관리') {
                expect(find.byType(RecordingManageScreen), findsOneWidget);
              }
              if (action == '삭제') {
                expect(find.byType(DeleteScreen), findsOneWidget);
              }
              if (action == '정보 수정') {
                await t.tap(find.text('취소'));
              } else {
                await t.pageBack();
              }
              await settle();
              expect(find.byType(RecordingDetailScreen), findsOneWidget);
            }
            expect(trash.writes, 0);
            expect((await repo.pending()).length, count);
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
