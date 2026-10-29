import 'package:flutter/material.dart';

import '../../core/domain/song_types.dart';
import '../../core/files/recording_file_status.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/editable_collection.dart';
import '../../core/widgets/music_view_data.dart';
import '../../core/widgets/recording_row.dart';
import '../../core/widgets/ui_controls.dart';
import '../songs/my_song_detail.dart';
import 'recording_filter.dart';
import 'recording_navigation.dart';
import 'recording_order.dart';
import 'recording_pages.dart';

export 'recording_order.dart';

class RecordingList extends StatefulWidget {
  const RecordingList({
    required this.rows,
    required this.onOpen,
    this.scope = 'test',
    this.metadataComplete = true,
    this.lastSync,
    this.onDelete,
    super.key,
  });
  final Future<bool> Function(List<Map<String, dynamic>>)? onDelete;
  final String scope;
  final bool metadataComplete;
  final DateTime? lastSync;
  final List<Map<String, dynamic>> rows;
  final void Function(Map<String, dynamic>) onOpen;
  @override
  State<RecordingList> createState() => _RecordingListState();
}

class _RecordingListState extends State<RecordingList> {
  final pages = RecordingPages();
  String query = '';
  @override
  void didUpdateWidget(RecordingList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope) {
      query = '';
      filter = RecordingFilter();
      sort = RecordingSort.newest;
    }
  }

  RecordingSort sort = RecordingSort.newest;
  RecordingFilter filter = RecordingFilter();
  Future<void> chooseFilter() async {
    final scope = widget.scope;
    final selected = await Navigator.push<RecordingFilter>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            RecordingFilterScreen(initial: filter, rows: widget.rows),
      ),
    );
    if (mounted && widget.scope == scope && selected != null) {
      setState(() => filter = selected);
    }
  }

  Future<void> chooseSort() async {
    final scope = widget.scope;
    final selected = await showModalBottomSheet<RecordingSort>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final value in RecordingSort.values)
              ListTile(
                title: Text(value.label),
                trailing: value == sort ? const AppIcon(Icons.check) : null,
                onTap: () => Navigator.pop(context, value),
              ),
          ],
        ),
      ),
    );
    if (mounted && widget.scope == scope && selected != null) {
      setState(() => sort = selected);
    }
  }

  RecordingViewData recordingView(Map<String, dynamic> row) {
    final view = MySongDetail.recordingView(row);
    final status = row['_file_status'] as RecordingFileStatus?;
    return status == null ? view : view.withFileStatus(status);
  }

  void play(Map<String, dynamic> row, {bool autoplay = true}) =>
      openRecordingPlayback(
        context,
        recordingView(row),
        autoplay: autoplay,
        onDetails: () => widget.onOpen(row),
      );

  @override
  Widget build(BuildContext context) {
    final search = query.trim().toLowerCase();
    pages.replace(
      search.isEmpty
          ? widget.rows
          : widget.rows
                .where(
                  (row) =>
                      '${row['title_snapshot'] ?? ''} ${row['artist_snapshot'] ?? ''}'
                          .toLowerCase()
                          .contains(search),
                )
                .toList(),
      widget.scope,
      complete: widget.metadataComplete,
      lastSync: widget.lastSync,
    );
    pages.select(filter, sort);
    final rows = pages.visible, unknown = pages.unknownFiles > 0;
    final exact = widget.metadataComplete && !unknown;
    final byId = {for (final row in pages.ordered) row['id'] as String: row};
    return EditableCollection(
      key: ValueKey(widget.scope),
      showScrollToTop: true,
      ids: rows.map((r) => r['id'] as String).toList(),
      selectionIds: pages.ordered.map((r) => r['id'] as String).toList(),
      selectionEnabled: widget.onDelete != null,
      onDelete: (ids) =>
          widget.onDelete?.call([
            for (final id in ids)
              if (byId[id] != null) byId[id]!,
          ]) ??
          Future.value(false),
      deleteLabel: (count) => '선택한 $count개 녹음 삭제',
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSearchField(
            fieldKey: ValueKey(widget.scope),
            hint: '녹음의 곡명 또는 가수 검색',
            onChanged: (value) => setState(() => query = value),
          ),
          const SizedBox(height: 12),
          if (!widget.metadataComplete)
            const Text('동기화 중 · 전체 개수는 아직 확정되지 않았어요.'),

          if (unknown) const Text('파일 상태 확인 불가 · 결과 개수를 아직 확정할 수 없어요.'),
          if (rows.isEmpty && exact)
            Text(
              filter.count == 0 && search.isEmpty
                  ? '저장된 녹음이 없습니다'
                  : '조건에 맞는 녹음이 없습니다',
            ),
        ],
      ),
      actions: (_, _) => Row(
        children: [
          Expanded(
            child: Text(
              exact ? '저장 녹음 ${pages.total}개' : '현재 확인된 ${pages.total}개',
            ),
          ),
          TextButton.icon(
            onPressed: chooseFilter,
            icon: const AppIcon(Icons.filter_list),
            label: Text('필터 ${filter.count}'),
          ),
          TextButton.icon(
            onPressed: chooseSort,
            icon: const AppIcon(Icons.sort),
            label: Text(sort.label),
          ),
        ],
      ),
      row: (id) {
        final row = byId[id]!;
        return RecordingRow(
          recording: recordingView(row),
          onTap: () => widget.onOpen(row),
          onPlay: () => play(row),
        );
      },
      footer: pages.cursor == null
          ? const SizedBox.shrink()
          : TextButton(
              onPressed: () => setState(() {
                final cursor = pages.cursor;
                if (cursor != null) pages.next(cursor);
              }),
              child: Text('다음 ${pages.limit}개'),
            ),
    );
  }
}

String recordingSummary(Map<String, dynamic> row) {
  final date = DateTime.parse(row['recorded_at'] as String)
      .toUtc()
      .add(const Duration(hours: 9));
  final key = MusicalKey(
    mode: KeyMode.values.firstWhere(
      (v) => v.name.toUpperCase() == row['key_mode'],
    ),
    shift: row['key_shift'] as int,
  );
  final version = VersionCode.values.firstWhere(
    (v) => v.name.toUpperCase() == row['version_code'],
  );
  final status = row['_file_status'] as RecordingFileStatus?;
  return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} · ${formatVersionCode(version)} · ${formatMusicalKey(key)}\n${status?.deviceLabel ?? '이 기기 파일: 확인 중'} · ${status?.serverLabel ?? '서버 파일: 확인 중'}';
}

String formatSyncTime(DateTime utc) {
  final t = utc.toUtc().add(const Duration(hours: 9));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}/${two(t.month)}/${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
