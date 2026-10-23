import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../core/database/account_store.dart';
import '../../../core/database/local_models.dart';
import '../../../core/sync/three_way_merge.dart';
import 'import_candidates.dart';
import 'import_decision.dart';
import 'import_preflight.dart';

const importEditableFields = <String, Set<String>>{
  'SONG': {
    'title',
    'artist',
    'version_code',
    'tier',
    'is_suitable',
    'note',
    'representative_key_mode',
    'representative_key_shift',
  },
  'RECORDING': {
    'title_snapshot',
    'artist_snapshot',
    'version_code',
    'key_mode',
    'key_shift',
    'tier',
    'note',
    'recorded_at',
    'timezone_id',
    'timezone_offset_minutes',
    'condition_code',
    'tag_ids',
  },
  'PLAYLIST': {'name', 'icon', 'display_order'},
  'TAG': {'name'},
  'RECORDING_CONDITION': {'name'},
};
String _key(String entity, String id) => '$entity/$id';
bool _equal(Object? a, Object? b) =>
    canonicalJson({'v': a}) == canonicalJson({'v': b});
Map<String, dynamic>? _map(Object? value) =>
    value == null ? null : Map<String, dynamic>.from(value as Map);
Map<String, dynamic>? _stored(Object? value) =>
    value == null ? null : jsonDecode(value as String) as Map<String, dynamic>;
Map<String, dynamic> _changes(
  Map<String, dynamic>? base,
  Map<String, dynamic> local,
  Set<String> fields,
) => {
  for (final f in fields)
    if (local.containsKey(f) &&
        (base == null || !base.containsKey(f) || !_equal(base[f], local[f])))
      f: local[f],
};

final class ImportConflict {
  ImportConflict(
    this.entity,
    this.id,
    this.code,
    Set<String> fields, {
    Map<String, dynamic>? base,
    Map<String, dynamic>? incoming,
    Map<String, dynamic>? server,
    Map<String, dynamic>? destination,
  }) : fields = Set.unmodifiable(fields),
       _values = jsonEncode({
         'base': base,
         'incoming': incoming,
         'server': server,
         'destination': destination,
       });
  final String entity, id, code, _values;
  final Set<String> fields;
  Map<String, dynamic> get values =>
      jsonDecode(_values) as Map<String, dynamic>;
  @override
  String toString() => 'ImportConflict[$code]';
}

final class ImportConflictPreview {
  ImportConflictPreview._(
    this.owner,
    this.localFence,
    List<Map<String, dynamic>> rows,
    List<ImportConflict> conflicts,
    Set<String> files,
    Set<String> reused,
  ) : _rows = jsonEncode(rows),
      conflicts = List.unmodifiable(conflicts),
      fileIds = Set.unmodifiable(files),
      reuseFileIds = Set.unmodifiable(reused);
  final String owner, localFence, _rows;
  final List<ImportConflict> conflicts;
  final Set<String> fileIds, reuseFileIds;
  List<Map<String, dynamic>> get records =>
      (jsonDecode(_rows) as List).cast<Map<String, dynamic>>();
  bool get requiresChoice => conflicts.isNotEmpty;
  @override
  String toString() => 'ImportConflictPreview[REDACTED]';
}

/// Preview only: keeps latest server state and only proposes non-conflicting
/// explicit local changes. No queued operation is replayed or acknowledged.
Future<ImportConflictPreview> previewImportConflicts({
  required ImportConsent consent,
  required ImportCandidatePlan candidates,
  required ImportServerBaseline server,
  required AccountStore store,
  required void Function() requireCurrent,
}) async {
  void guard() {
    requireCurrent();
    store.requireActive();
    if (store.userId != server.owner ||
        consent.source.manifest.sourceUserId != server.owner) {
      throw StateError('Import account changed');
    }
  }

  guard();
  final destination = await store.captureExportLocal();
  guard();
  final original = consent.source.data.toJson();
  final existing = <String, Map<String, dynamic>>{},
      specs = <String, Map<String, dynamic>>{};
  for (final e in server.entries) {
    final payload = e.payload;
    if (payload['user_id'] != server.owner) {
      throw const FormatException('Invalid import owner');
    }
    existing[_key(e.entity, e.resourceId)] = payload;
    if (e.entity == 'RECORDING_FILE_SPEC') specs[e.resourceId] = payload;
  }
  final copies = {
    for (final c in original['local_copies'] as List)
      _key(c['entity'] as String, c['resource_id'] as String):
          c as Map<String, dynamic>,
  };
  final destCopies = {
    for (final c in destination['copies'] as List)
      _key(c['entity_type'] as String, c['entity_id'] as String): c as Map,
  };
  final pending = <String, List<Map<String, dynamic>>>{};
  for (final raw in original['pending_changes'] as List) {
    final p = raw as Map<String, dynamic>;
    pending
        .putIfAbsent(
          _key(p['entity'] as String, p['resource_id'] as String),
          () => [],
        )
        .add(p);
  }
  final conflicts = <ImportConflict>[], rows = <Map<String, dynamic>>[];
  for (final row in candidates.records) {
    final entity = row['entity'] as String,
        id = row['resource_id'] as String,
        key = _key(entity, id),
        payload = row['payload'] as Map<String, dynamic>;
    final remote = existing[key], fields = importEditableFields[entity];
    if (remote == null) {
      final dest = destCopies[key];
      final currentLocal =
          _stored(dest?['local_payload']) ?? _stored(dest?['server_payload']);
      if (currentLocal != null) {
        final compared = {
          ...?fields,
          'source_type',
          'tj_number',
          'song_id',
          'metadata_state',
          'file',
          'tag_ids',
        };
        final different = {
          for (final f in compared)
            if (payload.containsKey(f) && !_equal(currentLocal[f], payload[f]))
              f,
        };
        if (different.isNotEmpty) {
          conflicts.add(
            ImportConflict(
              entity,
              id,
              'LOCAL_ONLY_UUID_CONFLICT',
              different,
              incoming: payload,
              destination: currentLocal,
            ),
          );
          continue;
        }
      }
      rows.add(row);
      continue;
    }
    if (fields == null) {
      continue;
    } // Historical server roles/status never become patches.
    final merged = Map<String, dynamic>.from(remote)..remove('user_id');
    final copy = copies[key], base = _map(copy?['server']);
    final archivedLocal = _map(copy?['local']);
    final changes = archivedLocal == null
        ? <String, dynamic>{}
        : _changes(base, archivedLocal, fields);
    Map<String, dynamic>? comparisonBase = base;
    for (final op in pending[key] ?? const <Map<String, dynamic>>[]) {
      if (op['operation'] != 'PATCH') {
        conflicts.add(
          ImportConflict(entity, id, 'IMPORT_OPERATION_REVIEW', {
            'operation',
          }, incoming: op),
        );
        continue;
      }
      final patch = _map(op['changes'])!;
      final unknown = patch.keys
          .where((k) => k != 'base_revision' && !fields.contains(k))
          .toSet();
      if (unknown.isNotEmpty) {
        conflicts.add(
          ImportConflict(
            entity,
            id,
            'IMPORT_OPERATION_REVIEW',
            unknown,
            incoming: op,
          ),
        );
      }
      changes.addAll({
        for (final f in fields)
          if (patch.containsKey(f)) f: patch[f],
      });
      comparisonBase ??= _map(op['base']);
    }
    final dest = destCopies[key],
        destBase = _stored(dest?['server_payload']),
        destLocal = _stored(dest?['local_payload']);
    final localChanges = destLocal == null
        ? <String, dynamic>{}
        : _changes(destBase, destLocal, fields);
    final competing = {
      for (final f in changes.keys)
        if (localChanges.containsKey(f) && !_equal(changes[f], localChanges[f]))
          f,
    };
    if (competing.isNotEmpty) {
      conflicts.add(
        ImportConflict(
          entity,
          id,
          'DESTINATION_LOCAL_CHANGE',
          competing,
          base: comparisonBase,
          incoming: archivedLocal,
          server: remote,
          destination: destLocal,
        ),
      );
      for (final field in competing) {
        changes.remove(field);
      }
    }
    if (changes.isNotEmpty) {
      try {
        final groups = entity == 'SONG'
            ? [
                {'representative_key_mode', 'representative_key_shift'},
              ]
            : entity == 'RECORDING'
            ? [
                {'key_mode', 'key_shift'},
                {'recorded_at', 'timezone_id', 'timezone_offset_minutes'},
              ]
            : const <Set<String>>[];
        final comparison = compareThreeWayPatch(
          base: comparisonBase,
          localChanges: changes,
          server: remote,
          editableFields: fields,
          atomicGroups: groups,
        );
        merged.addAll(comparison.safePatch);
        for (final group in comparison.conflicts) {
          conflicts.add(
            ImportConflict(
              entity,
              id,
              'REVISION_FIELD_CONFLICT',
              group,
              base: comparisonBase,
              incoming: archivedLocal ?? changes,
              server: remote,
              destination: destLocal,
            ),
          );
        }
      } on FormatException {
        conflicts.add(
          ImportConflict(
            entity,
            id,
            'INVALID_OR_NEWER_BASELINE',
            changes.keys.toSet(),
            base: comparisonBase,
            incoming: archivedLocal ?? changes,
            server: remote,
          ),
        );
      }
    }
    if (entity == 'RECORDING' && payload['song_id'] != remote['song_id']) {
      conflicts.add(
        ImportConflict(
          entity,
          id,
          'RECORDING_LINK_CONFLICT',
          {'song_id'},
          incoming: payload,
          server: remote,
        ),
      );
    }
    rows.add({...row, 'payload': merged});
  }
  final files = candidates.fileIds.toSet(),
      reused = <String>{},
      inspections = <String, Object?>{};
  final manifest = {
    for (final f in consent.source.manifest.files) f.recordingId: f,
  };
  final backupRecords = {
    for (final row
        in (original['records'] as List).cast<Map<String, dynamic>>())
      if (row['entity'] == 'RECORDING')
        row['resource_id'] as String: row['payload'] as Map,
  };
  for (final id in candidates.fileIds) {
    guard();
    final file = manifest[id]!;
    final old = await store.inspectImportLocalFile(id);
    guard();
    inspections[id] = {'exists': old.exists, 'checksum': old.checksum};
    String? code;
    final backupSpec = backupRecords[id]?['file'];
    if (backupSpec is Map &&
        ((backupSpec['sha256'] != null &&
                backupSpec['sha256'] != file.sha256) ||
            (backupSpec['size_bytes'] != null &&
                backupSpec['size_bytes'] != file.sizeBytes))) {
      code = 'BACKUP_FILE_DESCRIPTION_MISMATCH';
    }
    final remoteSpec = specs[id];
    if (remoteSpec != null &&
        (remoteSpec['sha256'] != file.sha256 ||
            remoteSpec['size_bytes'] != file.sizeBytes ||
            remoteSpec['duration_ms'] != file.durationMs)) {
      code = 'SERVER_FILE_DESCRIPTION_MISMATCH';
    }
    if (old.exists && old.checksum != file.sha256) {
      code = 'LOCAL_FILE_CHECKSUM_CONFLICT';
    }
    if (code != null) {
      files.remove(id);
      conflicts.add(
        ImportConflict(
          'RECORDING',
          id,
          code,
          {'file'},
          incoming: file.toJson(),
          server: remoteSpec,
          destination: {'exists': old.exists, 'checksum': old.checksum},
        ),
      );
    } else if (old.exists) {
      reused.add(id);
    }
  }
  final fence = sha256
      .convert(
        utf8.encode(
          canonicalJson({
            'owner': store.userId,
            'copies': destination['copies'],
            'changes': destination['changes'],
            'recording_inputs': destination['recording_inputs'],
            'files': inspections,
          }),
        ),
      )
      .toString();
  guard();
  return ImportConflictPreview._(
    server.owner,
    fence,
    rows,
    conflicts,
    files,
    reused,
  );
}
