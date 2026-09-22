import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/preview_navigation.dart';

void main() {
  testWidgets('5개 탭 재선택은 상세와 선택기를 닫고 기존 루트를 보존한다', (tester) async {
    await tester.pumpWidget(const NavigationPreviewApp());
    await tester.pumpAndSettle();
    for (final tab in ['songs', 'charts', 'recording', 'playlists', 'search']) {
      final tabButton = find.byKey(ValueKey('tab-$tab'));
      await tester.tap(tabButton);
      await tester.pumpAndSettle();
      final list = find.byKey(PageStorageKey('preview-list-$tab'));
      await tester.drag(list, const Offset(0, -600));
      await tester.pumpAndSettle();
      final scrollFinder = find.descendant(
        of: list,
        matching: find.byType(Scrollable),
      );
      final scrollState = tester.state<ScrollableState>(scrollFinder);
      final savedOffset = scrollState.position.pixels;
      expect(savedOffset, greaterThan(0));
      await tester.tap(find.byType(ListTile).hitTestable().first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('플레이리스트 선택'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('샘플 A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('플레이리스트 선택'));
      await tester.pumpAndSettle();
      // Reselect while two routes deep; the unfinished picker is cancelled.
      await tester.tap(tabButton);
      await tester.pumpAndSettle();
      expect(list, findsOneWidget);
      expect(find.text('플레이리스트 선택 미리보기'), findsNothing);
      expect(find.byTooltip('뒤로가기'), findsNothing);
      expect(find.text('선택: 샘플 A'), findsOneWidget);
      expect(tester.state<ScrollableState>(scrollFinder), same(scrollState));
      expect(scrollState.position.pixels, closeTo(savedOffset, 0.01));
      // Already at root: keep the same list and selection.
      await tester.tap(tabButton);
      await tester.pumpAndSettle();
      expect(tester.state<ScrollableState>(scrollFinder), same(scrollState));
      expect(find.text('선택: 샘플 A'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
