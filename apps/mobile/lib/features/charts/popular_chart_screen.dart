import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/widgets/content_state.dart';
import '../../core/widgets/music_view_data.dart';
import '../../core/widgets/song_row.dart';
import '../auth/auth_session.dart';
import '../search/karaoke_search.dart';
import 'popular_chart.dart';

class PopularChartScreen extends StatefulWidget {
  const PopularChartScreen({
    required this.load,
    this.auth,
    this.onSelected,
    super.key,
  });
  final ChartLoader load;
  final AuthController? auth;
  final void Function(PublishedChart chart, ChartItem item)? onSelected;
  @override
  State<PopularChartScreen> createState() => _PopularChartScreenState();
}

class _PopularChartScreenState extends State<PopularChartScreen> {
  late final PopularChartController controller;
  String? _account;
  String? tag() => widget.auth?.session == null
      ? null
      : '${widget.auth!.session!.userId}:${widget.auth!.session!.deviceId}';
  @override
  void initState() {
    super.initState();
    controller = PopularChartController((s) => widget.load(s));
    _account = tag();
    widget.auth?.addListener(_authChanged);
    controller.change();
  }

  void _authChanged() {
    if (widget.auth?.phase != AuthPhase.ready || tag() != _account) {
      _account = tag();
      controller.clearForAccount();
      if (widget.auth?.phase == AuthPhase.ready) controller.change();
    }
  }

  @override
  void didUpdateWidget(covariant PopularChartScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.auth != widget.auth) {
      oldWidget.auth?.removeListener(_authChanged);
      widget.auth?.addListener(_authChanged);
      _authChanged();
    }
  }

  @override
  void dispose() {
    widget.auth?.removeListener(_authChanged);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final chart = controller.chart;
      return ListView(
        key: const PageStorageKey('popular-chart'),
        primary: false,
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final brand in KaraokeBrand.values)
                ChoiceChip(
                  label: Text(brand == KaraokeBrand.tj ? 'TJ' : '금영'),
                  selected: controller.scope.brand == brand,
                  onSelected: (_) => controller.change(brand: brand),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final period in ChartPeriod.values)
                ChoiceChip(
                  label: Text(period.label),
                  selected: controller.scope.period == period,
                  onSelected: (_) => controller.change(period: period),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '제공자 기준 기간 · 정확 집계 날짜 미제공',
            style: AppTypography.supporting,
          ),
          if (chart != null) ...[
            const SizedBox(height: 8),
            const Text('출처: MANANA', style: AppTypography.supporting),
            SelectableText(
              chart.scope.sourceUrl,
              style: AppTypography.supporting,
            ),
            Text(
              '서버 수집: ${chart.fetchedAt.toLocal()} · revision ${chart.revision}',
              style: AppTypography.supporting,
            ),
            if (chart.stale)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('이전 정상 자료예요. 최신 수집을 완료하지 못했거나 진행 중입니다.'),
              ),
            for (final item in chart.items)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SongRow.candidate(
                  candidate: CandidateSongViewData(
                    brand: chart.scope.brand == KaraokeBrand.tj
                        ? CatalogBrand.tj
                        : CatalogBrand.ky,
                    number: item.number,
                    title: item.title,
                    artist: item.artist,
                  ),
                  placement: CandidatePlacement.chart,
                  rank: item.position,
                  onTap: widget.onSelected == null
                      ? null
                      : () => widget.onSelected!(chart, item),
                ),
              ),
          ] else if (controller.phase == ChartPhase.loading)
            const ContentState(
              phase: ContentPhase.loading,
              title: '차트를 불러오는 중이에요',
            )
          else if (controller.phase == ChartPhase.unavailable) ...[
            ContentState(
              phase: ContentPhase.empty,
              title: '선택한 브랜드·기간의 자료가 없어요',
              message: controller.message,
            ),
            OutlinedButton(
              onPressed: () => controller.change(),
              child: const Text('다시 시도'),
            ),
          ] else
            ContentState(
              phase: controller.phase == ChartPhase.error
                  ? ContentPhase.error
                  : ContentPhase.waiting,
              title: controller.phase == ChartPhase.error
                  ? '차트를 불러오지 못했어요'
                  : '로그인이 필요해요',
              message: controller.message,
              onRetry: controller.phase == ChartPhase.error
                  ? () => controller.change()
                  : null,
            ),
        ],
      );
    },
  );
}
