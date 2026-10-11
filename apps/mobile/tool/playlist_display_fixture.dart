import 'dart:convert';

import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/features/playlists/playlist_library.dart';

import 'playlist_addition_fixture.dart';

Future<void> preparePlaylistDisplay(PlaylistAdditionFixture fixture) async {
  await fixture.initialize();
  final library = PlaylistLibrary(fixture.repository);
  if ((await library.items(fixture.playlistId)).isEmpty) {
    await library.addRegistered(
      (await library.load()).single,
      playlistFixtureId(1910),
    )();
    await fixture.synchronize();
    await library.addCandidate(
      (await library.load()).single,
      'isolated-tj-candidate',
    )();
    await fixture.synchronize();
  }
}

Future<void> editPlaylistDisplaySong(PlaylistAdditionFixture fixture) async {
  final repo = fixture.repository, id = playlistFixtureId(1910);
  final copy = (await repo.read(LocalEntity.song, id))!;
  final value =
      jsonDecode(copy.localJson ?? copy.serverJson!) as Map<String, dynamic>;
  final changes = <String, Object?>{
    'title': '수정 반영 곡',
    'artist': '수정 가수',
    'version_code': 'LIVE',
    'tier': 'A',
    'representative_key_mode': 'MALE',
    'representative_key_shift': 2,
  };
  await repo.saveCheckedEdit(
    repo.preparePatch(
      entity: LocalEntity.song,
      entityId: id,
      baseRevision: copy.revision,
      draft: {...value, ...changes},
      changes: changes,
    ),
    value,
  );
}
