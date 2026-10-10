import '../../core/database/local_models.dart';
import '../../core/domain/identifiers.dart';
import '../../core/sync/local_repository.dart';
import 'my_song_detail.dart';

typedef RepresentativePreparer = Future<void> Function() Function(
  MySongDetail detail,
  RecordingId? recording,
);

Future<void> Function() prepareRepresentative(
  LocalRepository repository,
  MySongDetail detail,
  RecordingId? recording,
) {
  final original = Map<String, Object?>.unmodifiable(detail.song!.payload);
  if (recording != null && !detail.recordings.any((r) => r.id == recording)) {
    throw ArgumentError('Same-song saved recording required');
  }
  if (original['representative_recording_id'] == recording?.value) {
    return () async {};
  }
  final command = repository.preparePatch(
    entity: LocalEntity.song,
    entityId: detail.song!.view.id.value,
    baseRevision: detail.revision,
    draft: {...original, 'representative_recording_id': recording?.value},
    changes: {'representative_recording_id': recording?.value},
  );
  return () => repository.saveRepresentative(command, original);
}
