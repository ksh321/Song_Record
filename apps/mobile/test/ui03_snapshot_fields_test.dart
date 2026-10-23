import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/database/snapshot_metadata_projection.dart';

import 'change_payload_validation_test.dart' show songChange;
import 'snapshot_playlist_item_projection_test.dart'
    show playlistSource, playlistOwner, playlistParentId;

void main() {
  test('first-device snapshot retains suitability, playlist icon and library order', () {
    final song = {
      ...songChange(playlistParentId, 3),
      'user_id': playlistOwner,
      'is_suitable': true,
    };
    final projected = projectSnapshotMetadata(
      LocalEntity.song,
      song,
      owner: playlistOwner,
      id: playlistParentId,
    );
    expect(projected['is_suitable'], isTrue);
    final playlist = projectSnapshotMetadata(
      LocalEntity.playlist,
      {...playlistSource(), 'icon': 'star', 'display_order': 9},
      owner: playlistOwner,
      id: playlistParentId,
    );
    expect(playlist['icon'], 'star');
    expect(playlist['display_order'], 9);
    expect(
      () => projectSnapshotMetadata(
        LocalEntity.playlist,
        {...playlistSource(), 'display_order': -1},
        owner: playlistOwner,
        id: playlistParentId,
      ),
      throwsFormatException,
    );
    expect(
      () => projectSnapshotMetadata(
        LocalEntity.song,
        song,
        owner: playlistParentId,
        id: playlistParentId,
      ),
      throwsFormatException,
    );
  });
}
