import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/app/app_tab.dart';
import 'package:song_record/core/domain/domain_ordering.dart';
import 'package:song_record/core/domain/identifiers.dart';
import 'package:song_record/core/domain/song_types.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/core/theme/app_tokens.dart';
import 'package:song_record/core/widgets/content_state.dart';
import 'package:song_record/core/widgets/music_view_data.dart';
import 'package:song_record/core/widgets/musical_key_picker.dart';
import 'package:song_record/core/widgets/recording_roles_card.dart';
import 'package:song_record/core/widgets/selection_sheet.dart';
import 'package:song_record/core/widgets/song_discovery_sheet.dart';
import 'package:song_record/core/widgets/song_row.dart';
import 'package:song_record/core/widgets/song_summary.dart';
import 'package:song_record/routing/tab_navigation.dart';

void viewport(WidgetTester tester, Size size, {double keyboard = 0}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 16);
  tester.view.padding = FakeViewPadding(top: 24, bottom: keyboard == 0 ? 16 : 0);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
}

Widget app(Widget home, {double scale = 2, AppAccent accent = AppAccent.blue, bool reduced = false}) => MaterialApp(
  theme: AppTheme.dark(accent: accent),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(scale), disableAnimations: reduced,
    ),
    child: child!,
  ),
  home: home,
);

void main() {
  for (final size in [const Size(320, 640), const Size(640, 360)]) {
    for (final kind in ['선택', '키', '새 곡 찾기']) {
      testWidgets('$kind $size: 작은 화면·큰 글꼴·키보드에서 취소 버튼에 접근한다', (tester) async {
        final keyboard = size.height > 400 ? 240.0 : 100.0;
        viewport(tester, size, keyboard: keyboard);
        await tester.pumpWidget(app(Scaffold(body: Builder(builder: (context) => TextButton(
          onPressed: () {
            switch (kind) {
              case '선택':
                showSelectionSheet<int>(context: context, title: '버전 선택', selected: 0,
                  options: const [SelectionOption(0, '일반 반주'), SelectionOption(1, '길이가 긴 선택 항목')]);
              case '키':
                MusicalKeyPicker.song(context: context, selected: null);
              case '새 곡 찾기':
                showSongDiscoverySheet(context: context, playlistId: 'list', playlistTitle: '길이가 긴 연습 목록 제목');
            }
          },
          child: const Text('열기'),
        )))));
        await tester.tap(find.text('열기'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('취소'));
        await tester.pumpAndSettle();
        final button = find.widgetWithText(TextButton, '취소');
        expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
        expect(tester.getBottomLeft(button).dy, lessThanOrEqualTo(size.height - keyboard));
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
      });
    }

  }

  testWidgets('큰 글꼴의 키 휠 행이 늘어나고 적용은 계속 가능하다', (tester) async {
    viewport(tester, const Size(320, 640));
    await tester.pumpWidget(app(Scaffold(body: Builder(builder: (context) => TextButton(
      onPressed: () => MusicalKeyPicker.recording(context: context), child: const Text('열기'),
    )))));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(tester.widget<ListWheelScrollView>(find.byType(ListWheelScrollView)).itemExtent, greaterThan(44));
    await tester.ensureVisible(find.byKey(const ValueKey('apply-key')));
    await tester.tap(find.byKey(const ValueKey('apply-key')));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final accent in AppAccent.values) {
    testWidgets('${accent.name}: 긴 제목과 큰 글꼴의 행·요약·보관 카드', (tester) async {
      viewport(tester, const Size(320, 640));
      final song = RegisteredSongViewData(
        id: SongId('00000000-0000-4000-8000-000000000001'),
        title: '작은 화면에서도 끝까지 읽을 수 있어야 하는 아주 긴 노래 제목',
        artist: '길이가 긴 가수 이름', version: VersionCode.normal,
        note: '길이가 긴 메모를 표시할 때도 글자가 겹치지 않아야 합니다.',
      );
      var edited = false;
      await tester.pumpWidget(app(Scaffold(body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          SongRow.registered(song: song, onTap: () {}),
          SongSummary(song: song, onEdit: () => edited = true),
          RecordingRolesCard(songId: song.id, selection: const RecordingSelection(), recordings: const {}),
          const ContentState(phase: ContentPhase.waiting, title: '처리를 기다리고 있어요.'),
        ]),
      ))), accent: accent));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('곡 수정'));
      await tester.tap(find.text('곡 수정'));
      expect(edited, isTrue);
      await tester.ensureVisible(find.text('자동 보관 기준'));
      await tester.tap(find.text('자동 보관 기준'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('긴 화면 제목과 큰 글꼴에서도 설정·뒤로가기가 44 이상이다', (tester) async {
    viewport(tester, const Size(320, 640));
    await tester.pumpWidget(app(TabNavigator(
      tab: AppTab.songs, active: true, openSettings: () {},
      rootBuilder: (context) => TextButton(
        onPressed: () => TabNavigation.of(context).openPage<void>(
          title: '아주 길어서 화면 너비보다 긴 노래 상세 제목',
          builder: (_) => const Text('상세 내용'),
        ), child: const Text('상세 열기'),
      ),
    )));
    await tester.tap(find.text('상세 열기'));
    await tester.pumpAndSettle();
    for (final label in ['설정', '뒤로가기']) {
      final size = tester.getSize(find.byTooltip(label));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('뒤로가기'));
    await tester.pumpAndSettle();
    expect(find.text('상세 열기'), findsOneWidget);
  });

  testWidgets('모션 감소 시 이동 중에도 새 화면이 최종 위치에 표시된다', (tester) async {
    await tester.pumpWidget(app(Scaffold(body: Builder(builder: (context) => TextButton(
      onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Align(alignment: Alignment.topLeft, child: Text('도착'))),
      )), child: const Text('이동'),
    ))), reduced: true));
    await tester.tap(find.text('이동'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    final start = tester.getTopLeft(find.text('도착'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('도착')), start);
    expect(tester.takeException(), isNull);
  });
}
