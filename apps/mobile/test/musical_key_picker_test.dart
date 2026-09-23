import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/domain/song_types.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/core/theme/app_tokens.dart';
import 'package:song_record/core/widgets/musical_key_picker.dart';
import 'package:song_record/core/widgets/selection_sheet.dart';

import '../tool/preview_musical_key_picker.dart';

Future<void> launch(
  WidgetTester tester,
  void Function(BuildContext) open, {
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
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

FixedExtentScrollController wheel(WidgetTester tester) =>
    tester
            .widget<ListWheelScrollView>(
              find.byKey(const ValueKey('semitone-wheel')),
            )
            .controller!
        as FixedExtentScrollController;

void main() {
  test('원키도 ±12 반음을 기록하고 범위 밖은 거절한다', () {
    expect(MusicalKey.original, MusicalKey(mode: KeyMode.original, shift: 0));
    expect(formatMusicalKey(MusicalKey.original), '원키');
    expect(
      formatMusicalKey(MusicalKey(mode: KeyMode.original, shift: 1)),
      '원키 +1',
    );
    expect(
      formatMusicalKey(MusicalKey(mode: KeyMode.original, shift: -12)),
      '원키 -12',
    );
    expect(formatMusicalKey(MusicalKey(mode: KeyMode.male, shift: 0)), '남 0');
    expect(
      formatMusicalKey(MusicalKey(mode: KeyMode.female, shift: 12)),
      '여 +12',
    );
    expect(
      () => MusicalKey(mode: KeyMode.original, shift: -13),
      throwsRangeError,
    );
    expect(() => MusicalKey(mode: KeyMode.female, shift: 13), throwsRangeError);
  });

  testWidgets('모드를 바꿔도 +12가 유지되고 적용 결과에 값이 담긴다', (tester) async {
    SelectionResult<MusicalKey?>? result;
    await launch(tester, (context) async {
      result = await MusicalKeyPicker.song(context: context, selected: null);
    });
    expect(
      tester.getSize(find.byKey(const ValueKey('semitone-wheel'))).height,
      AppDimensions.keyWheelHeight,
    );
    expect(
      tester
          .widget<ListWheelScrollView>(find.byType(ListWheelScrollView))
          .itemExtent,
      AppDimensions.keyWheelItemHeight,
    );
    expect(find.text('선택할 키: 원키'), findsOneWidget);
    wheel(tester).jumpToItem(24);
    await tester.pumpAndSettle();
    expect(find.text('선택할 키: 원키 +12'), findsOneWidget);
    await tester.tap(find.text('여'));
    await tester.pumpAndSettle();
    expect(find.text('선택할 키: 여 +12'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('apply-key')));
    await tester.tap(find.byKey(const ValueKey('apply-key')));
    await tester.pumpAndSettle();
    expect(result?.value, MusicalKey(mode: KeyMode.female, shift: 12));
  });

  testWidgets('처음과 끝에서 멈추고 원키 -12도 선택한다', (tester) async {
    SelectionResult<MusicalKey?>? result;
    await launch(tester, (context) async {
      result = await MusicalKeyPicker.song(
        context: context,
        selected: MusicalKey.original,
      );
    });
    await tester.drag(
      find.byKey(const ValueKey('semitone-wheel')),
      const Offset(0, -5000),
    );
    await tester.pumpAndSettle();
    expect(wheel(tester).selectedItem, 24);
    await tester.drag(
      find.byKey(const ValueKey('semitone-wheel')),
      const Offset(0, 5000),
    );
    await tester.pumpAndSettle();
    expect(wheel(tester).selectedItem, 0);
    expect(find.text('선택할 키: 원키 -12'), findsOneWidget);
    await tester.ensureVisible(find.text('적용'));
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();
    expect(result?.value, MusicalKey(mode: KeyMode.original, shift: -12));
  });

  testWidgets('미정 선택은 취소와 다른 결과이며 취소는 원래 값을 유지한다', (tester) async {
    final before = MusicalKey(mode: KeyMode.male, shift: -1);
    SelectionResult<MusicalKey?>? result;
    await launch(tester, (context) async {
      result = await MusicalKeyPicker.song(context: context, selected: before);
    });
    await tester.tap(find.text('여'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('취소'));
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(before, MusicalKey(mode: KeyMode.male, shift: -1));

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.text('선택할 키: 남 -1'), findsOneWidget);
    await tester.ensureVisible(find.text('미정으로 두기'));
    await tester.tap(find.text('미정으로 두기'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.value, isNull);
  });

  testWidgets('녹음에는 미정이 없고 시작값 원키 0과 선택한 값을 반환한다', (tester) async {
    SelectionResult<MusicalKey>? result;
    await launch(tester, (context) async {
      result = await MusicalKeyPicker.recording(context: context);
    });
    expect(find.text('선택할 키: 원키'), findsOneWidget);
    expect(find.text('미정으로 두기'), findsNothing);
    wheel(tester).jumpToItem(13);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('적용'));
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();
    expect(result?.value, MusicalKey(mode: KeyMode.original, shift: 1));
  });

  testWidgets('작은 화면 큰 글꼴에서도 시트 안을 스크롤해 적용할 수 있다', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await launch(tester, (context) {
      MusicalKeyPicker.song(context: context, selected: null);
    }, scale: 2);
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(BottomSheet)).height,
      lessThanOrEqualTo(576),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('apply-key')));
    await tester.tap(find.byKey(const ValueKey('apply-key')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('샘플에서 대표 키 변경은 지난 녹음에 전파되지 않고 새 녹음만 복사한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const MusicalKeyPreview()),
    );
    await tester.tap(find.byKey(const ValueKey('morning-song-key')));
    await tester.pumpAndSettle();
    wheel(tester).jumpToItem(13);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('적용'));
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('morning-song-key')),
        matching: find.text('대표 키 · 원키 +1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('morning-recording-key')),
        matching: find.text('녹음 키 · 원키'),
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('copy-song-default')),
      200,
    );
    await tester.tap(find.byKey(const ValueKey('copy-song-default')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('new-recording-key')),
      200,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('new-recording-key')),
        matching: find.text('녹음 키 · 원키 +1'),
      ),
      findsOneWidget,
    );
  });
}
