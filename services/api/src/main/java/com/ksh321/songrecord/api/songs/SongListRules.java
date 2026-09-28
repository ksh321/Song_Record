package com.ksh321.songrecord.api.songs;

import com.ksh321.songrecord.api.domain.DomainOrdering;
import com.ksh321.songrecord.api.domain.DomainTypes.*;
import com.ksh321.songrecord.api.pagination.KeysetPages;
import com.ksh321.songrecord.api.pagination.PageCursor;
import com.ksh321.songrecord.api.web.ApiException;
import java.time.Instant;
import java.util.*;
import org.springframework.http.HttpStatus;
import tools.jackson.databind.json.JsonMapper;

/** Domain/query contract for the P08-05b SQL adapter. No repository, provider, or HTTP endpoint here. */
public final class SongListRules {
    private static final JsonMapper JSON = new JsonMapper();
    private SongListRules() {}

    public enum Sort { ADDED_DESC, RECORDED_DESC, TIER, TITLE, ARTIST }
    public enum View { ALL, TIER_GROUPED }

    public record Query(String q, Sort sort, View view, int limit) {
        public Query {
            q = DomainOrdering.normalizeText(q == null ? "" : q);
            if (q.codePointCount(0, q.length()) > 200) throw invalid();
            sort = sort == null ? Sort.ADDED_DESC : sort;
            view = view == null ? View.ALL : view;
            limit = PageCursor.pageSize(limit);
        }
        public static Query parse(String q, String sort, String view, Integer limit) {
            try {
                return new Query(q, sort == null ? null : Sort.valueOf(sort),
                        view == null ? null : View.valueOf(view), PageCursor.pageSize(limit));
            } catch (IllegalArgumentException e) { throw invalid(); }
        }
        public PageCursor.Query cursorQuery() {
            return new PageCursor.Query("songs", sort.name(),
                    DomainOrdering.SORT_KEY_VERSION + "/" + DomainOrdering.SORT_BYTES_VERSION,
                    JSON.writeValueAsString(Map.of("q", q, "view", view.name())), limit);
        }
        public boolean includes(UUID owner, Row row) {
            return owner.equals(row.owner) && row.lifecycle == LifecycleState.ACTIVE
                    && (DomainOrdering.normalizeText(row.title).contains(q)
                        || DomainOrdering.normalizeText(row.artist).contains(q));
        }
        /** Bind this value with an explicit SQL ESCAPE '!'; %, _ and ! are user text. */
        public String likePattern() { return "%" + q.replace("!", "!!").replace("%", "!%").replace("_", "!_") + "%"; }
        @Override public String toString() { return "SongListQuery[REDACTED]"; }
    }

    public record Row(UUID id, UUID owner, String title, String artist, SongTier tier,
                      Instant createdAt, Instant latestRecordedAt, LifecycleState lifecycle) {
        public Row {
            Objects.requireNonNull(id); Objects.requireNonNull(owner); Objects.requireNonNull(title);
            Objects.requireNonNull(artist); Objects.requireNonNull(createdAt); Objects.requireNonNull(lifecycle);
        }
    }

    /** File state is intentionally absent: only recording metadata determines eligibility. */
    public record Recording(UUID owner, UUID songId, Instant recordedAt,
                            MetadataState metadata, LifecycleState lifecycle) {
        public Recording {
            Objects.requireNonNull(owner); Objects.requireNonNull(recordedAt);
            Objects.requireNonNull(metadata); Objects.requireNonNull(lifecycle);
        }
    }
    public static Instant latestRecording(UUID owner, UUID song, Collection<Recording> recordings) {
        Objects.requireNonNull(owner); Objects.requireNonNull(song);
        return recordings.stream().filter(r -> owner.equals(r.owner) && song.equals(r.songId)
                && r.metadata == MetadataState.SAVED && r.lifecycle == LifecycleState.ACTIVE)
                .map(Recording::recordedAt).max(Comparator.naturalOrder()).orElse(null);
    }

    public static int tierRank(SongTier tier) {
        if (tier == null) return 5;
        return switch (tier) { case S -> 0; case A -> 1; case B -> 2; case C -> 3; case D -> 4; };
    }
    public static PageCursor.Tuple tuple(Query query, Row row) {
        var values = new ArrayList<String>();
        if (query.view == View.TIER_GROUPED) values.add(Integer.toString(tierRank(row.tier)));
        switch (query.sort) {
            case ADDED_DESC -> values.add(row.createdAt.toString());
            case RECORDED_DESC -> values.add(row.latestRecordedAt == null ? null : row.latestRecordedAt.toString());
            case TIER -> { values.add(Integer.toString(tierRank(row.tier))); values.add(row.title); }
            case TITLE -> values.add(row.title);
            case ARTIST -> { values.add(row.artist); values.add(row.title); }
        }
        // Keep text in the encrypted cursor; expanding it to hex-encoded DB keys wastes the size budget.
        return new PageCursor.Tuple(values, row.id);
    }
    public static Comparator<Row> order(Query query) {
        var compare = tupleOrder(query);
        return (left, right) -> compare.compare(tuple(query, left), tuple(query, right));
    }
    public static Comparator<PageCursor.Tuple> tupleOrder(Query query) {
        return (left, right) -> {
            int fields = (query.sort == Sort.TIER || query.sort == Sort.ARTIST ? 2 : 1)
                    + (query.view == View.TIER_GROUPED ? 1 : 0);
            if (left.values().size() != fields || right.values().size() != fields) throw PageCursor.invalid();
            try {
                int at = 0, compared = 0;
                if (query.view == View.TIER_GROUPED) compared = compareRank(left, right, at++);
                if (compared == 0) compared = switch (query.sort) {
                    case ADDED_DESC -> Instant.parse(right.values().get(at)).compareTo(Instant.parse(left.values().get(at)));
                    case RECORDED_DESC -> compareRecorded(left.values().get(at), right.values().get(at));
                    case TITLE -> DomainOrdering.compareSortText(left.values().get(at), right.values().get(at));
                    case TIER -> {
                        int rank = compareRank(left, right, at);
                        yield rank != 0 ? rank : DomainOrdering.compareSortText(left.values().get(at + 1), right.values().get(at + 1));
                    }
                    case ARTIST -> {
                        int artist = DomainOrdering.compareSortText(left.values().get(at), right.values().get(at));
                        yield artist != 0 ? artist : DomainOrdering.compareSortText(left.values().get(at + 1), right.values().get(at + 1));
                    }
                };
                return compared != 0 ? compared : KeysetPages.compareUuid(left.id(), right.id());
            } catch (IllegalArgumentException | NullPointerException | java.time.format.DateTimeParseException e) {
                throw PageCursor.invalid();
            }
        };
    }
    private static int compareRank(PageCursor.Tuple left, PageCursor.Tuple right, int at) {
        int a = Integer.parseInt(left.values().get(at)), b = Integer.parseInt(right.values().get(at));
        if (a < 0 || a > 5 || b < 0 || b > 5) throw PageCursor.invalid();
        return Integer.compare(a, b);
    }
    private static int compareRecorded(String left, String right) {
        if (left == null) return right == null ? 0 : 1;
        if (right == null) return -1;
        return Instant.parse(right).compareTo(Instant.parse(left));
    }
    private static ApiException invalid() {
        return new ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "곡 검색 조건을 확인해 주세요.", false, Map.of());
    }
}
