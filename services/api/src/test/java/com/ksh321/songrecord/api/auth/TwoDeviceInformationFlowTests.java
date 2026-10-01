package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.sync.ChangeQueries;
import com.ksh321.songrecord.api.sync.ChangeReadView;
import com.ksh321.songrecord.api.web.ApiException;
import java.util.*;
import java.util.concurrent.*;
import java.nio.file.*;
import org.junit.jupiter.api.*;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.util.LinkedMultiValueMap;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;

/** P10-10: two real authenticated device sessions over HTTP writes and change reads.
 * Isolated H2 data, synthetic identities, no provider login or audio upload. */
class TwoDeviceInformationFlowTests {
    final RecordingEditingTests fixture = new RecordingEditingTests();
    final JsonMapper json = new JsonMapper();
    IdempotencyTests f;
    AccountRegistrationService registrations;
    AccountRegistrationService.Registration second;
    SessionService.Tokens secondTokens;
    ChangeQueries changes;

    @BeforeEach void open() throws Exception {
        fixture.open();
        f = fixture.f;
        registrations = new AccountRegistrationService(f.jdbc, f.manager, f.clock);
        second = registrations.register(new VerifiedProviderIdentity("GOOGLE", "a"), null, "second device");
        secondTokens = f.sessions.issue(second);
        assertThat(second.userId()).isEqualTo(f.registration.userId());
        assertThat(second.deviceId()).isNotEqualTo(f.registration.deviceId());
        changes = new ChangeQueries(f.access, new ChangeReadView(f.jdbc.getDataSource(), f.access, f.clock));
    }

    @AfterEach void close() throws Exception { fixture.close(); }

    MockHttpServletResponse write(SessionService.Tokens tokens, UUID device,
            String method, String path, String key, Map<String,Object> body) throws Exception {
        var request = method.equals("POST") ? post(path) : patch(path);
        return fixture.setup.setup.mvc.perform(request
            .header("Authorization", "Bearer " + tokens.accessToken())
            .header("X-Device-Id", device).header("Idempotency-Key", key)
            .contentType("application/json").content(json.writeValueAsString(body)))
            .andReturn().getResponse();
    }

    JsonNode feed(SessionService.Tokens tokens, UUID device, long after) throws Exception {
        var query = new LinkedMultiValueMap<String,String>();
        query.add("after_seq", Long.toString(after)); query.add("limit", "100");
        return json.readTree(json.writeValueAsString(changes.get("Bearer " + tokens.accessToken(), device.toString(), query)));
    }

    String recordingPath() { return "/v1/recordings/" + fixture.setup.id; }
    String key() { return UUID.randomUUID().toString(); }

    @Test void metadataFileSpecificationAndTierReachTheOtherDeviceWithoutAudioUpload() throws Exception {
        var draft = fixture.setup.base();
        draft.put("title_snapshot", "offline input"); draft.put("note", "retained note");
        var createdReply = fixture.setup.create(draft);
        assertThat(createdReply.getStatus()).isEqualTo(201);
        var initial = feed(secondTokens, second.deviceId(), 0);
        assertThat(initial.get("changes").size()).isEqualTo(1);
        var received = initial.get("changes").get(0).get("payload");
        assertThat(received.get("id").asText()).isEqualTo(fixture.setup.id.toString());
        assertThat(received.get("metadata_state").asText()).isEqualTo("DRAFT");
        assertThat(received.get("origin_device_id").asText()).isEqualTo(f.registration.deviceId().toString());

        var spec = Map.of("sha256", "a".repeat(64), "size_bytes", 100, "duration_ms", 1000,
            "codec", "AAC_LC", "sample_rate", 48000, "channels", 1, "capture_integrity", "VALIDATED");
        var save = Map.<String,Object>of("base_revision", 1, "metadata_state", "SAVED",
            "artist_snapshot", "artist", "key_mode", "ORIGINAL", "key_shift", 0, "file", spec);
        var savedReply = write(f.tokens, f.registration.deviceId(), "PATCH", recordingPath(), key(), save);
        assertThat(savedReply.getStatus()).isEqualTo(200);
        var savedPage = feed(secondTokens, second.deviceId(), 1);
        assertThat(savedPage.get("next_seq").asLong()).isEqualTo(2);
        assertThat(savedPage.get("changes").size()).isEqualTo(1);
        var saved = savedPage.get("changes").get(0).get("payload");
        assertThat(saved.get("metadata_state").asText()).isEqualTo("SAVED");
        assertThat(saved.get("file").get("sha256").asText()).isEqualTo(spec.get("sha256"));
        assertThat(saved.get("note").asText()).isEqualTo("retained note");

        var tier = Map.<String,Object>of("base_revision", 2, "tier", "A");
        var operation = key();
        var first = write(secondTokens, second.deviceId(), "PATCH", recordingPath()+"/tier", operation, tier);
        assertThat(first.getStatus()).isEqualTo(200);
        var replay = write(secondTokens, second.deviceId(), "PATCH", recordingPath()+"/tier", operation, tier);
        assertThat(replay.getStatus()).isEqualTo(200);
        assertThat(replay.getContentAsString()).isEqualTo(first.getContentAsString());
        var returned = feed(f.tokens, f.registration.deviceId(), 2);
        assertThat(returned.get("next_seq").asLong()).isEqualTo(3);
        assertThat(returned.get("changes").size()).isEqualTo(1);
        assertThat(returned.get("changes").get(0).get("payload").get("tier").asText()).isEqualTo("A");
        assertThat(fixture.setup.setup.count("recording_file_spec")).isEqualTo(1);
        // A completed file specification must not imply uploaded audio.
        assertThat(fixture.setup.setup.count("recording_asset")).isZero();
        // Export only synthetic request/response bodies, never credentials.
        var evidence = Map.of("owner", f.registration.userId().toString(),
            "device_a", f.registration.deviceId().toString(), "device_b", second.deviceId().toString(),
            "recording_id", fixture.setup.id.toString(),
            "create_request", draft, "create_response", json.readTree(createdReply.getContentAsString()),
            "save_request", save, "save_response", json.readTree(savedReply.getContentAsString()),
            "tier_request", tier, "tier_response", json.readTree(first.getContentAsString()));
        var all = new LinkedHashMap<String,Object>(evidence);
        all.put("pages", List.of(initial, savedPage, returned));
        String normalized = json.writeValueAsString(all)
            .replace(f.registration.userId().toString(), "11111111-1111-4111-8111-111111111111")
            .replace(f.registration.deviceId().toString(), "44444444-4444-4444-8444-444444444444")
            .replace(second.deviceId().toString(), "55555555-5555-4555-8555-555555555555")
            .replace(fixture.setup.id.toString(), "33333333-3333-4333-8333-333333333333")
            .replaceAll("\"updated_at\":\"[^\"]*\"", "\"updated_at\":\"2026-09-24T00:00:00Z\"");
        Files.createDirectories(Path.of("build/two-device-evidence"));
        Files.writeString(Path.of("build/two-device-evidence/recording-flow.json"), normalized);
        assertThat(json.readTree(normalized)).isEqualTo(json.readTree(
            Files.readString(Path.of("../../fixtures/contracts/two-device-recording.json"))));
    }

    @Test void sameNoteConflictPreservesTheWinnerUntilAnExplicitNewRevisionWrite() throws Exception {
        var draft = fixture.setup.base(); draft.put("note", "base");
        assertThat(fixture.setup.create(draft).getStatus()).isEqualTo(201);
        assertThat(write(f.tokens, f.registration.deviceId(), "PATCH", recordingPath(), key(),
            Map.of("base_revision", 1, "note", "device A")).getStatus()).isEqualTo(200);
        var stale = write(secondTokens, second.deviceId(), "PATCH", recordingPath(), key(),
            Map.of("base_revision", 1, "note", "device B"));
        assertThat(stale.getStatus()).isEqualTo(409);
        var error = json.readTree(stale.getContentAsString()).get("error");
        assertThat(error.get("code").asText()).isEqualTo("REVISION_CONFLICT");
        assertThat(error.get("details").get("current").get("note").asText()).isEqualTo("device A");
        var held = feed(secondTokens, second.deviceId(), 1);
        assertThat(held.get("head_seq").asLong()).isEqualTo(2);
        assertThat(held.get("changes").get(0).get("payload").get("note").asText()).isEqualTo("device A");
        assertThat(write(secondTokens, second.deviceId(), "PATCH", recordingPath(), key(),
            Map.of("base_revision", 2, "note", "device B")).getStatus()).isEqualTo(200);
        var resolved = feed(f.tokens, f.registration.deviceId(), 2);
        assertThat(resolved.get("changes").get(0).get("revision").asLong()).isEqualTo(3);
        assertThat(resolved.get("changes").get(0).get("payload").get("note").asText()).isEqualTo("device B");
    }

    @Test void concurrentSameTjOnTwoDevicesProducesOneCanonicalSongAndOneChange() throws Exception {
        var pool = Executors.newFixedThreadPool(2);
        var start = new CountDownLatch(1);
        try {
            var a = pool.submit(() -> { start.await(); return write(f.tokens, f.registration.deviceId(), "POST", "/v1/songs", key(),
                Map.of("id", UUID.randomUUID().toString(), "source_type", "TJ", "source_token", "valid")); });
            var b = pool.submit(() -> { start.await(); return write(secondTokens, second.deviceId(), "POST", "/v1/songs", key(),
                Map.of("id", UUID.randomUUID().toString(), "source_type", "TJ", "source_token", "valid")); });
            start.countDown();
            var first = a.get(15, TimeUnit.SECONDS); var secondReply = b.get(15, TimeUnit.SECONDS);
            assertThat(List.of(first.getStatus(), secondReply.getStatus())).containsExactlyInAnyOrder(201, 200);
            assertThat(json.readTree(first.getContentAsString()).get("canonical_song_id"))
                .isEqualTo(json.readTree(secondReply.getContentAsString()).get("canonical_song_id"));
            assertThat(fixture.setup.setup.count("song")).isEqualTo(1);
            assertThat(fixture.setup.setup.count("change_log")).isEqualTo(1);
            assertThat(feed(f.tokens, f.registration.deviceId(), 0)).isEqualTo(feed(secondTokens, second.deviceId(), 0));
        } finally { pool.shutdownNow(); }
    }

    @Test void anotherAccountAndRevokedDeviceCannotUseTheOriginalAccountsStream() throws Exception {
        assertThat(fixture.setup.create(fixture.setup.base()).getStatus()).isEqualTo(201);
        var other = registrations.register(new VerifiedProviderIdentity("KAKAO", "b"), null, "other account");
        var otherTokens = f.sessions.issue(other);
        assertThat(feed(otherTokens, other.deviceId(), 0).get("changes").size()).isZero();
        assertThat(write(otherTokens, other.deviceId(), "PATCH", recordingPath(), key(),
            Map.of("base_revision", 1, "note", "foreign")).getStatus()).isEqualTo(404);
        f.sessions.logout(secondTokens.refreshToken(), second.deviceId());
        assertThatThrownBy(() -> feed(secondTokens, second.deviceId(), 0))
            .isInstanceOfSatisfying(ApiException.class, e -> assertThat(e.status().value()).isEqualTo(401));
        assertThat(feed(f.tokens, f.registration.deviceId(), 0).get("changes").size()).isEqualTo(1);
    }
}
