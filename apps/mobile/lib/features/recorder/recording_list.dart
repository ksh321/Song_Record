import 'package:flutter/material.dart';

import '../../core/domain/song_types.dart';
import '../../core/files/recording_file_status.dart';
import 'recording_filter.dart';
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
    super.key,
  });
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
  @override
  void didUpdateWidget(RecordingList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope) {
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
                trailing: value == sort ? const Icon(Icons.check) : null,
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

  @override
  Widget build(BuildContext context) {
    pages.replace(
      widget.rows,
      widget.scope,
      complete: widget.metadataComplete,
      lastSync: widget.lastSync,
    );
    pages.select(filter, sort);
    final rows = pages.visible, unknown = pages.unknownFiles > 0;
    final exact = widget.metadataComplete && !unknown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                exact ? '저장 녹음 ${pages.total}개' : '현재 확인된 ${pages.total}개',
              ),
            ),
            TextButton.icon(
              onPressed: chooseFilter,
              icon: const Icon(Icons.filter_list),
              label: Text('필터 ${filter.count}'),
            ),
            TextButton.icon(
              onPressed: chooseSort,
              icon: const Icon(Icons.sort),
              label: Text(sort.label),
            ),
          ],
        ),
        if (!widget.metadataComplete)
          const Text('동기화 중 · 전체 개수는 아직 확정되지 않았어요.'),
        Text(
          '로컬 정보 기준 · 마지막 동기화: ${widget.lastSync == null ? '확인된 기록 없음' : formatSyncTime(widget.lastSync!)}',
        ),
        if (unknown) const Text('파일 상태 확인 불가 · 결과 개수를 아직 확정할 수 없어요.'),
        if (rows.isEmpty && exact)
          Text(filter.count == 0 ? '저장된 녹음이 없습니다' : '조건에 맞는 녹음이 없습니다'),
        for (final row in rows)
          ListTile(
            key: ValueKey(row['id']),
            title: Text('${row['title_snapshot']} · ${row['artist_snapshot']}'),
            subtitle: Text(recordingSummary(row)),
            isThreeLine: true,
            trailing: Text(row['tier'] as String? ?? '미정'),
            onTap: () => widget.onOpen(row),
          ),
        if (pages.cursor != null)
          TextButton(
            onPressed: () => setState(() {
              final cursor = pages.cursor;
              if (cursor != null) pages.next(cursor);
            }),
            child: Text('다음 ${pages.limit}개'),
          ),
      ],
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
