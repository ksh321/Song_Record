import 'dart:convert';

import '../../../core/domain/identifiers.dart';
import 'import_decision.dart';
import 'import_preflight.dart';

final class ImportIdentityIssue {
  const ImportIdentityIssue(this.entity, this.id, this.code);
  final String entity, id, code;
  @override
  String toString() => 'ImportIdentityIssue[$code]';
}

final class ImportIdentityPlan {
  ImportIdentityPlan._(
    List<Map<String, dynamic>> rows,
    List<Map<String, dynamic>> inputs,
    Map<String, String> songs,
    Set<String> files,
    List<ImportIdentityIssue> blocked,
    List<ImportIdentityIssue> held,
  ) : _rows = jsonEncode(rows),
      _inputs = jsonEncode(inputs),
      songIds = Map.unmodifiable(songs),
      fileIds = Set.unmodifiable(files),
      blocked = List.unmodifiable(blocked),
      held = List.unmodifiable(held);
  final String _rows, _inputs;
  final Map<String, String> songIds;
  final Set<String> fileIds;
  final List<ImportIdentityIssue> blocked, held;
  List<Map<String, dynamic>> get records =>
      (jsonDecode(_rows) as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get recoveryInputs =>
      (jsonDecode(_inputs) as List).cast<Map<String, dynamic>>();
  @override
  String toString() => 'ImportIdentityPlan[REDACTED]';
}

String _key(String entity, String id) => '$entity/$id';
String _uuid(Object? value) {
  if (value is! String || UuidValue(value).value != value) {
    throw const FormatException('Invalid import identity');
  }
  return value;
}

String? _tj(Map<String, dynamic> payload) {
  if (payload['source_type'] == 'MANUAL' && payload['tj_number'] == null) {
    return null;
  }
  final value = payload['tj_number'];
  if (payload['source_type'] != 'TJ' ||
      value is! String ||
      TjNumber(value).value != value) {
    throw const FormatException('Invalid TJ identity');
  }
  return value;
}

/// Read-only identity plan, not authority to replay historical server state.
/// The caller composes the current account and live choice guard. Actual apply
/// must re-read current server state and enforce later P22 conflict/role policy.
ImportIdentityPlan planImportIdentities({
  required ImportConsent consent,
  required ImportServerBaseline server,
  required void Function() requireCurrent,
}) {
  requireCurrent();
  if (consent.source.manifest.sourceUserId != server.owner) {
    throw const FormatException('Import account mismatch');
  }
  final data = consent.source.data.toJson();
  final current = <String, Map<String, dynamic>>{},
      songs = <String, Map<String, dynamic>>{};
  final ledger = <String>{},
      activeTj = <String, List<String>>{},
      heldTj = <String>{};
  for (final entry in server.entries) {
    final payload = entry.payload;
    if (payload['user_id'] != server.owner) {
      throw const FormatException('Invalid import server owner');
    }
    current[_key(entry.entity, entry.resourceId)] = payload;
    if (entry.entity == 'DELETION_LEDGER') {
      ledger.add(
        _key(payload['entity_type'] as String, _uuid(payload['entity_id'])),
      );
    }
    if (entry.entity == 'SONG') {
      final state = payload['lifecycle_state'];
      if (!{'ACTIVE', 'TRASHED', 'PURGE_PENDING', 'PURGED'}.contains(state)) {
        throw const FormatException('Invalid song state');
      }
      songs[entry.resourceId] = payload;
      final number = _tj(payload);
      if (number != null && state == 'ACTIVE') {
        activeTj.putIfAbsent(number, () => []).add(entry.resourceId);
      }
      if (number != null && {'TRASHED', 'PURGE_PENDING'}.contains(state)) {
        heldTj.add(number);
      }
      if (state == 'PURGED') ledger.add(_key('SONG', entry.resourceId));
    }
    if (payload['lifecycle_state'] == 'PURGED') {
      ledger.add(_key(entry.entity, entry.resourceId));
    }
  }
  final blocked = <ImportIdentityIssue>[], held = <ImportIdentityIssue>[];
  final unavailable = <String>{},
      mapping = <String, String>{},
      remapped = <String>{};
  void block(String entity, String id, String reason) {
    unavailable.add(_key(entity, id));
    blocked.add(ImportIdentityIssue(entity, id, reason));
  }

  void hold(String entity, String id, String reason) {
    unavailable.add(_key(entity, id));
    held.add(ImportIdentityIssue(entity, id, reason));
  }

  final records = (data['records'] as List).cast<Map<String, dynamic>>();
  // Permanent markers win before considering a same-TJ canonical alias.
  for (final row in records) {
    final entity = row['entity'] as String, id = row['resource_id'] as String;
    if (ledger.contains(_key(entity, id))) {
      block(entity, id, 'PERMANENTLY_DELETED_UUID');
    }
  }
  const identityFields = {
    'SONG': 'id',
    'RECORDING': 'id',
    'PLAYLIST': 'id',
    'PLAYLIST_ITEM': 'id',
    'TAG': 'id',
    'RECORDING_CONDITION': 'id',
    'SONG_SOURCE': 'song_id',
    'SONG_CLOUD_SELECTION': 'song_id',
    'RECORDING_FILE_SPEC': 'recording_id',
    'RECORDING_ASSET': 'recording_id',
    'RECORDING_TAG': 'recording_id',
  };
  for (final row in records) {
    final entity = row['entity'] as String, id = row['resource_id'] as String;
    final field = identityFields[entity];
    if (!unavailable.contains(_key(entity, id)) &&
        field != null &&
        row['payload'][field] != id) {
      hold(entity, id, 'IDENTITY_MISMATCH');
    }
  }
  final incomingTj = <String, Set<String>>{};
  for (final row in records.where((r) => r['entity'] == 'SONG')) {
    final id = row['resource_id'] as String;
    if (unavailable.contains(_key('SONG', id))) continue;
    try {
      final number = _tj(row['payload'] as Map<String, dynamic>);
      if (number != null) {
        incomingTj.putIfAbsent(number, () => <String>{}).add(id);
      }
    } on FormatException {
      /* Classified per source row below. */
    }
  }
  for (final row in records.where((r) => r['entity'] == 'SONG')) {
    final id = row['resource_id'] as String;
    if (unavailable.contains(_key('SONG', id))) continue;
    final payload = row['payload'] as Map<String, dynamic>;
    if (payload['id'] != id) {
      hold('SONG', id, 'IDENTITY_MISMATCH');
      continue;
    }
    String? number;
    try {
      number = _tj(payload);
    } on FormatException {
      hold('SONG', id, 'INVALID_SOURCE_IDENTITY');
      continue;
    }
    final existing = songs[id];
    if (existing != null) {
      if (existing['lifecycle_state'] != 'ACTIVE') {
        hold('SONG', id, 'SERVER_LIFECYCLE_HOLD');
        continue;
      }
      if (existing['source_type'] != payload['source_type'] ||
          _tj(existing) != number) {
        hold('SONG', id, 'IDENTITY_MISMATCH');
        continue;
      }
      mapping[id] = id;
      continue;
    }
    if (row['tombstone'] == true ||
        (payload['lifecycle_state'] != null &&
            payload['lifecycle_state'] != 'ACTIVE')) {
      hold('SONG', id, 'BACKUP_LIFECYCLE_HOLD');
      continue;
    }
    if (number != null && heldTj.contains(number)) {
      hold('SONG', id, 'TJ_RESTORE_OR_PURGE_REQUIRED');
      continue;
    }
    if (number != null &&
        (activeTj[number] ?? const <String>[]).isEmpty &&
        (incomingTj[number]?.length ?? 0) > 1) {
      hold('SONG', id, 'AMBIGUOUS_BACKUP_TJ_IDENTITY');
      continue;
    }
    final matches = number == null
        ? const <String>[]
        : activeTj[number] ?? const <String>[];
    if (matches.length > 1) {
      hold('SONG', id, 'AMBIGUOUS_TJ_IDENTITY');
      continue;
    }
    final canonical = matches.isEmpty ? id : matches.single;
    mapping[id] = canonical;
    if (canonical != id) remapped.add(id);
  }
  String? mapSong(Object? value) {
    if (value == null) return null;
    final id = _uuid(value);
    if (ledger.contains(_key('SONG', id)) ||
        unavailable.contains(_key('SONG', id))) {
      throw const FormatException('Held song reference');
    }
    final target = mapping[id];
    if (target != null) return target;
    if (songs[id]?['lifecycle_state'] == 'ACTIVE') return id;
    throw const FormatException('Unresolved song reference');
  }

  final output = <Map<String, dynamic>>[];
  for (final row in records) {
    final entity = row['entity'] as String, id = row['resource_id'] as String;
    if (unavailable.contains(_key(entity, id))) continue;
    final payload = row['payload'] as Map<String, dynamic>;
    if (entity == 'SONG') {
      if (remapped.contains(id)) {
        continue; // Never replace canonical notes/version.
      }
    } else if ({
          'RECORDING',
          'PLAYLIST_ITEM',
          'SONG_SOURCE',
          'SONG_CLOUD_SELECTION',
        }.contains(entity) &&
        payload['song_id'] != null) {
      final original = payload['song_id'];
      try {
        payload['song_id'] = mapSong(original);
      } on FormatException {
        hold(entity, id, 'SONG_REFERENCE_HELD');
        continue;
      }
      if (entity == 'SONG_SOURCE' || entity == 'SONG_CLOUD_SELECTION') {
        if (original != payload['song_id']) {
          continue; // Existing server source/roles win.
        }
      }
    }
    if ({
          'RECORDING_TAG',
          'RECORDING_FILE_SPEC',
          'RECORDING_ASSET',
        }.contains(entity) &&
        ledger.contains(_key('RECORDING', _uuid(payload['recording_id'])))) {
      hold(entity, id, 'RECORDING_REFERENCE_PURGED');
      continue;
    }
    output.add(row);
  }
  final inputs = <Map<String, dynamic>>[];
  for (final raw in data['recording_inputs'] as List) {
    final input = raw as Map<String, dynamic>,
        id = input['recording_id'] as String;
    if (ledger.contains(_key('RECORDING', id))) {
      block('RECORDING', id, 'PERMANENTLY_DELETED_UUID');
      continue;
    }
    var valid = true;
    for (final field in ['draft', 'input_selection', 'input_form']) {
      final payload = input[field] as Map<String, dynamic>?;
      if (payload?['song_id'] == null) continue;
      try {
        payload!['song_id'] = mapSong(payload['song_id']);
      } on FormatException {
        valid = false;
      }
    }
    if (valid) {
      inputs.add(input);
    } else {
      hold('RECORDING', id, 'SONG_REFERENCE_HELD');
    }
  }
  final eligible = {
    for (final row in output)
      if (row['entity'] == 'RECORDING') row['resource_id'] as String,
    for (final input in inputs) input['recording_id'] as String,
  };
  final files = consent.fileIds
      .where(
        (id) =>
            !ledger.contains(_key('RECORDING', id)) &&
            (eligible.contains(id) ||
                {
                  'ACTIVE',
                  'TRASHED',
                }.contains(current[_key('RECORDING', id)]?['lifecycle_state'])),
      )
      .toSet();
  requireCurrent();
  return ImportIdentityPlan._(output, inputs, mapping, files, blocked, held);
}
