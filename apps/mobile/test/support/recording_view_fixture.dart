import 'package:song_record/core/files/recording_file_status.dart';

/// Complete the compact filtering fixtures with the wire fields used by rows.
Map<String, dynamic> recordingViewFixture(Map<String, dynamic> row) {
  String uuid(String value) => value.length == 36
      ? value
      : '00000000-0000-4000-8000-${value.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0')).join().padLeft(12, '0')}';
  final status = row['_file_status'] as RecordingFileStatus?;
  return {
    ...row,
    'id': uuid(row['id'] as String),
    'song_id': row['song_id'] == null ? null : uuid(row['song_id'] as String),
    'timezone_id': 'Asia/Seoul',
    'timezone_offset_minutes': row['timezone_offset_minutes'] ?? 540,
    if (status != null)
      '_file_status': RecordingFileStatus(
        recording: uuid(row['id'] as String),
        information: status.information,
        device: status.device,
        serverState: status.serverState,
        blockedReason: status.blockedReason,
        pinCurrent: status.pinCurrent,
        pinPending: status.pinPending,
      ),
  };
}
