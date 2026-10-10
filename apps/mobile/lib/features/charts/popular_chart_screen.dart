import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/widgets/content_state.dart';
import '../../core/widgets/music_view_data.dart';
import '../../core/widgets/song_row.dart';
import '../auth/auth_session.dart';
import '../search/karaoke_search.dart';
import '../search/karaoke_search_screen.dart';
import '../search/search_intent.dart';
import '../search/song_registration.dart';
import '../search/song_registration_screen.dart';
import 'popular_chart.dart';

class PopularChartScreen extends StatefulWidget {
  const PopularChartScreen({
    required this.load,
    this.auth,
    this.onSelected,
    this.intent = const SearchIntent(),
    this.searchLoad,
    this.prepareRegistration,
    super.key,
  });
  final SearchIntent intent;
  final KaraokeLoader? searchLoad;
  final SongRegistrationPreparer? prepareRegistration;
  final ChartLoader load;
  final AuthController? auth;
  final ValueChanged<KaraokeSelection>? onSelected;
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
    widget.intent.validate();
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

  Future<void> _select(PublishedChart chart, ChartItem item) async {
    final request = controller.requestId;
    final origin = widget.intent;
    final account = tag();
    bool current() =>
        mounted &&
        request == controller.requestId &&
        identical(controller.chart, chart) &&
        controller.scope == chart.scope &&
        identical(widget.intent, origin) &&
        tag() == account &&
        (widget.auth == null || widget.auth!.phase == AuthPhase.ready);
    if (!current()) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: AppDimensions.sheetPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: AppTypography.detailTitle),
                Text(item.artist),
                Text('${chart.scope.brandCode} ${item.number}'),
                const SizedBox(height: 16),
                if (chart.scope.brand == KaraokeBrand.ky) ...[
                  const Text('금영 결과는 직접 등록할 수 없어요. TJ에서 찾아 선택해 주세요.'),
                  if (widget.searchLoad != null)
                    FilledButton(
                      onPressed: () => Navigator.pop(sheet, 'find-tj'),
                      child: const Text('TJ에서 이 곡 찾기'),
                    ),
                ] else
                  FilledButton(
                    onPressed: () => Navigator.pop(sheet, 'use-tj'),
                    child: Text(
                      origin.purpose == SearchPurpose.playlist
                          ? '목록에 사용할 TJ 곡 선택'
                          : '이 TJ 곡 선택',
                    ),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(sheet),
                  child: const Text('취소'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || !current() || action == null) return;
    KaraokeSelection? selection;
    if (action == 'use-tj' && chart.scope.brand == KaraokeBrand.tj) {
      selection = KaraokeSelection(
        KaraokeCandidate(
          brand: KaraokeBrand.tj,
          number: item.number,
          title: item.title,
          artist: item.artist,
          provider: 'MANANA',
          sourceRef: 'manana:tj:${item.number}',
          sourceToken: item.sourceToken!,
          expiresAt: null,
        ),
        origin,
      );
    } else if (action == 'find-tj' && chart.scope.brand == KaraokeBrand.ky) {
      selection = await Navigator.of(context).push<KaraokeSelection>(
        MaterialPageRoute(
          settings: RouteSettings(
            name: '/charts/tj-from-ky',
            arguments: origin,
          ),
          builder: (route) => Scaffold(
            appBar: AppBar(title: const Text('TJ에서 찾기')),
            body: KaraokeSearchScreen(
              load: widget.searchLoad!,
              auth: widget.auth,
              intent: origin,
              initialQuery: KaraokeQuery(
                KaraokeBrand.tj,
                KaraokeKind.title,
                item.title,
              ),
              onSelected: (selected) => Navigator.of(route).pop(selected),
            ),
          ),
        ),
      );
    }
    if (!mounted ||
        !current() ||
        selection == null ||
        !identical(selection.intent, origin)) {
      return;
    }
    final selected = widget.onSelected;
    if (selected != null) {
      selected(selection);
      return;
    }
    final prepare = widget.prepareRegistration;
    if (prepare == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        settings: RouteSettings(name: '/songs/register', arguments: origin),
        builder: (_) => SongRegistrationScreen(
          intent: origin,
          candidate: selection!.candidate,
          prepare: (draft) {
            if (!current()) throw StateError('Chart selection changed');
            final save = prepare(draft);
            return () async {
              if (!current()) throw StateError('Chart selection changed');
              await save();
            };
          },
        ),
      ),
    );
    if (mounted && current() && saved == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('입력을 이 기기에 저장했어요. 연결되면 등록을 진행합니다.')),
      );
    }
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
                  onTap:
                      widget.onSelected == null &&
                          widget.prepareRegistration == null
                      ? null
                      : () => _select(chart, item),
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
