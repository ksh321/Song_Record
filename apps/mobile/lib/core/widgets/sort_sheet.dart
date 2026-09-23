import 'package:flutter/material.dart';
import 'package:song_record/core/widgets/selection_sheet.dart';

/// Selection identifiers only. Sorting domain records is the caller's job.
enum SongSort {
  recentlyAdded('최근 추가순'),
  recentlyRecorded('최근 녹음순'),
  tier('티어순'),
  title('곡명순'),
  artist('가수순');

  const SongSort(this.label);
  final String label;
}

enum RecordingSort {
  newest('최신순'),
  oldest('오래된순'),
  title('곡명순'),
  tier('티어순');

  const RecordingSort(this.label);
  final String label;
}

abstract final class SortSheet {
  static Future<SelectionResult<SongSort>?> songs({
    required BuildContext context,
    required SongSort selected,
  }) => showSelectionSheet<SongSort>(
    context: context,
    title: '내 곡 정렬',
    selected: selected,
    options: [
      for (final value in SongSort.values) SelectionOption(value, value.label),
    ],
  );

  static Future<SelectionResult<RecordingSort>?> recordings({
    required BuildContext context,
    required RecordingSort selected,
  }) => showSelectionSheet<RecordingSort>(
    context: context,
    title: '녹음 정렬',
    selected: selected,
    options: [
      for (final value in RecordingSort.values)
        SelectionOption(value, value.label),
    ],
  );
}
