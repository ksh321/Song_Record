import 'dart:collection';
import 'dart:convert';

import '../domain/identifiers.dart';

enum LocalEntity {
  song('SONG'),
  recording('RECORDING'),
  playlist('PLAYLIST'),
  playlistItem('PLAYLIST_ITEM'),
  tag('TAG'),
  recordingTag('RECORDING_TAG'),
  recordingCondition('RECORDING_CONDITION'),
  recordingFileSpec('RECORDING_FILE_SPEC'),
  recordingAsset('RECORDING_ASSET'),
  songCloudSelection('SONG_CLOUD_SELECTION'),
  pinSlot('PIN_SLOT'),
  userEntitlement('USER_ENTITLEMENT'),
  deletionLedger('DELETION_LEDGER');

  const LocalEntity(this.code);
  final String code;
}

enum LocalOperation {
  create('CREATE'),
  patch('PATCH'),
  trash('TRASH'),
  restore('RESTORE'),
  purge('PURGE');

  const LocalOperation(this.code);
  final String code;
}

enum FilePresence {
  capturing('CAPTURING'),
  inputPending('INPUT_PENDING'),
  saved('SAVED'),
  interrupted('INTERRUPTED'),
  corrupt('CORRUPT'),
  missing('MISSING');

  const FilePresence(this.code);
  final String code;
}

enum JournalPhase {
  preparing('PREPARING'),
  capturing('CAPTURING'),
  finalizing('FINALIZING'),
  verified('VERIFIED'),
  committed('COMMITTED'),
  failed('FAILED');

  const JournalPhase(this.code);
  final String code;
}

/// Captures values at construction so later mutation of a caller's Map cannot
/// change a queued edit. This fingerprint is local, not the future HTTP hash.
final class LocalEdit {
  LocalEdit({
    required String opId,
    required this.entity,
    required String entityId,
    required this.operation,
    required this.baseRevision,
    required Map<String, Object?> draft,
    required Map<String, Object?> changes,
  }) : opId = UuidValue(opId).value,
       entityId = UuidValue(entityId).value,
       draftJson = canonicalJson(draft),
       changesJson = canonicalJson(changes) {
    if (baseRevision < 0) {
      throw ArgumentError('baseRevision must be nonnegative');
    }
  }
  final String opId;
  final LocalEntity entity;
  final String entityId;
  final LocalOperation operation;
  final int baseRevision;
  final String draftJson;
  final String changesJson;
}

String canonicalJson(Map<String, Object?> value) =>
    jsonEncode(_canonical(value));

Object? _canonical(Object? value) {
  if (value is Map<String, Object?>) {
    return SplayTreeMap<String, Object?>.from(
      value.map((key, item) => MapEntry(key, _canonical(item))),
    );
  }
  if (value is List<Object?>) {
    return value.map(_canonical).toList(growable: false);
  }
  if (value == null || value is String || value is bool || value is num) {
    return value;
  }
  throw ArgumentError('Only JSON values may be persisted');
}

final class MetadataCopy {
  const MetadataCopy({
    required this.revision,
    this.serverJson,
    this.localJson,
    required this.tombstone,
  });
  final int revision;
  final String? serverJson;
  final String? localJson;
  final bool tombstone;
}

final class QueuedMutation {
  const QueuedMutation({
    required this.opId,
    required this.entity,
    required this.entityId,
    required this.operation,
    required this.state,
    required this.baseRevision,
    required this.payload,
    this.basePayload,
    this.serverResponse,
    required this.attemptCount,
  });
  final String opId;
  final LocalEntity entity;
  final String entityId;
  final LocalOperation operation;
  final String state;
  final int baseRevision;
  final String payload;
  final String? basePayload;
  final String? serverResponse;
  final int attemptCount;
}
