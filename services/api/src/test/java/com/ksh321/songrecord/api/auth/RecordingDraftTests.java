package com.ksh321.songrecord.api.auth;

import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.mock.web.MockHttpServletResponse;
import tools.jackson.databind.json.JsonMapper;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;

class RecordingDraftTests {
    final SongCreationTests setup=new SongCreationTests();final JsonMapper json=new JsonMapper();UUID id=UUID.randomUUID();
    @BeforeEach void open()throws Exception{
        setup.setup();for(String column:List.of("origin_device_id BINARY(16)","timezone_id VARCHAR(64)","timezone_offset_minutes SMALLINT","created_at TIMESTAMP(3)"))setup.f.jdbc.execute("ALTER TABLE recording ADD "+column);
        setup.f.jdbc.execute("ALTER TABLE recording ALTER COLUMN note VARCHAR(8000)");
        setup.f.jdbc.execute("CREATE TABLE recording_query_key(recording_id BINARY(16) PRIMARY KEY,user_id BINARY(16),key_version VARCHAR(64),title_key VARBINARY(2048))");
    }
    @AfterEach void close()throws Exception{setup.close();}
    Map<String,Object> base(){var m=new LinkedHashMap<String,Object>();m.put("id",id.toString());m.put("metadata_state","DRAFT");m.put("recorded_at","2026-09-28T07:00:00.123Z");m.put("timezone_id","Asia/Seoul");m.put("timezone_offset_minutes",540);return m;}
    MockHttpServletResponse create(String key,Map<String,Object> body)throws Exception{return setup.mvc.perform(post("/v1/recordings").header("Authorization","Bearer "+setup.f.tokens.accessToken()).header("X-Device-Id",setup.f.registration.deviceId()).header("Idempotency-Key",key).contentType("application/json").content(json.writeValueAsString(body))).andReturn().getResponse();}
    MockHttpServletResponse create(Map<String,Object> body)throws Exception{return create(UUID.randomUUID().toString(),body);}
    @Test void incompleteInputPersistsWithoutAnyFileOrStorageTables()throws Exception{
        var body=base();body.put("title_snapshot","  ");body.put("note","a\r\nb");var response=create(body);assertThat(response.getStatus()).isEqualTo(201);assertThat(response.getHeader("Cache-Control")).isEqualTo("no-store");
        var node=json.readTree(response.getContentAsString());assertThat(node.get("title_snapshot").isNull()).isTrue();assertThat(node.get("artist_snapshot").isNull()).isTrue();assertThat(node.get("key_mode").isNull()).isTrue();assertThat(node.get("version_code").asText()).isEqualTo("NORMAL");assertThat(node.get("note").asText()).isEqualTo("a\nb");assertThat(node.get("origin_device_id").asText()).isEqualTo(setup.f.registration.deviceId().toString());assertThat(node.get("recorded_at").asText()).isEqualTo("2026-09-28T07:00:00.123Z");
        assertThat(setup.count("recording")).isEqualTo(1);assertThat(setup.count("change_log")).isEqualTo(1);assertThat(setup.count("mutation_receipt")).isEqualTo(1);
        assertThat(setup.f.jdbc.queryForObject("SELECT entity_type FROM change_log",String.class)).isEqualTo("RECORDING");
    }
    @Test void conditionInputUsesFixedCatalogOrNullAndServerSnapshot()throws Exception{
        for(String code:List.of("VERY_GOOD","GOOD","NORMAL","BAD")){
            id=UUID.randomUUID();var body=base();body.put("condition_code",code);
            var response=create(body);assertThat(response.getStatus()).isEqualTo(201);
            var node=json.readTree(response.getContentAsString());
            assertThat(node.get("condition_code").asText()).isEqualTo(code);
            assertThat(node.get("condition_name_snapshot").asText()).isEqualTo(com.ksh321.songrecord.api.classifications.ConditionCatalog.name(code));
        }
        id=UUID.randomUUID();var body=base();body.put("condition_code",null);var response=create(body);
        assertThat(response.getStatus()).isEqualTo(201);assertThat(json.readTree(response.getContentAsString()).get("condition_name_snapshot").isNull()).isTrue();
        id=UUID.randomUUID();body=base();body.put("condition_code",UUID.randomUUID().toString());assertThat(create(body).getStatus()).isEqualTo(400);
        body.put("condition_code","GOOD");body.put("condition_name_snapshot","spoof");assertThat(create(body).getStatus()).isEqualTo(400);
    }
    @Test void retriesNeverDuplicateOrOverwriteExistingDraft()throws Exception{
        String key=UUID.randomUUID().toString();var body=base();body.put("title_snapshot","original");var first=create(key,body);assertThat(first.getStatus()).isEqualTo(201);assertThat(create(key,body).getContentAsString()).isEqualTo(first.getContentAsString());
        body.put("title_snapshot","overwrite");assertThat(create(key,body).getContentAsString()).contains("IDEMPOTENCY_CONFLICT");var duplicate=create(body);assertThat(duplicate.getStatus()).isEqualTo(200);assertThat(json.readTree(duplicate.getContentAsString()).get("title_snapshot").asText()).isEqualTo("original");assertThat(setup.count("change_log")).isEqualTo(1);
        setup.f.jdbc.update("UPDATE recording SET metadata_state='SAVED'");assertThat(create(body).getContentAsString()).contains("RECORDING_ALREADY_SAVED");assertThat(setup.f.jdbc.queryForObject("SELECT metadata_state FROM recording",String.class)).isEqualTo("SAVED");
    }
    @Test void validatesTimeVersionKeysInputLengthsAndRejectsUnsupportedFields()throws Exception{
        for(var entry:Map.<String,Object>ofEntries(Map.entry("metadata_state","SAVED"),Map.entry("version_code","BAD"),Map.entry("recorded_at","2026-02-30T07:00:00Z"),Map.entry("timezone_id","fake/zone"),Map.entry("timezone_offset_minutes",1081),Map.entry("key_shift",1),Map.entry("key_mode","MALE"),Map.entry("title_snapshot","x".repeat(201)),Map.entry("note","x".repeat(2001)),Map.entry("origin_device_id",UUID.randomUUID().toString()),Map.entry("file",Map.of()),Map.entry("tag_ids",List.of())).entrySet()){
            var body=base();body.put(entry.getKey(),entry.getValue());assertThat(create(body).getStatus()).as(entry.toString()).isEqualTo(400);
        }
        for(String field:List.of("id","metadata_state","recorded_at","timezone_id","timezone_offset_minutes")){var body=base();body.remove(field);assertThat(create(body).getStatus()).isEqualTo(400);}
        var body=base();body.put("version_code",null);assertThat(create(body).getStatus()).isEqualTo(400);
        body=base();body.put("key_mode","ORIGINAL");body.put("key_shift",1);assertThat(create(body).getStatus()).isEqualTo(400);
        body.put("key_shift",0);body.put("note","😀".repeat(2000));assertThat(create(body).getStatus()).isEqualTo(201);
    }
    @Test void songLinkChecksOwnershipAndLifecycleWithoutChangingSnapshots()throws Exception{
        assertThat(setup.postBody(UUID.randomUUID().toString(),setup.body("")).getStatus()).isEqualTo(201);var body=base();body.put("song_id",setup.id.toString());body.put("title_snapshot","내 초안");body.put("version_code","MR");assertThat(create(body).getStatus()).isEqualTo(201);
        assertThat(setup.f.jdbc.queryForObject("SELECT title_snapshot FROM recording",String.class)).isEqualTo("내 초안");
        id=UUID.randomUUID();body=base();body.put("song_id",UUID.randomUUID().toString());assertThat(create(body).getStatus()).isEqualTo(404);
        body.put("song_id",setup.id.toString());setup.f.jdbc.update("UPDATE song SET lifecycle_state='TRASHED'");assertThat(create(body).getStatus()).isEqualTo(409);
        setup.f.jdbc.update("UPDATE song SET lifecycle_state='ACTIVE',user_id=?",bytes(setup.f.other.principal().userId()));assertThat(create(body).getStatus()).isEqualTo(404);
    }
    @Test void authenticationTombstonesAndLifecycleBlockResurrection()throws Exception{
        assertThat(setup.mvc.perform(post("/v1/recordings").contentType("application/json").content(json.writeValueAsString(base()))).andReturn().getResponse().getStatus()).isEqualTo(401);
        assertThat(create(base()).getStatus()).isEqualTo(201);
        for(String state:List.of("TRASHED","PURGE_PENDING","PURGED")){setup.f.jdbc.update("UPDATE recording SET lifecycle_state=?",state);assertThat(create(base()).getStatus()).isEqualTo(409);}
        setup.f.jdbc.update("INSERT INTO deletion_ledger(user_id,entity_type,entity_id,revision) VALUES(?,'RECORDING',?,2)",bytes(setup.f.registration.userId()),bytes(id));setup.f.jdbc.update("DELETE FROM recording_query_key");setup.f.jdbc.update("DELETE FROM recording");
        assertThat(create(base()).getContentAsString()).contains("RESOURCE_PURGED");assertThat(setup.count("recording")).isZero();
    }
    @Test void logFailureRollsBackDraftAndReceiptAndAllowsSameKeyRetry()throws Exception{
        setup.f.jdbc.execute("ALTER TABLE change_log ADD CONSTRAINT reject_draft CHECK(entity_type<>'RECORDING')");String key=UUID.randomUUID().toString();assertThat(create(key,base()).getStatus()).isEqualTo(500);
        assertThat(setup.count("recording")).isZero();assertThat(setup.count("mutation_receipt")).isZero();assertThat(setup.count("change_log")).isZero();
        setup.f.jdbc.execute("ALTER TABLE change_log DROP CONSTRAINT reject_draft");assertThat(create(key,base()).getStatus()).isEqualTo(201);
    }
}
