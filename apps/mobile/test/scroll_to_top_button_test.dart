import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/widgets/scroll_to_top_button.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'shared top button appears after scroll and returns to zero reduced=$reduced',
      (tester) async {
        final scroll = ScrollController();
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: child!,
            ),
            home: Scaffold(
              body: Stack(
                children: [
                  ListView(
                    controller: scroll,
                    children: List.generate(
                      40,
                      (i) => SizedBox(height: 60, child: Text('row $i')),
                    ),
                  ),
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: ScrollToTopButton(controller: scroll),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byTooltip('맨 위로'), findsNothing);
        scroll.jumpTo(350);
        await tester.pumpAndSettle();
        expect(find.byTooltip('맨 위로'), findsOneWidget);
        await tester.tap(find.byTooltip('맨 위로'));
        await tester.pumpAndSettle();
        expect(scroll.offset, 0);
        expect(find.byTooltip('맨 위로'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        scroll.dispose();
      },
    );
  }
}
