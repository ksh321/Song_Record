import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/preview_navigation.dart';

void main() {
  Future<void> selectTab(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(ValueKey('tab-$name')));
    await tester.pumpAndSettle();
  }

  Future<void> openItem(WidgetTester tester, String tab, int index) async {
    final item = find.byKey(ValueKey('preview-item-$tab-$index'));
    await tester.scrollUntilVisible(
      item,
      200,
      scrollable: find.descendant(
        of: find.byKey(PageStorageKey('preview-list-$tab')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(item);
    await tester.pumpAndSettle();
  }

  double offset(WidgetTester tester, String tab) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byKey(PageStorageKey('preview-list-$tab')),
          matching: find.byType(Scrollable),
        ),
      )
      .position
      .pixels;

  testWidgets('각 탭 상세 스택과 원래 목록 스크롤을 독립적으로 유지한다', (tester) async {
    await tester.pumpWidget(const NavigationPreviewApp());
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const PageStorageKey('preview-list-songs')),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();
    final songsOffset = offset(tester, 'songs');
    expect(songsOffset, greaterThan(0));
    final songsItem = find.byType(ListTile).hitTestable().first;
    final songsLabel =
        (tester.widget<ListTile>(songsItem).title! as Text).data!;
    await tester.tap(songsItem);
    await tester.pumpAndSettle();

    await selectTab(tester, 'playlists');
    await openItem(tester, 'playlists', 24);
    await selectTab(tester, 'songs');
    expect(find.text('$songsLabel 상세'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(offset(tester, 'songs'), closeTo(songsOffset, 0.01));

    await selectTab(tester, 'playlists');
    expect(find.text('플레이리스트 샘플 25 상세'), findsOneWidget);
    await tester.tap(find.byTooltip('뒤로가기'));
    await tester.pumpAndSettle();
    expect(offset(tester, 'playlists'), greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('선택 확정은 유지하고 취소는 실제 상세와 목록으로 돌아온다', (tester) async {
    await tester.pumpWidget(const NavigationPreviewApp());
    await tester.pumpAndSettle();
    await selectTab(tester, 'playlists');
    await openItem(tester, 'playlists', 0);
    await tester.tap(find.text('플레이리스트 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('샘플 A'));
    await tester.pumpAndSettle();
    expect(find.text('선택: 샘플 A'), findsOneWidget);

    await tester.tap(find.text('플레이리스트 선택'));
    await tester.pumpAndSettle();
    // Settings sits above the entire shell; closing it must not pop the picker.
    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('플레이리스트 선택 미리보기'), findsOneWidget);
    await selectTab(tester, 'search');
    expect(find.text('선택: 없음'), findsOneWidget);
    await selectTab(tester, 'playlists');
    expect(find.text('플레이리스트 선택 미리보기'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('플레이리스트 샘플 1 상세'), findsOneWidget);
    expect(find.text('선택: 샘플 A'), findsOneWidget);

    await tester.tap(find.text('플레이리스트 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.text('선택: 샘플 A'), findsOneWidget);
    await tester.tap(find.byTooltip('뒤로가기'));
    await tester.pumpAndSettle();
    expect(find.text('선택: 샘플 A'), findsOneWidget);
    expect(
      find.byKey(const PageStorageKey('preview-list-playlists')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('활성 탭 루트의 뒤로가기는 숨은 탭 상세를 닫지 않는다', (tester) async {
    await tester.pumpWidget(const NavigationPreviewApp());
    await tester.pumpAndSettle();
    await openItem(tester, 'songs', 0);
    await selectTab(tester, 'search');
    // maybePop returns false at the shell root; the platform owns app exit.
    final root = Navigator.of(
      tester.element(find.byType(NavigationBar)),
      rootNavigator: true,
    );
    expect(await root.maybePop(), isFalse);
    await selectTab(tester, 'songs');
    expect(find.text('내 곡 샘플 1 상세'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
