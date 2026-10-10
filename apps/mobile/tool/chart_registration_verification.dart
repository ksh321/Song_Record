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
    throw StateError('Isolated verification only');
  }
  runApp(MaterialApp(theme: AppTheme.dark(), home: const Check()));
}

class Check extends StatefulWidget {
  const Check({super.key});
  @override
  State<Check> createState() => _CheckState();
}

class _CheckState extends State<Check> {
  int saves = 0;
  String last = '없음';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('P16-07 차트 등록 검증')),
    body: Column(
      children: [
        Text('합성 응답 · 개인 계정/서버/DB 저장 없음\n검사 저장 횟수: $saves · 마지막 TJ 번호: $last'),
        Expanded(
          child: PopularChartScreen(
            load: (s) async {
              await Future<void>.delayed(
                Duration(
                  milliseconds: s.period == ChartPeriod.daily ? 1600 : 300,
                ),
              );
              return PublishedChart(
                scope: s,
                fetchedAt: DateTime.utc(2026, 10, 1),
                revision: 1,
                stale: false,
                items: [
                  ChartItem(
                    position: 1,
                    number: '00123',
                    title: '검사 원본 (LIVE)',
                    artist: '검사 가수',
                    sourceToken: s.brand == KaraokeBrand.tj
                        ? 's1.fixture'
                        : null,
                  ),
                ],
              );
            },
            searchLoad: (q) async => [
              const KaraokeCandidate(
                brand: KaraokeBrand.tj,
                number: '00999',
                title: '사용자가 고를 TJ 결과',
                artist: 'TJ 검사 가수',
                provider: 'MANANA',
                sourceRef: 'manana:tj:00999',
                sourceToken: 's1.search',
                expiresAt: null,
              ),
            ],
            prepareRegistration: (d) => () async {
              setState(() {
                saves++;
                last = d.candidate!.number;
              });
            },
          ),
        ),
      ],
    ),
  );
}
