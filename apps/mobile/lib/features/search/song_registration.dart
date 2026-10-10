import '../../core/database/local_models.dart';
import '../../core/domain/input_validation.dart';
import '../../core/domain/song_types.dart';
import '../../core/sync/local_repository.dart';
import 'karaoke_search.dart';
import 'search_intent.dart';

typedef SongRegistrationPreparer = Future<void> Function() Function(
  SongRegistrationDraft draft,
);

class SongRegistrationDraft {
  SongRegistrationDraft({
    required this.intent,
    required this.title,
    required this.artist,
    this.note = '',
    this.version = VersionCode.normal,
    this.candidate,
    this.manualApproval,
  }) {
    intent.validate();
    if ((candidate == null) == (manualApproval == null) ||
        candidate != null && candidate!.brand != KaraokeBrand.tj) {
      throw ArgumentError('Verified TJ or confirmed manual input is required');
    }
  }
  final SearchIntent intent;
  final String title, artist, note;
  final VersionCode version;
  final KaraokeCandidate? candidate;
  final ManualSearchApproval? manualApproval;

  LocalEdit prepare(LocalRepository repository) {
    final t = validateInput(InputField.title, title),
        a = validateInput(InputField.artist, artist),
        n = validateInput(InputField.note, note);
    if (!t.isValid || !a.isValid || !n.isValid) {
      throw ArgumentError('Invalid song input');
    }
    final c = candidate;
    final changes = <String, Object?>{
      'source_type': c == null ? 'MANUAL' : 'TJ',
      if (c == null)
        'manual_reason': 'TJ_NOT_FOUND'
      else
        'source_token': c.sourceToken,
      'title': t.value,
      'artist': a.value,
      'note': n.value,
      'version_code': version.name.toUpperCase(),
    };
    final draft = <String, Object?>{
      'source_type': changes['source_type'],
      'tj_number': c?.number,
      'title': t.value,
      'artist': a.value,
      'note': n.value,
      'version_code': changes['version_code'],
      'lifecycle_state': 'ACTIVE',
      'tier': null,
    };
    return repository.prepareCreate(
      entity: LocalEntity.song,
      draft: draft,
      changes: changes,
    );
  }
}
