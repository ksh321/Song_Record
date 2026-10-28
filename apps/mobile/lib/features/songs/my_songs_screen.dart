import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/widgets/app_icon.dart';
import '../../core/widgets/content_state.dart';
import '../../core/widgets/editable_collection.dart';
import '../../core/widgets/song_row.dart';
import '../../core/widgets/sort_sheet.dart';
import '../../core/widgets/ui_controls.dart';
import '../../routing/tab_navigation.dart';
import '../auth/auth_session.dart';
import '../trash/bulk_song_delete.dart';
import '../trash/trash_workflow.dart';
import 'my_song.dart';
import 'my_song_pages.dart';
import 'song_detail_screen.dart';
import 'song_edit.dart';
import 'song_representative.dart';
import 'unlinked_recordings_screen.dart';

typedef MySongsWatch = Stream<List<MySong>> Function();

class MySongsScreen extends StatefulWidget {
  const MySongsScreen({
    required this.watch,
    required this.onFindSong,
    this.auth,
    this.watchDetail,
    this.prepareEdit,
    this.prepareRepresentative,
    this.watchUnlinked,
    this.onOpenRecording,
    this.trash,
    super.key,
  });
  final UnlinkedWatch? watchUnlinked;
  final ValueChanged<String>? onOpenRecording;
  final MySongsWatch watch;
  final VoidCallback onFindSong;
  final AuthController? auth;
  final SongDetailWatch Function(String songId)? watchDetail;
  final SongEditPreparer? prepareEdit;
  final RepresentativePreparer? prepareRepresentative;
  final TrashActions? trash;
  @override
  State<MySongsScreen> createState() => _MySongsScreenState();
}

class _MySongsScreenState extends State<MySongsScreen> {
  StreamSubscription<List<MySong>>? subscription;
  StreamSubscription<List<Map<String, dynamic>>>? unlinkedSubscription;
  int? unlinkedCount;
  List<MySong> songs = [];
  String query = '', scope = '';
  bool grouped = false, suitableOnly = false;
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
      suitableOnly = false;
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
    unlinkedCount = null;
    unawaited(unlinkedSubscription?.cancel());
    if (widget.watchUnlinked != null) {
      try {
        unlinkedSubscription = widget.watchUnlinked!().listen(
          (rows) {
            if (!mounted || request != generation || tag() != scope) return;
            setState(() => unlinkedCount = rows.length);
          },
          onError: (Object error) {
            if (!mounted || request != generation || tag() != scope) return;
            setState(() => unlinkedCount = null);
          },
        );
      } catch (_) {
        unlinkedCount = null;
      }
    }
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
    unawaited(unlinkedSubscription?.cancel());
    scroll.dispose();
    super.dispose();
  }

  Future<bool> deleteSelected(List<String> ids) async {
    final request = generation, owner = scope;
    final actions = widget.trash;
    if (actions == null) return false;
    return showBulkSongDelete(
      context,
      ids: ids,
      actions: actions,
      isCurrent: () =>
          mounted &&
          generation == request &&
          tag() == owner &&
          identical(actions, widget.trash),
    );
  }

  Widget songRow(MySong song) => Padding(
    padding: EdgeInsets.zero,
    child: GestureDetector(
      child: SongRow.registered(
        song: song.view,
        flat: true,
        onTap: widget.watchDetail == null
            ? null
            : () {
                FocusManager.instance.primaryFocus?.unfocus();
                Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => SongDetailScreen(
                      trash: widget.trash,
                      watch: widget.watchDetail!(song.view.id.value),
                      auth: widget.auth,
                      prepareEdit: widget.prepareEdit,
                      prepareRepresentative: widget.prepareRepresentative,
                    ),
                  ),
                );
              },
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    pages.select(search: query, selectedSort: sort, tierView: grouped);
    pages.replace(
      songs.where((s) => !suitableOnly || s.view.isSuitable).toList(),
      '$scope:$suitableOnly',
    );
    final visible = pages.visible;
    final groups = groupMySongs(pages.ordered, sort);
    return EditableCollection(
      key: ValueKey(scope),
      rowSpacing: 0,
      ids: visible.map((song) => song.view.id.value).toList(),
      selectionIds: pages.ordered.map((song) => song.view.id.value).toList(),
      onDelete: deleteSelected,
      enabled: !loading && failure == null,
      deleteLabel: (count) => '선택한 $count곡 삭제',
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabHeaderSubtitle(
            loading || failure != null ? null : '등록된 곡 ${songs.length}개',
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: AppCompactAction(
              label: '내 곡 등록',
              onPressed: widget.onFindSong,
            ),
          ),
          const SizedBox(height: 12),
          AppSearchField(
            fieldKey: ValueKey(scope),
            hint: '내 곡에서 곡명 또는 가수 검색',
            onChanged: (value) => setState(() => query = value),
          ),
          const SizedBox(height: 16),
          AppOptions<bool>(
            options: const {false: '전체 목록', true: '티어별 보기'},
            selected: grouped,
            onChanged: (v) => setState(() => grouped = v),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: InkWell(
              onTap: () => setState(() => suitableOnly = !suitableOnly),
              child: Row(
                children: [
                  SizedBox(
                    width: 17,
                    height: 23,
                    child: Checkbox(
                      value: suitableOnly,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      onChanged: (v) =>
                          setState(() => suitableOnly = v ?? false),
                    ),
                  ),
                  const SizedBox(width: 7),
                  AppIcon(
                    Icons.favorite,
                    size: 17,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: Text('나에게 어울리는 곡만', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: (_, _) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            loading || failure != null ? '—곡' : '${pages.total}곡',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            key: const ValueKey('my-song-count'),
          ),
          TextButton.icon(
            icon: const AppIcon(Icons.sort),
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
      row: (id) {
        final song = visible.firstWhere((song) => song.view.id.value == id);
        final firstInGroup =
            grouped &&
            groups.values.any(
              (group) => group.isNotEmpty && group.first.view.id.value == id,
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (firstInGroup)
              Text(
                '${groups.entries.firstWhere((entry) => entry.value.contains(song)).key} (${groups.values.firstWhere((group) => group.contains(song)).length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            songRow(song),
          ],
        );
      },
      footer: Column(
        children: [
          if (loading)
            const ContentState(
              phase: ContentPhase.loading,
              title: '내 곡을 불러오고 있어요.',
            ),
          if (failure != null)
            ContentState(
              phase: ContentPhase.error,
              title: '내 곡을 불러오지 못했어요.',
              onRetry: bind,
            ),
          if (!loading && failure == null && visible.isEmpty)
            const Text('등록된 내 곡이 없습니다'),
          if (!loading && failure == null && pages.cursor != null)
            OutlinedButton(
              onPressed: () => setState(() => pages.next(pages.cursor!)),
              child: const Text('더 보기'),
            ),
          if (widget.watchUnlinked != null)
            TextButton.icon(
              icon: const AppIcon(Icons.chevron_right, size: 16),
              label: Text('곡 미연결 녹음 (${unlinkedCount ?? '—'})'),
              onPressed: unlinkedCount == null
                  ? null
                  : () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => UnlinkedRecordingsScreen(
                          watch: widget.watchUnlinked!,
                          auth: widget.auth,
                          onOpenRecording: widget.onOpenRecording,
                        ),
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}
