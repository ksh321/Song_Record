package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.retention.*;
import com.ksh321.songrecord.api.web.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.test.web.servlet.*;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static com.ksh321.songrecord.api.retention.RetentionCandidateDatabaseChecks.recording;
import static com.ksh321.songrecord.api.retention.PinReservationDatabaseChecks.body;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;

class PinSlotsTests {
    final RecordingListingTests setup=new RecordingListingTests();IdempotencyTests f;PinSlots pins;MockMvc mvc;
    String auth,device;UUID owner;
    @BeforeEach void open()throws Exception {
        setup.open();f=setup.setup.setup.f;owner=f.registration.userId();device=f.registration.deviceId().toString();auth="Bearer "+f.tokens.accessToken();
        for(String column:List.of("revision BIGINT DEFAULT 1","operation_id BINARY(16)","requested_at TIMESTAMP(3)","updated_at TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP"))f.jdbc.execute("ALTER TABLE pin_slot ADD "+column);
        pins=new PinSlots(f.jdbc,f.access,f.mutations);mvc=MockMvcBuilders.standaloneSetup(new PinController(pins)).setControllerAdvice(new GlobalExceptionHandler()).build();
    }
    @AfterEach void close()throws Exception{setup.close();}
    UUID saved(){return recording(f.jdbc,owner,f.registration.deviceId(),null,true,true,"VALIDATED");}
    void asset(UUID id,String state){f.jdbc.update("INSERT INTO recording_asset(recording_id,user_id,cloud_state,cloud_revision,verified_size,sha256,generation,object_key,stored_at) VALUES(?,?,?,1,6291456,?,?,'fixture/object',CURRENT_TIMESTAMP)",bytes(id),bytes(owner),state,"a".repeat(64),bytes(UUID.randomUUID()));}
    @Test void pendingCountsAndTwoDevicesCannotBothTakeTenthSlot(){
        UUID second=com.ksh321.songrecord.api.retention.RetentionCandidateDatabaseChecks.device(f.jdbc,owner);
        var tokens=f.sessions.issue(new AccountRegistrationService.Registration(owner,second,false));
        PinReservationDatabaseChecks.verify(f.jdbc,pins,auth,device,owner,"Bearer "+tokens.accessToken(),second.toString());
    }
    @Test void storedConfirmsImmediatelyAndOnlyBumpsPolicyVersion(){
        UUID id=saved();asset(id,"STORED");var before=f.jdbc.queryForMap("SELECT * FROM recording");String key=UUID.randomUUID().toString();
        var result=pins.reserve(auth,device,key,body(id,1));assertThat(result.status()).isEqualTo(201);assertThat(result.body()).contains("\"current_recording_id\":\""+id,"\"pending_recording_id\":null");
        assertThat(pins.reserve(auth,device,key,body(id,1))).isEqualTo(result);
        assertThat(pins.reserve(auth,device,UUID.randomUUID().toString(),body(id,1)).status()).isEqualTo(200);
        assertThat(f.jdbc.queryForObject("SELECT cloud_revision FROM recording_asset",Long.class)).isEqualTo(2);
        assertThat(f.jdbc.queryForObject("SELECT cloud_state FROM recording_asset",String.class)).isEqualTo("STORED");
        assertThat(f.jdbc.queryForMap("SELECT * FROM recording")).usingRecursiveComparison().isEqualTo(before);
        assertThat(f.jdbc.queryForObject("SELECT used_bytes+reserved_bytes FROM storage_usage WHERE user_id=?",Long.class,bytes(owner))).isZero();
    }
    @Test void rejectsForeignDraftInactiveCleanupAndStaleEntitlement(){
        UUID id=saved();
        assertThatThrownBy(()->pins.reserve(auth,device,UUID.randomUUID().toString(),body(id,2))).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("ENTITLEMENT_REVISION_CONFLICT"));
        f.jdbc.update("UPDATE recording SET metadata_state='DRAFT' WHERE id=?",bytes(id));assertRejected(id,"PIN_NOT_ELIGIBLE");
        f.jdbc.update("UPDATE recording SET metadata_state='SAVED',lifecycle_state='TRASHED' WHERE id=?",bytes(id));assertRejected(id,"PIN_NOT_ELIGIBLE");
        f.jdbc.update("UPDATE recording SET lifecycle_state='ACTIVE' WHERE id=?",bytes(id));asset(id,"DELETING");assertRejected(id,"FILE_CLEANUP_IN_PROGRESS");
        f.jdbc.update("UPDATE recording SET user_id=? WHERE id=?",bytes(f.other.principal().userId()),bytes(id));assertRejected(id,"RESOURCE_NOT_FOUND");
        assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM pin_slot",Long.class)).isZero();
    }
    void assertRejected(UUID id,String code){assertThatThrownBy(()->pins.reserve(auth,device,UUID.randomUUID().toString(),body(id,1))).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo(code));}
    @Test void failedVersionFenceRollsBackSlotAndReceipt(){
        UUID id=saved();asset(id,"STORED");f.jdbc.update("UPDATE recording_asset SET cloud_revision=?",Long.MAX_VALUE);
        assertRejected(id,"REVISION_LIMIT_REACHED");assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM pin_slot",Long.class)).isZero();assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Long.class)).isZero();
    }
    @Test void httpRequiresSessionAndStrictRequestAndReturnsNoStore()throws Exception {
        UUID id=saved();assertThat(mvc.perform(post("/v1/pins").contentType("application/json").content(body(id,1))).andReturn().getResponse().getStatus()).isEqualTo(401);
        for(String input:List.of("{}","[]",body(id,0),body(id,1).replace("1}","1.5}"),body(id,1).replace("}",",\"user_id\":\""+owner+"\"}"))){assertThat(mvc.perform(post("/v1/pins").header("Authorization",auth).header("X-Device-Id",device).header("Idempotency-Key",UUID.randomUUID()).contentType("application/json").content(input)).andReturn().getResponse().getStatus()).isEqualTo(400);}
        var result=mvc.perform(post("/v1/pins").header("Authorization",auth).header("X-Device-Id",device).header("Idempotency-Key",UUID.randomUUID()).contentType("application/json").content(body(id,1))).andReturn().getResponse();
        assertThat(result.getStatus()).isEqualTo(201);assertThat(result.getHeader("Cache-Control")).isEqualTo("no-store");
    }
}
