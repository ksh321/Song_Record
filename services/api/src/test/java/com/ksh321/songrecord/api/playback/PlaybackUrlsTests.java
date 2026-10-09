package com.ksh321.songrecord.api.playback;

import com.ksh321.songrecord.api.auth.*;
import com.ksh321.songrecord.api.retention.PreservationDownloadSigner;
import com.ksh321.songrecord.api.storage.StorageObjectKeys;
import com.ksh321.songrecord.api.web.ApiException;
import java.time.Instant;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.*;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

class PlaybackUrlsTests {
    JdbcTemplate db;
    AccountAccess access; AccountAccess.Account account;
    PreservationDownloadSigner signer;
    PlaybackUrls service;
    UUID owner=UUID.randomUUID(), id=UUID.randomUUID(), generation=UUID.randomUUID(), device=UUID.randomUUID();
    StorageObjectKeys.Final key;
    @BeforeEach void setup() {
        db=new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1", "sa", ""));
        db.execute("CREATE TABLE recording(id BINARY(16) PRIMARY KEY,user_id BINARY(16),lifecycle_state VARCHAR(16))");
        db.execute("CREATE TABLE recording_asset(recording_id BINARY(16) PRIMARY KEY,user_id BINARY(16),generation BINARY(16),object_key VARCHAR(512),sha256 VARCHAR(64),verified_size BIGINT,cloud_revision BIGINT,cloud_state VARCHAR(16))");
        key=new StorageObjectKeys.Final(owner,id,generation);
        db.update("INSERT INTO recording VALUES(?,?,'ACTIVE')",bytes(id),bytes(owner));
        db.update("INSERT INTO recording_asset VALUES(?,?,?,?,?,12,3,'STORED')",bytes(id),bytes(owner),bytes(generation),key.value(),"a".repeat(64));
        access=mock(AccountAccess.class);account=mock(AccountAccess.Account.class);signer=mock(PreservationDownloadSigner.class);
        var principal=new SessionService.Principal(owner,device,UUID.randomUUID());
        when(account.principal()).thenReturn(principal);
        when(access.authenticate("fixture",device.toString())).thenReturn(account);
        when(access.revalidate(account)).thenReturn(principal);
        when(signer.sign(key)).thenReturn(new PreservationDownloadSigner.SignedGet("https://fixture.r2.cloudflarestorage.com/object",Instant.parse("2026-10-09T08:05:00Z")));
        service=new PlaybackUrls(db,access,new DataSourceTransactionManager(db.getDataSource()),signer);
    }
    @AfterEach void close(){db.execute("SHUTDOWN");}
    @Test void issuesOnlyCurrentOwnedStoredIdentityAndNoStoreEndpoint() {
        var ticket=service.issue("fixture",device.toString(),id);
        assertThat(ticket).containsEntry("user_id",owner.toString()).containsEntry("recording_id",id.toString())
            .containsEntry("generation",generation.toString()).containsEntry("size_bytes",12L)
            .containsEntry("sha256","a".repeat(64)).containsEntry("expires_at","2026-10-09T08:05:00Z");
        assertThat(new PlaybackController(service).issue("fixture",device.toString(),id).getHeaders().getFirst("Cache-Control")).isEqualTo("no-store");
        verify(signer,times(2)).sign(key);
    }
    @Test void othersDeletedMissingAndUnstoredNeverSign() {
        assertUnavailable(UUID.randomUUID());
        db.update("UPDATE recording SET user_id=?",bytes(UUID.randomUUID()));assertUnavailable(id);
        db.update("UPDATE recording SET user_id=?",bytes(owner));
        for(String life:List.of("TRASHED","PURGE_PENDING","PURGED")){
            db.update("UPDATE recording SET lifecycle_state=?",life);assertUnavailable(id);
        }
        db.update("UPDATE recording SET lifecycle_state='ACTIVE'");
        for(String state:List.of("NONE","QUEUED","UPLOADING","VERIFYING","DELETING")){
            db.update("UPDATE recording_asset SET cloud_state=?",state);assertUnavailable(id);
        }
        verifyNoInteractions(signer);
    }
    @Test void corruptKeySizeAndHashNeverSign() {
        db.update("UPDATE recording_asset SET object_key='other-owner'");
        assertThatIllegalStateException().isThrownBy(()->service.issue("fixture",device.toString(),id));
        db.update("UPDATE recording_asset SET object_key=?,sha256='bad'",key.value());
        assertThatIllegalStateException().isThrownBy(()->service.issue("fixture",device.toString(),id));
        db.update("UPDATE recording_asset SET sha256=?,verified_size=6291457","a".repeat(64));
        assertThatIllegalStateException().isThrownBy(()->service.issue("fixture",device.toString(),id));
        verifyNoInteractions(signer);
    }
    @Test void revokedSessionDoesNotReleaseSignedUrl() {
        var denied=new ApiException(HttpStatus.UNAUTHORIZED,"AUTH_INVALID_SESSION","fixture",false,Map.of());
        when(access.revalidate(account)).thenThrow(denied);
        assertThatThrownBy(()->service.issue("fixture",device.toString(),id)).isSameAs(denied);
        verifyNoInteractions(signer);
        reset(signer);
        when(signer.sign(key)).thenReturn(new PreservationDownloadSigner.SignedGet("https://fixture.r2.cloudflarestorage.com/object",Instant.now().plusSeconds(300)));
        doReturn(account.principal()).doThrow(denied).when(access).revalidate(account);
        assertThatThrownBy(()->service.issue("fixture",device.toString(),id)).isSameAs(denied);
        verify(signer).sign(key); // Revoked after signing: response URL still never escapes.
    }
    private void assertUnavailable(UUID recording) {
        assertThatThrownBy(()->service.issue("fixture",device.toString(),recording))
            .isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("AUDIO_UNAVAILABLE"));
    }
}
