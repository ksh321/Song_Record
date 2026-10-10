import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/widgets/content_state.dart';
import '../../core/widgets/song_row.dart';
import '../../core/widgets/sort_sheet.dart';
import '../auth/auth_session.dart';
import 'my_song.dart';
import 'my_song_pages.dart';
import 'song_detail_screen.dart';
import 'song_edit.dart';
import 'song_representative.dart';

typedef MySongsWatch = Stream<List<MySong>> Function();

class MySongsScreen extends StatefulWidget {
  const MySongsScreen({
    required this.watch,
    required this.onFindSong,
    this.auth,
    this.watchDetail,
    this.prepareEdit,
    this.prepareRepresentative,
    super.key,
  });
  final MySongsWatch watch;
  final VoidCallback onFindSong;
  final AuthController? auth;
  final SongDetailWatch Function(String songId)? watchDetail;
  final SongEditPreparer? prepareEdit;
  final RepresentativePreparer? prepareRepresentative;
  @override
  State<MySongsScreen> createState() => _MySongsScreenState();
}

class _MySongsScreenState extends State<MySongsScreen> {
  StreamSubscription<List<MySong>>? subscription;
  List<MySong> songs = [];
  String query = '', scope = '';
  bool grouped = false;
  SongSort sort = SongSort.recentlyAdded;
  bool loading = true;
  Object? failure;
  int generation = 0;
  final pages = MySongPages();
  final scroll = ScrollController();
  int pageGeneration = -1;
  String tag() =>
      '${widget.auth?.phase}:${widget.auth?.session?.userId}:${widget.auth?.session?.deviceId}';
  @override
  void initState() {
    super.initState();
    widget.auth?.addListener(authChanged);
    bind();
  }

  void authChanged() {
    if (tag() != scope) {
      query = '';
      bind();
    }
  }

  void bind() {
    scope = tag();
    final request = ++generation;
    unawaited(subscription?.cancel());
    subscription = null;
    setState(() {
      songs = [];
      failure = null;
      loading = true;
    });
    try {
      subscription = widget.watch().listen(
        (rows) {
          if (!mounted || request != generation || tag() != scope) return;
          setState(() {
            songs = rows;
            loading = false;
            failure = null;
          });
        },
        onError: (Object error) {
          if (!mounted || request != generation || tag() != scope) return;
          setState(() {
            songs = [];
            failure = error;
            loading = false;
          });
        },
      );
    } catch (error) {
      loading = false;
      failure = error;
    }
  }

  @override
  void didUpdateWidget(covariant MySongsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.auth != widget.auth) {
      oldWidget.auth?.removeListener(authChanged);
      widget.auth?.addListener(authChanged);
      query = '';
      bind();
    } else if (oldWidget.watch != widget.watch) {
      bind();
    }
  }

  @override
  void dispose() {
    ++generation;
    widget.auth?.removeListener(authChanged);
    unawaited(subscription?.cancel());
    scroll.dispose();
    super.dispose();
  }

  Widget songRow(MySong song) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: SongRow.registered(
      song: song.view,
      onTap: widget.watchDetail == null
          ? null
          : () {
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => SongDetailScreen(
                    watch: widget.watchDetail!(song.view.id.value),
                    auth: widget.auth,
                    prepareEdit: widget.prepareEdit,
                    prepareRepresentative: widget.prepareRepresentative,
                  ),
                ),
              );
            },
    ),
  );

  @override
  Widget build(BuildContext context) {
    pages.select(search: query, selectedSort: sort, tierView: grouped);
    pages.replace(songs, scope);
    final visible = pages.visible;
    final groups = groupMySongs(pages.ordered, sort);
    if (pageGeneration != pages.generation) {
      pageGeneration = pages.generation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) scroll.jumpTo(0);
      });
    }
    return ListView(
      controller: scroll,
      primary: false,
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        TextField(
          key: ValueKey(scope),
          decoration: const InputDecoration(
            labelText: '내 곡 검색',
            hintText: '곡명 또는 가수',
          ),
          onChanged: (value) => setState(() {
            query = value;
          }),
        ),
        const SizedBox(height: AppSpacing.md),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('전체 목록')),
            ButtonSegment(value: true, label: Text('티어별 보기')),
          ],
          selected: {grouped},
          onSelectionChanged: (selected) =>
              setState(() => grouped = selected.single),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              loading || failure != null ? '—곡' : '${pages.total}곡',
              key: const ValueKey('my-song-count'),
            ),
            TextButton.icon(
              icon: const Icon(Icons.sort),
              label: Text(sort.label),
              onPressed: () async {
                final result = await SortSheet.songs(
                  context: context,
                  selected: sort,
                );
                if (mounted && result != null) {
                  setState(() => sort = result.value);
                }
              },
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (loading)
          const ContentState(
            phase: ContentPhase.loading,
            title: '내 곡을 불러오고 있어요.',
          )
        else if (failure != null)
          ContentState(
            phase: ContentPhase.error,
            title: '내 곡을 불러오지 못했어요.',
            onRetry: bind,
          )
        else if (visible.isEmpty)
          const ContentState(phase: ContentPhase.empty, title: '등록된 내 곡이 없습니다')
        else if (grouped)
          for (final group in groups.entries) ...[
            Semantics(
              header: true,
              child: Text(
                '${group.key} (${group.value.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (group.value.isEmpty) const Text('이 티어에 등록된 곡이 없습니다'),
            if (group.value.isNotEmpty &&
                !visible.any((s) => s.view.tier == group.value.first.view.tier))
              const Text('다음 목록에서 볼 수 있어요'),
            for (final song in group.value.where((s) => visible.contains(s)))
              songRow(song),
            const SizedBox(height: AppSpacing.md),
          ]
        else
          for (final song in visible) songRow(song),
        if (!loading && failure == null && pages.cursor != null)
          OutlinedButton(
            onPressed: () => setState(() => pages.next(pages.cursor!)),
            child: const Text('더 보기'),
          ),
        FilledButton(onPressed: widget.onFindSong, child: const Text('새 곡 찾기')),
      ],
    );
  }
}
