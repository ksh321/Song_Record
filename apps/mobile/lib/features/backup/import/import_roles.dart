import 'dart:convert';

import '../../../core/domain/identifiers.dart';
import 'import_conflicts.dart';
import 'import_decision.dart';
import 'import_preflight.dart';

final class ImportRolePlan {
  ImportRolePlan._(
    List<Map<String, dynamic>> rows,
    this.pinCandidates,
    this.availablePinSlots,
    this.heldRepresentatives,
    this.owner,
  ) : _rows = jsonEncode(rows);
  final String _rows, owner;
  final Set<String> pinCandidates, heldRepresentatives;
  final int availablePinSlots;
  List<Map<String, dynamic>> get records =>
      (jsonDecode(_rows) as List).cast<Map<String, dynamic>>();

  /// Selection is a proposal, never authority to recreate old slots. Actual
  /// requests must use fresh server revisions and the existing pin API.
  Set<String> selectPins(Set<String> selected, void Function() requireCurrent) {
    requireCurrent();
    if (!pinCandidates.containsAll(selected) ||
        selected.length > availablePinSlots) {
      throw StateError(
        'Pin selection needs current capacity and eligible records',
      );
    }
    return Set.unmodifiable(selected);
  }
}

ImportRolePlan planImportRoles({
  required ImportConsent consent,
  required ImportConflictPreview preview,
  required ImportServerBaseline server,
  required void Function() requireCurrent,
}) {
  requireCurrent();
  if (preview.owner != server.owner ||
      consent.source.manifest.sourceUserId != server.owner) {
    throw StateError('Import account changed');
  }
  final plan = compareImportRoles(
    owner: server.owner,
    rows: preview.records,
    historicalRows: (consent.source.data.toJson()['records'] as List)
        .cast<Map<String, dynamic>>(),
    serverRows: [
      for (final e in server.entries)
        {'entity': e.entity, 'resource_id': e.resourceId, 'payload': e.payload},
    ],
  );
  requireCurrent();
  return plan;
}

/// Pure read-only role comparison. Caller supplies validated import rows and
/// a freshly verified account baseline; this function never writes DB or pins.
ImportRolePlan compareImportRoles({
  required String owner,
  required List<Map<String, dynamic>> rows,
  required List<Map<String, dynamic>> historicalRows,
  required List<Map<String, dynamic>> serverRows,
}) {
  UuidValue(owner);
  final serverSongs = <String, Map<String, dynamic>>{},
      recordings = <String, Map<String, dynamic>>{};
  final slots = <int>{}, occupied = <int>{}, alreadyPinned = <String>{};
  int? limit;
  for (final row in serverRows) {
    final p = Map<String, dynamic>.from(row['payload'] as Map);
    if (p['user_id'] != owner) {
      throw const FormatException('Invalid role owner');
    }
    final id = row['resource_id'] as String;
    if (row['entity'] == 'SONG') serverSongs[id] = p;
    if (row['entity'] == 'RECORDING' && row['tombstone'] != true) {
      recordings[id] = p;
    }
    if (row['entity'] == 'USER_ENTITLEMENT') {
      final value = p['pinned_limit'];
      if (value is! int || value < 0 || limit != null) {
        throw const FormatException('Invalid current pin entitlement');
      }
      limit = value > 10 ? 10 : value;
    }
    if (row['entity'] == 'PIN_SLOT') {
      final slot = p['slot_no'];
      if (slot is! int || slot < 1 || !slots.add(slot)) {
        throw const FormatException('Invalid current pin slots');
      }
      for (final field in ['current_recording_id', 'pending_recording_id']) {
        final value = p[field];
        if (value != null) {
          occupied.add(slot);
          alreadyPinned.add(UuidValue(value as String).value);
        }
      }
    }
  }
  for (final row in rows.where(
    (r) => r['entity'] == 'RECORDING' && r['tombstone'] != true,
  )) {
    final id = row['resource_id'] as String;
    recordings.putIfAbsent(
      id,
      () => Map<String, dynamic>.from(row['payload'] as Map),
    );
  }
  bool eligible(String id, {String? song}) {
    final r = recordings[id];
    return r != null &&
        (r['user_id'] == null || r['user_id'] == owner) &&
        r['id'] == id &&
        r['metadata_state'] == 'SAVED' &&
        r['lifecycle_state'] == 'ACTIVE' &&
        (song == null || r['song_id'] == song);
  }

  const readOnly = {
    'PIN_SLOT',
    'SONG_CLOUD_SELECTION',
    'USER_ENTITLEMENT',
    'STORAGE_USAGE',
    'USER_SYNC_STATE',
    'CHANGE_LOG',
    'DELETION_BATCH',
    'DELETION_ITEM',
    'DELETION_LEDGER',
    'RECORDING_ASSET',
  };
  final output = <Map<String, dynamic>>[], held = <String>{};
  for (final row in rows) {
    if (readOnly.contains(row['entity'])) continue;
    final p = Map<String, dynamic>.from(row['payload'] as Map);
    if (p['user_id'] != null && p['user_id'] != owner) {
      throw const FormatException('Invalid imported role owner');
    }
    if (row['entity'] == 'SONG') {
      final id = row['resource_id'] as String, remote = serverSongs[id];
      if (remote != null) {
        p['representative_recording_id'] =
            remote['representative_recording_id'];
      } else {
        final target = p['representative_recording_id'];
        if (target != null &&
            (row['tombstone'] == true ||
                p['lifecycle_state'] != 'ACTIVE' ||
                !eligible(UuidValue(target as String).value, song: id))) {
          held.add(id);
          p['representative_recording_id'] = null;
        }
      }
    }
    output.add({...row, 'payload': p});
  }
  final pins = <String>{};
  for (final row in historicalRows.where((r) => r['entity'] == 'PIN_SLOT')) {
    final p = row['payload'] as Map;
    for (final field in ['current_recording_id', 'pending_recording_id']) {
      final value = p[field];
      if (value != null) {
        final id = UuidValue(value as String).value;
        if (!alreadyPinned.contains(id) && eligible(id)) pins.add(id);
      }
    }
  }
  // An absent current entitlement is unknown, not a default grant of ten slots.
  final capacity = limit == null || occupied.length >= limit
      ? 0
      : limit - occupied.length;
  return ImportRolePlan._(
    output,
    Set.unmodifiable(pins),
    capacity,
    Set.unmodifiable(held),
    owner,
  );
}
