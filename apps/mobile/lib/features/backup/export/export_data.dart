import 'dart:convert';

import '../../../core/domain/identifiers.dart';
import '../../../core/sync/wire_json.dart';
import 'backup_json.dart';
import 'export_baseline.dart';
import 'export_fields.dart';

void _check(bool value) {
  if (!value) throw const FormatException('Invalid personal backup data');
}

const _fileFields = {
  'sha256',
  'size_bytes',
  'duration_ms',
  'codec',
  'sample_rate',
  'channels',
  'capture_integrity',
};
const _inputFields = {
  'song_id',
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
  'condition_name_snapshot',
  'tag_ids',
  'tags',
};
const _candidateFields = {
  'provider',
  'verified_at',
  'brand',
  'number',
  'title',
  'artist',
  'version_code',
  'source_type',
  'tj_number',
};
const _operationFields = {
  'base_revision',
  'mode',
  'preview_version',
  'pin_release_confirmed',
  'remove_item_id',
  'ordered_item_ids',
  'ordered_playlists',
  'song_ids',
  'item_id',
  'song_id',
  'manual_reason',
  'recording_id',
  'slot_no',
  'generation',
};

Map<String, dynamic> _map(Object? value) {
  _check(value is Map<String, dynamic>);
  return value as Map<String, dynamic>;
}

// Known business fields are copied. Credentials, status/search tokens, runtime
// storage evidence and device paths have no export slot, including nested JSON.
Map<String, Object?> _project(
  Map<String, dynamic> source,
  String entity,
  String owner, {
  Set<String>? fields,
  bool operation = false,
}) {
  final allowed = fields ?? exportPersonalFields[entity];
  _check(allowed != null);
  _check(!source.containsKey('user_id') || source['user_id'] == owner);
  final result = <String, Object?>{};
  for (final key in allowed!) {
    if (!source.containsKey(key)) continue;
    final value = source[key];
    final structured = {
      'file',
      'input_selection',
      'input_form',
      'candidate_snapshot',
      'payload',
      'tags',
      'tag_ids',
      'song_ids',
      'ordered_item_ids',
      'ordered_playlists',
    }.contains(key);
    if (value == null ||
        !structured && (value is String || value is bool || value is num)) {
      _check(value is! num || value.isFinite);
      result[key] = value;
    } else if (key == 'file') {
      result[key] = _project(_map(value), entity, owner, fields: _fileFields);
    } else if (key == 'input_selection' || key == 'input_form') {
      result[key] = _project(
        _map(value),
        'RECORDING',
        owner,
        fields: _inputFields,
      );
    } else if (key == 'candidate_snapshot') {
      result[key] = _project(
        _map(value),
        entity,
        owner,
        fields: _candidateFields,
      );
    } else if (key == 'payload' && entity == 'CHANGE_LOG') {
      result[key] = _project(
        _map(value),
        source['entity_type'] as String,
        owner,
        operation: true,
      );
    } else if (key == 'ordered_playlists' && value is List) {
      result[key] = [
        for (final entry in value)
          _project(_map(entry), entity, owner, fields: {'id', 'base_revision'}),
      ];
    } else if (key == 'tags' && value is List) {
      result[key] = [
        for (final tag in value)
          _project(_map(tag), entity, owner, fields: {'id', 'name_snapshot'}),
      ];
    } else if ({'tag_ids', 'song_ids', 'ordered_item_ids'}.contains(key) &&
        value is List) {
      _check(value.every((v) => v is String && UuidValue(v).value == v));
      result[key] = List<String>.from(value);
    } else {
      throw const FormatException('Invalid personal backup field');
    }
  }
  if (operation) {
    result.addAll(_project(source, entity, owner, fields: _operationFields));
  }
  return result;
}

Map<String, Object?>? _payload(
  Object? value,
  String entity,
  String owner, {
  bool operation = false,
}) {
  if (value == null) return null;
  final parsed = value is String ? decodeWireJson(value) : value;
  return _project(_map(parsed), entity, owner, operation: operation);
}

Map<String, Object?>? _response(Object? value, String entity, String owner) {
  if (value == null) return null;
  final source = _map(value is String ? decodeWireJson(value) : value);
  final result = _project(
    source,
    entity,
    owner,
    fields: {
      'code',
      'status',
      'revision',
      'id',
      'deleted_at',
      'purged_at',
      'entity_type',
      'entity_id',
      'base_revision',
    },
  );
  for (final key in ['current', 'base', 'local']) {
    if (source[key] != null) result[key] = _payload(source[key], entity, owner);
  }
  return result;
}

/// Two historical baselines and queue evidence stay separate. No acknowledgement,
/// conflict resolution or import authority is inferred from serialized records.
final class ExportData {
  ExportData._(Map<String, Object?> json) : _encoded = jsonEncode(json);
  final String _encoded;
  Map<String, dynamic> toJson() => jsonDecode(_encoded) as Map<String, dynamic>;
  String encode() => _encoded;

  /// Only a checksum-verified app-private export checkpoint may call this.
  /// External ZIP input still requires the separate P22 import preflight.
  factory ExportData.fromPrivateCheckpoint(String text) {
    final root = readJson(text);
    _check(root['schema_version'] == 1 && root['schema_version'] is int);
    _check(
      root.keys.toSet().difference({
        'schema_version',
        'export_id',
        'source_user_id',
        'local_cutoff_at',
        'server_rows',
        'local_copies',
        'pending_changes',
        'recording_inputs',
        'records',
      }).isEmpty,
    );
    UuidValue(root['export_id'] as String);
    UuidValue(root['source_user_id'] as String);
    for (final field in [
      'server_rows',
      'local_copies',
      'pending_changes',
      'recording_inputs',
      'records',
    ]) {
      _check(root[field] is List);
    }
    return ExportData._(root);
  }
  int get metadataCount => (toJson()['records'] as List).length;
  List<Map<String, dynamic>> get records =>
      (toJson()['records'] as List).cast<Map<String, dynamic>>();

  factory ExportData.fromBaseline(ExportBaseline baseline) {
    final owner = baseline.owner, local = baseline.local;
    _check(local['source_user_id'] == owner);
    final server = <Map<String, Object?>>[];
    if (baseline.online) {
      for (final entry in baseline.entries) {
        server.add({
          'entity': entry.entity,
          'resource_id': entry.resourceId,
          'ordinal': entry.ordinal,
          'payload': _project(entry.payload, entry.entity, owner),
        });
      }
    } else {
      for (final raw in local['snapshot_rows'] as List? ?? const []) {
        final row = _map(raw), entity = row['entity'] as String;
        server.add({
          'entity': entity,
          'resource_id': row['resource_id'],
          'ordinal': row['ordinal'],
          'payload': _payload(row['canonical_payload'], entity, owner),
        });
      }
    }
    final copies = <Map<String, Object?>>[], changes = <Map<String, Object?>>[];
    for (final raw in local['copies'] as List) {
      final row = _map(raw), entity = row['entity_type'] as String;
      _check(exportPersonalFields.containsKey(entity));
      UuidValue(row['entity_id'] as String);
      copies.add({
        'entity': entity,
        'resource_id': row['entity_id'],
        'server_revision': row['server_revision'],
        'tombstone': row['tombstone'] == 1,
        'server': _payload(row['server_payload'], entity, owner),
        'local': _payload(row['local_payload'], entity, owner),
      });
    }
    for (final raw in local['changes'] as List) {
      final row = _map(raw), entity = row['entity_type'] as String;
      _check(exportPersonalFields.containsKey(entity));
      UuidValue(row['op_id'] as String);
      UuidValue(row['entity_id'] as String);
      final source = _map(decodeWireJson(row['payload'] as String));
      changes.add({
        'op_id': row['op_id'], 'entity': entity,
        'resource_id': row['entity_id'], 'operation': row['operation'],
        'base_revision': row['base_revision'],
        'queue_state': row['queue_state'],
        'created_at': row['created_at'],
        'base': _payload(row['base_payload'], entity, owner),
        'changes': _project(source, entity, owner, operation: true),
        'server_response': _response(row['server_response'], entity, owner),
        // Expiring provider selection proof is not a reusable backup credential.
        'requires_source_refresh': source.containsKey('source_token'),
      });
    }
    final inputs = <Map<String, Object?>>[];
    for (final raw in local['recording_inputs'] as List? ?? const []) {
      final row = _map(raw), id = row['recording_id'] as String;
      UuidValue(id);
      final source = _map(decodeWireJson(row['recovery_payload'] as String));
      inputs.add({
        'recording_id': id,
        'phase': row['phase'],
        'revision': row['revision'],
        'file': source['file'] == null
            ? null
            : _project(
                _map(source['file']),
                'RECORDING',
                owner,
                fields: _fileFields,
              ),
        'draft': _payload(source['draft'], 'RECORDING', owner),
        'input_selection': source['input_selection'] == null
            ? null
            : _project(
                _map(source['input_selection']),
                'RECORDING',
                owner,
                fields: _inputFields,
              ),
        'input_form': source['input_form'] == null
            ? null
            : _project(
                _map(source['input_form']),
                'RECORDING',
                owner,
                fields: _inputFields,
              ),
      });
    }
    // Human/file collectors use a view; original server/local/conflict evidence
    // remains intact above. Preserve composite relation rows rather than ID-collapse.
    final records = <String, Map<String, Object?>>{};
    String key(String entity, Object? id, Map<String, Object?> payload) =>
        '$entity/$id/${entity == 'RECORDING_TAG'
            ? payload['tag_id']
            : entity == 'PIN_SLOT'
            ? payload['slot_no']
            : entity == 'DELETION_ITEM'
            ? '${payload['batch_id']}/${payload['entity_type']}'
            : entity == 'CHANGE_LOG'
            ? payload['change_seq']
            : ''}';
    for (final row in server) {
      final payload = row['payload'] as Map<String, Object?>;
      records[key(row['entity'] as String, row['resource_id'], payload)] = {
        'entity': row['entity'],
        'resource_id': row['resource_id'],
        'tombstone': false,
        'payload': payload,
      };
    }
    for (final row in copies) {
      final entity = row['entity'] as String;
      final localPayload = row['local'] as Map<String, Object?>?;
      final payload = localPayload ?? row['server'] as Map<String, Object?>?;
      if (payload == null) continue;
      final k = key(entity, row['resource_id'], payload);
      if (baseline.online && localPayload == null && records.containsKey(k)) {
        continue;
      }
      records[k] = {
        'entity': entity,
        'resource_id': row['resource_id'],
        'tombstone': row['tombstone'],
        'payload': payload,
      };
    }
    return ExportData._({
      'schema_version': 1,
      'export_id': baseline.id,
      'source_user_id': owner,
      'local_cutoff_at': local['local_cutoff_at'],
      'server_rows': server,
      'local_copies': copies,
      'pending_changes': changes,
      'recording_inputs': inputs,
      'records': records.values.toList(growable: false),
    });
  }

  /// Strict JSON parsing for future import preflight; not an authorization check.
  static Map<String, dynamic> readJson(String value) =>
      _map(decodeBackupJson(value));
  @override
  String toString() => 'ExportData[REDACTED]';
}
