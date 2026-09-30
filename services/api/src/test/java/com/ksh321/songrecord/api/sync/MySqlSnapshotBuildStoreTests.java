package com.ksh321.songrecord.api.sync;

import com.ksh321.songrecord.api.auth.*;
import com.ksh321.songrecord.api.web.ApiException;
import java.nio.ByteBuffer;
import java.nio.file.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.regex.Pattern;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.*;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

@EnabledIfEnvironmentVariable(named="P07_MYSQL_CI",matches="true")
class MySqlSnapshotBuildStoreTests {
    final UUID owner=UUID.randomUUID();
    final Instant now=Instant.parse("2026-09-30T00:00:00Z");
    JdbcTemplate admin,jdbc;
    String database;
    SnapshotBuildStore store;
    AccountAccess access;
    AccountAccess.Account account;
    DriverManagerDataSource source;
    @BeforeEach void setup() throws Exception {
        String port=System.getenv().getOrDefault("P10_MYSQL_PORT","3306");
        if(!port.matches("[0-9]{1,5}"))throw new IllegalArgumentException("Invalid test port");
        String base="jdbc:mysql://127.0.0.1:"+port+"/",options="?allowPublicKeyRetrieval=true&useSSL=false";
        String password=System.getenv("P07_MYSQL_PASSWORD");
        admin=new JdbcTemplate(new DriverManagerDataSource(base+options,"root",password));
        database="p10_build_test_"+UUID.randomUUID().toString().replace("-","");admin.execute("CREATE DATABASE "+database);
        source=new DriverManagerDataSource(base+database+options,"root",password);jdbc=new JdbcTemplate(source);
        jdbc.execute("CREATE TABLE app_user(id BINARY(16) PRIMARY KEY) ENGINE=InnoDB");
        jdbc.update("INSERT INTO app_user VALUES(?)",bytes(owner));
        String migration=Files.readString(Path.of("src/main/resources/db/migration/V7__charts_and_materialized_snapshots.sql"));
        for(String table:List.of("snapshot_capacity","snapshot_header","snapshot_entry")) {
            int start=migration.indexOf("CREATE TABLE "+table+" (");
            jdbc.execute(migration.substring(start,migration.indexOf(';',start)));
        }
        jdbc.update("INSERT INTO snapshot_capacity(id) VALUES(1)");
        var triggers=Pattern.compile("CREATE TRIGGER trg_snapshot_[\\s\\S]*?END\\$\\$").matcher(migration);
        int installed=0;while(triggers.find()){jdbc.execute(triggers.group().replaceFirst("\\$\\$$",""));installed++;}
        assertThat(installed).isEqualTo(8);
        access=mock(AccountAccess.class);account=mock(AccountAccess.Account.class);
        when(access.revalidate(account)).thenReturn(new SessionService.Principal(owner,UUID.randomUUID(),UUID.randomUUID()));
        store=new SnapshotBuildStore(jdbc,access,new DataSourceTransactionManager(source),Clock.fixed(now,ZoneOffset.UTC));
    }
    @AfterEach void cleanup(){if(admin!=null&&database!=null&&database.matches("p10_build_test_[0-9a-f]{32}"))admin.execute("DROP DATABASE "+database);}
    void code(String value,Runnable action){assertThatThrownBy(action::run).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo(value));}
    SnapshotBuildStore.Entry entry(long ordinal){return new SnapshotBuildStore.Entry(SnapshotPages.Entity.SONG,ordinal,UUID.randomUUID(),"{\"note\":\"한글\",\"revision\":1}");}
    long total(){return jdbc.queryForObject("SELECT reserved_bytes FROM snapshot_capacity WHERE id=1",Long.class);}
    @Test void beginIsIdempotentAndTwoSlotsDoNotReplaceExistingSnapshots(){
        UUID op=UUID.randomUUID();var first=store.begin(account,op,1);
        assertThat(store.begin(account,op,1)).isEqualTo(first);
        var second=store.begin(account,UUID.randomUUID(),1);assertThat(second.id()).isNotEqualTo(first.id());
        code("SNAPSHOT_CAPACITY_EXCEEDED",()->store.begin(account,UUID.randomUUID(),1));
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM snapshot_header",Integer.class)).isEqualTo(2);
        assertThat(total()).isZero();
    }
    @Test void appendReservesExactMysqlJsonBytesAndPreservesCapture(){
        var attempt=store.begin(account,UUID.randomUUID(),1);
        code("SNAPSHOT_CAPTURE_REQUIRED",()->store.append(account,attempt,List.of(entry(1))));
        store.capture(account,attempt,7,now);
        store.append(account,attempt,List.of(entry(1),entry(2)));
        Long size=jdbc.queryForObject("SELECT SUM(payload_bytes) FROM snapshot_entry",Long.class);
        assertThat(total()).isEqualTo(size);
        assertThat(jdbc.queryForObject("SELECT byte_count FROM snapshot_header",Long.class)).isEqualTo(size);
        assertThat(jdbc.queryForObject("SELECT row_count FROM snapshot_header",Long.class)).isEqualTo(2);
        code("SNAPSHOT_CAPTURE_ALREADY_SET",()->store.capture(account,attempt,8,now));
        assertThat(jdbc.queryForObject("SELECT snapshot_cursor FROM snapshot_header",Long.class)).isEqualTo(7);
    }
    @Test void failedBatchRollsBackReservationAndEveryInsertedRow(){
        var attempt=store.begin(account,UUID.randomUUID(),1);store.capture(account,attempt,7,now);
        assertThatThrownBy(()->store.append(account,attempt,List.of(entry(1),entry(1)))).isInstanceOf(org.springframework.dao.DataAccessException.class);
        assertThat(total()).isZero();
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM snapshot_entry",Integer.class)).isZero();
        assertThat(jdbc.queryForObject("SELECT row_count FROM snapshot_header",Long.class)).isZero();
    }
    @Test void staleAttemptExpiredLeaseAndOtherAccountCannotAppend(){
        var attempt=store.begin(account,UUID.randomUUID(),1);store.capture(account,attempt,7,now);
        var stale=new SnapshotBuildStore.Attempt(attempt.id(),UUID.randomUUID(),attempt.startedAt(),"BUILDING");
        code("SNAPSHOT_ATTEMPT_STALE",()->store.append(account,stale,List.of(entry(1))));
        var expired=new SnapshotBuildStore(jdbc,access,new DataSourceTransactionManager(source),Clock.fixed(now.plusSeconds(600),ZoneOffset.UTC));
        code("SNAPSHOT_ATTEMPT_STALE",()->expired.append(account,attempt,List.of(entry(1))));
        when(access.revalidate(account)).thenReturn(new SessionService.Principal(UUID.randomUUID(),UUID.randomUUID(),UUID.randomUUID()));
        code("SNAPSHOT_NOT_FOUND",()->store.append(account,attempt,List.of(entry(1))));
        assertThat(total()).isZero();
    }
    Map<SnapshotPages.Entity,Long> counts(long songs){
        var result=new EnumMap<SnapshotPages.Entity,Long>(SnapshotPages.Entity.class);
        for(var entity:SnapshotPages.Entity.values())result.put(entity,entity==SnapshotPages.Entity.SONG?songs:0L);
        return result;
    }
    @Test void completeManifestPublishesOnceWithFixedExpiryAndPagesStoredRows(){
        var op=UUID.randomUUID();var attempt=store.begin(account,op,1);store.capture(account,attempt,7,now);
        store.append(account,attempt,List.of(entry(1),entry(2)));
        var published=store.publish(account,attempt,counts(2));
        assertThat(published.cursor()).isEqualTo(7);assertThat(published.expiresAt()).isEqualTo(now.plusSeconds(1800));
        assertThat(published.manifestHash()).matches("[0-9a-f]{64}");
        assertThat(store.begin(account,op,1).status()).isEqualTo("READY");
        code("SNAPSHOT_ATTEMPT_STALE",()->store.append(account,attempt,List.of(entry(3))));
        var clock=Clock.fixed(now,ZoneOffset.UTC);
        var pages=new SnapshotPages(jdbc,access,new SnapshotPageCursor(new byte[32],clock),clock);
        var page=pages.read(account,published.id(),SnapshotPages.Entity.SONG,null,1);
        assertThat(page.entries()).hasSize(1);assertThat(page.nextCursor()).isNotNull();
        var next=pages.read(account,published.id(),SnapshotPages.Entity.SONG,page.nextCursor(),1);
        assertThat(next.entries().getFirst().ordinal()).isEqualTo(2);assertThat(next.nextCursor()).isNull();
        assertThat(next.expiresAt()).isEqualTo(published.expiresAt());
    }
    @Test void incompleteManifestAndOrdinalGapsStayUnpublished(){
        var attempt=store.begin(account,UUID.randomUUID(),1);store.capture(account,attempt,7,now);
        store.append(account,attempt,List.of(entry(2)));
        code("SNAPSHOT_INCOMPLETE",()->store.publish(account,attempt,counts(1)));
        assertThat(jdbc.queryForObject("SELECT status FROM snapshot_header",String.class)).isEqualTo("BUILDING");
        assertThatThrownBy(()->store.publish(account,attempt,Map.of(SnapshotPages.Entity.SONG,1L))).isInstanceOf(IllegalArgumentException.class);
        store.append(account,attempt,List.of(entry(1)));
        code("SNAPSHOT_INCOMPLETE",()->store.publish(account,attempt,counts(1)));
        assertThat(store.publish(account,attempt,counts(2)).manifestHash()).hasSize(64);
    }
    @Test void capacityFailureNeverPartiallyIncreasesReservation(){
        var attempt=store.begin(account,UUID.randomUUID(),1);store.capture(account,attempt,7,now);
        jdbc.update("UPDATE snapshot_header SET reserved_bytes=?",SnapshotBuildStore.MAX_BYTES);
        code("SNAPSHOT_CAPACITY_EXCEEDED",()->store.append(account,attempt,List.of(entry(1))));
        assertThat(total()).isEqualTo(SnapshotBuildStore.MAX_BYTES);
        jdbc.update("UPDATE snapshot_header SET reserved_bytes=0");
        jdbc.update("UPDATE snapshot_capacity SET reserved_bytes=?",SnapshotBuildStore.GLOBAL_BYTES);
        code("SNAPSHOT_CAPACITY_EXCEEDED",()->store.append(account,attempt,List.of(entry(1))));
        assertThat(total()).isEqualTo(SnapshotBuildStore.GLOBAL_BYTES);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM snapshot_entry",Integer.class)).isZero();
    }
    @Test void competingSameOperationCreatesOnlyOneAttempt() throws Exception {
        UUID op=UUID.randomUUID();var start=new CountDownLatch(1);
        try(var pool=Executors.newFixedThreadPool(2)){
            var first=pool.submit(()->{start.await();return store.begin(account,op,1);});
            var second=pool.submit(()->{start.await();return store.begin(account,op,1);});
            start.countDown();assertThat(first.get(10,TimeUnit.SECONDS)).isEqualTo(second.get(10,TimeUnit.SECONDS));
        }
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM snapshot_header",Integer.class)).isEqualTo(1);
    }
    @Test void revocationBeforePublishKeepsPartialRowsPrivate(){
        var attempt=store.begin(account,UUID.randomUUID(),1);store.capture(account,attempt,7,now);
        store.append(account,attempt,List.of(entry(1)));
        var principal=new SessionService.Principal(owner,UUID.randomUUID(),UUID.randomUUID());
        when(access.revalidate(account)).thenReturn(principal).thenThrow(new IllegalStateException("revoked"));
        assertThatThrownBy(()->store.publish(account,attempt,counts(1))).isInstanceOf(IllegalStateException.class).hasMessage("revoked");
        assertThat(jdbc.queryForObject("SELECT status FROM snapshot_header",String.class)).isEqualTo("BUILDING");
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM snapshot_entry",Integer.class)).isEqualTo(1);
    }
    static byte[] bytes(UUID id){return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();}
}
