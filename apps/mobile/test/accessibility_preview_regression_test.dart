import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/domain/domain_ordering.dart';
import 'package:song_record/core/domain/identifiers.dart';
import 'package:song_record/core/widgets/recording_roles_card.dart';

import '../tool/preview_accessibility.dart';

void main() {
  testWidgets('스크롤 위치와 보관 설명의 펼침 상태를 독립적으로 복원한다', (tester) async {
    final bucket = PageStorageBucket();
    final visible = ValueNotifier(false);
    final controller = ScrollController();
    addTearDown(visible.dispose);
    addTearDown(controller.dispose);
    final id = SongId('00000000-0000-4000-8000-000000000001');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageStorage(
            bucket: bucket,
            child: SingleChildScrollView(
              key: const PageStorageKey('scroll-with-retention'),
              controller: controller,
              child: Column(
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: visible,
                    builder: (_, show, _) => show
                        ? RecordingRolesCard(
                            songId: id,
                            selection: const RecordingSelection(),
                            recordings: const {},
                          )
                        : const SizedBox(height: 400),
                  ),
                  const SizedBox(height: 1200),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    controller.jumpTo(100);
    await tester.pumpAndSettle();
    // The scroll position is now stored before the ExpansionTile is mounted.
    visible.value = true;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('자동 보관 기준'));
    await tester.tap(find.text('자동 보관 기준'));
    await tester.pumpAndSettle();
    final description = find.textContaining('대표·최신·최저 티어 녹음을 자동 보관해요.');
    expect(description, findsOneWidget);
    visible.value = false;
    await tester.pumpAndSettle();
    controller.jumpTo(120);
    await tester.pumpAndSettle();
    visible.value = true;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(description, findsOneWidget);
    expect(controller.offset, closeTo(120, 0.01));
  });

  testWidgets('미리보기 설정에서 글꼴과 모션을 바꾸고 시스템 값으로 복원한다', (tester) async {
    await tester.pumpWidget(const AccessibilityPreviewApp());
    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2.0배'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('모션 줄이기'));
    await tester.tap(find.text('모션 줄이기'));
    await tester.pumpAndSettle();
    var media = MediaQuery.of(tester.element(find.byType(Scaffold).last));
    expect(media.textScaler.scale(10), 20);
    expect(media.disableAnimations, isTrue);
    await tester.ensureVisible(find.text('샘플로 돌아가기'));
    await tester.tap(find.text('샘플로 돌아가기'));
    await tester.pumpAndSettle();
    media = MediaQuery.of(tester.element(find.text('새 곡 찾기')));
    expect(media.textScaler.scale(10), 20);
    expect(media.disableAnimations, isTrue);
    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('시스템 설정으로 초기화'));
    await tester.tap(find.text('시스템 설정으로 초기화'));
    await tester.pumpAndSettle();
    media = MediaQuery.of(tester.element(find.byType(Scaffold).last));
    expect(media.textScaler.scale(10), 10);
    expect(media.disableAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });
}
