import '../../core/domain/domain_ordering.dart';
import '../../core/domain/identifiers.dart';
import '../../core/domain/recording_snapshot.dart';
import '../../core/domain/song_types.dart';
import '../../core/files/recording_file_status.dart';
import '../../core/widgets/music_view_data.dart';
import 'my_song.dart';

final class MySongDetail {
  MySongDetail(Map<String, dynamic> bundle)
    : song = bundle['song'] == null
          ? null
          : MySong(Map<String, dynamic>.from(bundle['song'] as Map)),
      revision = bundle['revision'] as int,
      recordings = [
        for (final r in bundle['recordings'] as List)
          _recording(Map<String, dynamic>.from(r as Map)),
      ];
  MySongDetail._(this.song, this.revision, this.recordings);
  static Future<MySongDetail> verified(
    Map<String, dynamic> bundle,
    Future<RecordingFileStatus> Function(String id) readStatus,
  ) async {
    final value = MySongDetail(bundle);
    final checked = <RecordingViewData>[];
    for (final r in value.recordings) {
      checked.add(r.withFileStatus(await readStatus(r.id.value)));
    }
    return MySongDetail._(value.song, value.revision, checked);
  }

  RecordingSelection get roles => selectRecordingRoles(
    [
      for (final r in recordings)
        RecordingCandidate(
          id: r.id,
          recordedAt: r.snapshot.recordedAt,
          tier: r.tier,
        ),
    ],
    representativeId: song?.payload['representative_recording_id'] == null
        ? null
        : RecordingId(song!.payload['representative_recording_id'] as String),
  );

  final MySong? song;
  final int revision;
  final List<RecordingViewData> recordings;

  static RecordingViewData _recording(Map<String, dynamic> p) {
    final spec = p['file_spec'] as Map? ?? p['file'] as Map?;
    final ms = spec?['duration_ms'] as int?;
    return RecordingViewData(
      snapshot: RecordingSnapshot(
        id: RecordingId(p['id'] as String),
        songId: p['song_id'] == null ? null : SongId(p['song_id'] as String),
        title: p['title_snapshot'] as String,
        artist: p['artist_snapshot'] as String,
        key: MusicalKey(
          mode: KeyMode.values.byName((p['key_mode'] as String).toLowerCase()),
          shift: p['key_shift'] as int,
        ),
        version: VersionCode.values.byName(
          (p['version_code'] as String).toLowerCase(),
        ),
        note: p['note'] as String? ?? '',
        recordedAt: DateTime.parse(p['recorded_at'] as String),
        timezoneId: p['timezone_id'] as String,
        timezoneOffsetMinutes: p['timezone_offset_minutes'] as int,
      ),
      duration: Duration(milliseconds: ms ?? 0),
      durationKnown: ms != null,
      fileAvailability: RecordingFileAvailability.unknown,
      tier: p['tier'] == null
          ? null
          : RecordingTier.values.byName((p['tier'] as String).toLowerCase()),
    );
  }
}
