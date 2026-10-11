import 'dart:convert';

import '../../../core/domain/identifiers.dart';
import 'backup_json.dart';
import 'export_baseline.dart';

const _maxInteger = 0x7fffffffffffffff;
void _valid(bool condition) {
  if (!condition) throw const FormatException('Invalid backup manifest');
}

String _id(Object? value) {
  _valid(value is String);
  final text = value as String;
  _valid(UuidValue(text).value == text);
  return text;
}

int _integer(Object? value) {
  _valid(value is int && value >= 0);
  return value as int;
}

DateTime _instant(Object? value) {
  _valid(
    value is String &&
        RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z$')
            .hasMatch(value),
  );
  final result = DateTime.tryParse(value as String);
  _valid(
    result != null &&
        result.isUtc &&
        result.toIso8601String().substring(0, 19) == value.substring(0, 19),
  );
  return result!;
}

Map<String, dynamic> _object(Object? value, Set<String> keys) {
  _valid(value is Map<String, dynamic>);
  final map = value as Map<String, dynamic>;
  _valid(map.length == keys.length && keys.every(map.containsKey));
  return map;
}

enum ExportMissingReason {
  offlineServerOnly('OFFLINE_SERVER_ONLY'),
  fileNotOnDevice('FILE_NOT_ON_DEVICE'),
  fileDeleted('FILE_DELETED'),
  downloadFailed('DOWNLOAD_FAILED'),
  checksumMismatch('CHECKSUM_MISMATCH'),
  incompleteRecording('INCOMPLETE_RECORDING'),
  trashNotSelected('TRASH_NOT_SELECTED'),
  notCollected('NOT_COLLECTED');

  const ExportMissingReason(this.wire);
  final String wire;
  static ExportMissingReason decode(Object? value) {
    for (final reason in values) {
      if (reason.wire == value) return reason;
    }
    throw const FormatException('Invalid backup omission reason');
  }
}

/// A hash/specification on a missing file is expected metadata, not file proof.
final class ExportAudioEntry {
  ExportAudioEntry({
    required this.recordingId,
    required this.selected,
    required this.included,
    required this.missingReason,
    this.sha256,
    this.sizeBytes,
    this.durationMs,
  }) {
    _id(recordingId);
    _valid(sha256 == null || RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256!));
    _valid(sizeBytes == null || sizeBytes! > 0);
    _valid(durationMs == null || durationMs! > 0);
    _valid(
      included
          ? selected &&
                missingReason == null &&
                sha256 != null &&
                sizeBytes != null &&
                durationMs != null
          : missingReason != null,
    );
    _valid(
      selected
          ? missingReason != ExportMissingReason.trashNotSelected
          : !included && missingReason == ExportMissingReason.trashNotSelected,
    );
  }
  final String recordingId;
  final bool selected, included;
  final ExportMissingReason? missingReason;
  final String? sha256;
  final int? sizeBytes, durationMs;
  String? get relativePath => included ? 'audio/$recordingId.m4a' : null;
  Map<String, Object?> toJson() => {
    'recording_id': recordingId,
    'relative_path': relativePath,
    'selected': selected,
    'included': included,
    'missing_reason': missingReason?.wire,
    'sha256': sha256,
    'size_bytes': sizeBytes,
    'duration_ms': durationMs,
  };
  factory ExportAudioEntry.fromJson(Object? value) {
    final map = _object(value, {
      'recording_id',
      'relative_path',
      'selected',
      'included',
      'missing_reason',
      'sha256',
      'size_bytes',
      'duration_ms',
    });
    _valid(map['selected'] is bool && map['included'] is bool);
    _valid(map['sha256'] == null || map['sha256'] is String);
    final entry = ExportAudioEntry(
      recordingId: _id(map['recording_id']),
      selected: map['selected'] as bool,
      included: map['included'] as bool,
      missingReason: map['missing_reason'] == null
          ? null
          : ExportMissingReason.decode(map['missing_reason']),
      sha256: map['sha256'] as String?,
      sizeBytes: map['size_bytes'] == null ? null : _integer(map['size_bytes']),
      durationMs: map['duration_ms'] == null
          ? null
          : _integer(map['duration_ms']),
    );
    _valid(map['relative_path'] == entry.relativePath);
    return entry;
  }
  @override
  String toString() => 'ExportAudioEntry[REDACTED]';
}

/// Shared schema 1 for export and subsequent P22 import validation.
/// source_user_id is historical provenance, never authentication authority.
final class ExportManifest {
  ExportManifest({
    required this.exportId,
    required this.sourceUserId,
    required this.createdAt,
    required this.localCutoffAt,
    required this.online,
    required this.includeTrash,
    required this.snapshotCursor,
    required this.serverBaselineComplete,
    required this.serverConfirmedAt,
    required this.serverCapturedAt,
    required this.metadataCount,
    required List<ExportAudioEntry> files,
  }) : files = List<ExportAudioEntry>.unmodifiable(
         <ExportAudioEntry>[...files]
           ..sort((a, b) => a.recordingId.compareTo(b.recordingId)),
       ) {
    _id(exportId);
    _id(sourceUserId);
    _valid(
      createdAt.isUtc &&
          localCutoffAt.isUtc &&
          (serverConfirmedAt == null || serverConfirmedAt!.isUtc) &&
          (serverCapturedAt == null || serverCapturedAt!.isUtc),
    );
    _valid(
      metadataCount >= 0 && (snapshotCursor == null || snapshotCursor! >= 0),
    );
    _valid(
      serverBaselineComplete ? snapshotCursor != null : snapshotCursor == null,
    );
    _valid(
      !online ||
          serverBaselineComplete &&
              serverConfirmedAt != null &&
              serverCapturedAt != null,
    );
    _valid(online || serverCapturedAt == null);
    _valid(serverBaselineComplete || serverConfirmedAt == null);
    _valid(
      this.files.map((f) => f.recordingId).toSet().length == this.files.length,
    );
    _valid(!includeTrash || this.files.every((f) => f.selected));
    var bytes = 0;
    for (final file in this.files.where((f) => f.included)) {
      _valid(file.sizeBytes! <= _maxInteger - bytes);
      bytes += file.sizeBytes!;
    }
    includedAudioBytes = bytes;
  }
  final String exportId, sourceUserId;
  final DateTime createdAt, localCutoffAt;
  final DateTime? serverConfirmedAt, serverCapturedAt;
  final bool online, includeTrash, serverBaselineComplete;
  final int? snapshotCursor;
  final int metadataCount;
  final List<ExportAudioEntry> files;
  late final int includedAudioBytes;
  int get includedAudioCount => files.where((f) => f.included).length;
  int get missingAudioCount =>
      files.where((f) => f.selected && !f.included).length;
  int get excludedAudioCount => files.where((f) => !f.selected).length;
  bool get canClaimCompleteOnline => online && missingAudioCount == 0;
  bool get collectionFinished =>
      files.every((f) => f.missingReason != ExportMissingReason.notCollected);
  Map<String, Object?> toJson() => {
    'schema_version': 1,
    'export_id': exportId,
    'source_user_id': sourceUserId,
    'backup_scope': online ? 'ONLINE_SNAPSHOT' : 'OFFLINE_PARTIAL',
    'created_at': createdAt.toIso8601String(),
    'local_cutoff_at': localCutoffAt.toIso8601String(),
    'include_trash': includeTrash,
    'snapshot_cursor': snapshotCursor,
    'server_baseline_complete': serverBaselineComplete,
    'server_confirmed_at': serverConfirmedAt?.toIso8601String(),
    'server_captured_at': serverCapturedAt?.toIso8601String(),
    'metadata_count': metadataCount,
    'included_audio_count': includedAudioCount,
    'missing_audio_count': missingAudioCount,
    'excluded_audio_count': excludedAudioCount,
    'included_audio_bytes': includedAudioBytes,
    'files': files.map((f) => f.toJson()).toList(growable: false),
  };
  String encode() => jsonEncode(toJson());
  ExportManifest withFiles(List<ExportAudioEntry> entries) => ExportManifest(
    exportId: exportId,
    sourceUserId: sourceUserId,
    createdAt: createdAt,
    localCutoffAt: localCutoffAt,
    online: online,
    includeTrash: includeTrash,
    snapshotCursor: snapshotCursor,
    serverBaselineComplete: serverBaselineComplete,
    serverConfirmedAt: serverConfirmedAt,
    serverCapturedAt: serverCapturedAt,
    metadataCount: metadataCount,
    files: entries,
  );
  factory ExportManifest.fromBaseline(
    ExportBaseline baseline, {
    required int metadataCount,
    required List<ExportAudioEntry> files,
  }) {
    final local = baseline.local;
    final confirmed = (local['baseline'] as List).single as Map;
    final complete =
        baseline.online ||
        confirmed['baseline_complete'] == 1 &&
            confirmed['last_change_seq'] is int;
    final updated = confirmed['updated_at'];
    return ExportManifest(
      exportId: baseline.id,
      sourceUserId: baseline.owner,
      createdAt: baseline.createdAt,
      localCutoffAt: _instant(local['local_cutoff_at']),
      online: baseline.online,
      includeTrash: baseline.includeTrash,
      snapshotCursor:
          baseline.manifest?.cursor ??
          (complete ? confirmed['last_change_seq'] as int : null),
      serverBaselineComplete: complete,
      serverConfirmedAt:
          baseline.manifest?.readyAt ??
          (complete && updated is int && updated > 0
              ? DateTime.fromMillisecondsSinceEpoch(updated, isUtc: true)
              : null),
      serverCapturedAt: baseline.manifest?.capturedAt,
      metadataCount: metadataCount,
      files: files,
    );
  }
  factory ExportManifest.decode(String text) {
    final map = _object(decodeBackupJson(text), {
      'schema_version',
      'export_id',
      'source_user_id',
      'backup_scope',
      'created_at',
      'local_cutoff_at',
      'include_trash',
      'snapshot_cursor',
      'server_baseline_complete',
      'server_confirmed_at',
      'server_captured_at',
      'metadata_count',
      'included_audio_count',
      'missing_audio_count',
      'excluded_audio_count',
      'included_audio_bytes',
      'files',
    });
    _valid(
      map['schema_version'] is int &&
          map['schema_version'] == 1 &&
          {'ONLINE_SNAPSHOT', 'OFFLINE_PARTIAL'}.contains(map['backup_scope']),
    );
    _valid(
      map['include_trash'] is bool &&
          map['server_baseline_complete'] is bool &&
          map['files'] is List,
    );
    final result = ExportManifest(
      exportId: _id(map['export_id']),
      sourceUserId: _id(map['source_user_id']),
      createdAt: _instant(map['created_at']),
      localCutoffAt: _instant(map['local_cutoff_at']),
      online: map['backup_scope'] == 'ONLINE_SNAPSHOT',
      includeTrash: map['include_trash'] as bool,
      snapshotCursor: map['snapshot_cursor'] == null
          ? null
          : _integer(map['snapshot_cursor']),
      serverBaselineComplete: map['server_baseline_complete'] as bool,
      serverConfirmedAt: map['server_confirmed_at'] == null
          ? null
          : _instant(map['server_confirmed_at']),
      serverCapturedAt: map['server_captured_at'] == null
          ? null
          : _instant(map['server_captured_at']),
      metadataCount: _integer(map['metadata_count']),
      files: (map['files'] as List).map(ExportAudioEntry.fromJson).toList(),
    );
    _valid(
      _integer(map['included_audio_count']) == result.includedAudioCount &&
          _integer(map['missing_audio_count']) == result.missingAudioCount &&
          _integer(map['excluded_audio_count']) == result.excludedAudioCount &&
          _integer(map['included_audio_bytes']) == result.includedAudioBytes,
    );
    return result;
  }
  @override
  String toString() => 'ExportManifest[REDACTED]';
}
