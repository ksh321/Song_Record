import 'package:flutter/material.dart';

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
  });
  final SearchIntent intent;
  final KaraokeLoader searchLoad;
  final ChartLoader? chartLoad;
  final AuthController? auth;
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
  }

  void select(KaraokeSelection selection) {
    if (!identical(selection.intent, widget.intent)) return;
    Navigator.of(context).pop(selection);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('목록에 추가할 곡 찾기')),
    body: SafeArea(
      child: Column(
        children: [
          SegmentedButton<int>(
            segments: [
              const ButtonSegment(value: 0, label: Text('검색')),
              ButtonSegment(
                value: 1,
                label: const Text('인기 차트'),
                enabled: widget.chartLoad != null,
              ),
            ],
            selected: {tab},
            onSelectionChanged: (value) => setState(() => tab = value.single),
          ),
          Expanded(
            child: IndexedStack(
              index: tab,
              children: [
                KaraokeSearchScreen(
                  load: widget.searchLoad,
                  auth: widget.auth,
                  intent: widget.intent,
                  onSelected: select,
                ),
                if (widget.chartLoad != null)
                  PopularChartScreen(
                    load: widget.chartLoad!,
                    searchLoad: widget.searchLoad,
                    auth: widget.auth,
                    intent: widget.intent,
                    onSelected: select,
                  )
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
