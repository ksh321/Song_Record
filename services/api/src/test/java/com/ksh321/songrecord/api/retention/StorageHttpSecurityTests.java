package com.ksh321.songrecord.api.retention;

import com.ksh321.songrecord.api.account.*;
import com.ksh321.songrecord.api.auth.*;
import com.ksh321.songrecord.api.config.*;
import com.ksh321.songrecord.api.idempotency.IdempotentMutations;
import com.ksh321.songrecord.api.jobs.JobQueue;
import com.ksh321.songrecord.api.pagination.KeysetPages;
import com.ksh321.songrecord.api.playback.*;
import com.ksh321.songrecord.api.recordings.RecordingConfiguration;
import com.ksh321.songrecord.api.revision.*;
import com.ksh321.songrecord.api.sync.AccountChanges;
import com.ksh321.songrecord.api.uploads.*;
import com.ksh321.songrecord.api.web.*;
import java.time.Clock;
import java.util.*;
import org.junit.jupiter.api.*;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;
import org.springframework.context.annotation.*;
import org.springframework.http.*;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.mock.web.MockServletContext;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.support.AnnotationConfigWebApplicationContext;
import org.springframework.web.servlet.config.annotation.EnableWebMvc;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.retention.RetentionCandidateDatabaseChecks.*;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;

/** Real HTTP filters/controllers/AccountAccess/services, isolated DB and synthetic session authority. */
class StorageHttpSecurityTests {
    private static final String ID = "00000000-0000-0000-0000-000000000001";
    private AnnotationConfigWebApplicationContext context;
    private MockMvc mvc;
    private JdbcTemplate db;
    private UUID owner, device, recording, otherDevice;

    @Configuration @EnableWebMvc @EnableWebSecurity
    @Import({SecurityConfig.class, StorageHttpSecurityConfiguration.class, RecordingConfiguration.class,
            RetentionController.class, PinController.class, CleanupConfirmationController.class,
            PreservationDownloadController.class, UploadController.class, PlaybackController.class,
            StorageRequestController.class, GlobalExceptionHandler.class})
    static class Config {
        @Bean SessionService sessions() { return mock(SessionService.class); }
        @Bean AccountAccess access(SessionService sessions) { return new AccountAccess(sessions); }
        @Bean JdbcTemplate db() { return PinReplacementTests.database(); }
        @Bean DataSourceTransactionManager manager(JdbcTemplate db) { return new DataSourceTransactionManager(db.getDataSource()); }
        @Bean IdempotentMutations mutations(JdbcTemplate db, AccountAccess access, DataSourceTransactionManager manager) {
            return new IdempotentMutations(db, access, manager, Clock.systemUTC());
        }
        @Bean RetentionQueries queries(JdbcTemplate db, AccountAccess access, DataSourceTransactionManager manager) { return new RetentionQueries(db, access, manager); }
        @Bean PinSlots pins(JdbcTemplate db, AccountAccess access, IdempotentMutations mutations) { return new PinSlots(db, access, mutations); }
        @Bean CleanupConfirmations cleanup(JdbcTemplate db, AccountAccess access, IdempotentMutations mutations) { return new CleanupConfirmations(db, access, mutations, Clock.systemUTC()); }
        @Bean PreservationDownloadSigner signer() { return mock(PreservationDownloadSigner.class); }
        @Bean PreservationDownloads downloads(JdbcTemplate db, AccountAccess access, DataSourceTransactionManager manager, PreservationDownloadSigner signer) { return new PreservationDownloads(db, access, manager, signer); }
        @Bean PlaybackUrls playback(JdbcTemplate db, AccountAccess access, DataSourceTransactionManager manager, PreservationDownloadSigner signer) { return new PlaybackUrls(db, access, manager, signer); }
        @Bean UploadUrls uploads(JdbcTemplate db, AccountAccess access, DataSourceTransactionManager manager, IdempotentMutations mutations) {
            var approval = new UploadApproval(db, access, manager, Clock.systemUTC(), mutations);
            return new UploadUrls(db, access, manager, mutations, approval, mock(UploadPutSigner.class), Clock.systemUTC());
        }
        @Bean UploadCompletion completion(JdbcTemplate db, AccountAccess access, DataSourceTransactionManager manager, IdempotentMutations mutations, JobQueue jobs) { return new UploadCompletion(db, access, manager, mutations, jobs, Clock.systemUTC()); }
        @Bean StorageRequests storageRequests(JdbcTemplate db, AccountAccess access, IdempotentMutations mutations, KeysetPages pages) { return new StorageRequests(db, access, mutations, pages, Clock.systemUTC()); }
        // Dependencies of the existing broad recording chain; this test exercises its real ordering.
        @Bean CreationGuard guard() { return mock(CreationGuard.class); }
        @Bean AccountChanges changes() { return mock(AccountChanges.class); }
        @Bean RevisionChanges revisions() { return mock(RevisionChanges.class); }
        @Bean JobQueue jobs() { return mock(JobQueue.class); }
        @Bean KeysetPages pages() { return mock(KeysetPages.class); }
    }

    @BeforeEach void setup() {
        context = new AnnotationConfigWebApplicationContext();
        context.setServletContext(new MockServletContext());
        context.getEnvironment().setActiveProfiles("dev");
        context.getEnvironment().getPropertySources().addFirst(new org.springframework.core.env.MapPropertySource(
                "storage-test", Map.of("songrecord.storage.enabled", "true")));
        context.register(Config.class); context.refresh();
        mvc = MockMvcBuilders.webAppContextSetup(context).apply(springSecurity()).build();
        db = context.getBean(JdbcTemplate.class);
        owner = account(db); device = device(db, owner);
        UUID other = account(db); otherDevice = device(db, other);
        for (UUID user : List.of(owner, other)) {
            db.update("INSERT INTO user_sync_state(user_id) VALUES(?)", bytes(user));
            db.update("INSERT INTO user_entitlement(user_id) VALUES(?)", bytes(user));
            db.update("INSERT INTO storage_usage(user_id) VALUES(?)", bytes(user));
        }
        recording = recording(db, owner, device, null, true, true, "VALIDATED");
        var sessions = context.getBean(SessionService.class);
        when(sessions.authenticate(anyString(), any(UUID.class))).thenThrow(new ApiException(
                HttpStatus.UNAUTHORIZED, "AUTH_INVALID_SESSION", "invalid synthetic session", false, Map.of()));
        doReturn(new SessionService.Principal(owner, device, UUID.randomUUID())).when(sessions).authenticate("owner", device);
        doReturn(new SessionService.Principal(other, otherDevice, UUID.randomUUID())).when(sessions).authenticate("other", otherDevice);
    }
    @AfterEach void close() { context.close(); }

    record Route(HttpMethod method, String path) {}
    static List<Route> routes() {
        return List.of(new Route(HttpMethod.GET, "/v1/storage"), new Route(HttpMethod.GET, "/v1/pins"),
                new Route(HttpMethod.GET, "/v1/recordings/"+ID+"/retention"),
                new Route(HttpMethod.GET, "/v1/recordings/"+ID+"/preservation-url"),
                new Route(HttpMethod.POST, "/v1/recordings/"+ID+"/playback-url"),
                new Route(HttpMethod.POST, "/v1/recordings/"+ID+"/uploads"),
                new Route(HttpMethod.POST, "/v1/uploads/"+ID+"/renew-url"),
                new Route(HttpMethod.POST, "/v1/uploads/"+ID+"/complete"),
                new Route(HttpMethod.POST, "/v1/uploads/"+ID+"/cancel"),
                new Route(HttpMethod.POST, "/v1/pins"), new Route(HttpMethod.DELETE, "/v1/pins/1"),
                new Route(HttpMethod.POST, "/v1/pins/1/replacement"), new Route(HttpMethod.POST, "/v1/pins/1/replacement/cancel"),
                new Route(HttpMethod.POST, "/v1/storage/cleanup-previews"), new Route(HttpMethod.POST, "/v1/storage/cleanup-confirmations"),
                new Route(HttpMethod.POST, "/v1/storage/requests"), new Route(HttpMethod.GET, "/v1/storage/requests/me"),
                new Route(HttpMethod.GET, "/v1/storage/requests/"+ID));
    }
    private MockHttpServletRequestBuilder requestFor(Route route) { return request(route.method(), route.path()).contentType(MediaType.APPLICATION_JSON).content("{}"); }
    private MockHttpServletRequestBuilder authorized(MockHttpServletRequestBuilder request, boolean other) {
        return request.header("Authorization", "Bearer "+(other?"other":"owner"))
                .header("X-Device-Id", (other?otherDevice:device).toString());
    }
    @ParameterizedTest @MethodSource("routes")
    void contractRoutesReachRealAuthenticationInsteadOfDefaultDeny(Route route) throws Exception {
        for (String mode : List.of("missing", "invalid", "wrong-device")) {
            var request = requestFor(route);
            if (!mode.equals("missing")) request.header("Authorization", "Bearer "+(mode.equals("invalid")?"invalid":"owner")).header("X-Device-Id", otherDevice.toString());
            var response = mvc.perform(request).andReturn().getResponse();
            assertThat(response.getStatus()).as(route+" "+mode).isEqualTo(401);
            assertThat(response.getContentAsString()).contains("AUTH_INVALID_SESSION");
        }
        assertThat(db.queryForObject("SELECT COUNT(*) FROM mutation_receipt", Long.class)).isZero();
        assertThat(db.queryForObject("SELECT COUNT(*) FROM recording_upload", Long.class)).isZero();
    }
    @ParameterizedTest @MethodSource("routes")
    void uncontractedMethodsStayDeniedEvenWithValidSession(Route route) throws Exception {
        var response = mvc.perform(authorized(put(route.path()).contentType(MediaType.APPLICATION_JSON).content("{}"), false)).andReturn().getResponse();
        assertThat(response.getStatus()).isEqualTo(403);
    }
    @Test void unknownAndNestedRoutesRemainDenied() throws Exception {
        for (String path : List.of("/v1/storage/admin", "/v1/pins/1/unknown", "/v1/uploads/"+ID+"/unknown", "/v1/recordings/"+ID+"/retention/extra", "/v1/not-a-contract"))
            assertThat(mvc.perform(authorized(get(path), false)).andReturn().getResponse().getStatus()).as(path).isEqualTo(403);
    }
    @Test void ownerStorageAndPinMutationWorkThroughFiltersWithoutCreatingBrowserSession() throws Exception {
        db.update("UPDATE storage_usage SET used_bytes=123 WHERE user_id=?", bytes(owner));
        var response = mvc.perform(authorized(get("/v1/storage"), false)).andReturn().getResponse();
        assertThat(response.getStatus()).isEqualTo(200);
        assertThat(new JsonMapper().readTree(response.getContentAsString()).get("used_bytes").asLong()).isEqualTo(123);
        assertThat(response.getHeader("Cache-Control")).isEqualTo("no-store");
        assertThat(response.getHeaders("Set-Cookie")).isEmpty();
        var body = "{\"recording_id\":\""+recording+"\",\"entitlement_revision\":1}";
        var op = UUID.randomUUID().toString();
        for (int i=0;i<2;i++) {
            var pinned = mvc.perform(authorized(post("/v1/pins").contentType(MediaType.APPLICATION_JSON).content(body).header("Idempotency-Key", op), false)).andReturn().getResponse();
            assertThat(pinned.getStatus()).isEqualTo(201);
        }
        assertThat(db.queryForObject("SELECT COUNT(*) FROM pin_slot", Long.class)).isEqualTo(1);
        assertThat(db.queryForObject("SELECT COUNT(*) FROM mutation_receipt", Long.class)).isEqualTo(1);
        assertThat(mvc.perform(authorized(get("/v1/pins"), true)).andReturn().getResponse().getContentAsString()).doesNotContain(recording.toString());
        var otherStorage = mvc.perform(authorized(get("/v1/storage"), true)).andReturn().getResponse();
        assertThat(new JsonMapper().readTree(otherStorage.getContentAsString()).get("used_bytes").asLong()).isZero();
    }
    @Test void foreignRecordingCannotBeReadPinnedUploadedOrSigned() throws Exception {
        assertThat(mvc.perform(authorized(get("/v1/recordings/"+recording+"/retention"), true)).andReturn().getResponse().getStatus()).isEqualTo(404);
        for (String path : List.of("/v1/recordings/"+recording+"/playback-url", "/v1/recordings/"+recording+"/preservation-url")) {
            var req = path.endsWith("playback-url")?post(path):get(path);
            assertThat(mvc.perform(authorized(req, true)).andReturn().getResponse().getStatus()).isEqualTo(409);
        }
        var pinBody = "{\"recording_id\":\""+recording+"\",\"entitlement_revision\":1}";
        assertThat(mvc.perform(authorized(post("/v1/pins").contentType(MediaType.APPLICATION_JSON).content(pinBody).header("Idempotency-Key", UUID.randomUUID()), true)).andReturn().getResponse().getStatus()).isEqualTo(404);
        var uploadBody = "{\"expected_size\":100,\"sha256\":\""+"a".repeat(64)+"\"}";
        assertThat(mvc.perform(authorized(post("/v1/recordings/"+recording+"/uploads").contentType(MediaType.APPLICATION_JSON).content(uploadBody).header("Idempotency-Key", UUID.randomUUID()), true)).andReturn().getResponse().getStatus()).isEqualTo(404);
        verifyNoInteractions(context.getBean(PreservationDownloadSigner.class));
        assertThat(db.queryForObject("SELECT COUNT(*) FROM pin_slot", Long.class)).isZero();
        assertThat(db.queryForObject("SELECT COUNT(*) FROM recording_upload", Long.class)).isZero();
    }
    @Test void routingDoesNotBypassManualUploadLock() throws Exception {
        db.update("INSERT INTO pin_slot(user_id,slot_no,pending_recording_id) VALUES(?,1,?)", bytes(owner), bytes(recording));
        db.update("UPDATE global_storage_usage SET upload_locked=TRUE");
        var body = "{\"expected_size\":6291456,\"sha256\":\""+"a".repeat(64)+"\"}";
        var response = mvc.perform(authorized(post("/v1/recordings/"+recording+"/uploads")
                .contentType(MediaType.APPLICATION_JSON).content(body)
                .header("Idempotency-Key", UUID.randomUUID()), false)).andReturn().getResponse();
        assertThat(response.getStatus()).isEqualTo(503);
        assertThat(response.getContentAsString()).contains("UPLOAD_BUDGET_LOCKED");
        assertThat(db.queryForObject("SELECT COUNT(*) FROM recording_upload", Long.class)).isZero();
        assertThat(db.queryForObject("SELECT reserved_bytes FROM global_storage_usage", Long.class)).isZero();
    }
}
