package com.ksh321.songrecord.api.auth;

import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.mock.web.MockHttpServletResponse;
import tools.jackson.databind.json.JsonMapper;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;

class RecordingSavingTests {
    final RecordingDraftTests setup=new RecordingDraftTests();final JsonMapper json=new JsonMapper();
    @BeforeEach void open()throws Exception{
        setup.open();setup.setup.f.jdbc.execute("CREATE TABLE recording_file_spec(recording_id BINARY(16) PRIMARY KEY,user_id BINARY(16),sha256 CHAR(64),size_bytes BIGINT,duration_ms INT,codec VARCHAR(32),sample_rate INT,channels SMALLINT,capture_integrity VARCHAR(32),created_at TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP)");
        assertThat(setup.create(setup.base()).getStatus()).isEqualTo(201);
    }
    @AfterEach void close()throws Exception{setup.close();}
    Map<String,Object> file(){return new LinkedHashMap<>(Map.of("size_bytes",6291456,"duration_ms",361000,"sha256","a".repeat(64),"codec","AAC_LC","sample_rate",48000,"channels",1,"capture_integrity","RECOVERED"));}
    Map<String,Object> body(){return new LinkedHashMap<>(Map.of("base_revision",1,"metadata_state","SAVED","title_snapshot"," title ","artist_snapshot"," artist ","key_mode","ORIGINAL","key_shift",0,"file",file()));}
    MockHttpServletResponse save(String op,Map<String,Object> body)throws Exception{return setup.setup.mvc.perform(patch("/v1/recordings/"+setup.id).header("Authorization","Bearer "+setup.setup.f.tokens.accessToken()).header("X-Device-Id",setup.setup.f.registration.deviceId()).header("Idempotency-Key",op).contentType("application/json").content(json.writeValueAsString(body))).andReturn().getResponse();}
    MockHttpServletResponse save(Map<String,Object> body)throws Exception{return save(UUID.randomUUID().toString(),body);}
    @Test void completesWithFileSpecWithoutCloudOrQuotaAndReplaysOnce()throws Exception{
        var before=setup.setup.f.jdbc.queryForMap("SELECT origin_device_id,recorded_at,timezone_id,song_id FROM recording");String op=UUID.randomUUID().toString();var first=save(op,body());assertThat(first.getStatus()).isEqualTo(200);assertThat(first.getHeader("Cache-Control")).isEqualTo("no-store");
        var result=json.readTree(first.getContentAsString());assertThat(result.get("metadata_state").asText()).isEqualTo("SAVED");assertThat(result.get("revision").asInt()).isEqualTo(2);assertThat(result.get("title_snapshot").asText()).isEqualTo("title");assertThat(result.get("version_code").asText()).isEqualTo("NORMAL");assertThat(result.get("file").get("duration_ms").asInt()).isEqualTo(361000);
        assertThat(save(op,body()).getContentAsString()).isEqualTo(first.getContentAsString());assertThat(setup.setup.count("recording_file_spec")).isEqualTo(1);assertThat(setup.setup.count("change_log")).isEqualTo(2);
        assertThat(setup.setup.f.jdbc.queryForMap("SELECT origin_device_id,recorded_at,timezone_id,song_id FROM recording")).usingRecursiveComparison().isEqualTo(before);
        var changed=body();changed.put("note","different");assertThat(save(op,changed).getContentAsString()).contains("IDEMPOTENCY_CONFLICT");
        assertThat(save(body()).getContentAsString()).contains("REVISION_CONFLICT");changed.put("base_revision",2);assertThat(save(changed).getContentAsString()).contains("RECORDING_ALREADY_SAVED");assertThat(setup.setup.count("change_log")).isEqualTo(2);
    }
    @Test void mergesDraftValuesAndRequiresCompleteValidFields()throws Exception{
        var partial=body();partial.remove("title_snapshot");assertThat(save(partial).getStatus()).isEqualTo(400);
        setup.setup.f.jdbc.update("UPDATE recording SET title_snapshot='retained',artist_snapshot='artist',key_mode='MALE',key_shift=10,version_code='LIVE'");
        var merged=new LinkedHashMap<String,Object>();merged.put("base_revision",1);merged.put("metadata_state","SAVED");merged.put("file",file());merged.put("note","😀".repeat(2000));var response=save(merged);assertThat(response.getStatus()).isEqualTo(200);var result=json.readTree(response.getContentAsString());assertThat(result.get("title_snapshot").asText()).isEqualTo("retained");assertThat(result.get("key_shift").asInt()).isEqualTo(10);assertThat(result.get("version_code").asText()).isEqualTo("LIVE");
    }
    @Test void rejectsInvalidFileBoundariesAndUnsupportedEditsWithoutWrites()throws Exception{
        for(var e:Map.<String,Object>of("size_bytes",6291457,"duration_ms",361001,"sha256","bad","codec","MP3","sample_rate",44100,"channels",2,"capture_integrity","UNKNOWN").entrySet()){var body=body();var file=file();file.put(e.getKey(),e.getValue());body.put("file",file);assertThat(save(body).getStatus()).as(e.toString()).isEqualTo(400);}
        for(String field:file().keySet()){var body=body();var file=file();file.remove(field);body.put("file",file);assertThat(save(body).getStatus()).isEqualTo(400);}
        for(var e:Map.<String,Object>of("song_id",UUID.randomUUID().toString(),"metadata_state","DRAFT","version_code","BAD","key_shift",1,"base_revision",0).entrySet()){var body=body();body.put(e.getKey(),e.getValue());assertThat(save(body).getStatus()).isEqualTo(400);}
        var missing=body();missing.remove("file");assertThat(save(missing).getStatus()).isEqualTo(400);assertThat(setup.setup.count("recording_file_spec")).isZero();assertThat(setup.setup.count("change_log")).isEqualTo(1);
    }
    @Test void authOwnerAndLifecycleAreCheckedBeforeAnyFileWrite()throws Exception{
        assertThat(setup.setup.mvc.perform(patch("/v1/recordings/"+setup.id).contentType("application/json").content(json.writeValueAsString(body()))).andReturn().getResponse().getStatus()).isEqualTo(401);
        var p=setup.setup.f.other.principal();var tokens=setup.setup.f.sessions.issue(new AccountRegistrationService.Registration(p.userId(),p.deviceId(),false));
        assertThat(setup.setup.mvc.perform(patch("/v1/recordings/"+setup.id).header("Authorization","Bearer "+tokens.accessToken()).header("X-Device-Id",p.deviceId()).header("Idempotency-Key",UUID.randomUUID()).contentType("application/json").content(json.writeValueAsString(body()))).andReturn().getResponse().getStatus()).isEqualTo(404);
        for(String state:List.of("TRASHED","PURGE_PENDING","PURGED")){setup.setup.f.jdbc.update("UPDATE recording SET lifecycle_state=?",state);assertThat(save(body()).getStatus()).isEqualTo(409);}assertThat(setup.setup.count("recording_file_spec")).isZero();
    }
    @Test void logFailureRollsBackSpecStateRevisionSequenceAndReceipt()throws Exception{
        var db=setup.setup.f.jdbc;var before=db.queryForMap("SELECT * FROM recording");String op=UUID.randomUUID().toString();
        db.execute("ALTER TABLE change_log ADD CONSTRAINT reject_save CHECK(revision=1)");assertThat(save(op,body()).getStatus()).isEqualTo(500);
        assertThat(db.queryForMap("SELECT * FROM recording")).usingRecursiveComparison().isEqualTo(before);assertThat(setup.setup.count("recording_file_spec")).isZero();assertThat(setup.setup.count("mutation_receipt")).isEqualTo(1);assertThat(db.queryForObject("SELECT last_change_seq FROM user_sync_state WHERE user_id=?",Long.class,bytes(setup.setup.f.registration.userId()))).isEqualTo(1);
        db.execute("ALTER TABLE change_log DROP CONSTRAINT reject_save");assertThat(save(op,body()).getStatus()).isEqualTo(200);
    }
}
