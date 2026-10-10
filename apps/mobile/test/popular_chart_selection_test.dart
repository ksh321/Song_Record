import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/charts/popular_chart.dart';
import 'package:song_record/features/charts/popular_chart_screen.dart';
import 'package:song_record/features/search/karaoke_search.dart';
import 'package:song_record/features/search/karaoke_search_screen.dart';
import 'package:song_record/features/search/search_intent.dart';
import 'package:song_record/features/search/song_registration.dart';

PublishedChart chart(ChartScope s) => PublishedChart(
  scope: s,
  fetchedAt: DateTime.utc(2026, 1, 1),
  revision: 1,
  stale: false,
  items: [
    ChartItem(
      position: 1,
      number: '00123',
      title: '원본 (LIVE)',
      artist: '원본 가수',
      sourceToken: s.brand == KaraokeBrand.tj ? 's1.original' : null,
    ),
  ],
);
const tj = KaraokeCandidate(
  brand: KaraokeBrand.tj,
  number: '00999',
  title: '실제 TJ 결과',
  artist: 'TJ 가수',
  provider: 'MANANA',
  sourceRef: 'manana:tj:00999',
  sourceToken: 's1.search',
  expiresAt: null,
);
Future<void> open(WidgetTester t) async {
  await t.ensureVisible(find.text('원본 (LIVE)'));
  await t.tap(find.text('원본 (LIVE)'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'TJ exact proof and playlist destination survive selection; cancel adds nothing',
    (t) async {
      const intent = SearchIntent(
        purpose: SearchPurpose.playlist,
        playlistId: 'list-1',
        returnRoute: '/origin',
      );
      final selected = <KaraokeSelection>[];
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PopularChartScreen(
              load: (s) async => chart(s),
              intent: intent,
              onSelected: selected.add,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await open(t);
      await t.tap(find.text('취소'));
      await t.pumpAndSettle();
      expect(selected, isEmpty);
      await open(t);
      await t.tap(find.text('목록에 사용할 TJ 곡 선택'));
      await t.pumpAndSettle();
      expect(selected.single.intent, same(intent));
      expect(selected.single.candidate.number, '00123');
      expect(selected.single.candidate.sourceToken, 's1.original');
      expect(selected.single.candidate.expiresAt, isNull);
      expect(find.text('월간'), findsOneWidget);
    },
  );
  testWidgets(
    'KY requires real TJ choice, keeps title/context and back cancels',
    (t) async {
      const intent = SearchIntent(
        purpose: SearchPurpose.playlist,
        playlistId: 'list-2',
        returnRoute: '/charts',
      );
      final queries = <KaraokeQuery>[];
      final selected = <KaraokeSelection>[];
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PopularChartScreen(
              load: (s) async => chart(s),
              intent: intent,
              onSelected: selected.add,
              searchLoad: (q) async {
                queries.add(q);
                return [tj];
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('금영'));
      await t.pumpAndSettle();
      await open(t);
      expect(find.text('목록에 사용할 TJ 곡 선택'), findsNothing);
      await t.tap(find.text('TJ에서 이 곡 찾기'));
      await t.pumpAndSettle();
      expect(queries.single.text, '원본 (LIVE)');
      expect(queries.single.brand, KaraokeBrand.tj);
      expect(selected, isEmpty);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(selected, isEmpty);
      expect(find.text('금영'), findsOneWidget);
      expect(find.text('월간'), findsOneWidget);
      await open(t);
      await t.tap(find.text('TJ에서 이 곡 찾기'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('실제 TJ 결과'));
      await t.tap(find.text('실제 TJ 결과'));
      await t.pumpAndSettle();
      await t.tap(find.text('목록에 사용할 TJ 곡 선택'));
      await t.pumpAndSettle();
      expect(selected.single.intent, same(intent));
      expect(selected.single.candidate.number, '00999');
      expect(selected.single.candidate.sourceToken, 's1.search');
    },
  );
  testWidgets('old sheet cannot commit after selected period changes', (
    t,
  ) async {
    final selected = <KaraokeSelection>[];
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PopularChartScreen(
            load: (s) async => chart(s),
            onSelected: selected.add,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await open(t);
    final chip = t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '일간'));
    chip.onSelected!(true);
    await t.pump();
    await t.tap(find.text('이 TJ 곡 선택'));
    await t.pumpAndSettle();
    expect(selected, isEmpty);
  });
  testWidgets(
    'registration uses exact TJ proof; cancellation never prepares or saves',
    (t) async {
      final drafts = <SongRegistrationDraft>[];
      var saves = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PopularChartScreen(
              load: (s) async => chart(s),
              prepareRegistration: (d) {
                drafts.add(d);
                return () async {
                  saves++;
                };
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await open(t);
      await t.tap(find.text('이 TJ 곡 선택'));
      await t.pumpAndSettle();
      expect(find.textContaining('TJ 00123'), findsOneWidget);
      await t.ensureVisible(find.text('취소'));
      await t.tap(find.text('취소'));
      await t.pumpAndSettle();
      expect(saves, 0);
      expect(drafts, isEmpty);
      await open(t);
      await t.tap(find.text('이 TJ 곡 선택'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('이 기기에 저장'));
      await t.tap(find.text('이 기기에 저장'));
      await t.pumpAndSettle();
      expect(saves, 1);
      expect(drafts.single.candidate!.sourceToken, 's1.original');
    },
  );
  testWidgets(
    'prepared save refuses stale chart even after first save failure',
    (t) async {
      var saves = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PopularChartScreen(
              load: (s) async => chart(s),
              prepareRegistration: (_) => () async {
                saves++;
                throw StateError('fixture failure');
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await open(t);
      await t.tap(find.text('이 TJ 곡 선택'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('이 기기에 저장'));
      await t.tap(find.text('이 기기에 저장'));
      await t.pumpAndSettle();
      expect(saves, 1);
      final chip = t.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, '주간', skipOffstage: false),
      );
      chip.onSelected!(true);
      await t.pump();
      await t.tap(find.text('이 기기에 저장'));
      await t.pumpAndSettle();
      expect(saves, 1);
    },
  );
  testWidgets(
    'short TJ/KY sheets keep cancel above three-button navigation, including TJ search',
    (t) async {
      t.view.physicalSize = const Size(400, 800);
      t.view.devicePixelRatio = 1;
      t.view.padding = const FakeViewPadding(bottom: 64);
      t.view.viewPadding = const FakeViewPadding(bottom: 64);
      addTearDown(t.view.reset);
      for (final search in [false, true]) {
        for (final brand in KaraokeBrand.values) {
          final candidate = KaraokeCandidate(
            brand: brand,
            number: '00123',
            title: '원본 (LIVE)',
            artist: '원본 가수',
            provider: 'MANANA',
            sourceRef: 'fixture',
            sourceToken: 's1.fixture',
            expiresAt: null,
          );
          await t.pumpWidget(
            MaterialApp(
              key: ValueKey('$search/$brand'),
              home: Scaffold(
                body: search
                    ? KaraokeSearchScreen(
                        load: (_) async => [candidate],
                        initialQuery: KaraokeQuery(
                          brand,
                          KaraokeKind.title,
                          '검색',
                        ),
                        onSelected: (_) {},
                      )
                    : PopularChartScreen(
                        load: (s) async => chart(s),
                        searchLoad: (_) async => [tj],
                        onSelected: (_) {},
                      ),
              ),
            ),
          );
          if (search) {
            await t.pump(const Duration(milliseconds: 500));
          }
          await t.pumpAndSettle();
          if (!search && brand == KaraokeBrand.ky) {
            await t.tap(find.text('금영'));
            await t.pumpAndSettle();
          }
          await open(t);
          final cancel = find.widgetWithText(TextButton, '취소');
          expect(cancel, findsOneWidget, reason: 'search=$search brand=$brand');
          expect(
            cancel.hitTestable(),
            findsOneWidget,
            reason: 'search=$search brand=$brand cancel=${t.getRect(cancel)}',
          );
          expect(t.getRect(cancel).bottom, lessThanOrEqualTo(800 - 64));
          await t.tap(cancel);
          await t.pumpAndSettle();
          expect(cancel, findsNothing);
          expect(t.takeException(), isNull);
        }
      }
    },
  );
}
