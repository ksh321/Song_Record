import '../../core/database/local_models.dart';
import '../../core/domain/input_validation.dart';
import '../../core/domain/song_types.dart';
import '../../core/sync/local_repository.dart';
import 'my_song_detail.dart';

typedef SongEditPreparer = Future<void> Function() Function(
  SongEditDraft draft,
);

final class SongEditDraft {
  SongEditDraft(MySongDetail detail)
    : original = Map<String, Object?>.unmodifiable(detail.song!.payload),
      revision = detail.revision,
      title = detail.song!.view.title,
      artist = detail.song!.view.artist,
      note = detail.song!.view.note,
      version = detail.song!.view.version,
      musicalKey = detail.song!.view.musicalKey,
      tier = detail.song!.view.tier;
  final Map<String, Object?> original;
  final int revision;
  String title, artist, note;
  VersionCode version;
  MusicalKey? musicalKey;
  SongTier? tier;

  Map<String, Object?> get changes {
    final t = validateInput(InputField.title, title),
        a = validateInput(InputField.artist, artist),
        n = validateInput(InputField.note, note);
    if (!t.isValid || !a.isValid || !n.isValid) {
      throw ArgumentError('곡명·가수는 1~200자, 아쉬운 점은 2,000자 이내로 입력해 주세요.');
    }
    final fields = <String, Object?>{
      'title': t.value,
      'artist': a.value,
      'note': n.value,
      'version_code': version.name.toUpperCase(),
      'representative_key_mode': musicalKey?.mode.name.toUpperCase(),
      'representative_key_shift': musicalKey?.shift,
      'tier': tier?.name.toUpperCase(),
    };
    return {
      for (final entry in fields.entries)
        if (original[entry.key] != entry.value) entry.key: entry.value,
    };
  }

  Future<void> Function() prepare(LocalRepository repository) {
    final patch = changes;
    if (patch.isEmpty) return () async {};
    final command = repository.preparePatch(
      entity: LocalEntity.song,
      entityId: original['id'] as String,
      baseRevision: revision,
      draft: {...original, ...patch},
      changes: patch,
    );
    return () => repository.saveCheckedEdit(command, original);
  }
}
