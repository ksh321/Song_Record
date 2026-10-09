import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/widgets/content_state.dart';
import '../auth/auth_session.dart';
import 'karaoke_search.dart';

class KaraokeSearchScreen extends StatefulWidget {
  const KaraokeSearchScreen({
    required this.load,
    this.auth,
    this.onSelected,
    super.key,
  });
  final KaraokeLoader load;
  final AuthController? auth;
  final ValueChanged<KaraokeCandidate>? onSelected;
  @override
  State<KaraokeSearchScreen> createState() => _KaraokeSearchScreenState();
}

class _KaraokeSearchScreenState extends State<KaraokeSearchScreen> {
  late final KaraokeSearchController controller;
  final input = TextEditingController();
  String? account;
  @override
  void initState() {
    super.initState();
    controller = KaraokeSearchController((q) => widget.load(q));
    account = widget.auth?.session?.userId;
    widget.auth?.addListener(_authChanged);
  }

  void _authChanged() {
    final auth = widget.auth;
    if (auth?.phase != AuthPhase.ready || auth?.session?.userId != account) {
      account = auth?.session?.userId;
      input.clear();
      controller.clearForAccount();
    }
  }

  @override
  void didUpdateWidget(covariant KaraokeSearchScreen oldWidget) {
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
    input.dispose();
    super.dispose();
  }

  void _select(KaraokeCandidate c) {
    if (widget.onSelected != null) {
      widget.onSelected!(c);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (_) => Padding(
        padding: AppDimensions.sheetPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.title, style: AppTypography.detailTitle),
            Text(c.artist),
            Text('${c.brand == KaraokeBrand.tj ? 'TJ' : '금영'} ${c.number}'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final state = controller.phase;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<KaraokeBrand>(
            segments: const [
              ButtonSegment(value: KaraokeBrand.tj, label: Text('TJ')),
              ButtonSegment(value: KaraokeBrand.ky, label: Text('금영')),
            ],
            selected: {controller.query.brand},
            onSelectionChanged: (v) => controller.change(brand: v.single),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: input,
            decoration: const InputDecoration(
              labelText: '검색어',
              hintText: '곡명·가수·번호 검색',
            ),
            onChanged: (v) => controller.change(text: v),
            onSubmitted: (_) => controller.retry(),
          ),
          const SizedBox(height: 12),
          SegmentedButton<KaraokeKind>(
            segments: const [
              ButtonSegment(value: KaraokeKind.title, label: Text('곡명')),
              ButtonSegment(value: KaraokeKind.artist, label: Text('가수')),
              ButtonSegment(value: KaraokeKind.number, label: Text('번호')),
            ],
            selected: {controller.query.kind},
            onSelectionChanged: (v) => controller.change(kind: v.single),
          ),
          const SizedBox(height: 16),
          if (state == SearchPhase.idle)
            const ContentState(
              phase: ContentPhase.waiting,
              title: '검색어를 입력해 주세요.',
            ),
          if (state == SearchPhase.waiting)
            const ContentState(
              phase: ContentPhase.waiting,
              title: '입력한 검색어로 찾을게요.',
            ),
          if (state == SearchPhase.loading)
            const ContentState(phase: ContentPhase.loading, title: '검색 중이에요.'),
          if (state == SearchPhase.empty)
            const ContentState(phase: ContentPhase.empty, title: '검색 결과가 없어요.'),
          if (state == SearchPhase.error)
            ContentState(
              phase: ContentPhase.error,
              title: '검색을 완료하지 못했어요.',
              message: controller.message,
              onRetry: controller.retry,
            ),
          for (final c in controller.results)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                vertical: 8,
                horizontal: 4,
              ),
              title: Text(c.title, style: AppTypography.songTitle),
              subtitle: Text(
                '${c.artist} · ${c.brand == KaraokeBrand.tj ? 'TJ' : '금영'} ${c.number}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _select(c),
            ),
        ],
      );
    },
  );
}
