import 'recording_file_status.dart';

final class RecordingCatalog {
  RecordingCatalog({
    required this.scope,
    required this.rows,
    required this.complete,
    this.lastSync,
  });
  final String scope;
  final List<Map<String, dynamic>> rows;
  final bool complete;
  final DateTime? lastSync;
  factory RecordingCatalog.fromSnapshot(
    String scope,
    String userId,
    Map<String, Object?> snapshot,
  ) => RecordingCatalog(
    scope: scope,
    complete: snapshot['complete'] == true,
    lastSync: snapshot['last_sync'] is int
        ? DateTime.fromMillisecondsSinceEpoch(
            snapshot['last_sync'] as int,
            isUtc: true,
          )
        : null,
    rows: (snapshot['rows'] as List)
        .cast<Map<String, dynamic>>()
        .map((row) {
          final evidence = (row['_storage_evidence'] as Map<String, dynamic>)
              .cast<String, Object?>();
          final device = DeviceAudioState.values.byName(
            row['_device_state'] as String,
          );
          final clean = Map<String, dynamic>.of(row)
            ..remove('_storage_evidence')
            ..remove('_device_state');
          return {
            ...clean,
            '_file_status': RecordingFileStatuses.fromEvidence(
              row['id'] as String,
              userId,
              evidence,
              device,
            ),
          };
        })
        .toList(growable: false),
  );
}
