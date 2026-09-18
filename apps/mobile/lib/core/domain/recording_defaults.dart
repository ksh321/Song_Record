import 'package:song_record/core/domain/identifiers.dart';
import 'package:song_record/core/domain/song_types.dart';

final class SongRecordingDefaults {
  const SongRecordingDefaults({
    required this.songId,
    required this.version,
    this.representativeKey,
  });

  final SongId songId;
  final VersionCode version;
  final MusicalKey? representativeKey;
}

final class RecordingDefaultState {
  const RecordingDefaultState({
    required this.songId,
    required this.key,
    required this.version,
    required this.keyEdited,
    required this.versionEdited,
  });

  factory RecordingDefaultState.initial() => const RecordingDefaultState(
    songId: null,
    key: MusicalKey.original,
    version: VersionCode.normal,
    keyEdited: false,
    versionEdited: false,
  );

  final SongId? songId;
  final MusicalKey key;
  final VersionCode version;
  final bool keyEdited;
  final bool versionEdited;

  RecordingDefaultState selectSong(SongRecordingDefaults song) =>
      RecordingDefaultState(
        songId: song.songId,
        key: keyEdited ? key : (song.representativeKey ?? MusicalKey.original),
        version: versionEdited ? version : song.version,
        keyEdited: keyEdited,
        versionEdited: versionEdited,
      );

  RecordingDefaultState editKey(MusicalKey value) => RecordingDefaultState(
    songId: songId,
    key: value,
    version: version,
    keyEdited: true,
    versionEdited: versionEdited,
  );

  RecordingDefaultState editVersion(VersionCode value) => RecordingDefaultState(
    songId: songId,
    key: key,
    version: value,
    keyEdited: keyEdited,
    versionEdited: true,
  );

  RecordingDefaultState applySongDefaults(SongRecordingDefaults song) =>
      RecordingDefaultState(
        songId: song.songId,
        key: song.representativeKey ?? MusicalKey.original,
        version: song.version,
        keyEdited: false,
        versionEdited: false,
      );
}
