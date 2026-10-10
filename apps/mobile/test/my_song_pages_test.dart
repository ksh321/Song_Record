import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/widgets/sort_sheet.dart';
import 'package:song_record/features/songs/my_song.dart';
import 'package:song_record/features/songs/my_song_pages.dart';

void main() {
  test(
    'all five sorts and both views match independent server shared fixture',
    () {
      final fixture = jsonDecode(
        File('../../fixtures/songs/list-order.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final rows = (fixture['rows'] as List)
          .map(
            (p) => MySong({
              ...Map<String, dynamic>.from(p as Map),
              'version_code': 'NORMAL',
              'lifecycle_state': 'ACTIVE',
            }),
          )
          .toList()
          .reversed
          .toList();
      const names = ['ADDED_DESC', 'RECORDED_DESC', 'TIER', 'TITLE', 'ARTIST'];
      for (final grouped in [false, true]) {
        for (final sort in SongSort.values) {
          final pages = MySongPages()
            ..replace(rows, 'owner-A')
            ..select(search: '', selectedSort: sort, tierView: grouped);
          expect(
            pages.visible.map((s) => s.view.id.value).toList(),
            fixture['expected'][grouped
                ? 'TIER_GROUPED'
                : 'ALL'][names[sort.index]],
            reason: '$grouped/$sort',
          );
          expect(pages.total, 8);
        }
      }
    },
  );
  test('cursor resets for query sort view data and scope; full count remains exact', () {
    final rows = List.generate(
      120,
      (i) => MySong({
        'id': '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
        'title': 'song${i < 70 ? 'match' : 'other'}$i',
        'artist': 'Singer',
        'version_code': 'NORMAL',
        'lifecycle_state': 'ACTIVE',
        'tier': null,
        'created_at': '2026-01-01T00:00:00Z',
      }),
    );
    final pages = MySongPages()..replace(rows, 'A');
    expect(pages.total, 120);
    expect(pages.visible, hasLength(50));
    final first = pages.cursor!;
    pages.next(first);
    expect(pages.visible, hasLength(100));
    expect(() => pages.next(first), throwsStateError);
    final second = pages.cursor!;
    pages.next(second);
    expect(pages.visible, hasLength(120));
    expect(pages.cursor, isNull);
    expect(pages.visible.map((s) => s.view.id).toSet(), hasLength(120));
    pages.select(
      search: 'match',
      selectedSort: SongSort.title,
      tierView: false,
    );
    expect(pages.total, 70);
    expect(pages.visible, hasLength(50));
    expect(() => pages.next(second), throwsStateError);
    final filtered = pages.cursor!;
    pages.select(
      search: 'match',
      selectedSort: SongSort.artist,
      tierView: false,
    );
    expect(() => pages.next(filtered), throwsStateError);
    final sorted = pages.cursor!;
    pages.select(
      search: 'match',
      selectedSort: SongSort.artist,
      tierView: true,
    );
    expect(() => pages.next(sorted), throwsStateError);
    final grouped = pages.cursor!;
    pages.replace([...rows.sublist(1)], 'A');
    expect(() => pages.next(grouped), throwsStateError);
    final changed = pages.cursor!;
    pages.replace(rows, 'B');
    expect(() => pages.next(changed), throwsStateError);
    pages.select(
      search: 'missing',
      selectedSort: SongSort.title,
      tierView: false,
    );
    expect(pages.total, 0);
    expect(pages.visible, isEmpty);
    expect(pages.cursor, isNull);
  });
}
