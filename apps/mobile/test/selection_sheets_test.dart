import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/domain/song_types.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/core/widgets/selection_sheet.dart';
import 'package:song_record/core/widgets/sort_sheet.dart';
import 'package:song_record/core/widgets/tier_picker.dart';
import 'package:song_record/core/widgets/version_picker.dart';

Future<void> launch(
  WidgetTester tester,
  void Function(BuildContext) open, {
  double scale = 1,
  bool reduceMotion = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: reduceMotion,
        ),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => open(context),
            child: const Text('열기'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('내 곡과 녹음 정렬은 서로 다른 항목과 선택값을 반환한다', (tester) async {
    SelectionResult<SongSort>? song;
    await launch(tester, (context) async {
      song = await SortSheet.songs(
        context: context,
        selected: SongSort.recentlyAdded,
      );
    });
    expect(find.text('최근 추가순'), findsOneWidget);
    expect(find.text('최근 녹음순'), findsOneWidget);
    expect(find.text('가수순'), findsOneWidget);
    expect(find.text('오래된순'), findsNothing);
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.tap(find.text('곡명순'));
    await tester.pumpAndSettle();
    expect(song?.value, SongSort.title);

    SelectionResult<RecordingSort>? recording;
    await launch(tester, (context) async {
      recording = await SortSheet.recordings(
        context: context,
        selected: RecordingSort.newest,
      );
    });
    expect(find.text('오래된순'), findsOneWidget);
    expect(find.text('최근 추가순'), findsNothing);
    expect(find.text('가수순'), findsNothing);
    await tester.tap(find.text('오래된순'));
    await tester.pumpAndSettle();
    expect(recording?.value, RecordingSort.oldest);
  });

  testWidgets('티어 안내와 체크가 보이고 미정 선택은 취소와 구분한다', (tester) async {
    SelectionResult<SongTier?>? result;
    await launch(tester, (context) async {
      result = await TierPicker.song(context: context, selected: SongTier.a);
    });
    expect(find.text('평소 이 곡을 부르는 상태를 기준으로 선택해 주세요.'), findsOneWidget);
    expect(find.text('음정·박자·호흡이 안정적이고 끝까지 여유 있게 소화해요.'), findsOneWidget);
    final selected = find.ancestor(
      of: find.text('A'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(of: selected, matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('미정'));
    await tester.tap(find.text('미정'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.value, isNull);

    result = const SelectionResult(SongTier.b);
    await launch(tester, (context) async {
      result = await TierPicker.song(context: context, selected: SongTier.a);
    });
    await tester.ensureVisible(find.text('취소'));
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('녹음 티어는 녹음 기준 안내와 녹음 타입을 사용한다', (tester) async {
    SelectionResult<RecordingTier?>? result;
    await launch(tester, (context) async {
      result = await TierPicker.recording(context: context, selected: null);
    });
    expect(find.text('이 녹음을 기준으로 선택해 주세요.'), findsOneWidget);
    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    expect(result?.value, RecordingTier.b);
  });

  testWidgets('버전 선택은 일반 반주 MR LIVE만 제공하고 선택을 반환한다', (tester) async {
    SelectionResult<VersionCode>? result;
    await launch(tester, (context) async {
      result = await VersionPicker.show(
        context: context,
        selected: VersionCode.normal,
      );
    });
    for (final label in ['일반 반주', 'MR', 'LIVE']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('미정'), findsNothing);
    await tester.tap(find.text('LIVE'));
    await tester.pumpAndSettle();
    expect(result?.value, VersionCode.live);
  });

  testWidgets('바깥 터치와 시스템 뒤로가기는 선택 없이 취소한다', (tester) async {
    for (final back in [false, true]) {
      SelectionResult<VersionCode>? result = const SelectionResult(
        VersionCode.live,
      );
      await launch(tester, (context) async {
        result = await VersionPicker.show(
          context: context,
          selected: VersionCode.mr,
        );
      });
      if (back) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tapAt(const Offset(10, 10));
      }
      await tester.pumpAndSettle();
      expect(result, isNull);
    }
  });

  testWidgets('작은 화면 큰 글꼴에서도 최대 높이 안에서 스크롤하여 취소한다', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final scale in [1.0, 2.0, 3.0]) {
      await launch(
        tester,
        (context) {
          TierPicker.song(context: context, selected: null);
        },
        scale: scale,
        reduceMotion: true,
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(BottomSheet)).height,
        lessThanOrEqualTo(640 * 0.9),
      );
      final route = ModalRoute.of(tester.element(find.byType(ListTile).first))!;
      expect(route.transitionDuration, Duration.zero);
      await tester.ensureVisible(find.text('취소'));
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
