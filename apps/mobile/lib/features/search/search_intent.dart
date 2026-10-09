import 'karaoke_search.dart';

enum SearchPurpose { song, playlist }

class SearchIntent {
  const SearchIntent({
    this.purpose = SearchPurpose.song,
    this.playlistId,
    this.returnRoute = '/',
  });
  final SearchPurpose purpose;
  final String? playlistId;
  final String returnRoute;
  void validate() {
    if (returnRoute.isEmpty ||
        purpose == SearchPurpose.playlist &&
            (playlistId == null || playlistId!.trim().isEmpty)) {
      throw ArgumentError('Missing search destination context');
    }
  }
}

/// A selection carries its originating intent; KY cannot cross this boundary.
class KaraokeSelection {
  KaraokeSelection(this.candidate, this.intent) {
    intent.validate();
    if (candidate.brand != KaraokeBrand.tj) {
      throw ArgumentError('A TJ selection is required');
    }
  }
  final KaraokeCandidate candidate;
  final SearchIntent intent;
  @override
  String toString() => 'KaraokeSelection[REDACTED]';
}
