import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/search/karaoke_search.dart';
import 'package:song_record/features/search/karaoke_search_screen.dart';

KaraokeCandidate row(KaraokeBrand brand, String number) => KaraokeCandidate(
  brand: brand,
  number: number,
  title: '원본 (LIVE)',
  artist: '가수',
  provider: 'MANANA',
  sourceRef: 'manana:${brand == KaraokeBrand.tj ? 'tj' : 'kumyoung'}:$number',
  sourceToken: 's1.fixture',
  expiresAt: DateTime.utc(2026, 1, 2),
);
void main() {
  testWidgets(
    '400ms debounce invalidates old response before next request and preserves number zeros',
    (tester) async {
      final queries = <KaraokeQuery>[];
      final responses = <Completer<List<KaraokeCandidate>>>[];
      final c = KaraokeSearchController((q) {
        queries.add(q);
        final r = Completer<List<KaraokeCandidate>>();
        responses.add(r);
        return r.future;
      });
      addTearDown(c.dispose);
      c.change(kind: KaraokeKind.number, text: ' 00123 ');
      await tester.pump(const Duration(milliseconds: 399));
      expect(queries, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(queries.single.text, '00123');
      expect(c.phase, SearchPhase.loading);
      c.change(brand: KaraokeBrand.ky, kind: KaraokeKind.artist, text: '새 가수');
      responses[0].complete([row(KaraokeBrand.tj, '00123')]);
      await tester.pump();
      expect(c.phase, SearchPhase.waiting);
      expect(c.results, isEmpty);
      await tester.pump(const Duration(milliseconds: 400));
      expect(queries.last.brand, KaraokeBrand.ky);
      expect(queries.last.kind, KaraokeKind.artist);
      responses[1].complete([row(KaraokeBrand.ky, '012')]);
      await tester.pump();
      expect(c.results.single.number, '012');
    },
  );
  testWidgets(
    'latest request wins over later failure, account clear and disposal invalidate pending work',
    (tester) async {
      final responses = <Completer<List<KaraokeCandidate>>>[];
      final c = KaraokeSearchController((q) {
        final r = Completer<List<KaraokeCandidate>>();
        responses.add(r);
        return r.future;
      });
      c.change(text: '곡');
      await tester.pump(const Duration(milliseconds: 400));
      c.retry();
      responses[1].complete([row(KaraokeBrand.tj, '1')]);
      await tester.pump();
      responses[0].completeError(const KaraokeFailure('old failure'));
      await tester.pump();
      expect(c.phase, SearchPhase.results);
      expect(c.results.single.number, '1');
      c.retry();
      c.clearForAccount();
      responses[2].complete([row(KaraokeBrand.tj, '2')]);
      await tester.pump();
      expect(c.phase, SearchPhase.idle);
      expect(c.results, isEmpty);
      c.change(text: '곡');
      await tester.pump(const Duration(milliseconds: 400));
      c.dispose();
      responses[3].complete([]);
      await tester.pump();
    },
  );
  testWidgets(
    'empty and provider error are distinct and retry preserves exact conditions',
    (tester) async {
      var fail = false;
      final seen = <KaraokeQuery>[];
      final c = KaraokeSearchController((q) async {
        seen.add(q);
        if (fail) throw const KaraokeFailure('제공자 장애');
        return [];
      });
      addTearDown(c.dispose);
      c.change(brand: KaraokeBrand.ky, kind: KaraokeKind.number, text: '00001');
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.phase, SearchPhase.empty);
      fail = true;
      c.retry();
      await tester.pump();
      expect(c.phase, SearchPhase.error);
      expect(c.message, '제공자 장애');
      expect(c.query.text, '00001');
      expect(seen.last.brand, KaraokeBrand.ky);
      expect(seen.last.kind, KaraokeKind.number);
    },
  );
  testWidgets(
    'screen displays actual loading, empty, error and retains input across failure',
    (tester) async {
      final responses = <Completer<List<KaraokeCandidate>>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KaraokeSearchScreen(
              load: (q) {
                final r = Completer<List<KaraokeCandidate>>();
                responses.add(r);
                return r.future;
              },
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '곡');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('검색 중이에요.'), findsOneWidget);
      responses[0].complete([]);
      await tester.pump();
      expect(find.text('검색 결과가 없어요.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '다른 곡');
      await tester.pump(const Duration(milliseconds: 400));
      responses[1].completeError(const KaraokeFailure('외부 장애'));
      await tester.pump();
      expect(find.text('검색을 완료하지 못했어요.'), findsOneWidget);
      expect(find.text('다른 곡'), findsOneWidget);
      expect(find.text('외부 장애'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
