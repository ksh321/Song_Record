package com.ksh321.songrecord.api.sync;

import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;

class SnapshotPageCursorTests {
    private static final UUID OWNER = UUID.fromString("00000000-0000-4000-8000-000000000001");
    private static final UUID SNAPSHOT = UUID.fromString("00000000-0000-4000-8000-000000000002");
    private static final Instant NOW = Instant.parse("2026-09-30T00:00:00.123Z");
    private static final Instant EXPIRY = NOW.plus(Duration.ofMinutes(30));
    private static final byte[] KEY = new byte[32]; // Synthetic unit-test key only.
    private SnapshotPageCursor at(Instant now) {
        return new SnapshotPageCursor(KEY, Clock.fixed(now, ZoneOffset.UTC));
    }
    private void invalid(Runnable action) {
        assertThatThrownBy(action::run).isInstanceOfSatisfying(ApiException.class,
                e -> assertThat(e.code()).isEqualTo("INVALID_CURSOR"));
    }

    @Test void positionSurvivesRestartAndDoesNotExposeOwnerOrSnapshot() {
        String token = at(NOW).issue(OWNER, SNAPSHOT, "RECORDING", Long.MAX_VALUE, EXPIRY);
        assertThat(token).startsWith("sp1.").doesNotContain(OWNER.toString(), SNAPSHOT.toString(), "RECORDING");
        assertThat(at(NOW.plusSeconds(10)).read(token, OWNER, SNAPSHOT, "RECORDING", EXPIRY)).isEqualTo(Long.MAX_VALUE);
        assertThat(at(NOW).issue(OWNER, SNAPSHOT, "RECORDING", Long.MAX_VALUE, EXPIRY)).isNotEqualTo(token);
    }
    @Test void bindsAccountSnapshotEntityAndExactExpiry() {
        var codec = at(NOW);
        String token = codec.issue(OWNER, SNAPSHOT, "SONG", 51, EXPIRY);
        invalid(() -> codec.read(token, SNAPSHOT, SNAPSHOT, "SONG", EXPIRY));
        invalid(() -> codec.read(token, OWNER, OWNER, "SONG", EXPIRY));
        invalid(() -> codec.read(token, OWNER, SNAPSHOT, "PLAYLIST", EXPIRY));
        invalid(() -> codec.read(token, OWNER, SNAPSHOT, "SONG", EXPIRY.plusMillis(1)));
    }
    @Test void refusesTamperingTruncationPaddingWrongKeyAndListCursor() {
        var codec = at(NOW);
        String token = codec.issue(OWNER, SNAPSHOT, "SONG", 1, EXPIRY);
        byte[] bytes = Base64.getUrlDecoder().decode(token.substring(4));
        bytes[20] ^= 1;
        String changed = "sp1." + Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
        for (String bad : Arrays.asList(null, "", changed, token + "=", token.substring(0, token.length()-1),
                "p1." + token.substring(4), "sp1." + "A".repeat(201))) {
            invalid(() -> codec.read(bad, OWNER, SNAPSHOT, "SONG", EXPIRY));
        }
        byte[] otherKey = KEY.clone(); otherKey[0] = 1;
        var other = new SnapshotPageCursor(otherKey, Clock.fixed(NOW, ZoneOffset.UTC));
        invalid(() -> other.read(token, OWNER, SNAPSHOT, "SONG", EXPIRY));
    }
    @Test void thirtyMinuteBoundaryIsExclusiveAndLaterPageDoesNotRenewExpiry() {
        String token = at(EXPIRY.minusMillis(1)).issue(OWNER, SNAPSHOT, "SONG", 100, EXPIRY);
        assertThat(at(EXPIRY.minusMillis(1)).read(token, OWNER, SNAPSHOT, "SONG", EXPIRY)).isEqualTo(100);
        assertThatThrownBy(() -> at(EXPIRY).read(token, OWNER, SNAPSHOT, "SONG", EXPIRY))
                .isInstanceOfSatisfying(ApiException.class, e -> {
                    assertThat(e.code()).isEqualTo("SNAPSHOT_EXPIRED");
                    assertThat(e.status().value()).isEqualTo(410);
                });
        assertThatThrownBy(() -> at(EXPIRY).issue(OWNER, SNAPSHOT, "SONG", 101, EXPIRY))
                .isInstanceOf(ApiException.class);
    }
    @Test void rejectsInvalidConstructionAndPositionsAndCopiesKey() {
        assertThatThrownBy(() -> new SnapshotPageCursor(new byte[16], Clock.systemUTC())).isInstanceOf(IllegalArgumentException.class);
        for(long ordinal : new long[]{0,-1})
            assertThatThrownBy(() -> at(NOW).issue(OWNER, SNAPSHOT, "SONG", ordinal, EXPIRY)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> at(NOW).issue(OWNER, SNAPSHOT, "song", 1, EXPIRY)).isInstanceOf(IllegalArgumentException.class);
        byte[] mutable = KEY.clone();
        var codec = new SnapshotPageCursor(mutable, Clock.fixed(NOW, ZoneOffset.UTC));
        mutable[0] = 1;
        String token = codec.issue(OWNER, SNAPSHOT, "SONG", 1, EXPIRY);
        assertThat(at(NOW).read(token, OWNER, SNAPSHOT, "SONG", EXPIRY)).isEqualTo(1);
    }
}
