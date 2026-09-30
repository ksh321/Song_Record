package com.ksh321.songrecord.api.sync;

import com.ksh321.songrecord.api.auth.*;
import com.ksh321.songrecord.api.jobs.JobQueue;
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
    @BeforeEach void isolateQueuedFixtureJobs() {
        // Claim is intentionally global; a previous test's unconsumed job must
        // not be selected instead of this test's new account fixture.
        jdbc.update("UPDATE job SET state='CANCELLED',lease_token=NULL,claimed_at=NULL,lease_until=NULL,finished_at=? WHERE type='SNAPSHOT_BUILD' AND state IN ('QUEUED','RUNNING','RETRY_WAIT')",
                LocalDateTime.ofInstant(NOW,ZoneOffset.UTC));
    }
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
    @Test void durableJobAuthorityRejectsForgeryRevocationAndDifferentSnapshot() throws Exception {
        UUID owner=owner();var access=mock(AccountAccess.class);var account=mock(AccountAccess.Account.class);
        when(access.revalidate(account)).thenReturn(new SessionService.Principal(owner,UUID.randomUUID(),UUID.randomUUID()));
        var manager=new DataSourceTransactionManager(source);var tx=new org.springframework.transaction.support.TransactionTemplate(manager);
        var store=new SnapshotBuildStore(jdbc,access,manager,CLOCK);var attempt=store.begin(account,UUID.randomUUID(),1);
        var queue=new JobQueue(jdbc,access,manager,CLOCK,Duration.ofMinutes(10),5);
        tx.executeWithoutResult(s->queue.enqueue(account,JobQueue.Type.SNAPSHOT_BUILD,attempt.id(),UUID.randomUUID(),"{}"));
        var lease=queue.claim(JobQueue.Type.SNAPSHOT_BUILD).orElseThrow();
        var authority=SnapshotAuthority.job(jdbc,lease,CLOCK);
        assertThat(authority.requireActive()).isEqualTo(owner);
        assertThat(authority.toString()).isEqualTo("SnapshotAuthority[REDACTED]");
        assertThatThrownBy(()->authority.requireSnapshot(UUID.randomUUID())).isInstanceOf(IllegalStateException.class);
        var forged=new JobQueue.Lease(lease.id(),UUID.randomUUID(),owner,lease.type(),attempt.id(),"{}",lease.attempt());
        assertThatThrownBy(()->SnapshotAuthority.job(jdbc,forged,CLOCK).requireActive()).isInstanceOf(IllegalStateException.class);
        var expired=SnapshotAuthority.job(jdbc,lease,Clock.fixed(NOW.plusSeconds(600),ZoneOffset.UTC));
        assertThatThrownBy(expired::requireActive).isInstanceOf(IllegalStateException.class);
        store.capture(authority,attempt,7,NOW);
        store.append(authority,attempt,List.of(new SnapshotBuildStore.Entry(SnapshotPages.Entity.SONG,1,UUID.randomUUID(),"{\"id\":\"fixture\"}")));
        jdbc.update("UPDATE app_user SET status='DELETING' WHERE id=?",bytes(owner));
        assertThatThrownBy(authority::requireActive).isInstanceOf(IllegalStateException.class);
    }
    @Test void jobFenceLocksCurrentLeaseThroughSnapshotTransaction() throws Exception {
        UUID owner=owner();var access=mock(AccountAccess.class);var account=mock(AccountAccess.Account.class);
        when(access.revalidate(account)).thenReturn(new SessionService.Principal(owner,UUID.randomUUID(),UUID.randomUUID()));
        var manager=new DataSourceTransactionManager(source);var tx=new org.springframework.transaction.support.TransactionTemplate(manager);
        var store=new SnapshotBuildStore(jdbc,access,manager,CLOCK);var attempt=store.begin(account,UUID.randomUUID(),1);
        var queue=new JobQueue(jdbc,access,manager,CLOCK,Duration.ofMinutes(10),5);
        tx.executeWithoutResult(s->queue.enqueue(account,JobQueue.Type.SNAPSHOT_BUILD,attempt.id(),UUID.randomUUID(),"{}"));
        var lease=queue.claim(JobQueue.Type.SNAPSHOT_BUILD).orElseThrow();
        var authority=SnapshotAuthority.job(jdbc,lease,CLOCK);
        assertThatThrownBy(authority::fence).isInstanceOf(IllegalStateException.class);
        tx.executeWithoutResult(s->{
            authority.fence();
            assertThat(canLockJob(lease.id())).isFalse();
        });
        assertThat(canLockJob(lease.id())).isTrue();
        jdbc.update("UPDATE job SET lease_token=? WHERE id=?",bytes(UUID.randomUUID()),bytes(lease.id()));
        assertThatThrownBy(()->tx.executeWithoutResult(s->authority.fence())).isInstanceOf(IllegalStateException.class);
    }
    boolean canLockJob(UUID job) {
        try(var connection=source.getConnection();var query=connection.prepareStatement("SELECT id FROM job WHERE id=? FOR UPDATE SKIP LOCKED")) {
            query.setBytes(1,bytes(job));try(var result=query.executeQuery()){return result.next();}
        }catch(java.sql.SQLException e){throw new IllegalStateException(e);}
    }
    @Test void lostFinalWorkerFenceRollsBackRowsAndByteReservation(){
        UUID owner=owner();var access=mock(AccountAccess.class);var account=mock(AccountAccess.Account.class);
        when(access.revalidate(account)).thenReturn(new SessionService.Principal(owner,UUID.randomUUID(),UUID.randomUUID()));
        var store=new SnapshotBuildStore(jdbc,access,new DataSourceTransactionManager(source),CLOCK);
        var attempt=store.begin(account,UUID.randomUUID(),1);store.capture(account,attempt,7,NOW);
        var authority=mock(SnapshotAuthority.class);when(authority.requireActive()).thenReturn(owner);
        doThrow(new IllegalStateException("lost final fence")).when(authority).fence();
        long before=jdbc.queryForObject("SELECT reserved_bytes FROM snapshot_capacity WHERE id=1",Long.class);
        assertThatThrownBy(()->store.append(authority,attempt,List.of(new SnapshotBuildStore.Entry(SnapshotPages.Entity.SONG,1,UUID.randomUUID(),"{}"))))
                .isInstanceOf(IllegalStateException.class).hasMessage("lost final fence");
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM snapshot_entry WHERE snapshot_id=?",Integer.class,bytes(attempt.id()))).isZero();
        assertThat(jdbc.queryForObject("SELECT reserved_bytes FROM snapshot_capacity WHERE id=1",Long.class)).isEqualTo(before);
    }
    @Test void receiptSnapshotAndJobCommitTogetherAndReplayWithoutAnotherBuild(){
        UUID owner=owner();var access=mock(AccountAccess.class);var account=mock(AccountAccess.Account.class);
        when(access.authenticate("fixture-auth","fixture-device")).thenReturn(account);
        when(access.revalidate(account)).thenReturn(new SessionService.Principal(owner,UUID.randomUUID(),UUID.randomUUID()));
        var manager=new DataSourceTransactionManager(source);var store=new SnapshotBuildStore(jdbc,access,manager,CLOCK);
        var queue=new JobQueue(jdbc,access,manager,CLOCK,Duration.ofMinutes(10),5);
        var receipts=new com.ksh321.songrecord.api.idempotency.IdempotentMutations(jdbc,access,manager,CLOCK);
        var requests=new SnapshotRequests(access,receipts,store,queue);String op=UUID.randomUUID().toString();
        var first=requests.create("fixture-auth","fixture-device",op,"{\"schema_version\":1}");
        var replay=requests.create("fixture-auth","fixture-device",op,"{ \"schema_version\" : 1 }");
        assertThat(first.status()).isEqualTo(202);assertThat(replay).isEqualTo(first);
        for(String table:List.of("mutation_receipt","snapshot_header","job"))
            assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM "+table+" WHERE user_id=?",Integer.class,bytes(owner))).isEqualTo(1);
        assertThat(jdbc.queryForObject("SELECT CAST(payload AS CHAR) FROM job WHERE user_id=?",String.class,bytes(owner))).isEqualTo("{}");
        assertThatThrownBy(()->requests.create("fixture-auth","fixture-device",UUID.randomUUID().toString(),"{\"schema_version\":18446744073709551617}"))
                .isInstanceOf(com.ksh321.songrecord.api.web.ApiException.class);
        assertThatThrownBy(()->store.beginJoined(account,UUID.randomUUID(),1)).isInstanceOf(IllegalStateException.class);
    }
    @Test void enqueueFailureRollsBackReceiptAndSnapshotReservation(){
        UUID owner=owner();var access=mock(AccountAccess.class);var account=mock(AccountAccess.Account.class);
        when(access.authenticate("fixture-auth","fixture-device")).thenReturn(account);
        when(access.revalidate(account)).thenReturn(new SessionService.Principal(owner,UUID.randomUUID(),UUID.randomUUID()));
        var manager=new DataSourceTransactionManager(source);var store=new SnapshotBuildStore(jdbc,access,manager,CLOCK);
        var queue=mock(JobQueue.class);
        when(queue.enqueue(any(),any(),any(),any(),any())).thenThrow(new IllegalStateException("synthetic enqueue failure"));
        var receipts=new com.ksh321.songrecord.api.idempotency.IdempotentMutations(jdbc,access,manager,CLOCK);
        var requests=new SnapshotRequests(access,receipts,store,queue);
        assertThatThrownBy(()->requests.create("fixture-auth","fixture-device",UUID.randomUUID().toString(),"{\"schema_version\":1}"))
                .isInstanceOf(IllegalStateException.class).hasMessage("synthetic enqueue failure");
        for(String table:List.of("mutation_receipt","snapshot_header","job"))
            assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM "+table+" WHERE user_id=?",Integer.class,bytes(owner))).isZero();
    }
    @Test void durableWorkerBuildsAndReclaimedJobDoesNotRenewReadySnapshot(){
        UUID owner=owner();song(owner,UUID.randomUUID(),"worker song");
        var access=mock(AccountAccess.class);var account=mock(AccountAccess.Account.class);
        when(access.authenticate("fixture-auth","fixture-device")).thenReturn(account);
        when(access.revalidate(account)).thenReturn(new SessionService.Principal(owner,UUID.randomUUID(),UUID.randomUUID()));
        var manager=new DataSourceTransactionManager(source);var store=new SnapshotBuildStore(jdbc,access,manager,CLOCK);
        var jobs=new JobQueue(jdbc,access,manager,CLOCK,Duration.ofMinutes(10),5);
        var receipts=new com.ksh321.songrecord.api.idempotency.IdempotentMutations(jdbc,access,manager,CLOCK);
        var requests=new SnapshotRequests(access,receipts,store,jobs);
        var accepted=requests.create("fixture-auth","fixture-device",UUID.randomUUID().toString(),"{\"schema_version\":1}");
        var id=UUID.fromString(new JsonMapper().readTree(accepted.body()).get("snapshot_token").asText());
        var worker=new SnapshotWorker(jdbc,jobs,store,new SnapshotReadView(source,access,CLOCK),new SnapshotSourceRows(CLOCK),CLOCK);
        assertThat(worker.runOnce()).isTrue();assertThat(worker.runOnce()).isFalse();
        assertThat(jdbc.queryForObject("SELECT status FROM snapshot_header WHERE id=?",String.class,bytes(id))).isEqualTo("READY");
        assertThat(jdbc.queryForObject("SELECT state FROM job WHERE user_id=?",String.class,bytes(owner))).isEqualTo("SUCCEEDED");
        var expiry=jdbc.queryForObject("SELECT expires_at FROM snapshot_header WHERE id=?",java.sql.Timestamp.class,bytes(id));
        // Simulate a lost completion acknowledgement with the READY snapshot intact.
        jdbc.update("UPDATE job SET state='RETRY_WAIT',finished_at=NULL WHERE user_id=?",bytes(owner));
        assertThat(worker.runOnce()).isTrue();
        assertThat(jdbc.queryForObject("SELECT expires_at FROM snapshot_header WHERE id=?",java.sql.Timestamp.class,bytes(id))).isEqualTo(expiry);
        assertThat(jdbc.queryForObject("SELECT attempt_count FROM snapshot_header WHERE id=?",Integer.class,bytes(id))).isEqualTo(1);
    }
    @Test void reclaimedJobDiscardsPartialAttemptBeforeAnotherReadView(){
        UUID owner=owner();song(owner,UUID.randomUUID(),"real source");
        var access=mock(AccountAccess.class);var account=mock(AccountAccess.Account.class);
        when(access.revalidate(account)).thenReturn(new SessionService.Principal(owner,UUID.randomUUID(),UUID.randomUUID()));
        var manager=new DataSourceTransactionManager(source);var tx=new org.springframework.transaction.support.TransactionTemplate(manager);
        var store=new SnapshotBuildStore(jdbc,access,manager,CLOCK);var old=store.begin(account,UUID.randomUUID(),1);
        store.capture(account,old,7,NOW);store.append(account,old,List.of(new SnapshotBuildStore.Entry(SnapshotPages.Entity.SONG,1,UUID.randomUUID(),"{\"note\":\"discard partial\"}")));
        var jobs=new JobQueue(jdbc,access,manager,CLOCK,Duration.ofMinutes(10),5);
        tx.executeWithoutResult(s->jobs.enqueue(account,JobQueue.Type.SNAPSHOT_BUILD,old.id(),UUID.randomUUID(),"{}"));
        var worker=new SnapshotWorker(jdbc,jobs,store,new SnapshotReadView(source,access,CLOCK),new SnapshotSourceRows(CLOCK),CLOCK);
        assertThat(worker.runOnce()).isTrue();
        assertThat(jdbc.queryForObject("SELECT status FROM snapshot_header WHERE id=?",String.class,bytes(old.id()))).isEqualTo("READY");
        assertThat(jdbc.queryForObject("SELECT attempt_count FROM snapshot_header WHERE id=?",Integer.class,bytes(old.id()))).isEqualTo(2);
        assertThat(jdbc.queryForList("SELECT CAST(payload AS CHAR) FROM snapshot_entry WHERE snapshot_id=? AND entity='SONG'",String.class,bytes(old.id())))
                .singleElement().asString().contains("real source").doesNotContain("discard partial");
    }
    @Test void queriesAndExpiryCleanupPreserveSourcesReceiptsAndReplay() {
        UUID owner=owner();song(owner,UUID.randomUUID(),"retained source");
        var access=mock(AccountAccess.class);var account=mock(AccountAccess.Account.class);
        when(access.authenticate("fixture-auth","fixture-device")).thenReturn(account);
        when(access.revalidate(account)).thenReturn(new SessionService.Principal(owner,UUID.randomUUID(),UUID.randomUUID()));
        var manager=new DataSourceTransactionManager(source);var store=new SnapshotBuildStore(jdbc,access,manager,CLOCK);
        var jobs=new JobQueue(jdbc,access,manager,CLOCK,Duration.ofMinutes(10),5);
        var receipts=new com.ksh321.songrecord.api.idempotency.IdempotentMutations(jdbc,access,manager,CLOCK);
        var requests=new SnapshotRequests(access,receipts,store,jobs);String op=UUID.randomUUID().toString();
        var accepted=requests.create("fixture-auth","fixture-device",op,"{\"schema_version\":1}");
        String token=new JsonMapper().readTree(accepted.body()).get("snapshot_token").asText();
        var queries=new SnapshotQueries(jdbc,access,new SnapshotPages(jdbc,access,new SnapshotPageCursor(new byte[32],CLOCK),CLOCK),CLOCK);
        var empty=new org.springframework.util.LinkedMultiValueMap<String,String>();
        assertThat(queries.get("fixture-auth","fixture-device",token,empty).status()).isEqualTo(202);
        var page=new org.springframework.util.LinkedMultiValueMap<String,String>();page.add("entity","SONG");
        assertThatThrownBy(()->queries.get("fixture-auth","fixture-device",token,page))
                .isInstanceOfSatisfying(com.ksh321.songrecord.api.web.ApiException.class,e->assertThat(e.code()).isEqualTo("SNAPSHOT_NOT_READY"));
        assertThat(new SnapshotWorker(jdbc,jobs,store,new SnapshotReadView(source,access,CLOCK),new SnapshotSourceRows(CLOCK),CLOCK).runOnce()).isTrue();
        var ready=queries.get("fixture-auth","fixture-device",token,empty);
        assertThat(ready.status()).isEqualTo(200);assertThat(ready.body()).containsEntry("snapshot_cursor",7L).containsEntry("expires_at",NOW.plusSeconds(1800).toString());
        assertThat((Map<?,?>)ready.body().get("entity_counts")).hasSize(19);
        var result=queries.get("fixture-auth","fixture-device",token,page);
        assertThat((List<?>)result.body().get("entries")).hasSize(1);assertThat(result.body().get("next_cursor")).isNull();
        page.add("entity","TAG");
        assertThatThrownBy(()->queries.get("fixture-auth","fixture-device",token,page)).isInstanceOf(com.ksh321.songrecord.api.web.ApiException.class);
        var expired=Clock.fixed(NOW.plusSeconds(1800),ZoneOffset.UTC);
        var after=new SnapshotQueries(jdbc,access,new SnapshotPages(jdbc,access,new SnapshotPageCursor(new byte[32],expired),expired),expired);
        assertThatThrownBy(()->after.get("fixture-auth","fixture-device",token,empty))
                .isInstanceOfSatisfying(com.ksh321.songrecord.api.web.ApiException.class,e->assertThat(e.code()).isEqualTo("SNAPSHOT_EXPIRED"));
        new SnapshotCleanup(jdbc,manager,expired).runOnce();
        for(String table:List.of("song","mutation_receipt"))
            assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM "+table+" WHERE user_id=?",Integer.class,bytes(owner))).isEqualTo(1);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM snapshot_header WHERE id=?",Integer.class,bytes(UUID.fromString(token)))).isZero();
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM snapshot_entry WHERE snapshot_id=?",Integer.class,bytes(UUID.fromString(token)))).isZero();
        assertThat(jdbc.queryForObject("SELECT reserved_bytes FROM snapshot_capacity WHERE id=1",Long.class))
                .isEqualTo(jdbc.queryForObject("SELECT COALESCE(SUM(reserved_bytes),0) FROM snapshot_header",Long.class));
        assertThat(requests.create("fixture-auth","fixture-device",op,"{\"schema_version\":1}")).isEqualTo(accepted);
        assertThatThrownBy(()->after.get("fixture-auth","fixture-device",token,empty))
                .isInstanceOfSatisfying(com.ksh321.songrecord.api.web.ApiException.class,e->assertThat(e.code()).isEqualTo("SNAPSHOT_EXPIRED"));
        when(access.revalidate(account)).thenReturn(new SessionService.Principal(owner(),UUID.randomUUID(),UUID.randomUUID()));
        assertThatThrownBy(()->after.get("fixture-auth","fixture-device",token,empty))
                .isInstanceOfSatisfying(com.ksh321.songrecord.api.web.ApiException.class,e->assertThat(e.code()).isEqualTo("SNAPSHOT_NOT_FOUND"));
    }
    @Test void cleanupRetainsDurableRetriesButRemovesOrphansAndDeletingAccounts() {
        UUID owner=owner();var access=mock(AccountAccess.class);var account=mock(AccountAccess.Account.class);
        when(access.revalidate(account)).thenReturn(new SessionService.Principal(owner,UUID.randomUUID(),UUID.randomUUID()));
        var manager=new DataSourceTransactionManager(source);var store=new SnapshotBuildStore(jdbc,access,manager,CLOCK);
        var pending=store.begin(account,UUID.randomUUID(),1);var orphan=store.begin(account,UUID.randomUUID(),1);
        var jobs=new JobQueue(jdbc,access,manager,CLOCK,Duration.ofMinutes(10),5);
        var tx=new org.springframework.transaction.support.TransactionTemplate(manager);
        tx.executeWithoutResult(s->jobs.enqueue(account,JobQueue.Type.SNAPSHOT_BUILD,pending.id(),UUID.randomUUID(),"{}"));
        var janitor=new SnapshotCleanup(jdbc,manager,Clock.fixed(NOW.plusSeconds(600),ZoneOffset.UTC));
        janitor.runOnce();
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM snapshot_header WHERE id=?",Integer.class,bytes(orphan.id()))).isZero();
        assertThat(jdbc.queryForObject("SELECT status FROM snapshot_header WHERE id=?",String.class,bytes(pending.id()))).isEqualTo("BUILDING");
        jdbc.update("UPDATE app_user SET status='DELETING' WHERE id=?",bytes(owner));janitor.runOnce();
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM snapshot_header WHERE id=?",Integer.class,bytes(pending.id()))).isZero();
        assertThat(jdbc.queryForObject("SELECT state FROM job WHERE user_id=?",String.class,bytes(owner))).isEqualTo("CANCELLED");
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM app_user WHERE id=?",Integer.class,bytes(owner))).isEqualTo(1);
    }
    @Test void sharedMobileFixtureRetainsExactCanonicalNumbersAndManifestBytes() throws Exception {
        var fixture=new JsonMapper().readTree(java.nio.file.Files.readString(java.nio.file.Path.of("../../fixtures/contracts/snapshot-wire.json")));
        UUID owner=UUID.fromString(fixture.get("owner").asText());jdbc.update("INSERT INTO app_user(id) VALUES(?)",bytes(owner));
        var access=mock(AccountAccess.class);var account=mock(AccountAccess.Account.class);
        when(access.authenticate("fixture-auth","fixture-device")).thenReturn(account);
        when(access.revalidate(account)).thenReturn(new SessionService.Principal(owner,UUID.randomUUID(),UUID.randomUUID()));
        var store=new SnapshotBuildStore(jdbc,access,new DataSourceTransactionManager(source),CLOCK);
        var attempt=store.begin(account,UUID.randomUUID(),1);store.capture(account,attempt,7,NOW);
        var counts=new EnumMap<SnapshotPages.Entity,Long>(SnapshotPages.Entity.class);
        for(var page:fixture.get("pages")) {
            var entity=SnapshotPages.Entity.valueOf(page.get("entity").asText());counts.put(entity,(long)page.get("entries").size());
            for(var entry:page.get("entries")) {
                String canonical=entry.get("canonical_payload").asText();
                assertThat(com.ksh321.songrecord.api.idempotency.CanonicalRequest.canonical(entry.get("payload").toString())).isEqualTo(canonical);
                store.append(account,attempt,List.of(new SnapshotBuildStore.Entry(entity,entry.get("ordinal").asLong(),UUID.fromString(entry.get("resource_id").asText()),canonical)));
            }
        }
        assertThat(store.publish(account,attempt,counts).manifestHash()).isEqualTo(fixture.get("manifest").get("manifest_hash").asText());
        var queries=new SnapshotQueries(jdbc,access,new SnapshotPages(jdbc,access,new SnapshotPageCursor(new byte[32],CLOCK),CLOCK),CLOCK);
        var params=new org.springframework.util.LinkedMultiValueMap<String,String>();params.add("entity","SONG");
        var reply=queries.get("fixture-auth","fixture-device",attempt.id().toString(),params);
        String serialized=new JsonMapper().writeValueAsString(reply.body());
        assertThat(new JsonMapper().readTree(serialized).get("entries").get(0).get("canonical_payload").asText())
                .contains("1E+2","한글 🎵");
    }
    static byte[] bytes(UUID id){return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();}
}
