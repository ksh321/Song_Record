import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/domain/domain_ordering.dart';
import 'package:song_record/core/domain/identifiers.dart';
import 'package:song_record/core/domain/recording_defaults.dart';
import 'package:song_record/core/domain/recording_snapshot.dart';
import 'package:song_record/core/domain/song_types.dart';

void main() {
  test('재연결은 당시 녹음 스냅샷을 바꾸지 않는다', () {
    final firstSong = SongId('00000000-0000-4000-8000-000000000010');
    final nextSong = SongId('00000000-0000-4000-8000-000000000011');
    final snapshot = RecordingSnapshot(
      id: RecordingId('00000000-0000-4000-8000-000000000001'),
      songId: firstSong,
      title: '당시 곡명',
      artist: '당시 가수',
      key: MusicalKey(mode: KeyMode.female, shift: 1),
      version: VersionCode.live,
      note: '당시 메모',
      recordedAt: DateTime.parse('2026-09-18T01:00:00+09:00'),
      timezoneId: 'Asia/Seoul',
      timezoneOffsetMinutes: 540,
    );

    final relinked = snapshot.relink(nextSong);
    expect(relinked.songId, nextSong);
    expect(relinked.title, snapshot.title);
    expect(relinked.artist, snapshot.artist);
    expect(relinked.key, snapshot.key);
    expect(relinked.version, snapshot.version);
    expect(relinked.note, snapshot.note);
    expect(relinked.recordedAt, snapshot.recordedAt);
  });

  test('곡 변경은 사용자가 수정하지 않은 기본값만 바꾼다', () {
    final first = SongRecordingDefaults(
      songId: SongId('00000000-0000-4000-8000-000000000010'),
      version: VersionCode.mr,
      representativeKey: MusicalKey(mode: KeyMode.male, shift: -1),
    );
    final next = SongRecordingDefaults(
      songId: SongId('00000000-0000-4000-8000-000000000011'),
      version: VersionCode.live,
      representativeKey: MusicalKey(mode: KeyMode.female, shift: 2),
    );

    var state = RecordingDefaultState.initial().selectSong(first);
    state = state.editKey(MusicalKey(mode: KeyMode.male, shift: 3));
    final selected = state.selectSong(next);
    expect(selected.key, MusicalKey(mode: KeyMode.male, shift: 3));
    expect(selected.version, VersionCode.live);
    expect(selected.keyEdited, isTrue);
    expect(selected.versionEdited, isFalse);

    final reset = selected.applySongDefaults(next);
    expect(reset.key, next.representativeKey);
    expect(reset.version, next.version);
    expect(reset.keyEdited, isFalse);
    expect(reset.versionEdited, isFalse);
  });

  test('SR-SORT-1 공통 fixture 순서와 일치한다', () async {
    final root = jsonDecode(
      await File('../../fixtures/contracts/sorting.json').readAsString(),
    ) as Map<String, Object?>;
    for (final rawCase in root['cases']! as List<Object?>) {
      final testCase = rawCase! as Map<String, Object?>;
      final input = testCase['input']! as Map<String, Object?>;
      final expected = testCase['expected']! as Map<String, Object?>;
      final rows = (input['rows']! as List<Object?>).map((raw) {
        final row = raw! as Map<String, Object?>;
        return TitleSortRow(
          id: SongId(row['id']! as String),
          title: row['title']! as String,
        );
      });
      final actual = sortByTitle(rows).map((row) => row.id.value).toList();
      expect(actual, expected['ids'], reason: testCase['id']! as String);
    }
    expect(compareSortText('가', '가'), 0);
  });

  test('대표·최신·최저 티어 선정 fixture와 일치한다', () async {
    final root = jsonDecode(
      await File('../../fixtures/retention/selection.json').readAsString(),
    ) as Map<String, Object?>;
    for (final rawCase in root['cases']! as List<Object?>) {
      final testCase = rawCase! as Map<String, Object?>;
      final input = testCase['input']! as Map<String, Object?>;
      final candidates = (input['recordings']! as List<Object?>).map((raw) {
        final candidate = raw! as Map<String, Object?>;
        return RecordingCandidate(
          id: RecordingId(candidate['id']! as String),
          recordedAt: DateTime.parse(candidate['recorded_at']! as String),
          tier: _tier(candidate['tier'] as String?),
          eligible: candidate['lifecycle'] == 'ACTIVE' &&
              candidate['metadata'] == 'SAVED' &&
              candidate['valid_file_manifest'] == true,
        );
      });
      final representative = input['representative_id'] as String?;
      final result = selectRecordingRoles(
        candidates,
        representativeId: representative == null
            ? null
            : RecordingId(representative),
      );
      final expected = testCase['expected']! as Map<String, Object?>;
      expect(result.representative?.value, expected['representative']);
      expect(result.latest?.value, expected['latest']);
      expect(result.lowestTier?.value, expected['lowest']);
      final expectedIds =
          (expected['unique_ids']! as List<Object?>).cast<String>().toSet();
      final actualIds = result.uniqueIds.map((id) => id.value).toSet();
      expect(actualIds.length, expectedIds.length);
      expect(actualIds.containsAll(expectedIds), isTrue);
    }
  });
}

RecordingTier? _tier(String? value) => switch (value) {
  null => null,
  'S' => RecordingTier.s,
  'A' => RecordingTier.a,
  'B' => RecordingTier.b,
  'C' => RecordingTier.c,
  'D' => RecordingTier.d,
  final value => throw StateError('Unknown tier: $value'),
};
