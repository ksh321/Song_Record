package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.retention.*;
import com.ksh321.songrecord.api.web.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.test.web.servlet.*;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static com.ksh321.songrecord.api.retention.PinReservationDatabaseChecks.body;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;

class PinReleaseQueriesTests {
    final PinSlotsTests f=new PinSlotsTests();RetentionQueries query;MockMvc mvc;
    @BeforeEach void open()throws Exception{
        f.open();f.f.jdbc.execute("CREATE TABLE cloud_hold(id BINARY(16),user_id BINARY(16),recording_id BINARY(16),reason VARCHAR(32))");
        query=new RetentionQueries(f.f.jdbc,f.f.access,f.f.manager);
        mvc=MockMvcBuilders.standaloneSetup(new PinController(f.pins),new RetentionController(query)).setControllerAdvice(new GlobalExceptionHandler()).build();
    }
    @AfterEach void close()throws Exception{f.close();}
    @Test void releasePreservesOtherReasonsAndCountsOneFileOneSlot(){PinReleaseDatabaseChecks.verify(f.f.jdbc,f.pins,query,f.auth,f.device,f.owner);}
    @Test void deletionWaitBytesRemainUsedAndOrphanHoldIsNotCleanupReady(){
        UUID id=f.saved();f.asset(id,"STORED");f.f.jdbc.update("INSERT INTO cloud_hold VALUES(?,?,?,'ORPHAN_KEEP')",bytes(UUID.randomUUID()),bytes(f.owner),bytes(id));
        f.f.jdbc.update("UPDATE storage_usage SET used_bytes=6291456 WHERE user_id=?",bytes(f.owner));
        assertThat(((Number)query.storage(f.auth,f.device).get("cleanup_pending_bytes")).longValue()).isZero();
        f.f.jdbc.update("UPDATE recording_asset SET cloud_state='DELETING'");f.f.jdbc.update("UPDATE recording SET lifecycle_state='TRASHED'");
        var usage=query.storage(f.auth,f.device);for(String key:List.of("used_bytes","trash_bytes","cleanup_pending_bytes","hold_bytes"))assertThat(((Number)usage.get(key)).longValue()).isEqualTo(6291456);
        assertThat(((Map<?,?>)query.retention(f.auth,f.device,id.toString()).get("cloud")).get("stored")).isEqualTo(false);
    }
    @Test void failedReleasePreservesSlotVersionAndProtection(){
        UUID id=f.saved();f.asset(id,"STORED");f.pins.reserve(f.auth,f.device,UUID.randomUUID().toString(),body(id,1));
        f.f.jdbc.update("UPDATE recording_asset SET cloud_revision=?",Long.MAX_VALUE);
        assertThatThrownBy(()->f.pins.release(f.auth,f.device,UUID.randomUUID().toString(),"1","{\"base_revision\":1}")).isInstanceOf(ApiException.class);
        assertThat(f.f.jdbc.queryForObject("SELECT current_recording_id FROM pin_slot",byte[].class)).isEqualTo(bytes(id));assertThat(f.f.jdbc.queryForObject("SELECT revision FROM pin_slot",Long.class)).isEqualTo(1);
    }
    @Test void readAndReleaseAreAccountScopedAndHttpContractsAreNoStore()throws Exception{
        UUID id=f.saved();f.pins.reserve(f.auth,f.device,UUID.randomUUID().toString(),body(id,1));
        assertThat(mvc.perform(get("/v1/storage")).andReturn().getResponse().getStatus()).isEqualTo(401);
        var principal=f.f.other.principal();String foreign="Bearer "+f.f.sessions.issue(new AccountRegistrationService.Registration(principal.userId(),principal.deviceId(),false)).accessToken();
        assertThatThrownBy(()->query.retention(foreign,principal.deviceId().toString(),id.toString())).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("RESOURCE_NOT_FOUND"));
        assertThatThrownBy(()->f.pins.release(foreign,principal.deviceId().toString(),UUID.randomUUID().toString(),"1","{\"base_revision\":1}")).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("RESOURCE_NOT_FOUND"));
        assertThat(((Number)query.storage(foreign,principal.deviceId().toString()).get("pinned_used")).longValue()).isZero();
        for(String path:List.of("/v1/storage","/v1/recordings/"+id+"/retention")){
            var response=mvc.perform(get(path).header("Authorization",f.auth).header("X-Device-Id",f.device)).andReturn().getResponse();assertThat(response.getStatus()).isEqualTo(200);assertThat(response.getHeader("Cache-Control")).isEqualTo("no-store");assertThat(response.getContentAsString()).doesNotContain("object_key", "fixture/object");
        }
        var response=mvc.perform(delete("/v1/pins/1").header("Authorization",f.auth).header("X-Device-Id",f.device).header("Idempotency-Key",UUID.randomUUID()).contentType("application/json").content("{\"base_revision\":1}")).andReturn().getResponse();assertThat(response.getStatus()).isEqualTo(200);assertThat(response.getHeader("Cache-Control")).isEqualTo("no-store");
    }
}
