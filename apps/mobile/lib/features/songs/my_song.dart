import '../../core/domain/domain_ordering.dart';
import '../../core/domain/identifiers.dart';
import '../../core/domain/song_types.dart';
import '../../core/widgets/music_view_data.dart';
import '../../core/widgets/sort_sheet.dart';

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

/// The same selected comparator is used inside each fixed tier group.
List<MySong> orderMySongs(Iterable<MySong> songs, SongSort sort) =>
    songs.toList()..sort((a, b) {
      int title() => compareSortText(a.view.title, b.view.title);
      int rank(MySong song) => song.view.tier?.index ?? 5;
      DateTime? time(MySong song, String field) =>
          DateTime.tryParse(song.payload[field] as String? ?? '');
      int descending(String field) {
        final left = time(a, field), right = time(b, field);
        if (left == null) return right == null ? 0 : 1;
        if (right == null) return -1;
        return right.compareTo(left);
      }

      final primary = switch (sort) {
        SongSort.recentlyAdded => descending('created_at'),
        SongSort.recentlyRecorded => descending('latest_recorded_at'),
        SongSort.tier => rank(a).compareTo(rank(b)),
        SongSort.title => title(),
        SongSort.artist => compareSortText(a.view.artist, b.view.artist),
      };
      if (primary != 0) return primary;
      if (sort == SongSort.tier || sort == SongSort.artist) {
        final compared = title();
        if (compared != 0) return compared;
      }
      return a.view.id.compareTo(b.view.id);
    });

Map<String, List<MySong>> groupMySongs(Iterable<MySong> songs, SongSort sort) {
  final ordered = orderMySongs(songs, sort);
  return {
    for (final tier in [...SongTier.values, null])
      formatSongTier(tier): ordered.where((s) => s.view.tier == tier).toList(),
  };
}
