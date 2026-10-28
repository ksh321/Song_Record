import 'package:flutter/material.dart';
import 'package:song_record/core/widgets/app_page_bar.dart';

import '../../core/widgets/content_state.dart';
import '../../core/widgets/music_view_data.dart';
import '../../core/widgets/scroll_to_top_button.dart';
import '../../core/widgets/song_row.dart';
import '../../core/widgets/ui_controls.dart';
import '../auth/auth_session.dart';
import '../search/karaoke_candidate_dialog.dart';
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
    this.candidateActions,
    this.onSelected,
    this.intent = const SearchIntent(),
    this.searchLoad,
    this.prepareRegistration,
    super.key,
  });
  final KaraokeCandidateActions? candidateActions;
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
  final _scroll = ScrollController();
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
    _scroll.dispose();
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
    final action = await showKaraokeCandidateDialog(
      context: context,
      actions: widget.onSelected == null && widget.intent.returnRoute == '/'
          ? widget.candidateActions
          : null,
      title: item.title,
      artist: item.artist,
      number: item.number,
      isTj: chart.scope.brand == KaraokeBrand.tj,
      allowFindTj: widget.searchLoad != null,
    );
    if (!mounted || !current() || action == null) return;
    KaraokeSelection? selection;
    if ((action == 'use-tj' ||
            action == 'add-playlist' ||
            action.startsWith('view-song:')) &&
        chart.scope.brand == KaraokeBrand.tj) {
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
            appBar: appPageBar(context, title: const Text('TJ에서 찾기')),
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
    if (widget.candidateActions != null && action == 'add-playlist') {
      await widget.candidateActions!.addToPlaylist(
        context,
        selection.candidate,
      );
      return;
    }
    if (widget.candidateActions != null && action.startsWith('view-song:')) {
      await widget.candidateActions!.openSong(context, action.substring(10));
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
      if (origin.returnRoute == '/recording/input' &&
          Navigator.canPop(context)) {
        Navigator.pop(context);
        return;
      }
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
      return Stack(
        fit: StackFit.expand,
        children: [
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(context)
                .copyWith(overscroll: false),
            child: ListView(
              controller: _scroll,
              physics: const ClampingScrollPhysics(),
              key: const PageStorageKey('popular-chart'),
              primary: false,
              padding: AppLayout.bodyPadding,
              children: [
                AppBrandTabs<KaraokeBrand>(
                  options: const {KaraokeBrand.tj: 'TJ', KaraokeBrand.ky: '금영'},
                  selected: controller.scope.brand,
                  onChanged: (v) => controller.change(brand: v),
                ),
                const SizedBox(height: 14),
                AppOptions<ChartPeriod>(
                  pills: true,
                  equalWidth: true,
                  options: {for (final p in ChartPeriod.values) p: p.label},
                  selected: controller.scope.period,
                  onChanged: (v) => controller.change(period: v),
                ),
                const SizedBox(height: 14),
                if (chart != null) ...[
                  Text(
                    '${controller.scope.period.label} 인기곡',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (chart.stale)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('이전 정상 자료예요. 최신 수집을 완료하지 못했거나 진행 중입니다.'),
                    ),
                  for (final item in chart.items)
                    Padding(
                      padding: EdgeInsets.zero,
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
            ),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: ScrollToTopButton(controller: _scroll),
          ),
        ],
      );
    },
  );
}
