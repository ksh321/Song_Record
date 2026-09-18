enum VersionCode { normal, mr, live }

enum KeyMode { original, male, female }

enum SongTier { s, a, b, c, d }

enum RecordingTier { s, a, b, c, d }

final class MusicalKey {
  const MusicalKey._(this.mode, this.shift);

  factory MusicalKey({required KeyMode mode, required int shift}) {
    if (shift < -12 || shift > 12) {
      throw RangeError.range(shift, -12, 12, 'shift');
    }
    if (mode == KeyMode.original && shift != 0) {
      throw ArgumentError.value(shift, 'shift', '원키의 이동값은 0이어야 합니다.');
    }
    return MusicalKey._(mode, shift);
  }

  static const original = MusicalKey._(KeyMode.original, 0);

  final KeyMode mode;
  final int shift;
}

String formatVersionCode(VersionCode version) => switch (version) {
  VersionCode.normal => '일반 반주',
  VersionCode.mr => 'MR',
  VersionCode.live => 'LIVE',
};

String formatMusicalKey(MusicalKey key) {
  final mode = switch (key.mode) {
    KeyMode.original => '원키',
    KeyMode.male => '남',
    KeyMode.female => '여',
  };
  if (key.mode == KeyMode.original && key.shift == 0) return mode;
  final shift = key.shift > 0 ? '+${key.shift}' : '${key.shift}';
  return '$mode $shift';
}

String formatSongTier(SongTier? tier) => tier?.name.toUpperCase() ?? '미정';

String formatRecordingTier(RecordingTier? tier) =>
    tier?.name.toUpperCase() ?? '미정';
