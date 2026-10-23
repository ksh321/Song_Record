import 'package:flutter/material.dart';
import 'package:song_record/core/widgets/app_page_bar.dart';

import '../../core/widgets/app_icon.dart';
import '../../core/widgets/feature_icon.dart';
import '../../core/widgets/ui_controls.dart';
import '../../routing/tab_navigation.dart';
import '../auth/auth_session.dart';
import '../charts/popular_chart.dart';
import '../search/karaoke_search.dart';
import '../trash/trash_workflow.dart';
import 'playlist_detail_screen.dart';
import 'playlist_library.dart';
import 'playlist_order_picker.dart';

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
    var input = row?['name'] as String? ?? '';
    var icon = 'music';
    final name = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(row == null ? '새 플레이리스트' : '목록 이름 변경'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: input,
                onChanged: (value) => input = value,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '목록 이름',
                  helperText: '1~100자 · 같은 이름도 사용할 수 있어요',
                ),
              ),
              if (row == null)
                Wrap(
                  spacing: 8,
                  children: [
                    for (final entry in playlistIcons.entries)
                      IconButton(
                        tooltip: playlistIconLabels[entry.key],
                        onPressed: () => update(() => icon = entry.key),
                        isSelected: icon == entry.key,
                        icon: FeatureIcon(
                          entry.value,
                          selected: icon == entry.key,
                        ),
                      ),
                  ],
                ),
            ],
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
      ),
    );
    if (name == null || !mounted) return;
    await run(
      () => row == null
          ? widget.library.create(name, icon: icon)()
          : widget.library.rename(row, name)(),
    );
  }

  Future<void> reorder() async {
    if (busy || loading) return;
    final library = widget.library;
    final rejected = await library.rejectedOrder();
    if (!mounted || !identical(library, widget.library)) return;
    if (rejected != null) {
      final accept = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('목록이 변경됐어요'),
          content: const Text(
            '다른 곳에서 목록이 변경되어 지난 순서를 저장하지 못했어요. 최신 목록을 확인하고 다시 정렬할까요?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('다시 정렬'),
            ),
          ],
        ),
      );
      if (accept != true || !mounted || !identical(library, widget.library)) {
        return;
      }
      await run(() => library.repository.acceptLatestPlaylistOrder(rejected));
      if (!mounted || error != null || !identical(library, widget.library)) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('목록 동기화를 요청했어요. 목록을 확인한 뒤 다시 정렬해 주세요.')),
      );
      return;
    }
    if (rows.length < 2) return;
    final original = List<Map<String, dynamic>>.of(rows);
    final ids = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: .8,
        child: PlaylistOrderPicker(
          items: original,
          title: '플레이리스트 순서',
          titles: {
            for (final row in original)
              row['id'] as String: row['name'] as String,
          },
        ),
      ),
    );
    if (ids == null || !mounted || !identical(library, widget.library)) return;
    await run(() => library.reorderLibrary(original, ids));
  }

  Future<void> editIcon(Map<String, dynamic> row) async {
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
    if (icon != null && mounted) {
      await run(widget.library.changeIcon(row, icon));
    }
  }

  Future<void> remove(Map<String, dynamic> row) async {
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
    if (confirmed != true || !mounted) return;
    await run(() => widget.library.delete(row)());
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
  Widget build(BuildContext context) => Scaffold(
    appBar: widget.embedded
        ? null
        : appPageBar(context, title: const Text('플레이리스트')),
    body: SafeArea(
      top: !widget.embedded,
      child: ListView(
        padding: AppLayout.bodyPadding,
        children: [
          TabHeaderSubtitle(loading ? null : '${rows.length}개 목록'),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed:
                    busy || loading || (rows.length < 2 && !rejectedOrder)
                    ? null
                    : reorder,
                child: const Text('순서 변경'),
              ),
              AppCompactAction(
                label: '새 플레이리스트',
                onPressed: busy || loading ? null : () => edit(),
              ),
            ],
          ),
          if (orderNotice != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(orderNotice!),
            ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('아직 플레이리스트가 없어요.'),
            ),
          for (final row in rows)
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Theme.of(context).colorScheme.outline),
              ),
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                onLongPress: busy || loading || rows.length < 2
                    ? null
                    : reorder,
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
                    PopupMenuButton<String>(
                      enabled: !busy && !loading,
                      onSelected: (value) => value == 'rename'
                          ? edit(row)
                          : value == 'icon'
                          ? editIcon(row)
                          : remove(row),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'rename',
                          child: Text('이름 변경'),
                        ),
                        const PopupMenuItem(
                          value: 'icon',
                          child: Text('아이콘 수정'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('목록 삭제'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
