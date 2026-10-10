import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/charts/popular_chart.dart';
import 'package:song_record/features/charts/popular_chart_screen.dart';
import 'package:song_record/features/search/karaoke_search.dart';

Map<String, Object?> wire(ChartScope scope, {bool stale = false}) => {
  'brand': scope.brandCode,
  'period': scope.period.name.toUpperCase(),
  'provider': 'MANANA',
  'source_url': scope.sourceUrl,
  'fetched_at': '2026-10-01T00:00:00Z',
  'revision': 1,
  'stale': stale,
  'items': [
    {
      'position': 1,
      'number': '00123',
      'title': '원본 (LIVE)',
      'artist': '가수',
      'source_token': scope.brand == KaraokeBrand.tj ? 's1.fixture' : null,
    },
  ],
};
PublishedChart fixture(ChartScope scope, {bool stale = false}) =>
    PublishedChart.fromJson(scope, wire(scope, stale: stale));
void main() {
  test('six scopes preserve originals and reject scope, duplicate, empty and KY token corruption', () {
    for (final b in KaraokeBrand.values) {
      for (final p in ChartPeriod.values) {
        final s = ChartScope(b, p);
        final c = fixture(s);
        expect(c.items.single.number, '00123');
        expect(c.items.single.title, '원본 (LIVE)');
        expect(c.scope, s);
      }
    }
    final s = const ChartScope(KaraokeBrand.tj, ChartPeriod.monthly);
    final bad = wire(s)..['brand'] = 'KY';
    expect(() => PublishedChart.fromJson(s, bad), throwsFormatException);
    final duplicate = wire(s);
    duplicate['items'] = [
      ...(duplicate['items'] as List),
      {
        'position': 2,
        'number': '00123',
        'title': '원본',
        'artist': '가수',
        'source_token': 's1.fixture',
      },
    ];
    expect(() => PublishedChart.fromJson(s, duplicate), throwsFormatException);
    expect(
      () => PublishedChart.fromJson(s, wire(s)..['items'] = []),
      throwsFormatException,
    );
    final ky = const ChartScope(KaraokeBrand.ky, ChartPeriod.daily);
    final badKy = wire(ky);
    (badKy['items'] as List).first['source_token'] = 's1.invalid';
    expect(() => PublishedChart.fromJson(ky, badKy), throwsFormatException);
  });
  test('brand changes preserve period and late old reply cannot mix the visible scope', () async {
    final pending = <Completer<PublishedChart>>[];
    final requested = <ChartScope>[];
    final controller = PopularChartController((s) {
      requested.add(s);
      final c = Completer<PublishedChart>();
      pending.add(c);
      return c.future;
    });
    final first = controller.change(period: ChartPeriod.weekly);
    final next = controller.change(brand: KaraokeBrand.ky);
    expect(requested.last.period, ChartPeriod.weekly);
    pending.last.complete(fixture(requested.last));
    await next;
    pending.first.complete(fixture(requested.first));
    await first;
    expect(controller.chart!.scope.brand, KaraokeBrand.ky);
    expect(controller.scope.period, ChartPeriod.weekly);
    controller.dispose();
  });
  test('no source and failure stay distinct and account clear invalidates pending rows', () async {
    var code = 'CHART_SOURCE_UNAVAILABLE';
    final c = PopularChartController(
      (_) async => throw ChartFailure('시험', code: code),
    );
    await c.change();
    expect(c.phase, ChartPhase.unavailable);
    code = 'CHART_UNAVAILABLE';
    await c.change();
    expect(c.phase, ChartPhase.error);
    c.dispose();
    final pending = Completer<PublishedChart>();
    final a = PopularChartController((_) => pending.future);
    final load = a.change();
    a.clearForAccount();
    pending.complete(fixture(a.scope));
    await load;
    expect(a.chart, isNull);
    expect(a.phase, ChartPhase.waiting);
    a.dispose();
  });
  testWidgets(
    'default monthly, scope controls, source collection notice and stale remain explicit',
    (tester) async {
      final scopes = <ChartScope>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: PopularChartScreen(
              load: (s) async {
                scopes.add(s);
                return fixture(s, stale: true);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(scopes.single.period, ChartPeriod.monthly);
      expect(find.text('원본 (LIVE)'), findsOneWidget);
      expect(find.text('제공자 기준 기간 · 정확 집계 날짜 미제공'), findsOneWidget);
      expect(find.text('출처: MANANA'), findsOneWidget);
      expect(find.textContaining('서버 수집:'), findsOneWidget);
      expect(find.textContaining('이전 정상 자료'), findsOneWidget);
      await tester.tap(find.text('주간'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('금영'));
      await tester.pumpAndSettle();
      expect(scopes.last.brand, KaraokeBrand.ky);
      expect(scopes.last.period, ChartPeriod.weekly);
      expect(find.textContaining('집계 월'), findsNothing);
    },
  );
  testWidgets(
    'no-data differs from connection error and retry preserves scope',
    (tester) async {
      var code = 'CHART_SOURCE_UNAVAILABLE';
      final scopes = <ChartScope>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: PopularChartScreen(
              load: (s) async {
                scopes.add(s);
                throw ChartFailure('시험', code: code);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('선택한 브랜드·기간의 자료가 없어요'), findsOneWidget);
      code = 'CHART_UNAVAILABLE';
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();
      expect(find.text('차트를 불러오지 못했어요'), findsOneWidget);
      expect(scopes.first, scopes.last);
    },
  );
  testWidgets('small display large text preserves controls without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(body: PopularChartScreen(load: (s) async => fixture(s))),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('월간'), findsOneWidget);
  });
}
