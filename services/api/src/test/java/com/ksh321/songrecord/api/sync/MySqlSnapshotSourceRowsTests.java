package com.ksh321.songrecord.api.sync;

import com.ksh321.songrecord.api.auth.*;
import java.nio.ByteBuffer;
import java.time.*;
import java.util.*;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.*;
import tools.jackson.databind.json.JsonMapper;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

@EnabledIfEnvironmentVariable(named="P07_MYSQL_CI",matches="true")
class MySqlSnapshotSourceRowsTests {
    static JdbcTemplate admin,jdbc;
    static DriverManagerDataSource source;
    static String database;
    static final Instant NOW=Instant.parse("2026-09-30T00:00:00Z");
    static final Clock CLOCK=Clock.fixed(NOW,ZoneOffset.UTC);
    @BeforeAll static void setup() {
        String port=System.getenv().getOrDefault("P10_MYSQL_PORT","3306");
        if(!port.matches("[0-9]{1,5}"))throw new IllegalArgumentException("Invalid test port");
        String base="jdbc:mysql://127.0.0.1:"+port+"/",options="?allowPublicKeyRetrieval=true&useSSL=false";
        String password=System.getenv("P07_MYSQL_PASSWORD");
        admin=new JdbcTemplate(new DriverManagerDataSource(base+options,"root",password));
        database="p10_source_test_"+UUID.randomUUID().toString().replace("-","");admin.execute("CREATE DATABASE "+database);
        source=new DriverManagerDataSource(base+database+options,"root",password);jdbc=new JdbcTemplate(source);
        Flyway.configure().dataSource(source).locations("classpath:db/migration").load().migrate();
    }
    @AfterAll static void cleanup(){if(admin!=null&&database!=null&&database.matches("p10_source_test_[0-9a-f]{32}"))admin.execute("DROP DATABASE "+database);}
    UUID owner(){
        UUID owner=UUID.randomUUID();jdbc.update("INSERT INTO app_user(id) VALUES(?)",bytes(owner));
        jdbc.update("INSERT INTO user_sync_state(user_id,last_change_seq) VALUES(?,7)",bytes(owner));
        jdbc.update("INSERT INTO user_entitlement(user_id) VALUES(?)",bytes(owner));
        jdbc.update("INSERT INTO storage_usage(user_id) VALUES(?)",bytes(owner));
        return owner;
    }
    void song(UUID owner,UUID song,String note){
        jdbc.update("INSERT INTO song(id,user_id,source_type,title,artist,note) VALUES(?,?,'MANUAL','song','artist',?)",bytes(song),bytes(owner),note);
    }
    @Test void completeAllowlistBuildsAcrossBatchesAndExcludesOtherOwnersAndSecrets() throws Exception {
        UUID owner=owner(),other=owner();song(other,UUID.randomUUID(),"other-owner-private");
        UUID linkedSong=UUID.randomUUID(),recording=UUID.randomUUID(),device=UUID.randomUUID();
        song(owner,linkedSong,"linked song");
        for(int i=0;i<100;i++)song(owner,UUID.randomUUID(),"local-note-"+i);
        jdbc.update("INSERT INTO device(id,user_id,display_name,last_seen_at) VALUES(?,?,'fixture',?)",bytes(device),bytes(owner),LocalDateTime.ofInstant(NOW,ZoneOffset.UTC));
        jdbc.update("INSERT INTO recording(id,user_id,origin_device_id,song_id,note,recorded_at,timezone_id,timezone_offset_minutes) VALUES(?,?,?,?,'recording',?,'UTC',0)",bytes(recording),bytes(owner),bytes(device),bytes(linkedSong),LocalDateTime.ofInstant(NOW,ZoneOffset.UTC));
        jdbc.update("INSERT INTO recording_asset(recording_id,user_id,cloud_state,object_key,generation,verified_size,sha256,stored_at) VALUES(?,?,'STORED','synthetic-private-object-key',?,10,?,?)",bytes(recording),bytes(owner),bytes(UUID.randomUUID()),"a".repeat(64),LocalDateTime.ofInstant(NOW,ZoneOffset.UTC));
        jdbc.update("INSERT INTO deletion_batch(id,user_id,op_id,mode,preview_version) VALUES(?,?,?,'RECORDING','synthetic-private-preview')",bytes(UUID.randomUUID()),bytes(owner),bytes(UUID.randomUUID()));
        jdbc.update("INSERT INTO auth_identity(id,user_id,provider,provider_user_id,email) VALUES(?,?,'GOOGLE','synthetic-secret-subject','synthetic-secret-email')",bytes(UUID.randomUUID()),bytes(owner));
        var access=mock(AccountAccess.class);var account=mock(AccountAccess.Account.class);
        when(access.revalidate(account)).thenReturn(new SessionService.Principal(owner,UUID.randomUUID(),UUID.randomUUID()));
        var store=new SnapshotBuildStore(jdbc,access,new DataSourceTransactionManager(source),CLOCK);
        var attempt=store.begin(account,UUID.randomUUID(),1);
        var batches=new ArrayList<Integer>();
        var changed=new java.util.concurrent.atomic.AtomicBoolean();
        var captured=new SnapshotReadView(source,access,CLOCK).capture(account,NOW,
                (cursor,time)->store.capture(account,attempt,cursor,time),
                (connection,id)->new SnapshotSourceRows(CLOCK).extract(connection,id,NOW.plusSeconds(600),batch->{
                    batches.add(batch.size());store.append(account,attempt,batch);
                    if(changed.compareAndSet(false,true)) {
                        var write=new org.springframework.transaction.support.TransactionTemplate(new DataSourceTransactionManager(source));
                        write.executeWithoutResult(tx->{
                            jdbc.update("UPDATE recording SET song_id=NULL,link_revision=2 WHERE id=?",bytes(recording));
                            jdbc.update("UPDATE user_sync_state SET last_change_seq=8 WHERE user_id=?",bytes(owner));
                        });
                    }
                }));
        assertThat(captured.cursor()).isEqualTo(7);
        assertThat(captured.value()).containsEntry(SnapshotPages.Entity.SONG,101L).containsEntry(SnapshotPages.Entity.RECORDING_CONDITION,4L);
        assertThat(captured.value()).hasSize(SnapshotPages.Entity.values().length);
        assertThat(batches).contains(100).allMatch(size->size>=1&&size<=100);
        var published=store.publish(account,attempt,captured.value());
        var page=new SnapshotPages(jdbc,access,new SnapshotPageCursor(new byte[32],CLOCK),CLOCK)
                .read(account,published.id(),SnapshotPages.Entity.SONG,null,100);
        assertThat(page.entries()).hasSize(100);
        String payloads=String.join("\n",jdbc.queryForList("SELECT CAST(payload AS CHAR) FROM snapshot_entry WHERE snapshot_id=?",String.class,bytes(attempt.id())));
        assertThat(payloads).doesNotContain("other-owner-private","synthetic-secret-subject","synthetic-secret-email","synthetic-private-object-key","synthetic-private-preview","object_key","preview_version","normalized_name_key");
        var row=new JsonMapper().readTree(page.entries().getFirst().payload());
        assertThat(row.get("user_id").asText()).isEqualTo(owner.toString());
        assertThat(row.has("tier")).isTrue();assertThat(row.has("song_tier")).isFalse();
        String recorded=jdbc.queryForObject("SELECT CAST(payload AS CHAR) FROM snapshot_entry WHERE snapshot_id=? AND entity='RECORDING'",String.class,bytes(attempt.id()));
        assertThat(new JsonMapper().readTree(recorded).get("song_id").asText()).isEqualTo(linkedSong.toString());
        assertThat(jdbc.queryForObject("SELECT last_change_seq FROM user_sync_state WHERE user_id=?",Long.class,bytes(owner))).isEqualTo(8);
        assertThat(jdbc.queryForObject("SELECT song_id FROM recording WHERE id=?",byte[].class,bytes(recording))).isNull();
    }
    @Test void abortingBatchConsumerNeverPublishesPartialExtraction() throws Exception {
        UUID owner=owner();song(owner,UUID.randomUUID(),"partial");
        var access=mock(AccountAccess.class);var account=mock(AccountAccess.Account.class);
        when(access.revalidate(account)).thenReturn(new SessionService.Principal(owner,UUID.randomUUID(),UUID.randomUUID()));
        var view=new SnapshotReadView(source,access,CLOCK);
        var store=new SnapshotBuildStore(jdbc,access,new DataSourceTransactionManager(source),CLOCK);
        var attempt=store.begin(account,UUID.randomUUID(),1);
        assertThatThrownBy(()->view.capture(account,NOW,(cursor,time)->store.capture(account,attempt,cursor,time),
                (connection,id)->new SnapshotSourceRows(CLOCK)
                .extract(connection,id,NOW.plusSeconds(600),batch->{
                    store.append(account,attempt,batch);throw new IllegalStateException("synthetic sink failure");
                })))
                .isInstanceOf(IllegalStateException.class).hasMessage("synthetic sink failure");
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM snapshot_entry WHERE snapshot_id=?",Integer.class,bytes(attempt.id()))).isGreaterThan(0);
        var pages=new SnapshotPages(jdbc,access,new SnapshotPageCursor(new byte[32],CLOCK),CLOCK);
        assertThatThrownBy(()->pages.read(account,attempt.id(),SnapshotPages.Entity.SONG,null,50))
                .isInstanceOfSatisfying(com.ksh321.songrecord.api.web.ApiException.class,e->assertThat(e.code()).isEqualTo("SNAPSHOT_NOT_READY"));
    }
    static byte[] bytes(UUID id){return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();}
}
