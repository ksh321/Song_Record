import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/domain/identifiers.dart';
import 'package:song_record/core/domain/input_validation.dart';
import 'package:song_record/core/domain/song_types.dart';
import 'package:song_record/core/domain/state_types.dart';

void main() {
  test('식별자는 UUID와 TJ 선행 0을 보존한다', () {
    final song = SongId('00000000-0000-4000-8000-0000000000AA');
    final recording = RecordingId('00000000-0000-4000-8000-0000000000ab');
    expect(song.value, endsWith('00aa'));
    expect(SongId.fromBytes(song.bytes), song);
    expect(song.compareTo(SongId(recording.value)), lessThan(0));
    expect(TjNumber(' 00123 ').value, '00123');
    expect(TjNumber('00123'), isNot(TjNumber('123')));
  });

  test('녹음 상태 축은 서로 다른 타입으로 유지한다', () {
    expect(LocalState.values, contains(LocalState.inputPending));
    expect(MetadataState.values, contains(MetadataState.saved));
    expect(SyncState.values, contains(SyncState.pending));
    expect(CloudState.values, contains(CloudState.verifying));
    expect(BlockedReason.values, contains(BlockedReason.fileMissing));
    expect(LifecycleState.values, contains(LifecycleState.purgePending));
  });

  test('키와 버전 표시 계약을 지킨다', () {
    expect(formatVersionCode(VersionCode.normal), '일반 반주');
    expect(formatMusicalKey(MusicalKey.original), '원키');
    expect(
      formatMusicalKey(MusicalKey(mode: KeyMode.male, shift: 0)),
      '남 0',
    );
    expect(
      formatMusicalKey(MusicalKey(mode: KeyMode.female, shift: 1)),
      '여 +1',
    );
    expect(() => MusicalKey(mode: KeyMode.original, shift: 13), throwsRangeError);
    expect(formatSongTier(null), '미정');
    expect(formatRecordingTier(RecordingTier.s), 'S');
  });

  test('공통 입력 fixture를 코드 포인트 기준으로 검증한다', () async {
    final file = File('../../fixtures/contracts/input.json');
    final root = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    final cases = root['cases']! as List<Object?>;

    for (final rawCase in cases) {
      final testCase = rawCase! as Map<String, Object?>;
      final input = testCase['input']! as Map<String, Object?>;
      final expected = testCase['expected']! as Map<String, Object?>;
      final field = switch (input['field']) {
        'title' => InputField.title,
        'artist' => InputField.artist,
        'note' => InputField.note,
        'tag' => InputField.tag,
        'condition' => InputField.condition,
        'playlist' => InputField.playlist,
        final value => throw StateError('Unknown field: $value'),
      };
      final result = validateInput(field, input['value']! as String);
      expect(result.actual, expected['actual'], reason: testCase['id'] as String);
      expect(result.isValid, expected['valid'], reason: testCase['id'] as String);
    }
  });
}
