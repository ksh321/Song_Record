import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../../../core/domain/identifiers.dart';
import '../export/export_data.dart';
import '../export/export_fields.dart';
import '../export/export_manifest.dart';
import 'import_zip.dart';

void _valid(bool ok) {
  if (!ok) throw const FormatException('Invalid import data');
}

Map<String, dynamic> _map(Object? v) {
  _valid(v is Map<String, dynamic>);
  return v as Map<String, dynamic>;
}

void _keys(Map<String, dynamic> map, Set<String> keys) {
  _valid(map.length == keys.length && keys.every(map.containsKey));
}

void _id(Object? v) {
  _valid(v is String && UuidValue(v).value == v);
}

/// External input is stricter than trusted private export checkpoints.
final class ImportData {
  ImportData._(Map<String, dynamic> data) : _json = jsonEncode(data);
  final String _json;
  Map<String, dynamic> toJson() => jsonDecode(_json) as Map<String, dynamic>;
  factory ImportData.decode(String text, ExportManifest manifest) {
    final root = ExportData.readJson(text);
    _keys(root, {
      'schema_version',
      'export_id',
      'source_user_id',
      'local_cutoff_at',
      'server_rows',
      'local_copies',
      'pending_changes',
      'recording_inputs',
      'records',
    });
    _valid(
      root['schema_version'] is int &&
          root['schema_version'] == 1 &&
          root['export_id'] == manifest.exportId &&
          root['source_user_id'] == manifest.sourceUserId &&
          root['local_cutoff_at'] == manifest.localCutoffAt.toIso8601String(),
    );
    for (final name in [
      'server_rows',
      'local_copies',
      'pending_changes',
      'recording_inputs',
      'records',
    ]) {
      _valid(root[name] is List && (root[name] as List).length <= 100000);
      for (final item in root[name] as List) {
        final row = _map(item);
        if (name == 'recording_inputs') {
          _keys(row, {
            'recording_id',
            'phase',
            'revision',
            'file',
            'draft',
            'input_selection',
            'input_form',
          });
          _id(row['recording_id']);
          _valid(
            row['phase'] is String &&
                row['revision'] is int &&
                (row['revision'] as int) >= 0,
          );
          for (final key in [
            'file',
            'draft',
            'input_selection',
            'input_form',
          ]) {
            if (row[key] != null) {
              _fields(_map(row[key]));
            }
          }
          continue;
        }
        final entity = row['entity'];
        _valid(entity is String && exportPersonalFields.containsKey(entity));
        _valid(
          row['resource_id'] is String &&
              (row['resource_id'] as String).isNotEmpty &&
              (row['resource_id'] as String).length <= 128,
        );
        if (entity != 'PIN_SLOT' && entity != 'CHANGE_LOG') {
          _id(row['resource_id']);
        }
        if (name == 'server_rows') {
          _keys(row, {'entity', 'resource_id', 'ordinal', 'payload'});
          _valid(row['ordinal'] is int && (row['ordinal'] as int) >= 0);
          _payload(row['payload'], entity as String);
        } else if (name == 'records') {
          _keys(row, {'entity', 'resource_id', 'tombstone', 'payload'});
          _valid(row['tombstone'] is bool);
          _payload(row['payload'], entity as String);
        } else if (name == 'local_copies') {
          _keys(row, {
            'entity',
            'resource_id',
            'server_revision',
            'tombstone',
            'server',
            'local',
          });
          _valid(
            row['tombstone'] is bool &&
                row['server_revision'] is int &&
                (row['server_revision'] as int) >= 0,
          );
          for (final key in ['server', 'local']) {
            if (row[key] != null) _payload(row[key], entity as String);
          }
        } else {
          _keys(row, {
            'op_id',
            'entity',
            'resource_id',
            'operation',
            'base_revision',
            'queue_state',
            'created_at',
            'base',
            'changes',
            'server_response',
            'requires_source_refresh',
          });
          _id(row['op_id']);
          _valid(
            row['operation'] is String &&
                row['queue_state'] is String &&
                row['base_revision'] is int &&
                (row['base_revision'] as int) >= 0 &&
                row['created_at'] is int &&
                row['requires_source_refresh'] is bool,
          );
          for (final key in ['base', 'changes', 'server_response']) {
            if (row[key] != null) {
              _fields(_map(row[key]));
            }
          }
        }
      }
    }
    _valid((root['records'] as List).length == manifest.metadataCount);
    final recordings = {
      for (final row in root['records'] as List)
        if (row['entity'] == 'RECORDING') row['resource_id'],
      for (final row in root['recording_inputs'] as List) row['recording_id'],
    };
    _valid(manifest.files.every((f) => recordings.contains(f.recordingId)));
    return ImportData._(root);
  }
  static void _payload(Object? value, String entity) {
    final map = _map(value);
    _valid(map.keys.every(exportPersonalFields[entity]!.contains));
    _fields(map);
  }

  static void _fields(Object? value, [int depth = 0]) {
    _valid(depth <= 32);
    if (value == null ||
        value is bool ||
        value is String ||
        value is num && value.isFinite) {
      return;
    }
    if (value is List) {
      _valid(value.length <= 100000);
      for (final v in value) {
        _fields(v, depth + 1);
      }
      return;
    }
    final map = _map(value);
    final allowed = {
      for (final set in exportPersonalFields.values) ...set,
      'input_selection',
      'input_form',
      'tags',
      'tag_ids',
      'name_snapshot',
      'base_revision',
      'mode',
      'preview_version',
      'pin_release_confirmed',
      'remove_item_id',
      'ordered_item_ids',
      'song_ids',
      'item_id',
      'manual_reason',
      'code',
      'status',
      'current',
      'base',
      'local',
      'brand',
      'number',
      'title',
      'artist',
    };
    _valid(map.keys.every(allowed.contains));
    for (final item in map.entries) {
      const objects = {
        'file',
        'input_selection',
        'input_form',
        'candidate_snapshot',
        'payload',
        'current',
        'base',
        'local',
      };
      const arrays = {'tags', 'tag_ids', 'song_ids', 'ordered_item_ids'};
      _valid(item.value is! Map || objects.contains(item.key));
      _valid(item.value is! List || arrays.contains(item.key));
      if (item.value != null &&
          {'tag_ids', 'song_ids', 'ordered_item_ids'}.contains(item.key)) {
        _valid(item.value is List);
        for (final id in item.value as List) {
          _id(id);
        }
      }
      if (item.value != null &&
          {
            'file',
            'input_selection',
            'input_form',
            'candidate_snapshot',
            'payload',
            'current',
            'base',
            'local',
          }.contains(item.key)) {
        _map(item.value);
      }
      if (item.value != null &&
          {
            'tags',
            'tag_ids',
            'song_ids',
            'ordered_item_ids',
          }.contains(item.key)) {
        _valid(item.value is List);
      }
      if (item.value != null && item.key == 'timezone_id') {
        _valid(
          item.value is String &&
              (item.value as String).isNotEmpty &&
              (item.value as String).length <= 64,
        );
      }
      if (item.value != null &&
          (item.key == 'id' ||
              item.key.endsWith('_id') && item.key != 'timezone_id')) {
        _id(item.value);
      }
      _fields(item.value, depth + 1);
    }
  }

  @override
  String toString() => 'ImportData[REDACTED]';
}

abstract interface class ImportAudioProbe {
  Future<Map<String, dynamic>> inspect(File file);
}

final class AndroidImportAudioProbe implements ImportAudioProbe {
  static const channel = MethodChannel(
    'com.ksh321.songrecord/recorder_commands',
  );
  @override
  Future<Map<String, dynamic>> inspect(File file) async {
    final result = await channel.invokeMapMethod<String, dynamic>(
      'inspectImportAudio',
      {'path': file.path},
    );
    if (result == null) throw const FormatException('Invalid import audio');
    return result;
  }
}

final class ImportValidationIssue {
  const ImportValidationIssue(this.code, this.recordingId);
  final String code;
  final String? recordingId;
  @override
  String toString() => 'ImportValidationIssue[$code]';
}

final class ValidatedImport {
  ValidatedImport(
    this.staging,
    this.manifest,
    this.data,
    List<ImportValidationIssue> issues,
  ) : issues = List.unmodifiable(issues);
  final ImportZipStaging staging;
  final ExportManifest manifest;
  final ImportData data;
  final List<ImportValidationIssue> issues;
  bool get wholeBackupValid => issues.isEmpty;
  @override
  String toString() => 'ValidatedImport[REDACTED]';
}

/// Read-only proof. A damaged file blocks whole-backup import; no DB/file apply.
final class ImportValidator {
  ImportValidator({
    required this.owner,
    required this.requireCurrent,
    required this.audio,
  });
  final String owner;
  final void Function() requireCurrent;
  final ImportAudioProbe audio;
  Future<ValidatedImport> verify(ImportZipStaging staging) async {
    requireCurrent();
    _valid(
      staging.entries.containsKey('manifest.json') &&
          staging.entries.containsKey('data.json'),
    );
    final manifest = ExportManifest.decode(
      await staging.file('manifest.json').readAsString(),
    );
    requireCurrent();
    _valid(manifest.sourceUserId == owner && manifest.collectionFinished);
    final data = ImportData.decode(
      await staging.file('data.json').readAsString(),
      manifest,
    );
    requireCurrent();
    final allowed = {
      'manifest.json',
      'data.json',
      'recordings.csv',
      for (final f in manifest.files.where((f) => f.included)) f.relativePath!,
    };
    _valid(
      staging.entries.values
          .where((e) => !e.directory)
          .every((e) => allowed.contains(e.name)),
    );
    final issues = <ImportValidationIssue>[];
    for (final entry in manifest.files.where((f) => f.included)) {
      requireCurrent();
      if (!staging.entries.containsKey(entry.relativePath)) {
        issues.add(ImportValidationIssue('MISSING_AUDIO', entry.recordingId));
        continue;
      }
      final file = staging.file(entry.relativePath!);
      if (!await file.exists()) {
        issues.add(ImportValidationIssue('MISSING_AUDIO', entry.recordingId));
        continue;
      }
      if (await file.length() != entry.sizeBytes ||
          (await sha256.bind(file.openRead()).first).toString() !=
              entry.sha256) {
        issues.add(
          ImportValidationIssue('AUDIO_HASH_OR_SIZE', entry.recordingId),
        );
        continue;
      }
      requireCurrent();
      try {
        final spec = await audio
            .inspect(file)
            .timeout(const Duration(seconds: 35));
        requireCurrent();
        final duration = spec['duration_ms'];
        if (spec['mime'] != 'audio/mp4a-latm' ||
            spec['aac_profile'] != 2 ||
            spec['channels'] != 1 ||
            spec['sample_rate'] != 48000 ||
            duration is! int ||
            duration <= 0 ||
            duration > 361000 ||
            (duration - entry.durationMs!).abs() > 250) {
          issues.add(ImportValidationIssue('AUDIO_FORMAT', entry.recordingId));
        }
      } on TimeoutException {
        issues.add(
          ImportValidationIssue('AUDIO_INSPECTION_TIMEOUT', entry.recordingId),
        );
      } on PlatformException {
        issues.add(ImportValidationIssue('AUDIO_FORMAT', entry.recordingId));
      } on FormatException {
        issues.add(ImportValidationIssue('AUDIO_FORMAT', entry.recordingId));
      }
    }
    requireCurrent();
    return ValidatedImport(staging, manifest, data, issues);
  }
}
