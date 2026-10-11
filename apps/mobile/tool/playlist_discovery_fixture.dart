import 'package:song_record/features/charts/popular_chart.dart';
import 'package:song_record/features/search/karaoke_search.dart';

const playlistTjCandidate = KaraokeCandidate(
  brand: KaraokeBrand.tj,
  number: '00555',
  title: '미등록 TJ 후보',
  artist: '후보 가수',
  provider: 'FIXTURE',
  sourceRef: 'fixture:tj:00555',
  sourceToken: 'isolated-tj-candidate',
  expiresAt: null,
);
Future<List<KaraokeCandidate>> playlistSearchFixture(
  KaraokeQuery query,
) async => [
  query.brand == KaraokeBrand.tj
      ? playlistTjCandidate
      : const KaraokeCandidate(
          brand: KaraokeBrand.ky,
          number: '01234',
          title: '미등록 TJ 후보',
          artist: '후보 가수',
          provider: 'FIXTURE',
          sourceRef: 'fixture:ky:01234',
          sourceToken: 'isolated-ky-candidate',
          expiresAt: null,
        ),
];
Future<PublishedChart> playlistChartFixture(ChartScope scope) async =>
    PublishedChart(
      scope: scope,
      fetchedAt: DateTime.utc(2026, 10, 11),
      revision: 1,
      stale: false,
      items: [
        ChartItem(
          position: 1,
          number: scope.brand == KaraokeBrand.tj ? '00555' : '01234',
          title: '미등록 TJ 후보',
          artist: '후보 가수',
          sourceToken: scope.brand == KaraokeBrand.tj
              ? 'isolated-tj-candidate'
              : null,
        ),
      ],
    );
