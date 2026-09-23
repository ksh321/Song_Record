import 'package:song_record/core/domain/identifiers.dart';
import 'package:song_record/core/domain/recording_snapshot.dart';
import 'package:song_record/core/domain/song_types.dart';

/// Read-only presentation data. Callers supply validated domain/account data.
class RegisteredSongViewData {
  const RegisteredSongViewData({
    required this.id,
    required this.title,
    required this.artist,
    required this.version,
    this.tjNumber,
    this.musicalKey,
    this.tier,
    this.note = '',
  });

  final SongId id;
  final String title;
  final String artist;
  final VersionCode version;
  final TjNumber? tjNumber;
  final MusicalKey? musicalKey;
  final SongTier? tier;
  final String note;
}

enum CatalogBrand { tj, ky }

enum CandidatePlacement { search, chart, playlist }

/// A catalog candidate has no personal version, key or tier fields.
class CandidateSongViewData {
  CandidateSongViewData({
    required this.brand,
    required String number,
    required this.title,
    required this.artist,
  }) : number = _validateNumber(number);

  final CatalogBrand brand;
  final String number;
  final String title;
  final String artist;

  String get sourceLabel => '${brand == CatalogBrand.tj ? "TJ" : "금영"} $number';

  static String _validateNumber(String value) {
    if (!RegExp(r'^\d{1,20}$').hasMatch(value)) {
      throw ArgumentError.value(value, 'number', '숫자 문자열을 전달하세요.');
    }
    return value; // Preserve leading zeroes and source identity.
  }
}

/// Actual availability supplied by the caller, never inferred from role selection.
/// Upload/retention decisions remain in their own domain/service layer.
enum RecordingFileAvailability {
  localOnly('이 기기에 파일 있음'),
  cloudOnly('서버에 파일 있음 · 이 기기에 없음'),
  localAndCloud('이 기기·서버에 파일 있음'),
  metadataOnly('파일 없음 · 정보만'),
  unknown('파일 상태 확인 중');

  const RecordingFileAvailability(this.label);
  final String label;
}

class RecordingViewData {
  RecordingViewData({
    required this.snapshot,
    required this.duration,
    required this.fileAvailability,
    this.tier,
  }) {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', '길이는 음수일 수 없습니다.');
    }
  }

  final RecordingSnapshot snapshot;
  final Duration duration;
  final RecordingFileAvailability fileAvailability;
  final RecordingTier? tier;

  RecordingId get id => snapshot.id;

  /// Preserve the recording's captured local time, not the viewer's timezone.
  String get dateLabel {
    final time = snapshot.recordedAt.toUtc().add(
      Duration(minutes: snapshot.timezoneOffsetMinutes),
    );
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}.${two(time.month)}.${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  String get durationLabel =>
      '${duration.inMinutes.toString().padLeft(2, "0")}:'
      '${(duration.inSeconds % 60).toString().padLeft(2, "0")}';
}
