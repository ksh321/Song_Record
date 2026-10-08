package com.ksh321.songrecord.api.retention;

import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.context.annotation.AnnotationConfigApplicationContext;
import static com.ksh321.songrecord.api.retention.RetentionCandidateDatabaseChecks.*;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;

class RetentionCandidatesTests {
    JdbcTemplate db;
    @BeforeEach void setup() {
        db=new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa",""));
        db.execute("CREATE TABLE app_user(id BINARY(16) PRIMARY KEY,status VARCHAR(16) DEFAULT 'ACTIVE')");
        db.execute("CREATE TABLE device(id BINARY(16) PRIMARY KEY,user_id BINARY(16),display_name VARCHAR(200),last_seen_at TIMESTAMP)");
        db.execute("CREATE TABLE song(id BINARY(16) PRIMARY KEY,user_id BINARY(16),source_type VARCHAR(16),title VARCHAR(200),artist VARCHAR(200),note VARCHAR(2000),lifecycle_state VARCHAR(16) DEFAULT 'ACTIVE',deleted_at TIMESTAMP)");
        db.execute("CREATE TABLE recording(id BINARY(16) PRIMARY KEY,user_id BINARY(16),origin_device_id BINARY(16),song_id BINARY(16),title_snapshot VARCHAR(200),artist_snapshot VARCHAR(200),key_mode VARCHAR(16),key_shift INT,note VARCHAR(2000),recorded_at TIMESTAMP,timezone_id VARCHAR(64),timezone_offset_minutes INT,metadata_state VARCHAR(16) DEFAULT 'DRAFT',lifecycle_state VARCHAR(16) DEFAULT 'ACTIVE',tier VARCHAR(1),version_code VARCHAR(16) DEFAULT 'NORMAL',revision BIGINT DEFAULT 1,link_revision BIGINT DEFAULT 1,deleted_at TIMESTAMP)");
        db.execute("CREATE TABLE recording_file_spec(recording_id BINARY(16) PRIMARY KEY,user_id BINARY(16),sha256 VARCHAR(70),size_bytes BIGINT,duration_ms INT,codec VARCHAR(32),sample_rate INT,channels INT,capture_integrity VARCHAR(32))");
        // Deliberately no recording_asset or device-local file tables: candidates must not depend on them.
    }
    @Test void representativeUsesOnlyExplicitEligiblePointer() {
        db.execute("ALTER TABLE song ADD representative_recording_id BINARY(16)");
        verifyRepresentative(db);
    }
    @Test void representativeRejectsWrongSongDraftAndDamagedWithoutChangingPointer() {
        db.execute("ALTER TABLE song ADD representative_recording_id BINARY(16)");
        UUID owner=account(db), dev=device(db,owner), song=song(db,owner), other=song(db,owner);
        var roles=new RetentionRoles(new RetentionCandidates(db));
        UUID id=recording(db,owner,dev,other,true,true,"VALIDATED");
        db.update("UPDATE song SET representative_recording_id=? WHERE id=?",bytes(id),bytes(song));
        assertThat(roles.representative(owner,song)).isEmpty();
        db.update("UPDATE recording SET song_id=?,metadata_state='DRAFT' WHERE id=?",bytes(song),bytes(id));
        assertThat(roles.representative(owner,song)).isEmpty();
        db.update("UPDATE recording SET metadata_state='SAVED' WHERE id=?",bytes(id));
        db.update("UPDATE recording_file_spec SET capture_integrity='DAMAGED' WHERE recording_id=?",bytes(id));
        assertThat(roles.representative(owner,song)).isEmpty();
    }
    @Test void latestUsesRecordedTimeThenUnsignedIdWithoutStorageOrArrivalOrder() { verifyLatest(db); }
    @Test void lowestTierIgnoresUnratedAndSongTierThenUsesTimeAndUnsignedId() {
        db.execute("ALTER TABLE song ADD song_tier VARCHAR(1)");
        verifyLowestTier(db);
    }
    @AfterEach void close() { db.execute("SHUTDOWN"); }
    @Test void ownerSongLifecycleAndCrossDeviceEligibility() { verify(db); }
    @Test void rejectsIncompleteDamagedAndCrossOwnerFileSpecs() {
        UUID owner=account(db), device=device(db,owner), song=song(db,owner);
        UUID id=recording(db,owner,device,song,true,true,"VALIDATED");
        var query=new RetentionCandidates(db);
        assertThat(query.forSong(owner,song)).hasSize(1);
        for (String assignment:List.of("sha256=NULL","sha256='bad'","sha256='"+"A".repeat(64)+"'",
                "size_bytes=0","size_bytes=6291457","duration_ms=0","duration_ms=361001",
                "codec='MP3'","sample_rate=44100","channels=2","capture_integrity='DAMAGED'","capture_integrity=NULL")) {
            db.update("UPDATE recording_file_spec SET "+assignment+" WHERE recording_id=?",bytes(id));
            assertThat(query.forSong(owner,song)).as(assignment).isEmpty();
            db.update("UPDATE recording_file_spec SET sha256=?,size_bytes=1,duration_ms=1,codec='AAC_LC',sample_rate=48000,channels=1,capture_integrity='VALIDATED' WHERE recording_id=?","a".repeat(64),bytes(id));
        }
        assertThat(query.forSong(owner,song)).hasSize(1); // lower valid bounds
        db.update("UPDATE recording_file_spec SET user_id=? WHERE recording_id=?",bytes(UUID.randomUUID()),bytes(id));
        assertThat(query.forSong(owner,song)).isEmpty();
        db.update("DELETE FROM recording_file_spec WHERE recording_id=?",bytes(id));
        assertThat(query.forSong(owner,song)).isEmpty(); // malformed imported SAVED without specification
    }
    @Test void readDoesNotChangeMetadataOrCandidateSetAndIncludesEveryEligibleRecording() {
        UUID owner=account(db), device=device(db,owner), song=song(db,owner);
        for(int i=0;i<5;i++)recording(db,owner,device,song,true,true,"VALIDATED");
        var before=db.queryForList("SELECT * FROM recording ORDER BY id");
        var query=new RetentionCandidates(db);var first=query.forSong(owner,song);
        assertThat(first).hasSize(5);assertThat(query.forSong(owner,song)).isEqualTo(first);
        assertThat(db.queryForList("SELECT * FROM recording ORDER BY id")).usingRecursiveComparison().isEqualTo(before);
        db.update("UPDATE recording SET lifecycle_state='PURGE_PENDING'");assertThat(query.forSong(owner,song)).isEmpty();
        db.update("UPDATE recording SET lifecycle_state='PURGED'");assertThat(query.forSong(owner,song)).isEmpty();
    }
    @Test void registeredAsInternalSpringComponentAndRejectsMissingScope() {
        try(var context=new AnnotationConfigApplicationContext()) {
            context.registerBean(JdbcTemplate.class,()->db);context.register(RetentionCandidates.class);context.refresh();
            var query=context.getBean(RetentionCandidates.class);
            assertThatNullPointerException().isThrownBy(()->query.forSong(null,UUID.randomUUID()));
            assertThatNullPointerException().isThrownBy(()->query.forSong(UUID.randomUUID(),null));
        }
    }
}
