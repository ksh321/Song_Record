import 'package:song_record/core/domain/identifiers.dart';
import 'package:song_record/core/domain/song_types.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

const sortKeyVersion = 'SR-SORT-1';

final class TitleSortRow {
  const TitleSortRow({required this.id, required this.title});
  final SongId id;
  final String title;
}

List<TitleSortRow> sortByTitle(Iterable<TitleSortRow> rows) {
  final sorted = rows.toList();
  sorted.sort((left, right) {
    final compared = compareSortText(left.title, right.title);
    return compared != 0 ? compared : left.id.compareTo(right.id);
  });
  return sorted;
}

int compareSortText(String left, String right) {
  final a = _SortKey.from(left);
  final b = _SortKey.from(right);
  final group = a.group.compareTo(b.group);
  if (group != 0) return group;
  final count = a.tokens.length < b.tokens.length
      ? a.tokens.length
      : b.tokens.length;
  for (var index = 0; index < count; index += 1) {
    final compared = a.tokens[index].compareTo(b.tokens[index]);
    if (compared != 0) return compared;
  }
  return a.tokens.length.compareTo(b.tokens.length);
}

final class RecordingCandidate {
  const RecordingCandidate({
    required this.id,
    required this.recordedAt,
    required this.tier,
    this.eligible = true,
  });
  final RecordingId id;
  final DateTime recordedAt;
  final RecordingTier? tier;
  final bool eligible;
}

final class RecordingSelection {
  const RecordingSelection({this.representative, this.latest, this.lowestTier});
  final RecordingId? representative;
  final RecordingId? latest;
  final RecordingId? lowestTier;

  Set<RecordingId> get uniqueIds => {?representative, ?latest, ?lowestTier};
}

RecordingSelection selectRecordingRoles(
  Iterable<RecordingCandidate> candidates, {
  RecordingId? representativeId,
}) {
  final eligible = candidates.where((candidate) => candidate.eligible).toList();
  final representative = representativeId == null
      ? null
      : eligible
            .where((candidate) => candidate.id == representativeId)
            .firstOrNull
            ?.id;
  eligible.sort(_latestFirst);
  final latest = eligible.firstOrNull?.id;
  final tiered = eligible.where((candidate) => candidate.tier != null).toList()
    ..sort(_lowestTierFirst);
  return RecordingSelection(
    representative: representative,
    latest: latest,
    lowestTier: tiered.firstOrNull?.id,
  );
}

int _latestFirst(RecordingCandidate left, RecordingCandidate right) {
  final time = right.recordedAt.compareTo(left.recordedAt);
  return time != 0 ? time : left.id.compareTo(right.id);
}

int _lowestTierFirst(RecordingCandidate left, RecordingCandidate right) {
  final tier = _lowTierRank(left.tier!).compareTo(_lowTierRank(right.tier!));
  return tier != 0 ? tier : _latestFirst(left, right);
}

int _lowTierRank(RecordingTier tier) => switch (tier) {
  RecordingTier.d => 0,
  RecordingTier.c => 1,
  RecordingTier.b => 2,
  RecordingTier.a => 3,
  RecordingTier.s => 4,
};

final class _SortKey {
  const _SortKey(this.group, this.tokens);
  final int group;
  final List<_SortToken> tokens;

  factory _SortKey.from(String raw) {
    final value = normalizeSongText(raw);
    if (value.isEmpty) return const _SortKey(4, []);
    final runes = value.runes.toList();
    final tokens = <_SortToken>[];
    for (var index = 0; index < runes.length;) {
      final rune = runes[index];
      if (rune >= 0x30 && rune <= 0x39) {
        final buffer = StringBuffer();
        while (index < runes.length &&
            runes[index] >= 0x30 &&
            runes[index] <= 0x39) {
          buffer.writeCharCode(runes[index]);
          index += 1;
        }
        tokens.add(_SortToken.number(buffer.toString()));
      } else {
        tokens.add(_SortToken.character(rune));
        index += 1;
      }
    }
    return _SortKey(_groupOf(runes.first), tokens);
  }
}

final class _SortToken implements Comparable<_SortToken> {
  const _SortToken._({
    required this.number,
    required this.text,
    required this.rune,
  });
  factory _SortToken.number(String raw) {
    final trimmed = raw.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    return _SortToken._(number: true, text: trimmed, rune: null);
  }
  const _SortToken.character(int value)
    : this._(number: false, text: '', rune: value);

  final bool number;
  final String text;
  final int? rune;

  @override
  int compareTo(_SortToken other) {
    if (number != other.number) return number ? -1 : 1;
    if (!number) return rune!.compareTo(other.rune!);
    final length = text.length.compareTo(other.text.length);
    return length != 0 ? length : text.compareTo(other.text);
  }
}

String normalizeSongText(String raw) {
  final trimmed = trimContractWhitespace(raw);
  final composed = unorm.nfc(trimmed);
  return String.fromCharCodes(
    composed.runes.map((rune) {
      if (rune >= 0x41 && rune <= 0x5a) return rune + 0x20;
      return rune;
    }),
  );
}

int _groupOf(int rune) {
  final hangul =
      (rune >= 0xac00 && rune <= 0xd7a3) ||
      (rune >= 0x1100 && rune <= 0x11ff) ||
      (rune >= 0x3130 && rune <= 0x318f) ||
      (rune >= 0xa960 && rune <= 0xa97f) ||
      (rune >= 0xd7b0 && rune <= 0xd7ff);
  if (hangul) return 0;
  if ((rune >= 0x41 && rune <= 0x5a) || (rune >= 0x61 && rune <= 0x7a)) {
    return 1;
  }
  if (rune >= 0x30 && rune <= 0x39) return 2;
  return 3;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
