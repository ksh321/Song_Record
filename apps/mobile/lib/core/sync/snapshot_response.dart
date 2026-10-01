import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../domain/identifiers.dart';
import 'wire_json.dart';

const snapshotEntities = <String>[
  'CHANGE_LOG',
  'DELETION_BATCH',
  'DELETION_ITEM',
  'DELETION_LEDGER',
  'PIN_SLOT',
  'PLAYLIST',
  'PLAYLIST_ITEM',
  'RECORDING',
  'RECORDING_ASSET',
  'RECORDING_CONDITION',
  'RECORDING_FILE_SPEC',
  'RECORDING_TAG',
  'SONG',
  'SONG_CLOUD_SELECTION',
  'SONG_SOURCE',
  'STORAGE_USAGE',
  'TAG',
  'USER_ENTITLEMENT',
  'USER_SYNC_STATE',
];

void _check(bool condition) {
  if (!condition) throw const FormatException('Invalid snapshot response');
}

Map<String, dynamic> _object(Object? value, Set<String> keys) {
  _check(value is Map<String, dynamic>);
  final result = value as Map<String, dynamic>;
  _check(result.length == keys.length && result.keys.every(keys.contains));
  return result;
}

String _uuid(Object? value) {
  _check(value is String);
  final text = value as String;
  _check(UuidValue(text).value == text);
  return text;
}

int _integer(Object? value, {int minimum = 0}) {
  _check(value is int && value >= minimum);
  return value as int;
}

DateTime _instant(Object? value) {
  _check(value is String);
  final text = value as String;
  _check(
    RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,3})?Z$').hasMatch(text),
  );
  final parsed = DateTime.tryParse(text);
  _check(parsed != null && parsed.isUtc);
  // DateTime.parse normalizes invalid dates such as February 31.
  _check(parsed!.toIso8601String().substring(0, 19) == text.substring(0, 19));
  return parsed;
}

/// Frozen status. It is scoped to the authenticated account by the receiving
/// AccountStore lease, never by an untrusted server-supplied account selector.
final class SnapshotManifest {
  SnapshotManifest._(
    this.token,
    this.cursor,
    this.capturedAt,
    this.readyAt,
    this.expiresAt,
    this.hash,
    Map<String, int> counts,
  ) : counts = Map.unmodifiable(counts);
  final String token, hash;
  final int cursor;
  final DateTime capturedAt, readyAt, expiresAt;
  final Map<String, int> counts;

  factory SnapshotManifest.decode(
    String body, {
    required String expectedToken,
    required DateTime now,
  }) {
    final data = _object(decodeWireJson(body), {
      'snapshot_token',
      'status',
      'schema_version',
      'snapshot_cursor',
      'captured_at',
      'ready_at',
      'expires_at',
      'manifest_hash',
      'entity_counts',
    });
    final token = _uuid(data['snapshot_token']);
    _check(
      token == expectedToken &&
          data['status'] == 'READY' &&
          data['schema_version'] is int &&
          data['schema_version'] == 1,
    );
    final captured = _instant(data['captured_at']),
        ready = _instant(data['ready_at']),
        expiry = _instant(data['expires_at']);
    _check(
      !captured.isAfter(ready) &&
          expiry.difference(ready) == const Duration(minutes: 30) &&
          now.isBefore(expiry),
    );
    final counts = _object(
      data['entity_counts'],
      snapshotEntities.toSet(),
    ).map((key, value) => MapEntry(key, _integer(value)));
    _check(counts['USER_SYNC_STATE'] == 1);
    final hash = data['manifest_hash'];
    _check(hash is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(hash));
    return SnapshotManifest._(
      token,
      _integer(data['snapshot_cursor']),
      captured,
      ready,
      expiry,
      hash as String,
      counts,
    );
  }
  @override
  String toString() => 'SnapshotManifest[REDACTED]';
}

final class SnapshotEntry {
  SnapshotEntry._(
    this.entity,
    this.ordinal,
    this.resourceId,
    this.canonicalPayload,
  );
  final String entity, resourceId, canonicalPayload;
  final int ordinal;

  /// Revalidate persisted rows before hashing; raw database contents are not a
  /// substitute for the account and resource checks used for network pages.
  factory SnapshotEntry.fromStored({
    required String entity,
    required int ordinal,
    required String resourceId,
    required String canonicalPayload,
    required String owner,
    required int snapshotCursor,
  }) {
    _check(
      snapshotEntities.contains(entity) &&
          ordinal > 0 &&
          canonicalPayload.length <= 1048576,
    );
    _uuid(owner);
    _uuid(resourceId);
    final decoded = decodeWireJson(canonicalPayload);
    _check(decoded is Map<String, dynamic> && decoded['user_id'] == owner);
    final value = decoded as Map<String, dynamic>;
    const idFields = {
      'SONG_SOURCE': 'song_id',
      'RECORDING_FILE_SPEC': 'recording_id',
      'RECORDING_ASSET': 'recording_id',
      'RECORDING_TAG': 'recording_id',
      'USER_ENTITLEMENT': 'user_id',
      'STORAGE_USAGE': 'user_id',
      'SONG_CLOUD_SELECTION': 'song_id',
      'PIN_SLOT': 'user_id',
      'USER_SYNC_STATE': 'user_id',
      'CHANGE_LOG': 'entity_id',
      'DELETION_ITEM': 'entity_id',
    };
    _check(value[idFields[entity] ?? 'id'] == resourceId);
    if (entity == 'USER_SYNC_STATE') {
      _check(
        value['last_change_seq'] is int &&
            value['last_change_seq'] == snapshotCursor,
      );
    }
    return SnapshotEntry._(entity, ordinal, resourceId, canonicalPayload);
  }

  /// Each call returns a detached value; callers cannot mutate stored hash input.
  Map<String, dynamic> get payload =>
      decodeWireJson(canonicalPayload) as Map<String, dynamic>;
  @override
  String toString() => 'SnapshotEntry[REDACTED]';
}

bool _sameJson(Object? left, Object? right) {
  if (left is Map && right is Map) {
    return left.length == right.length &&
        left.keys.every(
          (k) => right.containsKey(k) && _sameJson(left[k], right[k]),
        );
  }
  if (left is List && right is List) {
    return left.length == right.length &&
        Iterable<int>.generate(left.length)
            .every((i) => _sameJson(left[i], right[i]));
  }
  return left == right;
}

/// Strict page/manifest binding before any page is written to staging.
final class SnapshotPage {
  SnapshotPage._(List<SnapshotEntry> entries, this.nextCursor)
    : entries = List.unmodifiable(entries);
  final List<SnapshotEntry> entries;
  final String? nextCursor;
  factory SnapshotPage.decode(
    String body, {
    required SnapshotManifest manifest,
    required String entity,
    required String owner,
    required int afterOrdinal,
    required DateTime now,
  }) {
    _check(
      snapshotEntities.contains(entity) &&
          afterOrdinal >= 0 &&
          now.isBefore(manifest.expiresAt),
    );
    _uuid(owner);
    final data = _object(decodeWireJson(body), {
      'snapshot_token',
      'snapshot_cursor',
      'expires_at',
      'entity',
      'entries',
      'next_cursor',
    });
    _check(
      data['snapshot_token'] == manifest.token &&
          data['snapshot_cursor'] is int &&
          data['snapshot_cursor'] == manifest.cursor &&
          data['entity'] == entity &&
          _instant(data['expires_at']) == manifest.expiresAt,
    );
    final rows = data['entries'];
    _check(rows is List && rows.length <= 100);
    final entries = <SnapshotEntry>[];
    var ordinal = afterOrdinal;
    for (final item in rows as List) {
      final row = _object(item, {
        'ordinal',
        'resource_id',
        'payload',
        'canonical_payload',
      });
      _check(_integer(row['ordinal'], minimum: 1) == ++ordinal);
      final canonical = row['canonical_payload'];
      _check(canonical is String && canonical.length <= 1048576);
      final value = decodeWireJson(canonical as String);
      _check(
        value is Map<String, dynamic> &&
            value['user_id'] == owner &&
            _sameJson(value, row['payload']),
      );
      final resource = _uuid(row['resource_id']);
      entries.add(
        SnapshotEntry.fromStored(
          entity: entity,
          ordinal: ordinal,
          resourceId: resource,
          canonicalPayload: canonical,
          owner: owner,
          snapshotCursor: manifest.cursor,
        ),
      );
    }
    final next = data['next_cursor'];
    _check(
      next == null ||
          next is String && RegExp(r'^sp1\.[A-Za-z0-9_-]+$').hasMatch(next),
    );
    final total = manifest.counts[entity]!;
    _check(
      ordinal <= total &&
          (next == null
              ? ordinal == total
              : entries.isNotEmpty && ordinal < total),
    );
    return SnapshotPage._(entries, next as String?);
  }
}

final class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}

/// Hash staged rows in entity/ordinal order without loading a 100MiB snapshot
/// into RAM. Canonical bytes are retained from the server, not reserialized.
final class SnapshotIntegrity {
  SnapshotIntegrity(this.manifest) {
    _sink = sha256.startChunkedConversion(_result);
    _sink.add(ascii.encode('SongRecord:snapshot-manifest:1'));
    _sink.add(_number(manifest.cursor, 8));
  }
  final SnapshotManifest manifest;
  final _result = _DigestSink();
  late final ByteConversionSink _sink;
  final _counts = <String, int>{};
  int _lastEntity = -1, _bytes = 0;
  bool _closed = false;
  static List<int> _number(int number, int width) {
    final data = ByteData(width);
    if (width == 8) {
      data.setInt64(0, number);
    } else {
      data.setInt32(0, number);
    }
    return data.buffer.asUint8List();
  }

  void add(SnapshotEntry entry) {
    _check(!_closed);
    try {
      _add(entry);
    } on FormatException {
      _closed = true;
      _sink.close();
      rethrow;
    }
  }

  void _add(SnapshotEntry entry) {
    final index = snapshotEntities.indexOf(entry.entity);
    _check(
      index >= _lastEntity &&
          entry.ordinal == (_counts[entry.entity] ?? 0) + 1 &&
          entry.ordinal <= manifest.counts[entry.entity]!,
    );
    final name = ascii.encode(entry.entity),
        payload = utf8.encode(entry.canonicalPayload);
    _bytes += payload.length;
    _check(_bytes <= 100 * 1024 * 1024);
    _lastEntity = index;
    _counts[entry.entity] = entry.ordinal;
    _sink.add(_number(name.length, 4));
    _sink.add(name);
    _sink.add(_number(entry.ordinal, 8));
    _sink.add(UuidValue(entry.resourceId).bytes);
    _sink.add(_number(payload.length, 4));
    _sink.add(payload);
  }

  void finish({required DateTime now}) {
    _check(!_closed);
    _closed = true;
    _sink.close();
    _check(
      now.isBefore(manifest.expiresAt) &&
          snapshotEntities.every(
            (entity) => (_counts[entity] ?? 0) == manifest.counts[entity],
          ) &&
          _result.value.toString() == manifest.hash,
    );
  }
}
