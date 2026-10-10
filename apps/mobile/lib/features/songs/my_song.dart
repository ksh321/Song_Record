import '../../core/domain/identifiers.dart';
import '../../core/domain/song_types.dart';
import '../../core/widgets/music_view_data.dart';

final class MySong {
  MySong(this.payload) : view = _view(payload);
  final Map<String, dynamic> payload;
  final RegisteredSongViewData view;
  static RegisteredSongViewData _view(Map<String, dynamic> p) {
    if (p['lifecycle_state'] != 'ACTIVE' ||
        p['title'] is! String ||
        p['artist'] is! String) {
      throw const FormatException('Invalid active song');
    }
    final key = p['representative_key_mode'];
    final shift = p['representative_key_shift'];
    return RegisteredSongViewData(
      id: SongId(p['id'] as String),
      title: p['title'] as String,
      artist: p['artist'] as String,
      version: VersionCode.values.byName(
        (p['version_code'] as String).toLowerCase(),
      ),
      tier: p['tier'] == null
          ? null
          : SongTier.values.byName((p['tier'] as String).toLowerCase()),
      tjNumber: p['tj_number'] == null
          ? null
          : TjNumber(p['tj_number'] as String),
      musicalKey: key == null || shift == null
          ? null
          : MusicalKey(
              mode: KeyMode.values.byName((key as String).toLowerCase()),
              shift: shift as int,
            ),
      note: p['note'] as String? ?? '',
    );
  }

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    return q.isEmpty ||
        view.title.toLowerCase().contains(q) ||
        view.artist.toLowerCase().contains(q);
  }
}
