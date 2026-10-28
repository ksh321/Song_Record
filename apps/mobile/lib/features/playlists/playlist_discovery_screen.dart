import 'package:flutter/material.dart';
import 'package:song_record/core/widgets/app_page_bar.dart';

import '../auth/auth_session.dart';
import '../charts/popular_chart.dart';
import '../charts/popular_chart_screen.dart';
import '../search/karaoke_search.dart';
import '../search/karaoke_search_screen.dart';
import '../search/search_intent.dart';

/// Searching and chart browsing share a destination. Only an explicit TJ
/// selection returns a result; closing never queues a mutation.
class PlaylistDiscoveryScreen extends StatefulWidget {
  const PlaylistDiscoveryScreen({
    super.key,
    required this.intent,
    required this.searchLoad,
    this.chartLoad,
    this.auth,
    this.initiallyCharts = false,
  });
  final SearchIntent intent;
  final KaraokeLoader searchLoad;
  final ChartLoader? chartLoad;
  final AuthController? auth;
  final bool initiallyCharts;
  @override
  State<PlaylistDiscoveryScreen> createState() =>
      _PlaylistDiscoveryScreenState();
}

class _PlaylistDiscoveryScreenState extends State<PlaylistDiscoveryScreen> {
  int tab = 0;
  @override
  void initState() {
    super.initState();
    widget.intent.validate();
    tab = widget.initiallyCharts && widget.chartLoad != null ? 1 : 0;
  }

  void select(KaraokeSelection selection) {
    if (!identical(selection.intent, widget.intent)) return;
    Navigator.of(context).pop(selection);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: appPageBar(context, title: Text(tab == 1 ? '인기 차트' : '검색')),
    body: SafeArea(
      child: tab == 1
          ? PopularChartScreen(
              load: widget.chartLoad!,
              searchLoad: widget.searchLoad,
              auth: widget.auth,
              intent: widget.intent,
              onSelected: select,
            )
          : KaraokeSearchScreen(
              load: widget.searchLoad,
              auth: widget.auth,
              intent: widget.intent,
              onSelected: select,
            ),
    ),
  );
}
