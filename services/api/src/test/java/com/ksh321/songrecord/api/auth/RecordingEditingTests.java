package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.recordings.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.mock.web.MockHttpServletResponse;
import tools.jackson.databind.json.JsonMapper;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;

class RecordingEditingTests {
    final RecordingListingTests listing=new RecordingListingTests();final JsonMapper json=new JsonMapper();
    RecordingDraftTests setup;IdempotencyTests f;
    @BeforeEach void open()throws Exception{
        listing.open();setup=listing.setup;f=setup.setup.f;
        new ResourceDatabasePopulator(new ClassPathResource("job-schema.sql")).populate(f.keeper);
        f.jdbc.execute("CREATE TABLE condition_catalog(code VARCHAR(16) PRIMARY KEY,name VARCHAR(50))");
        f.jdbc.update("INSERT INTO condition_catalog VALUES('GOOD','좋음'),('BAD','안 좋음'),('NORMAL','보통'),('VERY_GOOD','매우 좋음')");
        f.jdbc.execute("CREATE TABLE recording_time_correction(user_id BINARY(16),recording_id BINARY(16),revision BIGINT,actor_device_id BINARY(16),old_recorded_at TIMESTAMP(3),new_recorded_at TIMESTAMP(3),old_timezone_id VARCHAR(64),new_timezone_id VARCHAR(64),old_offset_minutes SMALLINT,new_offset_minutes SMALLINT,corrected_at TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP,PRIMARY KEY(recording_id,revision))");
    }
    @AfterEach void close()throws Exception{listing.close();}
    MockHttpServletResponse edit(Map<String,Object> body)throws Exception{return setup.setup.mvc.perform(patch("/v1/recordings/"+setup.id).header("Authorization","Bearer "+f.tokens.accessToken()).header("X-Device-Id",f.registration.deviceId()).header("Idempotency-Key",UUID.randomUUID()).contentType("application/json").content(json.writeValueAsString(body))).andReturn().getResponse();}
    @Test void metadataHistoryTagsJobsReplayAndRollbackMatchMySql(){RecordingEditingDatabaseChecks.verify(f.jdbc,setup.setup.context.getBean(RecordingDrafts.class),setup.setup.context.getBean(RecordingEditing.class),"Bearer "+f.tokens.accessToken(),f.registration.deviceId().toString(),f.registration.userId());}
    @Test void draftPartialEditsNullSemanticsAndCursorInvalidation()throws Exception{
        var body=setup.base();body.put("title_snapshot","zzz");assertThat(setup.create(body).getStatus()).isEqualTo(201);UUID id=setup.id;
        setup.id=UUID.randomUUID();body=setup.base();body.put("title_snapshot","middle");assertThat(setup.create(body).getStatus()).isEqualTo(201);setup.id=id;
        String cursor=json.readTree(listing.list("sort","TITLE","limit","1").getContentAsString()).get("next_cursor").asText();
        var edited=edit(Map.of("base_revision",1,"title_snapshot"," alpha ","artist_snapshot","artist","key_mode","FEMALE","key_shift",12,"version_code","MR","note","😀".repeat(2000)));
        assertThat(edited.getStatus()).isEqualTo(200);assertThat(edited.getHeader("Cache-Control")).isEqualTo("no-store");assertThat(json.readTree(edited.getContentAsString()).get("metadata_state").asText()).isEqualTo("DRAFT");
        assertThat(listing.list("sort","TITLE","limit","1","cursor",cursor).getContentAsString()).contains("LIST_CURSOR_EXPIRED");
        assertThat(json.readTree(listing.list("sort","TITLE").getContentAsString()).get("items").get(0).get("id").asText()).isEqualTo(id.toString());
        var clear=new LinkedHashMap<String,Object>();clear.put("base_revision",2);for(String key:List.of("title_snapshot","artist_snapshot","key_mode","key_shift","note"))clear.put(key,null);
        var response=edit(clear);assertThat(response.getStatus()).isEqualTo(200);var node=json.readTree(response.getContentAsString());assertThat(node.get("note").asText()).isEmpty();assertThat(node.get("title_snapshot").isNull()).isTrue();assertThat(node.get("key_mode").isNull()).isTrue();
        var conflict=edit(Map.of("base_revision",2,"note","stale"));assertThat(conflict.getContentAsString()).contains("REVISION_CONFLICT", "recorded_at", "tag_ids", "condition_name_snapshot");
    }
    @Test void rejectsMalformedFieldsWithoutChangingAnything()throws Exception{
        setup.create(setup.base());
        var cases=new ArrayList<Map<String,Object>>();
        for(var e:Map.<String,Object>ofEntries(Map.entry("version_code","INVALID"),Map.entry("key_shift",13),Map.entry("key_mode","MALE"),Map.entry("recorded_at","2026-02-30T00:00:00Z"),Map.entry("timezone_id","fake/zone"),Map.entry("timezone_offset_minutes",1081),Map.entry("tag_ids",List.of("bad")),Map.entry("title_snapshot","x".repeat(201)),Map.entry("note","x".repeat(2001)),Map.entry("condition_code","UNKNOWN"),Map.entry("song_id",UUID.randomUUID().toString()),Map.entry("tier","A"),Map.entry("user_id",f.registration.userId().toString()),Map.entry("metadata_state","SAVED")).entrySet())cases.add(Map.of("base_revision",1,e.getKey(),e.getValue()));
        for(String key:List.of("version_code","tag_ids","recorded_at","timezone_id","timezone_offset_minutes")){var b=new LinkedHashMap<String,Object>();b.put("base_revision",1);b.put(key,null);cases.add(b);}
        String tag=UUID.randomUUID().toString();cases.add(Map.of("base_revision",1,"tag_ids",List.of(tag,tag)));
        for(var b:cases)assertThat(edit(b).getStatus()).as(b.toString()).isEqualTo(400);
        assertThat(f.jdbc.queryForObject("SELECT revision FROM recording",Long.class)).isEqualTo(1);assertThat(setup.setup.count("mutation_receipt")).isEqualTo(1);
    }
    @Test void savedRequiredFieldsFileAndRelationshipStayProtected()throws Exception{
        setup.create(setup.base());var file=Map.of("size_bytes",100,"duration_ms",1000,"sha256","a".repeat(64),"codec","AAC_LC","sample_rate",48000,"channels",1,"capture_integrity","VALIDATED");
        var save=Map.of("base_revision",1,"metadata_state","SAVED","title_snapshot","title","artist_snapshot","artist","key_mode","ORIGINAL","key_shift",0,"file",file);assertThat(edit(save).getStatus()).isEqualTo(200);
        for(String key:List.of("title_snapshot","artist_snapshot","key_mode","key_shift","version_code")){var b=new LinkedHashMap<String,Object>();b.put("base_revision",2);b.put(key,null);assertThat(edit(b).getStatus()).as(key).isEqualTo(400);}
        assertThat(edit(Map.of("base_revision",2,"metadata_state","DRAFT")).getStatus()).isEqualTo(409);
        assertThat(edit(Map.of("base_revision",2,"metadata_state","SAVED","file",file)).getStatus()).isEqualTo(409);
        assertThat(edit(Map.of("base_revision",2,"metadata_state","SAVED","note","edited")).getStatus()).isEqualTo(200);
        assertThat(setup.setup.count("recording_file_spec")).isEqualTo(1);
    }
    @Test void ownerAuthArchivedStateAndOtherAccountsTags()throws Exception{
        setup.create(setup.base());String request=json.writeValueAsString(Map.of("base_revision",1,"note","private"));
        assertThat(setup.setup.mvc.perform(patch("/v1/recordings/"+setup.id).contentType("application/json").content(request)).andReturn().getResponse().getStatus()).isEqualTo(401);
        var p=f.other.principal();var tokens=f.sessions.issue(new AccountRegistrationService.Registration(p.userId(),p.deviceId(),false));
        assertThat(setup.setup.mvc.perform(patch("/v1/recordings/"+setup.id).header("Authorization","Bearer "+tokens.accessToken()).header("X-Device-Id",p.deviceId()).header("Idempotency-Key",UUID.randomUUID()).contentType("application/json").content(request)).andReturn().getResponse().getStatus()).isEqualTo(404);
        UUID tag=UUID.randomUUID();f.jdbc.update("INSERT INTO tag(id,user_id,name) VALUES(?,?,'other')",bytes(tag),bytes(p.userId()));assertThat(edit(Map.of("base_revision",1,"tag_ids",List.of(tag.toString()))).getStatus()).isEqualTo(404);
        for(String state:List.of("TRASHED","PURGE_PENDING","PURGED")){f.jdbc.update("UPDATE recording SET lifecycle_state=?",state);assertThat(edit(Map.of("base_revision",1,"note","x")).getStatus()).isEqualTo(409);}
    }
    @Test void timezoneOnlyCorrectionKeepsInstantAndDoesNotQueuePolicy()throws Exception{
        setup.create(setup.base());assertThat(edit(Map.of("base_revision",1,"timezone_id","UTC","timezone_offset_minutes",0)).getStatus()).isEqualTo(200);
        assertThat(setup.setup.count("recording_time_correction")).isEqualTo(1);assertThat(setup.setup.count("job")).isZero();
        assertThat(f.jdbc.queryForObject("SELECT old_recorded_at=new_recorded_at FROM recording_time_correction",Boolean.class)).isTrue();
    }
}
