import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/widgets/editable_collection.dart';
import 'package:song_record/core/widgets/folding_scaffold.dart';
import 'package:song_record/core/widgets/ui_controls.dart';

void main() {
  for (final library in [false, true]) {
    testWidgets(
      'scroll compacts actions and highlights count only when pinned library=$library',
      (tester) async {
        final ids = List.generate(30, (i) => '$i');
        var rowTaps = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EditableCollection(
                ids: ids,
                header: const SizedBox(height: 100),
                belowActions: library ? const Text('summary') : null,
                actions: (compact, reorder) => Row(
                  children: [
                    CollectionControlSurface(
                      active: compact && !library,
                      padding: const EdgeInsets.all(8),
                      child: const Text('30곡'),
                    ),
                    const Spacer(),
                    AppReorderAction(onPressed: reorder, compact: compact),
                    AppCompactAction(
                      label: '곡 추가',
                      onPressed: () {},
                      compact: compact,
                    ),
                    const Icon(Icons.more_vert),
                  ],
                ),
                row: (id) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => rowTaps++,
                  child: SizedBox(
                    height: 70,
                    width: double.infinity,
                    child: Text('track $id'),
                  ),
                ),
                onReorder: (_) async {},
                onDelete: (_) async => false,
                deleteLabel: (n) => '$n 삭제',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('곡 추가'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('collection-control-surface')),
          findsNothing,
        );
        final scroll = tester
            .widget<CustomScrollView>(find.byType(CustomScrollView))
            .controller!;
        scroll.jumpTo(350);
        await tester.pumpAndSettle();
        expect(find.text('곡 추가'), findsNothing);
        expect(find.text('순서 변경'), findsNothing);
        expect(find.text('30곡'), findsOneWidget);
        expect(find.byIcon(Icons.more_vert), findsOneWidget);
        expect(
          find.byKey(const ValueKey('collection-control-surface')),
          library ? findsNothing : findsOneWidget,
        );
        // Only the small control surface may intercept hits; the middle gap
        // must reach the song underneath the pinned bar.
        await tester.tapAt(const Offset(200, 26));
        await tester.pump();
        expect(rowTaps, 1);
        if (!library) {
          await tester.tap(find.text('30곡'));
          await tester.pump();
          expect(rowTaps, 1);
        }
        scroll.jumpTo(0);
        await tester.pumpAndSettle();
        expect(find.text('곡 추가'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('collection-control-surface')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'long title selection preserves rows; only top reorder folds header',
    (tester) async {
      tester.view.physicalSize = const Size(390, 840);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var folded = false;
      final ids = List.generate(30, (i) => '$i');
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, update) => FoldingScaffold(
              collapsed: folded,
              appBar: AppBar(title: const Text('목록 제목')),
              body: EditableCollection(
                ids: ids,
                header: const SizedBox(height: 20),
                belowActions: const Text('나만의 선곡'),
                onHeaderFold: (value) => update(() => folded = value),
                row: (id) => Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('곡 $id 아주 긴 제목을 가진 노래와 가수 이름'),
                ),
                actions: (_, reorder) =>
                    TextButton(onPressed: reorder, child: const Text('순서 변경')),
                onDelete: (_) async => false,
                deleteLabel: (n) => '$n 삭제',
                onReorder: (_) async {},
              ),
            ),
          ),
        ),
      );
      final second = find.byKey(const ValueKey('1'));
      final y = tester.getTopLeft(second).dy;
      await tester.longPress(find.text('곡 0 아주 긴 제목을 가진 노래와 가수 이름'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(second).dy, y);
      expect(folded, isFalse);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('전체 1'));
      await tester.pumpAndSettle();
      expect(find.text('전체 30'), findsOneWidget);
      expect(find.byType(ReorderableDragStartListener), findsNothing);
      expect(folded, isFalse);
      expect(tester.getTopLeft(second).dy, y);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(find.text('전체 0'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('순서 변경'));
      await tester.pumpAndSettle();
      expect(folded, isTrue);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(folded, isFalse);
      final scroll = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      scroll.jumpTo(400);
      await tester.pumpAndSettle();
      await tester.tap(find.text('순서 변경'));
      await tester.pumpAndSettle();
      expect(folded, isFalse);
      expect(scroll.pixels, 400);
      expect(tester.takeException(), isNull);
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'selection and actual handle drop retain scroll in $brightness',
      (tester) async {
        final ids = List.generate(60, (i) => '$i');
        List<String>? saved;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: brightness,
              colorSchemeSeed: Colors.purple,
            ),
            home: Scaffold(
              body: EditableCollection(
                ids: ids,
                header: const SizedBox(height: 80),
                row: (id) => SizedBox(height: 64, child: Text('곡 $id')),
                actions: (_, reorder) => Row(
                  children: [
                    TextButton(onPressed: reorder, child: const Text('순서 변경')),
                  ],
                ),
                onDelete: (_) async => false,
                deleteLabel: (n) => '$n 삭제',
                onReorder: (order) async => saved = order,
              ),
            ),
          ),
        );
        final scroll = tester
            .state<ScrollableState>(find.byType(Scrollable))
            .position;
        scroll.jumpTo(900);
        await tester.pumpAndSettle();
        final title = find.text('곡 12');
        final y = tester.getTopLeft(title).dy;
        await tester.longPress(title);
        await tester.pumpAndSettle();
        expect(find.text('전체 1'), findsOneWidget);
        expect(tester.getTopLeft(title).dy, y);
        expect(scroll.pixels, 900);
        await tester.tap(find.text('취소'));
        await tester.pumpAndSettle();
        expect(scroll.pixels, 900);
        await tester.tap(find.text('순서 변경'));
        await tester.pumpAndSettle();
        final handle = find.descendant(
          of: find.byKey(const ValueKey('13')),
          matching: find.byType(ReorderableDragStartListener),
        );
        final gesture = await tester.startGesture(tester.getCenter(handle));
        await gesture.moveBy(const Offset(0, 10));
        await tester.pump(const Duration(milliseconds: 100));
        await gesture.moveBy(const Offset(0, 140));
        await tester.pump(const Duration(milliseconds: 300));
        final accent = Theme.of(tester.element(find.byType(EditableCollection)))
            .colorScheme
            .primary;
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is DecoratedBox &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).border ==
                    Border.all(color: accent, width: 2),
          ),
          findsOneWidget,
        );
        await gesture.up();
        await tester.pumpAndSettle();
        expect(scroll.pixels, 900);
        await tester.tap(find.text('완료'));
        await tester.pumpAndSettle();
        expect(saved, isNotNull);
        expect(saved!.toSet(), ids.toSet());
        expect(saved, isNot(ids));
        expect(scroll.pixels, 900);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
