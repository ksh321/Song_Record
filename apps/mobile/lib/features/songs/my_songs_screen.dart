import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/widgets/content_state.dart';
import '../../core/widgets/song_row.dart';
import '../../core/widgets/sort_sheet.dart';
import '../auth/auth_session.dart';
import 'my_song.dart';

typedef MySongsWatch = Stream<List<MySong>> Function();

class MySongsScreen extends StatefulWidget {
  const MySongsScreen({
    required this.watch,
    required this.onFindSong,
    this.auth,
    super.key,
  });
  final MySongsWatch watch;
  final VoidCallback onFindSong;
  final AuthController? auth;
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
    super.dispose();
  }

  Widget songRow(MySong song) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: SongRow.registered(song: song.view),
  );

  @override
  Widget build(BuildContext context) {
    final visible = orderMySongs(
      songs.where((song) => song.matches(query)),
      sort,
    );
    return ListView(
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
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
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
          for (final group in groupMySongs(visible, sort).entries) ...[
            Semantics(
              header: true,
              child: Text(
                '${group.key} (${group.value.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (group.value.isEmpty) const Text('이 티어에 등록된 곡이 없습니다'),
            for (final song in group.value) songRow(song),
            const SizedBox(height: AppSpacing.md),
          ]
        else
          for (final song in visible) songRow(song),
        FilledButton(onPressed: widget.onFindSong, child: const Text('새 곡 찾기')),
      ],
    );
  }
}
