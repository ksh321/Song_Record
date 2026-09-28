package com.ksh321.songrecord.api.domain;

import java.text.Normalizer;
import java.io.ByteArrayOutputStream;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Objects;
import java.util.Set;

public final class DomainOrdering {
    public static final String SORT_KEY_VERSION = "SR-SORT-1";
    public static final String SORT_BYTES_VERSION = "SR-SORT-BYTES-1";

    private DomainOrdering() {}

    public record TitleRow(DomainTypes.SongId id, String title) {}

    public static List<TitleRow> sortByTitle(List<TitleRow> rows) {
        return rows.stream()
                .sorted((left, right) -> {
                    var compared = compareSortText(left.title, right.title);
                    return compared != 0 ? compared : left.id.compareTo(right.id);
                })
                .toList();
    }

    public static int compareSortText(String left, String right) {
        return SortKey.from(left).compareTo(SortKey.from(right));
    }

    /** Unsigned lexicographic bytes for VARBINARY keys; never compare with signed byte ordering. */
    public static byte[] sortKeyBytes(String text) {
        var key = SortKey.from(text);
        var out = new ByteArrayOutputStream();
        out.write(key.group);
        for (var token : key.tokens) {
            if (token.number) {
                out.write(1);
                int length = token.text.length();
                for (int shift = 24; shift >= 0; shift -= 8) out.write(length >>> shift);
                token.text.chars().forEach(out::write);
            } else {
                out.write(2);
                out.write(token.codePoint >>> 16);
                out.write(token.codePoint >>> 8);
                out.write(token.codePoint);
            }
        }
        out.write(0); // End sorts before another token, including numeric zero.
        return out.toByteArray();
    }

    public record RecordingCandidate(
            DomainTypes.RecordingId id,
            Instant recordedAt,
            DomainTypes.RecordingTier tier,
            boolean eligible) {
        public RecordingCandidate {
            Objects.requireNonNull(id, "id");
            Objects.requireNonNull(recordedAt, "recordedAt");
        }
    }

    public record RecordingSelection(
            DomainTypes.RecordingId representative,
            DomainTypes.RecordingId latest,
            DomainTypes.RecordingId lowestTier) {
        public Set<DomainTypes.RecordingId> uniqueIds() {
            var ids = new LinkedHashSet<DomainTypes.RecordingId>();
            if (representative != null) ids.add(representative);
            if (latest != null) ids.add(latest);
            if (lowestTier != null) ids.add(lowestTier);
            return Set.copyOf(ids);
        }
    }

    public static RecordingSelection selectRecordingRoles(
            List<RecordingCandidate> candidates,
            DomainTypes.RecordingId representativeId) {
        var eligible = candidates.stream().filter(RecordingCandidate::eligible).toList();
        var representative = representativeId == null ? null : eligible.stream()
                .filter(candidate -> candidate.id.equals(representativeId))
                .map(RecordingCandidate::id)
                .findFirst()
                .orElse(null);
        var latest = eligible.stream().min(DomainOrdering::compareLatestFirst)
                .map(RecordingCandidate::id).orElse(null);
        var lowestTier = eligible.stream().filter(candidate -> candidate.tier != null)
                .min(DomainOrdering::compareLowestTierFirst)
                .map(RecordingCandidate::id).orElse(null);
        return new RecordingSelection(representative, latest, lowestTier);
    }

    private static int compareLatestFirst(RecordingCandidate left, RecordingCandidate right) {
        var time = right.recordedAt.compareTo(left.recordedAt);
        return time != 0 ? time : left.id.compareTo(right.id);
    }

    private static int compareLowestTierFirst(RecordingCandidate left, RecordingCandidate right) {
        var tier = Integer.compare(lowTierRank(left.tier), lowTierRank(right.tier));
        return tier != 0 ? tier : compareLatestFirst(left, right);
    }

    private static int lowTierRank(DomainTypes.RecordingTier tier) {
        return switch (tier) {
            case D -> 0;
            case C -> 1;
            case B -> 2;
            case A -> 3;
            case S -> 4;
        };
    }

    private record SortKey(int group, List<SortToken> tokens) implements Comparable<SortKey> {
        static SortKey from(String raw) {
            var value = normalizeText(raw);
            if (value.isEmpty()) return new SortKey(4, List.of());
            var codePoints = value.codePoints().toArray();
            var tokens = new ArrayList<SortToken>();
            for (var index = 0; index < codePoints.length;) {
                var codePoint = codePoints[index];
                if (codePoint >= '0' && codePoint <= '9') {
                    var digits = new StringBuilder();
                    while (index < codePoints.length && codePoints[index] >= '0' && codePoints[index] <= '9') {
                        digits.appendCodePoint(codePoints[index++]);
                    }
                    tokens.add(SortToken.number(digits.toString()));
                } else {
                    tokens.add(SortToken.character(codePoint));
                    index++;
                }
            }
            return new SortKey(groupOf(codePoints[0]), List.copyOf(tokens));
        }

        @Override
        public int compareTo(SortKey other) {
            var groupCompared = Integer.compare(group, other.group);
            if (groupCompared != 0) return groupCompared;
            var count = Math.min(tokens.size(), other.tokens.size());
            for (var index = 0; index < count; index++) {
                var compared = tokens.get(index).compareTo(other.tokens.get(index));
                if (compared != 0) return compared;
            }
            return Integer.compare(tokens.size(), other.tokens.size());
        }
    }

    private record SortToken(boolean number, String text, int codePoint) implements Comparable<SortToken> {
        static SortToken number(String raw) {
            var index = 0;
            while (index < raw.length() - 1 && raw.charAt(index) == '0') index++;
            return new SortToken(true, raw.substring(index), 0);
        }

        static SortToken character(int codePoint) {
            return new SortToken(false, "", codePoint);
        }

        @Override
        public int compareTo(SortToken other) {
            if (number != other.number) return number ? -1 : 1;
            if (!number) return Integer.compare(codePoint, other.codePoint);
            var length = Integer.compare(text.length(), other.text.length());
            return length != 0 ? length : text.compareTo(other.text);
        }
    }

    public static String normalizeText(String raw) {
        var value = Normalizer.normalize(InputContracts.trimContractWhitespace(raw), Normalizer.Form.NFC);
        var builder = new StringBuilder();
        value.codePoints().forEach(codePoint ->
                builder.appendCodePoint(codePoint >= 'A' && codePoint <= 'Z' ? codePoint + 32 : codePoint));
        return builder.toString();
    }

    private static int groupOf(int codePoint) {
        var hangul = (codePoint >= 0xac00 && codePoint <= 0xd7a3)
                || (codePoint >= 0x1100 && codePoint <= 0x11ff)
                || (codePoint >= 0x3130 && codePoint <= 0x318f)
                || (codePoint >= 0xa960 && codePoint <= 0xa97f)
                || (codePoint >= 0xd7b0 && codePoint <= 0xd7ff);
        if (hangul) return 0;
        if ((codePoint >= 'A' && codePoint <= 'Z') || (codePoint >= 'a' && codePoint <= 'z')) return 1;
        if (codePoint >= '0' && codePoint <= '9') return 2;
        return 3;
    }
}
