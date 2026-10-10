import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/charts/popular_chart.dart';
import 'package:song_record/features/charts/popular_chart_screen.dart';
import 'package:song_record/features/search/karaoke_search.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode || appFlavor != 'searchVerification') {
    throw StateError('Isolated debug verification only');
  }
  runApp(MaterialApp(theme: AppTheme.dark(), home: const ChartCheck()));
}

class ChartCheck extends StatelessWidget {
  const ChartCheck({super.key});
  Future<PublishedChart> load(int mode, ChartScope scope) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (mode == 2) {
      throw const ChartFailure(
        '이 조건의 합성 자료 없음',
        code: 'CHART_SOURCE_UNAVAILABLE',
      );
    }
    if (mode == 3) throw const ChartFailure('합성 연결 오류 · 내 곡·녹음은 계속 사용 가능');
    return PublishedChart.fromJson(scope, {
      'brand': scope.brandCode,
      'period': scope.period.name.toUpperCase(),
      'provider': 'MANANA',
      'source_url': scope.sourceUrl,
      'fetched_at': '2026-10-01T00:00:00Z',
      'revision': 1,
      'stale': mode == 1,
      'items': [
        {
          'position': 1,
          'number': '00123',
          'title': '검사 원본 (LIVE)',
          'artist': '검사 가수',
          'source_token': scope.brand == KaraokeBrand.tj ? 's1.fixture' : null,
        },
      ],
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('P16-06 차트 화면 검증')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('개인 계정/서버 연결 없음 · 합성 응답으로 실제 화면 검사'),
        for (final mode in [0, 1, 2, 3])
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: FilledButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(
                      title: Text(['정상 화면', '이전 자료', '자료 없음', '연결 오류'][mode]),
                    ),
                    body: PopularChartScreen(load: (s) => load(mode, s)),
                  ),
                ),
              ),
              child: Text(
                ['1 정상 화면 · 브랜드/기간', '2 이전 정상 자료', '3 자료 없음', '4 연결 오류'][mode],
              ),
            ),
          ),
      ],
    ),
  );
}
