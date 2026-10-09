import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/search/karaoke_search.dart';
import 'package:song_record/features/search/karaoke_search_screen.dart';
import 'package:song_record/features/search/search_intent.dart';

import 'karaoke_search_test.dart' show row;

void main() {
  testWidgets(
    'KY to TJ retains original title, playlist and return context, mutates only after explicit TJ selection',
    (tester) async {
      final queries = <KaraokeQuery>[];
      final selections = <KaraokeSelection>[];
      const intent = SearchIntent(
        purpose: SearchPurpose.playlist,
        playlistId: 'fixture-list',
        returnRoute: '/playlist/fixture-list',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KaraokeSearchScreen(
              intent: intent,
              initialQuery: const KaraokeQuery(
                KaraokeBrand.ky,
                KaraokeKind.artist,
                '가수',
              ),
              load: (q) async {
                queries.add(q);
                return [
                  row(q.brand, q.brand == KaraokeBrand.ky ? '88176' : '00123'),
                ];
              },
              onSelected: selections.add,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.tap(find.text('원본 (LIVE)'));
      await tester.pumpAndSettle();
      expect(find.text('목록에 사용할 TJ 곡 선택'), findsNothing);
      expect(selections, isEmpty);
      await tester.tap(find.text('TJ에서 이 곡 찾기'));
      await tester.pumpAndSettle();
      expect(queries.last.brand, KaraokeBrand.tj);
      expect(queries.last.kind, KaraokeKind.title);
      expect(queries.last.text, '원본 (LIVE)');
      expect(selections, isEmpty);
      await tester.tap(find.text('원본 (LIVE)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('목록에 사용할 TJ 곡 선택'));
      await tester.pumpAndSettle();
      expect(selections, hasLength(1));
      expect(selections.single.candidate.number, '00123');
      expect(selections.single.intent, same(intent));
      expect(find.text('TJ에서 찾기'), findsNothing);
    },
  );
  testWidgets(
    'cancelling TJ lookup returns to KY without creating song or playlist item',
    (tester) async {
      final selections = <KaraokeSelection>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KaraokeSearchScreen(
              initialQuery: const KaraokeQuery(
                KaraokeBrand.ky,
                KaraokeKind.title,
                '금영 곡',
              ),
              load: (q) async => [row(q.brand, '00123')],
              onSelected: selections.add,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.tap(find.text('원본 (LIVE)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TJ에서 이 곡 찾기'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(selections, isEmpty);
      expect(find.text('금영 곡'), findsOneWidget);
      expect(find.text('금영'), findsOneWidget);
      expect(find.text('TJ에서 찾기'), findsNothing);
    },
  );
  test('KY cannot be used as registration selection and playlist context is mandatory', () {
    expect(
      () => KaraokeSelection(row(KaraokeBrand.ky, '1'), const SearchIntent()),
      throwsArgumentError,
    );
    expect(
      () => KaraokeSelection(
        row(KaraokeBrand.tj, '1'),
        const SearchIntent(purpose: SearchPurpose.playlist),
      ),
      throwsArgumentError,
    );
  });
}
