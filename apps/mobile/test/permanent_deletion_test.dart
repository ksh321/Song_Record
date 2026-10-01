import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/sync/permanent_deletion.dart';

void main() {
  const owner = '11111111-1111-4111-8111-111111111111',
      id = '22222222-2222-4222-8222-222222222222',
      ledgerId = '33333333-3333-4333-8333-333333333333';
  Map<String, dynamic> row(String type) => {
    'id': ledgerId,
    'user_id': owner,
    'entity_type': type,
    'entity_id': id,
    'object_generation': null,
    'revision': 5,
    'purged_at': '2026-10-01T00:00:00.123Z',
  };
  test('ordinary UUID markers project target UUID without altering ledger', () {
    for (final type in [
      'SONG',
      'RECORDING',
      'TAG',
      'PLAYLIST',
      'PLAYLIST_ITEM',
      'CONDITION',
    ]) {
      final source = row(type), before = Map<String, dynamic>.from(row(type));
      final marker = permanentDeletionPayload(
        source,
        owner: owner,
        entity: type,
        id: id,
      );
      expect(marker['id'], id);
      expect(marker['status'], 'DELETED');
      expect(marker['revision'], 5);
      expect(source, before);
      expect(marker.containsKey('user_id'), isFalse);
    }
  });
  test('foreign owner, generation, invalid revision and malformed time are rejected', () {
    for (final change in <Map<String, dynamic>>[
      {'user_id': id},
      {'entity_id': owner},
      {'object_generation': ledgerId},
      {'revision': 0},
      {'revision': 1.0},
      {'purged_at': '2026-02-30T00:00:00Z'},
      {'purged_at': '2026-10-01T00:00:00+09:00'},
      {'unexpected': true},
    ]) {
      expect(
        () => permanentDeletionPayload(
          {...row('SONG'), ...change},
          owner: owner,
          entity: 'SONG',
          id: id,
        ),
        throwsFormatException,
      );
    }
    expect(
      () => permanentDeletionPayload(
        row('RECORDING_ASSET'),
        owner: owner,
        entity: 'RECORDING_ASSET',
        id: id,
      ),
      throwsFormatException,
    );
  });
}
