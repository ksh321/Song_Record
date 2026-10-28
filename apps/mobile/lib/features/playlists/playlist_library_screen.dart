import 'package:flutter/material.dart';
import 'package:song_record/core/widgets/app_page_bar.dart';

import '../../core/widgets/app_icon.dart';
import '../../core/widgets/editable_collection.dart';
import '../../core/widgets/feature_icon.dart';
import '../../core/widgets/folding_scaffold.dart';
import '../../core/widgets/ui_controls.dart';
import '../../routing/tab_navigation.dart';
import '../auth/auth_session.dart';
import '../charts/popular_chart.dart';
import '../search/karaoke_search.dart';
import '../trash/trash_workflow.dart';
import 'playlist_create_screen.dart';
import 'playlist_detail_screen.dart';
import 'playlist_library.dart';

const playlistIcons = <String, IconData>{
  'music': Icons.music_note_outlined,
  'mic': Icons.mic_none,
  'heart': Icons.favorite_border,
  'star': Icons.star_border,
  'headphones': Icons.headphones_outlined,
  'sun': Icons.wb_sunny_outlined,
};
const playlistIconLabels = <String, String>{
  'music': '음표',
  'mic': '마이크',
  'heart': '하트',
  'star': '별',
  'headphones': '헤드폰',
  'sun': '해',
};

class PlaylistLibraryScreen extends StatefulWidget {
  const PlaylistLibraryScreen({
    super.key,
    required this.library,
    this.onOpen,
    this.searchLoad,
    this.chartLoad,
    this.auth,
    this.afterSave,
    this.onOpenSong,
    this.embedded = false,
    this.syncChanges,
    this.trash,
  });
  final bool embedded;
  final Listenable? syncChanges;
  final TrashActions? trash;
  final KaraokeLoader? searchLoad;
  final ChartLoader? chartLoad;
  final AuthController? auth;
  final Future<void> Function()? afterSave;
  final void Function(String)? onOpenSong;
  final PlaylistLibrary library;
  final void Function(Map<String, dynamic>)? onOpen;
  @override
  State<PlaylistLibraryScreen> createState() => _PlaylistLibraryScreenState();
}

class _PlaylistLibraryScreenState extends State<PlaylistLibraryScreen> {
  List<Map<String, dynamic>> rows = [];
  Map<String, PlaylistSummary> summaries = {};
  bool busy = false;
  bool headerFolded = false;
  bool loading = true;
  bool rejectedOrder = false;
  String? orderNotice;
  String? error;
  int _loadGeneration = 0;
  @override
  void initState() {
    super.initState();
    widget.syncChanges?.addListener(reload);
    reload();
  }

  @override
  void didUpdateWidget(PlaylistLibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.library != widget.library) {
      rows = [];
      summaries = {};
    }
    if (oldWidget.syncChanges != widget.syncChanges ||
        oldWidget.library != widget.library) {
      oldWidget.syncChanges?.removeListener(reload);
      widget.syncChanges?.addListener(reload);
      reload();
    }
  }

  @override
  void dispose() {
    widget.syncChanges?.removeListener(reload);
    super.dispose();
  }

  Future<void> reload() async {
    final generation = ++_loadGeneration;
    final library = widget.library;
    if (mounted) setState(() => loading = true);
    try {
      final value = await library.load();
      final previews = await library.summaries(value);
      final order = await library.pendingOrder();
      final rejected = await library.rejectedOrder();
      if (mounted &&
          generation == _loadGeneration &&
          identical(library, widget.library)) {
        setState(() {
          rows = value;
          summaries = previews;
          rejectedOrder = rejected != null;
          orderNotice = order == null
              ? null
              : rejected != null
              ? '목록이 변경되어 순서를 저장하지 못했어요. 다시 정렬해 주세요.'
              : order.state == 'FAILED' || order.state == 'CONFLICT'
              ? '순서를 저장하지 못했어요. 설정에서 전송 상태를 확인해 주세요.'
              : '순서 저장 대기 · 연결되면 다른 기기에도 반영돼요';
          error = null;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          error = '목록을 불러오지 못했어요. 다시 시도해 주세요.';
          loading = false;
        });
      }
    }
  }

  Future<void> edit([Map<String, dynamic>? row]) async {
    if (row == null) {
      final library = widget.library;
      final result = await Navigator.of(context)
          .push<({String name, String icon})>(
            MaterialPageRoute(
              builder: (_) => PlaylistCreateScreen(
                icons: playlistIcons,
                labels: playlistIconLabels,
              ),
            ),
          );
      if (!mounted || result == null || !identical(library, widget.library)) {
        return;
      }
      await run(() => library.create(result.name, icon: result.icon)());
      return;
    }
    var input = row['name'] as String;
    final library = widget.library;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('목록 이름 변경'),
        content: TextFormField(
          initialValue: input,
          onChanged: (value) => input = value,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '목록 이름',
            helperText: '1~100자 · 같은 이름도 사용할 수 있어요',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (name == null || !mounted || !identical(library, widget.library)) return;
    await run(() => library.rename(row, name)());
  }

  List<Map<String, dynamic>>? orderBase;

  Future<void> acceptLatestOrder() async {
    final library = widget.library;
    final rejected = await library.rejectedOrder();
    if (!mounted || !identical(library, widget.library) || rejected == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('최신 목록을 확인할까요?'),
        content: const Text('다른 곳에서 바뀐 목록을 받아 온 뒤 다시 순서를 정할 수 있어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('최신 목록 확인'),
          ),
        ],
      ),
    );
    if (!mounted || !identical(library, widget.library) || confirmed != true) {
      return;
    }
    await run(() => library.repository.acceptLatestPlaylistOrder(rejected));
  }

  Future<void> saveOrder(List<String> ids) async {
    final library = widget.library;
    final original = orderBase ?? List<Map<String, dynamic>>.of(rows);
    if (await library.rejectedOrder() != null) {
      throw StateError('최신 목록 확인이 필요합니다.');
    }
    if (!mounted || !identical(library, widget.library)) return;
    await library.reorderLibrary(original, ids);
    await widget.afterSave?.call();
    await reload();
  }

  Future<bool> removeSelected(List<String> ids) async {
    final library = widget.library;
    final epoch = widget.auth?.accountEpoch;
    final targets = rows.where((row) => ids.contains(row['id'])).toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('플레이리스트 ${targets.length}개를 삭제할까요?'),
        content: const Text('선택한 목록과 구성·순서는 복원할 수 없습니다. 내 곡과 녹음은 그대로 유지돼요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    try {
      for (final row in targets) {
        if (!mounted ||
            !identical(library, widget.library) ||
            widget.auth?.accountEpoch != epoch) {
          throw StateError('Account changed');
        }
        await library.delete(row)();
        await widget.afterSave?.call();
      }
    } finally {
      if (mounted) await reload();
    }
    return true;
  }

  Future<void> editIcon(Map<String, dynamic> row) async {
    final library = widget.library;
    final icon = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('아이콘 수정'),
        children: [
          for (final entry in playlistIcons.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, entry.key),
              child: Row(
                children: [
                  FeatureIcon(entry.value),
                  const SizedBox(width: 12),
                  Text(playlistIconLabels[entry.key]!),
                  if ((row['icon'] ?? 'music') == entry.key) ...[
                    const Spacer(),
                    AppIcon(
                      Icons.check,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
    if (icon != null && mounted && identical(library, widget.library)) {
      await run(library.changeIcon(row, icon));
    }
  }

  Future<void> remove(Map<String, dynamic> row) async {
    final library = widget.library;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('플레이리스트를 영구 삭제할까요?'),
        content: const Text(
          '이 목록과 목록 안의 구성·순서는 복원할 수 없습니다. 내 곡과 녹음은 삭제되지 않습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('영구 삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !identical(library, widget.library)) {
      return;
    }
    await run(() => library.delete(row)());
    if (mounted && error == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('목록 삭제 전송 대기')));
    }
  }

  Future<void> run(Future<void> Function() save) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await save();
      await widget.afterSave?.call();
      await reload();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ArgumentError
              ? e.message.toString()
              : '목록 변경을 저장하지 못했어요. 최신 목록을 확인해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FoldingScaffold(
    collapsed: headerFolded,
    appBar: widget.embedded
        ? null
        : appPageBar(context, title: const Text('플레이리스트')),
    body: SafeArea(
      top: !widget.embedded,
      child: EditableCollection(
        key: ObjectKey(widget.library),
        ids: rows.map((row) => row['id'] as String).toList(),
        enabled: !busy && !loading,
        onHeaderFold: (value) {
          if (widget.embedded) {
            TabNavigation.maybeOf(context)?.foldHeader(value);
          } else {
            setState(() => headerFolded = value);
          }
        },
        onBeginReorder: () => orderBase = List<Map<String, dynamic>>.of(rows),
        onReorder: saveOrder,
        onDelete: removeSelected,
        deleteLabel: (count) => '선택한 $count개 플리 삭제',
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TabHeaderSubtitle(loading ? null : '나만의 목록 ${rows.length}개'),
            if (error != null) Text(error!),
            if (orderNotice != null) Text(orderNotice!),
            if (rejectedOrder)
              TextButton(
                onPressed: busy ? null : acceptLatestOrder,
                child: const Text('최신 목록 확인'),
              ),
            if (!loading && rows.isEmpty) const Text('아직 플레이리스트가 없어요.'),
          ],
        ),
        belowActions: Row(
          children: [
            const Text('나만의 선곡', style: TextStyle(fontSize: 12)),
            const Spacer(),
            Text(
              '${rows.length}개 목록 · ${summaries.values.fold<int>(0, (count, summary) => count + summary.count)}곡',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: (compact, reorder) => Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppReorderAction(onPressed: reorder, compact: compact),
            const SizedBox(width: 8),
            AppCompactAction(
              label: '새 플레이리스트',
              compact: compact,
              onPressed: busy || loading ? null : () => edit(),
            ),
          ],
        ),
        row: (id) {
          final row = rows.firstWhere((row) => row['id'] == id);
          return Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Theme.of(context).colorScheme.outline),
            ),
            margin: const EdgeInsets.only(bottom: 2),
            child: ListTile(
              leading: FeatureIcon(
                playlistIcons[row['icon']] ?? Icons.music_note_outlined,
              ),
              title: Text(
                row['name'] as String,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                summaries[row['id']]?.preview ?? '',
                style: TextStyle(
                  fontSize: 10,
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: busy || loading
                  ? null
                  : () async {
                      if (widget.onOpen != null) {
                        widget.onOpen!(row);
                        return;
                      }
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PlaylistDetailScreen(
                            onOptions: (action, current) async {
                              final library = widget.library;
                              final latest = (await library.load())
                                  .where((row) => row['id'] == current['id'])
                                  .firstOrNull;
                              if (!mounted ||
                                  latest == null ||
                                  !identical(library, widget.library)) {
                                return;
                              }
                              if (action == 'rename') {
                                await edit(latest);
                              } else if (action == 'icon') {
                                await editIcon(latest);
                              } else if (action == 'delete') {
                                await remove(latest);
                              }
                            },
                            library: widget.library,
                            id: row['id'] as String,
                            searchLoad: widget.searchLoad,
                            chartLoad: widget.chartLoad,
                            auth: widget.auth,
                            trash: widget.trash,
                            afterSave: widget.afterSave,
                            onOpenSong: widget.onOpenSong,
                          ),
                        ),
                      );
                      await reload();
                    },
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${summaries[row['id']]?.count ?? 0}곡'),
                  const SizedBox(width: 8),
                  const AppIcon(Icons.chevron_right, size: 16),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}
