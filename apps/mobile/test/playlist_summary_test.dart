import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/playlists/playlist_library.dart';

void main() {
  test(
    'preview counts registered and standalone candidates, not missing songs',
    () {
      final summary = PlaylistSummary.fromItems(
        [
          {'song_id': 'active'},
          {
            'candidate_brand': 'TJ',
            'candidate_snapshot': {'title': '후보 곡'},
          },
          {
            'song_id': 'trashed',
            'candidate_brand': 'TJ',
            'candidate_snapshot': {'title': '지운 곡'},
          },
          {
            'candidate_brand': 'KY',
            'candidate_snapshot': {'title': '지원하지 않는 후보'},
          },
          {'song_id': 'third'},
        ],
        {
          'active': {'title': '현재 곡'},
          'third': {'title': '다음 곡'},
        },
      );
      expect(summary.count, 3);
      expect(summary.preview, '현재 곡 · 후보 곡');
      expect(PlaylistSummary.fromItems([], {}).preview, '첫 곡을 담아보세요');
      expect(PlaylistSummary.fromItems([], {}).count, 0);
    },
  );
}
