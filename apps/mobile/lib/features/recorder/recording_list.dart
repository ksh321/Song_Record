import 'package:flutter/material.dart';

import '../../core/domain/domain_ordering.dart';
import '../../core/domain/song_types.dart';
import '../../core/files/recording_file_status.dart';
import 'recording_filter.dart';

enum RecordingSort {
  newest('최신순'),
  oldest('오래된순'),
  title('곡명순'),
  tier('티어순');

  const RecordingSort(this.label);
  final String label;
}

List<Map<String, dynamic>> sortRecordings(
  List<Map<String, dynamic>> source,
  RecordingSort sort,
) {
  int latest(Map<String, dynamic> a, Map<String, dynamic> b) =>
      DateTime.parse(b['recorded_at'] as String)
          .compareTo(DateTime.parse(a['recorded_at'] as String));
  int tier(Object? value) =>
      const <Object?>['S', 'A', 'B', 'C', 'D', null].indexOf(value);
  final rows = List<Map<String, dynamic>>.of(source);
  rows.sort((a, b) {
    var result = switch (sort) {
      RecordingSort.newest => latest(a, b),
      RecordingSort.oldest => -latest(a, b),
      RecordingSort.title => compareSortText(
        a['title_snapshot'] as String,
        b['title_snapshot'] as String,
      ),
      RecordingSort.tier => tier(a['tier']).compareTo(tier(b['tier'])),
    };
    if (result == 0) result = latest(a, b);
    return result != 0
        ? result
        : (a['id'] as String).compareTo(b['id'] as String);
  });
  return rows;
}

class RecordingList extends StatefulWidget {
  const RecordingList({required this.rows, required this.onOpen, super.key});
  final List<Map<String, dynamic>> rows;
  final void Function(Map<String, dynamic>) onOpen;
  @override
  State<RecordingList> createState() => _RecordingListState();
}

class _RecordingListState extends State<RecordingList> {
  RecordingSort sort = RecordingSort.newest;
  RecordingFilter filter = RecordingFilter();
  Future<void> chooseFilter() async {
    final selected = await Navigator.push<RecordingFilter>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            RecordingFilterScreen(initial: filter, rows: widget.rows),
      ),
    );
    if (mounted && selected != null) setState(() => filter = selected);
  }

  Future<void> chooseSort() async {
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
    if (mounted && selected != null) setState(() => sort = selected);
  }

  @override
  Widget build(BuildContext context) {
    final rows = sortRecordings(
      widget.rows.where(filter.matches).toList(),
      sort,
    );
    final withoutFile = RecordingFilter(Map.of(filter.values)..remove('file'));
    final unknown =
        filter.values.containsKey('file') &&
        widget.rows.where(withoutFile.matches).any((r) {
          final status = r['_file_status'] as RecordingFileStatus?;
          return status == null ||
              status.device == DeviceAudioState.unknown ||
              status.serverState == 'UNKNOWN';
        });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                unknown ? '현재 확인된 ${rows.length}개' : '저장 녹음 ${rows.length}개',
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
        if (unknown) const Text('파일 상태 확인 불가 · 결과 개수를 아직 확정할 수 없어요.'),
        if (rows.isEmpty && !unknown)
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
