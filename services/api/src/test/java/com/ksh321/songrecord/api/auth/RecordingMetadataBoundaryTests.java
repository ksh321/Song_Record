package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.recordings.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import static org.assertj.core.api.Assertions.*;

class RecordingMetadataBoundaryTests {
    final RecordingLinkingTests fixture = new RecordingLinkingTests();
    @BeforeEach void open() throws Exception {
        fixture.open();
        fixture.setup.f.jdbc.execute("CREATE TABLE global_storage_usage(id INT PRIMARY KEY,used_bytes BIGINT DEFAULT 0,reserved_bytes BIGINT DEFAULT 0,upload_locked BOOLEAN DEFAULT FALSE)");
        fixture.setup.f.jdbc.update("INSERT INTO global_storage_usage(id) VALUES(1)");
    }
    @AfterEach void close() throws Exception { fixture.close(); }

    @ParameterizedTest @ValueSource(strings={"QUOTA","PIN_LIMIT","BUDGET"})
    void storageRestrictionsDoNotGateMetadata(String reason) {
        var s = fixture.setup; var c = s.setup.setup.context;
        RecordingMetadataBoundaryChecks.verify(s.f.jdbc, c.getBean(RecordingDrafts.class),
                c.getBean(RecordingEditing.class), c.getBean(RecordingRating.class),
                c.getBean(RecordingLinking.class), c.getBean(RecordingListing.class),
                "Bearer " + s.f.tokens.accessToken(), s.f.registration.deviceId().toString(),
                s.f.registration.userId(), reason);
    }

    @Test void httpSaveStillRequiresValidMetadataWhileUploadIsLocked() throws Exception {
        var s = fixture.setup;
        s.f.jdbc.update("UPDATE global_storage_usage SET upload_locked=TRUE");
        assertThat(s.setup.create(s.setup.base()).getStatus()).isEqualTo(201);
        var file = Map.of("size_bytes",100,"duration_ms",1000,"sha256","a".repeat(64),
                "codec","AAC_LC","sample_rate",48000,"channels",1,"capture_integrity","VALIDATED");
        var body = new LinkedHashMap<String,Object>(Map.of("base_revision",1,"metadata_state","SAVED",
                "artist_snapshot","artist","key_mode","ORIGINAL","key_shift",0,"file",file));
        assertThat(s.edit(body).getStatus()).isEqualTo(400);
        assertThat(s.setup.setup.count("recording_file_spec")).isZero();
        body.put("title_snapshot","title");
        assertThat(s.edit(body).getStatus()).isEqualTo(200);
        var invalid = new LinkedHashMap<String,Object>();invalid.put("base_revision",2);invalid.put("key_mode",null);invalid.put("key_shift",null);
        assertThat(s.edit(invalid).getStatus()).isEqualTo(400);
        assertThat(s.setup.setup.count("recording_file_spec")).isEqualTo(1);
        assertThat(s.setup.setup.count("recording_asset")).isZero();
        assertThat(s.f.jdbc.queryForObject("SELECT key_shift FROM recording",Integer.class)).isZero();
        assertThat(s.f.jdbc.queryForObject("SELECT revision FROM recording",Long.class)).isEqualTo(2);
        assertThat(s.f.jdbc.queryForObject("SELECT upload_locked FROM global_storage_usage",Boolean.class)).isTrue();
    }
}
