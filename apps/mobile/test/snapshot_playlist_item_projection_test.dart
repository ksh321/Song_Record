import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/database/snapshot_playlist_item_projection.dart';

const playlistOwner = '11111111-1111-4111-8111-111111111111';
const playlistItemId = '33333333-3333-4333-8333-333333333333';
const playlistParentId = '44444444-4444-4444-8444-444444444444';
const playlistSongId = '77777777-7777-4777-8777-777777777777';
Map<String, dynamic> playlistSource() => {
  'id': playlistParentId,
  'user_id': playlistOwner,
  'name': '연습',
  'revision': 8,
  'deleted_at': null,
  'created_at': '2026-10-01T00:00:00Z',
  'updated_at': '2026-10-01T00:00:00Z',
};
Map<String, dynamic> playlistItemSource() => {
  'id': playlistItemId,
  'user_id': playlistOwner,
  'playlist_id': playlistParentId,
  'song_id': null,
  'candidate_brand': 'TJ',
  'candidate_number': '123',
  'candidate_snapshot': {'title': '후보 곡', 'artist': '합성 자료'},
  'entry_key': 'tj:123',
  'position': 0,
  'hidden_by_batch_id': null,
  'created_at': '2026-10-01T00:00:00Z',
  'updated_at': '2026-10-01T00:00:00Z',
};
void main() {
  Map<String, dynamic> project(
    Map<String, dynamic> item, {
    Map<String, dynamic>? parent,
    Map<String, dynamic>? song,
  }) => projectSnapshotPlaylistItem(
    item,
    owner: playlistOwner,
    id: playlistItemId,
    playlist: parent ?? playlistSource(),
    song: song,
  );
  test(
    'candidate retains identity/order and derives version from its parent',
    () {
      final source = playlistItemSource();
      final result = project(source);
      expect(result['revision'], 8);
      expect(result['playlist_revision'], 8);
      expect(result['position'], 0);
      expect(source.containsKey('revision'), isFalse);
      (result['candidate_snapshot'] as Map)['title'] = 'edited';
      expect((source['candidate_snapshot'] as Map)['title'], '후보 곡');
    },
  );
  for (final bad in <String, dynamic>{
    'id': playlistParentId,
    'user_id': playlistParentId,
    'playlist_id': playlistItemId,
    'candidate_brand': 'KY',
    'candidate_number': '12a',
    'candidate_snapshot': null,
    'entry_key': 'tj:999',
    'position': -1,
    'hidden_by_batch_id': 'bad',
    'revision': 77,
    'updated_at': '2026-02-30T00:00:00Z',
  }.entries) {
    test('invalid item ${bad.key} is rejected', () {
      expect(
        () => project({...playlistItemSource(), bad.key: bad.value}),
        throwsFormatException,
      );
    });
  }
  test(
    'linked TJ keeps candidate identity; different number or owner is rejected',
    () {
      final item = {...playlistItemSource(), 'song_id': playlistSongId};
      final song = {
        'id': playlistSongId,
        'user_id': playlistOwner,
        'source_type': 'TJ',
        'tj_number': '123',
      };
      expect(project(item, song: song)['entry_key'], 'tj:123');
      expect(
        () => project(item, song: {...song, 'tj_number': '124'}),
        throwsFormatException,
      );
      expect(
        () => project(item, song: {...song, 'user_id': playlistParentId}),
        throwsFormatException,
      );
      expect(() => project(item), throwsFormatException);
    },
  );
  test('manual link has no external candidate and uses its song UUID key', () {
    final item = {
      ...playlistItemSource(),
      'song_id': playlistSongId,
      'candidate_brand': null,
      'candidate_number': null,
      'candidate_snapshot': null,
      'entry_key': 'manual:$playlistSongId',
    };
    final song = {
      'id': playlistSongId,
      'user_id': playlistOwner,
      'source_type': 'MANUAL',
      'tj_number': null,
    };
    expect(project(item, song: song)['song_id'], playlistSongId);
    expect(
      () => project({...item, 'candidate_brand': 'TJ'}, song: song),
      throwsFormatException,
    );
  });
  test(
    'parent deletion and hidden item remain distinct from source row removal',
    () {
      final result = project(
        {...playlistItemSource(), 'hidden_by_batch_id': playlistSongId},
        parent: {...playlistSource(), 'deleted_at': '2026-10-01T01:00:00Z'},
      );
      expect(result['playlist_deleted_at'], '2026-10-01T01:00:00Z');
      expect(result['hidden_by_batch_id'], playlistSongId);
      expect(result['candidate_snapshot'], isNotNull);
    },
  );
}
