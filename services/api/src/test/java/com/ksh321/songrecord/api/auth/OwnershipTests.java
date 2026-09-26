package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.ownership.OwnershipGuard;
import com.ksh321.songrecord.api.ownership.OwnershipGuard.Resource;
import com.ksh321.songrecord.api.web.*;
import java.nio.ByteBuffer;
import java.time.Duration;
import java.util.UUID;
import org.junit.jupiter.api.*;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.*;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.*;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;

class OwnershipTests {
    java.sql.Connection keeper;
    JdbcTemplate jdbc;
    SessionService sessions;
    AccountAccess access;
    OwnershipGuard guard;
    AccountRegistrationService.Registration a, b;
    SessionService.Tokens tokens;
    AccountAccess.Account scope;
    SessionServiceTests.MutableClock clock;
    UUID song=UUID.randomUUID(), recording=UUID.randomUUID(), playlist=UUID.randomUUID(),
            item=UUID.randomUUID(), tag=UUID.randomUUID(), upload=UUID.randomUUID();

    @BeforeEach void setup() throws Exception {
        var ds=new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL", "sa", "");
        keeper=ds.getConnection();
        new ResourceDatabasePopulator(new ClassPathResource("registration-schema.sql"),
                new ClassPathResource("session-schema.sql"),new ClassPathResource("ownership-schema.sql")).populate(keeper);
        jdbc=new JdbcTemplate(ds);
        var manager=new DataSourceTransactionManager(ds);
        clock=new SessionServiceTests.MutableClock();
        var registration=new AccountRegistrationService(jdbc,manager,clock);
        a=registration.register(new VerifiedProviderIdentity("GOOGLE","owner-a"),null,"phone");
        b=registration.register(new VerifiedProviderIdentity("KAKAO","owner-b"),null,"same-phone");
        sessions=new SessionService(jdbc,manager,clock,Duration.ofMinutes(15),Duration.ofDays(30));
        access=new AccountAccess(sessions);guard=new OwnershipGuard(jdbc,access);
        tokens=sessions.issue(a);scope=access.authenticate("Bearer "+tokens.accessToken(),a.deviceId().toString());
        jdbc.update("INSERT INTO song VALUES(?,?,'TRASHED')",bytes(song),bytes(a.userId()));
        jdbc.update("INSERT INTO recording VALUES(?,?,?)",bytes(recording),bytes(a.userId()),bytes(song));
        jdbc.update("INSERT INTO playlist VALUES(?,?)",bytes(playlist),bytes(a.userId()));
        jdbc.update("INSERT INTO tag VALUES(?,?)",bytes(tag),bytes(a.userId()));
        jdbc.update("INSERT INTO playlist_item VALUES(?,?,?,?)",bytes(item),bytes(a.userId()),bytes(playlist),bytes(song));
        jdbc.update("INSERT INTO recording_tag VALUES(?,?,?)",bytes(a.userId()),bytes(recording),bytes(tag));
        jdbc.update("INSERT INTO recording_asset VALUES(?,?)",bytes(recording),bytes(a.userId()));
        jdbc.update("INSERT INTO recording_upload VALUES(?,?,?)",bytes(upload),bytes(a.userId()),bytes(recording));
    }
    @AfterEach void close() throws Exception {keeper.close();}
    UUID id(Resource resource) {
        return switch(resource) {
            case SONG -> song; case RECORDING,RECORDING_ASSET -> recording;
            case PLAYLIST -> playlist; case TAG -> tag; case UPLOAD -> upload; case DEVICE -> a.deviceId();
        };
    }
    AccountAccess.Account other() {
        return access.authenticate("Bearer "+sessions.issue(b).accessToken(),b.deviceId().toString());
    }
    void fails(String code,Runnable action) {
        assertThatThrownBy(action::run).isInstanceOfSatisfying(ApiException.class,e->{
            assertThat(e.code()).isEqualTo(code);assertThat(e.details()).isEmpty();
            assertThat(e.status().value()).isEqualTo(code.equals("RESOURCE_NOT_FOUND")?404:401);
        });
    }
    @ParameterizedTest @EnumSource(Resource.class)
    void eachResourceAllowsOwnerAndHidesForeignMissingAndMalformed(Resource resource) {
        guard.require(scope,resource,id(resource).toString());
        var other=other();
        fails("RESOURCE_NOT_FOUND",()->guard.require(other,resource,id(resource).toString()));
        fails("RESOURCE_NOT_FOUND",()->guard.require(scope,resource,UUID.randomUUID().toString()));
        fails("RESOURCE_NOT_FOUND",()->guard.require(scope,resource,"private-url-or-invalid-id"));
    }
    @Test void existingRelationsRequireBothOwnershipAndCorrectParent() {
        guard.requireRecordingForSong(scope,song.toString(),recording.toString());
        guard.requirePlaylistItem(scope,playlist.toString(),item.toString());
        guard.requireRecordingTag(scope,recording.toString(),tag.toString());
        var other=other();
        fails("RESOURCE_NOT_FOUND",()->guard.requireRecordingForSong(other,song.toString(),recording.toString()));
        fails("RESOURCE_NOT_FOUND",()->guard.requirePlaylistItem(other,playlist.toString(),item.toString()));
        fails("RESOURCE_NOT_FOUND",()->guard.requireRecordingTag(other,recording.toString(),tag.toString()));
        var second=UUID.randomUUID();jdbc.update("INSERT INTO song VALUES(?,?,'ACTIVE')",bytes(second),bytes(a.userId()));
        fails("RESOURCE_NOT_FOUND",()->guard.requireRecordingForSong(scope,second.toString(),recording.toString()));
        fails("RESOURCE_NOT_FOUND",()->guard.requirePlaylistItem(scope,UUID.randomUUID().toString(),item.toString()));
        jdbc.update("DELETE FROM recording_tag");
        fails("RESOURCE_NOT_FOUND",()->guard.requireRecordingTag(scope,recording.toString(),tag.toString()));
    }
    @Test void corruptMixedOwnerRelationsFailClosed() {
        jdbc.update("UPDATE song SET user_id=?",bytes(b.userId()));
        fails("RESOURCE_NOT_FOUND",()->guard.requireRecordingForSong(scope,song.toString(),recording.toString()));
        fails("RESOURCE_NOT_FOUND",()->guard.requirePlaylistItem(scope,playlist.toString(),item.toString()));
        jdbc.update("UPDATE tag SET user_id=?",bytes(b.userId()));
        fails("RESOURCE_NOT_FOUND",()->guard.requireRecordingTag(scope,recording.toString(),tag.toString()));
        jdbc.update("UPDATE recording SET user_id=?",bytes(b.userId()));
        fails("RESOURCE_NOT_FOUND",()->guard.require(scope,Resource.RECORDING_ASSET,recording.toString()));
        fails("RESOURCE_NOT_FOUND",()->guard.require(scope,Resource.UPLOAD,upload.toString()));
    }
    @Test void candidatePlaylistItemDoesNotRequireSong() {
        jdbc.update("UPDATE playlist_item SET song_id=NULL");
        guard.requirePlaylistItem(scope,playlist.toString(),item.toString());
    }
    @Test void wrongDeviceAndMalformedHeadersAreUnauthorized() {
        fails("AUTH_INVALID_SESSION",()->access.authenticate("Bearer "+tokens.accessToken(),b.deviceId().toString()));
        fails("AUTH_INVALID_SESSION",()->access.authenticate(null,a.deviceId().toString()));
        fails("AUTH_INVALID_SESSION",()->access.authenticate("Bearer "+tokens.accessToken(),"1-1-1-1-1"));
        fails("AUTH_INVALID_SESSION",()->guard.require(null,Resource.SONG,song.toString()));
        assertThat(scope.toString()).doesNotContain(tokens.accessToken(),a.userId().toString());
    }
    @Test void logoutInvalidatesPreviouslyCreatedScope() {
        sessions.logout(tokens.refreshToken(),a.deviceId());
        fails("AUTH_INVALID_SESSION",()->guard.require(scope,Resource.SONG,song.toString()));
    }
    @Test void expiryInvalidatesPreviouslyCreatedScopeBeforeResourceParsing() {
        clock.instant=clock.instant.plus(Duration.ofMinutes(15));
        fails("AUTH_INVALID_SESSION",()->guard.require(scope,Resource.SONG,"invalid"));
    }
    @Test void accountDeletionInvalidatesPreviouslyCreatedScope() {
        jdbc.update("UPDATE app_user SET status='DELETING' WHERE id=?",bytes(a.userId()));
        fails("AUTH_INVALID_SESSION",()->guard.require(scope,Resource.SONG,song.toString()));
    }
    @Test void deviceRevocationInvalidatesPreviouslyCreatedScope() {
        jdbc.update("UPDATE device SET revoked_at=CURRENT_TIMESTAMP WHERE id=?",bytes(a.deviceId()));
        fails("AUTH_INVALID_SESSION",()->guard.require(scope,Resource.SONG,song.toString()));
    }
    // Test-only HTTP route. Production security does not expose ownership probes.
    @RestController static class Probe {
        final AccountAccess access;final OwnershipGuard guard;
        Probe(AccountAccess access,OwnershipGuard guard){this.access=access;this.guard=guard;}
        @GetMapping("/test-owned/{id}") void read(@RequestHeader("Authorization") String auth,
                @RequestHeader("X-Device-Id") String device,@PathVariable("id") String id) {
            guard.require(access.authenticate(auth,device),Resource.SONG,id);
        }
    }
    @Test void httpForeignAndMissingAreIdenticalWithoutIdentifiersOrSecrets() throws Exception {
        var mvc=MockMvcBuilders.standaloneSetup(new Probe(access,guard))
                .setControllerAdvice(new GlobalExceptionHandler()).addFilters(new RequestIdFilter()).build();
        var token=sessions.issue(b).accessToken();
        String body=null;
        for(String id:new String[]{song.toString(),UUID.randomUUID().toString(),"private-name"}) {
            var response=mvc.perform(get("/test-owned/"+id).header("Authorization","Bearer "+token)
                    .header("X-Device-Id",b.deviceId().toString()).header("X-Request-Id","ownership-test"))
                    .andReturn().getResponse();
            assertThat(response.getStatus()).isEqualTo(404);
            var text=response.getContentAsString();
            assertThat(text).contains("RESOURCE_NOT_FOUND","ownership-test").doesNotContain(id,token,a.userId().toString());
            if(body!=null)assertThat(text).isEqualTo(body);body=text;
        }
    }
    static byte[] bytes(UUID id) {return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();}
}
