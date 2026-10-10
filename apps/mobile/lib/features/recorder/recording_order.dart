import '../../core/domain/domain_ordering.dart';

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
