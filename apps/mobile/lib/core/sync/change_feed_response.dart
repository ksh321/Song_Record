import 'dart:convert';

import '../database/local_models.dart';
import '../domain/identifiers.dart';
import 'wire_json.dart';

void _valid(bool condition) {
  if (!condition) throw const FormatException('Invalid change feed');
}

Map<String, dynamic> _object(Object? value, Set<String> fields) {
  _valid(value is Map<String, dynamic>);
  final result = value as Map<String, dynamic>;
  _valid(result.length == fields.length && result.keys.every(fields.contains));
  return result;
}

int _sequence(Object? value, {int minimum = 0}) {
  _valid(value is int && value >= minimum && value <= 9223372036854775807);
  return value as int;
}

final class ChangeFeedEntry {
  const ChangeFeedEntry._(
    this.sequence,
    this.entity,
    this.id,
    this.revision,
    this.deleted,
    this._payload,
  );
  final int sequence, revision;
  final LocalEntity entity;
  final String id, _payload;
  final bool deleted;
  Map<String, dynamic> get payload =>
      jsonDecode(_payload) as Map<String, dynamic>;
  @override
  String toString() => 'ChangeFeedEntry[REDACTED]';
}

/// Validation only. Neither a successful decode nor nextSequence acknowledges a
/// local commit. The caller must apply the complete page in an account transaction.
final class ChangeFeedPage {
  ChangeFeedPage._(
    this.owner,
    this.afterSequence,
    this.nextSequence,
    this.head,
    this.hasMore,
    List<ChangeFeedEntry> entries,
  ) : entries = List.unmodifiable(entries);
  final int afterSequence, nextSequence, head;
  final String owner;
  final bool hasMore;
  final List<ChangeFeedEntry> entries;

  factory ChangeFeedPage.decode(
    String body, {
    required String owner,
    required int expectedAfter,
    int limit = 50,
  }) {
    _valid(UuidValue(owner).value == owner);
    _valid(expectedAfter >= 0 && expectedAfter <= 9223372036854775807);
    _valid(limit >= 1 && limit <= 100);
    final root = _object(jsonDecode(body), {
      'after_seq',
      'next_seq',
      'head_seq',
      'has_more',
      'changes',
    });
    final after = _sequence(root['after_seq']);
    final next = _sequence(root['next_seq']);
    final head = _sequence(root['head_seq']);
    _valid(
      after == expectedAfter && head >= after && next >= after && next <= head,
    );
    _valid(root['has_more'] is bool && root['changes'] is List);
    final more = root['has_more'] as bool;
    final values = root['changes'] as List;
    // The feed envelope is not canonicalized by the server; retain its strict
    // cursor/revision types. Only stored domain payloads use exponent spelling.
    final normalizedValues =
        (decodeWireJson(body) as Map<String, dynamic>)['changes'] as List;
    _valid(values.length <= limit);
    const types = {
      'SONG': LocalEntity.song,
      'RECORDING': LocalEntity.recording,
      'PLAYLIST': LocalEntity.playlist,
      'PLAYLIST_ITEM': LocalEntity.playlistItem,
      'TAG': LocalEntity.tag,
      'RECORDING_ASSET': LocalEntity.recordingAsset,
      'CONDITION': LocalEntity.recordingCondition,
    };
    var previous = after;
    final entries = <ChangeFeedEntry>[];
    for (var index = 0; index < values.length; index++) {
      final value = values[index];
      final row = _object(value, {
        'change_seq',
        'entity_type',
        'entity_id',
        'revision',
        'operation',
        'payload',
      });
      final sequence = _sequence(row['change_seq'], minimum: 1);
      _valid(
        previous < 9223372036854775807 &&
            sequence == previous + 1 &&
            sequence <= head,
      );
      final entity = types[row['entity_type']];
      _valid(entity != null && row['entity_id'] is String);
      final id = row['entity_id'] as String;
      _valid(UuidValue(id).value == id);
      final revision = _sequence(row['revision'], minimum: 1);
      final operation = row['operation'];
      _valid(operation == 'UPSERT' || operation == 'DELETE');
      _valid(row['payload'] is Map<String, dynamic>);
      final payload = normalizedValues[index]['payload'] as Map<String, dynamic>;
      _valid(!payload.containsKey('user_id') || payload['user_id'] == owner);
      _valid(!payload.containsKey('id') || payload['id'] == id);
      _valid(
        !payload.containsKey('revision') ||
            payload['revision'] == revision && payload['revision'] is int,
      );
      // Some change payloads represent related state and have their own revision
      // names. Preserve them; numeric spelling does not create missing fields.
      entries.add(
        ChangeFeedEntry._(
          sequence,
          entity!,
          id,
          revision,
          operation == 'DELETE',
          jsonEncode(payload),
        ),
      );
      previous = sequence;
    }
    _valid(next == previous);
    _valid(more ? values.length == limit && next < head : next == head);
    return ChangeFeedPage._(owner, after, next, head, more, entries);
  }
  @override
  String toString() => 'ChangeFeedPage[REDACTED]';
}
