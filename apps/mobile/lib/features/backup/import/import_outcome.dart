import '../../../core/database/account_store.dart';
import '../../../core/domain/identifiers.dart';
import 'import_decision.dart';
import 'import_preflight.dart';

final class ImportOutcome {
  const ImportOutcome({
    required this.information,
    required this.files,
    required this.missingFiles,
    required this.held,
    required this.conflicts,
    required this.pending,
    required this.uploadCandidates,
  });
  final int information, files, missingFiles, held, conflicts, pending;
  final Set<String> uploadCandidates;
  bool get complete =>
      missingFiles == 0 && held == 0 && conflicts == 0 && pending == 0;
}

/// Current server roles only. Old ZIP roles never participate in this set.
Set<String> importUploadTargets({
  required String owner,
  required List<Map<String, dynamic>> currentRows,
  required Set<String> verifiedFiles,
}) {
  final selected = <String>{}, active = <String>{}, stored = <String>{};
  for (final row in currentRows) {
    final p = row['payload'] as Map<String, dynamic>;
    if (p['user_id'] != owner) {
      throw const FormatException('Import policy owner changed');
    }
    final entity = row['entity'], id = row['resource_id'] as String;
    if (entity == 'SONG_CLOUD_SELECTION' || entity == 'PIN_SLOT') {
      for (final field
          in entity == 'PIN_SLOT'
              ? ['current_recording_id', 'pending_recording_id']
              : ['representative_id', 'latest_id', 'lowest_tier_id']) {
        final value = p[field];
        if (value != null) selected.add(UuidValue(value as String).value);
      }
    }
    if (entity == 'RECORDING' &&
        row['tombstone'] != true &&
        p['metadata_state'] == 'SAVED' &&
        p['lifecycle_state'] == 'ACTIVE') {
      active.add(id);
    }
    if (entity == 'RECORDING_ASSET' && p['cloud_state'] == 'STORED') {
      stored.add(id);
    }
  }
  return Set.unmodifiable(
    selected
        .intersection(active)
        .intersection(verifiedFiles)
        .difference(stored),
  );
}

Future<ImportOutcome> readImportOutcome({
  required AccountStore store,
  required ImportConsent consent,
  required String jobId,
  required List<Map<String, dynamic>> plannedRecords,
  required int held,
  required int conflicts,
  required Future<ImportServerBaseline> Function() refreshPolicy,
  required void Function() requireCurrent,
}) async {
  void guard() {
    requireCurrent();
    store.requireActive();
    if (store.userId != consent.source.manifest.sourceUserId) {
      throw StateError('Import account changed');
    }
  }

  guard();
  final results = await store.importApplyResults(jobId);
  guard();
  final verified = <String>{};
  for (final f in consent.source.manifest.files) {
    if (!f.included || f.sha256 == null) continue;
    final disk = await store.inspectImportLocalFile(f.recordingId);
    guard();
    if (disk.exists && disk.checksum == f.sha256) verified.add(f.recordingId);
  }
  final current = await refreshPolicy();
  guard();
  if (current.owner != store.userId) {
    throw StateError('Import policy account changed');
  }
  final targets = importUploadTargets(
    owner: current.owner,
    currentRows: [
      for (final e in current.entries)
        {'entity': e.entity, 'resource_id': e.resourceId, 'payload': e.payload},
    ],
    verifiedFiles: verified,
  );
  // Existing queue discovery still enforces acknowledged SAVED metadata,
  // matching hashes, no pending edits and deletion/mapping fences.
  await store.discoverImportUploads(targets);
  guard();
  final local = await store.captureExportLocal();
  guard();
  final actual = <String>{
    for (final e in current.entries) '${e.entity}/${e.resourceId}',
    for (final c in local['copies'] as List)
      if (c['tombstone'] == 0 &&
          (c['local_payload'] != null || c['server_payload'] != null))
        "${c['entity_type']}/${c['entity_id']}",
  };
  final expected = {
    for (final r in plannedRecords)
      "${r['entity']}/${UuidValue(r['resource_id'] as String).value}",
  };
  final information = expected.intersection(actual);
  final missingInformation = expected.difference(actual).length;
  return ImportOutcome(
    information: information.length,
    files: verified.length,
    missingFiles: consent.source.manifest.files.length - verified.length,
    held: held,
    conflicts: conflicts,
    pending:
        missingInformation +
        results.where((r) => r['status'] != 'APPLIED').length,
    uploadCandidates: targets,
  );
}
