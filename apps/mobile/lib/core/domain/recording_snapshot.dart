import 'package:song_record/core/domain/identifiers.dart';
import 'package:song_record/core/domain/song_types.dart';

final class RecordingSnapshot {
  RecordingSnapshot({
    required this.id,
    required this.songId,
    required this.title,
    required this.artist,
    required this.key,
    required this.version,
    required this.note,
    required DateTime recordedAt,
    required this.timezoneId,
    required this.timezoneOffsetMinutes,
  }) : recordedAt = recordedAt.toUtc() {
    if (title.isEmpty || artist.isEmpty) {
      throw ArgumentError('저장 완료된 녹음의 곡명과 가수는 필수입니다.');
    }
    if (timezoneOffsetMinutes < -1080 || timezoneOffsetMinutes > 1080) {
      throw RangeError.range(
        timezoneOffsetMinutes,
        -1080,
        1080,
        'timezoneOffsetMinutes',
      );
    }
  }

  final RecordingId id;
  final SongId? songId;
  final String title;
  final String artist;
  final MusicalKey key;
  final VersionCode version;
  final String note;
  final DateTime recordedAt;
  final String timezoneId;
  final int timezoneOffsetMinutes;

  RecordingSnapshot relink(SongId? nextSongId) => RecordingSnapshot(
    id: id,
    songId: nextSongId,
    title: title,
    artist: artist,
    key: key,
    version: version,
    note: note,
    recordedAt: recordedAt,
    timezoneId: timezoneId,
    timezoneOffsetMinutes: timezoneOffsetMinutes,
  );
}
