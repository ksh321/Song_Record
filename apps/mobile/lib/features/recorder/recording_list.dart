import 'package:flutter/material.dart';

import '../../core/domain/song_types.dart';
import '../../core/files/recording_file_status.dart';

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
      RecordingSort.title => (a['title_snapshot'] as String).compareTo(
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
    final rows = sortRecordings(widget.rows, sort);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('저장 녹음 ${rows.length}개')),
            TextButton.icon(
              onPressed: chooseSort,
              icon: const Icon(Icons.sort),
              label: Text(sort.label),
            ),
          ],
        ),
        if (rows.isEmpty) const Text('저장된 녹음이 없습니다'),
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
      .add(Duration(minutes: row['timezone_offset_minutes'] as int? ?? 0));
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
