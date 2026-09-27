package com.ksh321.songrecord.api.idempotency;

import com.ksh321.songrecord.api.auth.*;
import com.ksh321.songrecord.api.web.ApiException;
import java.nio.ByteBuffer;
import java.nio.file.*;
import java.time.Clock;
import java.util.UUID;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.*;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

/** CI-only, real InnoDB and V6 receipt DDL. Authentication itself is covered by IdempotencyTests. */
@EnabledIfEnvironmentVariable(named="P07_MYSQL_CI", matches="true")
class MySqlIdempotencyTests {
    JdbcTemplate admin,jdbc;String database;
    IdempotentMutations service;AccountAccess.Account account;AccountAccess access;
    AtomicInteger calls=new AtomicInteger();String key=UUID.randomUUID().toString();
    @BeforeEach void setup() throws Exception {
        String password=System.getenv("P07_MYSQL_PASSWORD");
        admin=new JdbcTemplate(new DriverManagerDataSource("jdbc:mysql://127.0.0.1:3306/?allowPublicKeyRetrieval=true&useSSL=false","root",password));
        database="p07_test_"+UUID.randomUUID().toString().replace("-","");
        admin.execute("CREATE DATABASE "+database);
        jdbc=new JdbcTemplate(new DriverManagerDataSource("jdbc:mysql://127.0.0.1:3306/"+database+"?allowPublicKeyRetrieval=true&useSSL=false","root",password));
        jdbc.execute("CREATE TABLE app_user(id BINARY(16) PRIMARY KEY) ENGINE=InnoDB");
        String migration=Files.readString(Path.of("src/main/resources/db/migration/V6__sync_and_deletion_jobs.sql"));
        int start=migration.indexOf("CREATE TABLE mutation_receipt (");
        jdbc.execute(migration.substring(start,migration.indexOf(';',start)));
        installTrigger("trg_receipt_before_update");
        jdbc.execute("CREATE TABLE mutation_effect(id INT PRIMARY KEY,value_count INT NOT NULL) ENGINE=InnoDB");
        jdbc.update("INSERT INTO mutation_effect VALUES(1,0)");
        var user=UUID.randomUUID();jdbc.update("INSERT INTO app_user VALUES(?)",ByteBuffer.allocate(16).putLong(user.getMostSignificantBits()).putLong(user.getLeastSignificantBits()).array());
        access=mock(AccountAccess.class);account=mock(AccountAccess.Account.class);
        when(access.revalidate(account)).thenReturn(new SessionService.Principal(user,UUID.randomUUID(),UUID.randomUUID()));
        service=new IdempotentMutations(jdbc,access,new DataSourceTransactionManager(jdbc.getDataSource()),Clock.systemUTC());
    }
    @AfterEach void cleanup() {if(admin!=null && database!=null)admin.execute("DROP DATABASE "+database);}
    IdempotentMutations.Reply effect() {
        calls.incrementAndGet();jdbc.update("UPDATE mutation_effect SET value_count=value_count+1 WHERE id=1");
        return new IdempotentMutations.Reply(201,"{\"n\":1.0,\"nested\":{\"z\":2,\"a\":1}}");
    }
    IdempotentMutations.Reply run(String body) {return service.execute(account,key,"POST","/v1/songs",body,this::effect);}
    @Test void concurrentReplayUsesInnoDbUniqueKeyAndJsonRoundTrip() throws Exception {
        try(var pool=Executors.newFixedThreadPool(2)) {
            var start=new CountDownLatch(1);
            Callable<IdempotentMutations.Reply> request=()->{start.await();return run("{}");};
            var a=pool.submit(request);var b=pool.submit(request);start.countDown();
            assertThat(a.get(20,TimeUnit.SECONDS)).isEqualTo(b.get(20,TimeUnit.SECONDS));
            assertThat(calls.get()).isEqualTo(1);
            assertThat(jdbc.queryForObject("SELECT value_count FROM mutation_effect",Integer.class)).isEqualTo(1);
            assertThatThrownBy(()->run("{\"changed\":true}")).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("IDEMPOTENCY_CONFLICT"));
        }
    }
    @Test void rollbackLeavesNoReceiptAndRetrySucceeds() {
        assertThatThrownBy(()->service.execute(account,key,"POST","/v1/songs","{}",()->{effect();throw new IllegalStateException();})).isInstanceOf(IllegalStateException.class);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Integer.class)).isZero();
        assertThat(jdbc.queryForObject("SELECT value_count FROM mutation_effect",Integer.class)).isZero();
        run("{}");assertThat(jdbc.queryForObject("SELECT value_count FROM mutation_effect",Integer.class)).isEqualTo(1);
    }

    @Test void concurrentRevisionEditsOnRealPlaylistReturnOneConflictAndReplayWinner() throws Exception {
        String migration=Files.readString(Path.of("src/main/resources/db/migration/V4__playlists_and_classifications.sql"));
        int start=migration.indexOf("CREATE TABLE playlist (");
        jdbc.execute(migration.substring(start,migration.indexOf(';',start)));
        var id=UUID.randomUUID();var owner=access.revalidate(account).userId();
        byte[] idBytes=ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();
        byte[] ownerBytes=ByteBuffer.allocate(16).putLong(owner.getMostSignificantBits()).putLong(owner.getLeastSignificantBits()).array();
        jdbc.update("INSERT INTO playlist(id,user_id,name) VALUES(?,?,'before')",idBytes,ownerBytes);
        var revisions=new com.ksh321.songrecord.api.revision.RevisionChanges(jdbc,access,new DataSourceTransactionManager(jdbc.getDataSource()),Clock.systemUTC());
        var json=new tools.jackson.databind.json.JsonMapper();
        java.util.function.BiFunction<String,String,IdempotentMutations.Reply> rename=(op,name)->
            service.execute(account,op,"PATCH","/v1/playlists/"+id,json.writeValueAsString(java.util.Map.of("name",name,"base_revision",1)),()->
                new IdempotentMutations.Reply(200,json.writeValueAsString(revisions.change(account,
                    com.ksh321.songrecord.api.revision.RevisionChanges.Resource.PLAYLIST,id.toString(),1L,current->{
                        calls.incrementAndGet();jdbc.update("UPDATE playlist SET name=? WHERE user_id=? AND id=?",name,ownerBytes,idBytes);
                    }))));
        String opA=UUID.randomUUID().toString(),opB=UUID.randomUUID().toString();
        try(var pool=Executors.newFixedThreadPool(2)) {
            var startGate=new CountDownLatch(1);
            java.util.function.BiFunction<String,String,Callable<Integer>> request=(op,name)->()->{
                startGate.await();try{return rename.apply(op,name).status();}catch(ApiException e){
                    assertThat(e.code()).isEqualTo("REVISION_CONFLICT");
                    assertThat(e.details().get("current_revision")).isEqualTo(2L);return e.status().value();
                }
            };
            var a=pool.submit(request.apply(opA,"a"));var b=pool.submit(request.apply(opB,"b"));startGate.countDown();
            int resultA=a.get(20,TimeUnit.SECONDS),resultB=b.get(20,TimeUnit.SECONDS);
            assertThat(java.util.List.of(resultA,resultB)).containsExactlyInAnyOrder(200,409);
            assertThat(calls.get()).isEqualTo(1);
            assertThat(jdbc.queryForObject("SELECT revision FROM playlist",Long.class)).isEqualTo(2);
            var replay=rename.apply(resultA==200?opA:opB,resultA==200?"a":"b");
            assertThat(replay.status()).isEqualTo(200);assertThat(calls.get()).isEqualTo(1);
            assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Integer.class)).isEqualTo(1);
        }
    }

    com.ksh321.songrecord.api.sync.AccountChanges syncService() throws Exception {
        String migration=Files.readString(Path.of("src/main/resources/db/migration/V6__sync_and_deletion_jobs.sql"));
        for(String table:java.util.List.of("user_sync_state","change_log")) {
            int start=migration.indexOf("CREATE TABLE "+table+" (");
            jdbc.execute(migration.substring(start,migration.indexOf(';',start)));
        }
        jdbc.update("INSERT INTO user_sync_state(user_id) SELECT id FROM app_user");
        return new com.ksh321.songrecord.api.sync.AccountChanges(jdbc,access,new DataSourceTransactionManager(jdbc.getDataSource()),Clock.systemUTC());
    }
    com.ksh321.songrecord.api.sync.AccountChanges.Change change(long revision) {
        return new com.ksh321.songrecord.api.sync.AccountChanges.Change(
            com.ksh321.songrecord.api.sync.AccountChanges.Entity.SONG,UUID.randomUUID(),revision,
            com.ksh321.songrecord.api.sync.AccountChanges.Operation.UPSERT,"{\"revision\":"+revision+"}");
    }
    @Test void accountSequenceLockOrdersCommitsOnMySql() throws Exception {
        var sync=syncService();
        var firstInside=new CountDownLatch(1);var releaseFirst=new CountDownLatch(1);
        var secondInside=new CountDownLatch(1);var releaseSecond=new CountDownLatch(1);var secondStarted=new CountDownLatch(1);
        try(var pool=Executors.newFixedThreadPool(2)) {
            Callable<Long> firstTask=()->new org.springframework.transaction.support.TransactionTemplate(new DataSourceTransactionManager(jdbc.getDataSource())).execute(s->
                sync.write(account,()->{firstInside.countDown();gate(releaseFirst);return new com.ksh321.songrecord.api.sync.AccountChanges.Batch<>(1,java.util.List.of(change(1)));}).lastChangeSeq());
            var first=pool.submit(firstTask);
            try {
                assertThat(firstInside.await(5,TimeUnit.SECONDS)).isTrue();
                var second=pool.submit(()->{secondStarted.countDown();return new org.springframework.transaction.support.TransactionTemplate(new DataSourceTransactionManager(jdbc.getDataSource())).execute(s->
                    sync.write(account,()->{secondInside.countDown();gate(releaseSecond);return new com.ksh321.songrecord.api.sync.AccountChanges.Batch<>(2,java.util.List.of(change(2)));}).lastChangeSeq());});
                assertThat(secondStarted.await(5,TimeUnit.SECONDS)).isTrue();assertThat(secondInside.await(200,TimeUnit.MILLISECONDS)).isFalse();
                assertThat(jdbc.queryForObject("SELECT last_change_seq FROM user_sync_state",Long.class)).isZero();
                releaseFirst.countDown();assertThat(first.get(5,TimeUnit.SECONDS)).isEqualTo(1);
                assertThat(secondInside.await(5,TimeUnit.SECONDS)).isTrue();
                assertThat(jdbc.queryForObject("SELECT last_change_seq FROM user_sync_state",Long.class)).isEqualTo(1);
                assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM change_log",Integer.class)).isEqualTo(1);
                releaseSecond.countDown();assertThat(second.get(5,TimeUnit.SECONDS)).isEqualTo(2);
                assertThat(jdbc.queryForList("SELECT change_seq FROM change_log WHERE change_seq>1",Long.class)).containsExactly(2L);
            } finally {releaseFirst.countDown();releaseSecond.countDown();}
        }
    }
    @Test void failedChangeLogRollsBackBusinessAndReceiptOnMySql() throws Exception {
        var sync=syncService();jdbc.execute("ALTER TABLE change_log ADD CONSTRAINT injected CHECK(revision=1)");
        assertThatThrownBy(()->service.execute(account,key,"POST","/v1/songs","{}",()->{
            sync.write(account,()->{effect();return new com.ksh321.songrecord.api.sync.AccountChanges.Batch<>(1,java.util.List.of(change(2)));});
            return new IdempotentMutations.Reply(201,"{}");
        })).isInstanceOf(org.springframework.dao.DataAccessException.class);
        assertThat(jdbc.queryForObject("SELECT value_count FROM mutation_effect",Integer.class)).isZero();
        assertThat(jdbc.queryForObject("SELECT last_change_seq FROM user_sync_state",Long.class)).isZero();
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM change_log",Integer.class)).isZero();
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Integer.class)).isZero();
    }
    static void gate(CountDownLatch latch) {
        try{if(!latch.await(8,TimeUnit.SECONDS))throw new IllegalStateException("Test gate timeout");}
        catch(InterruptedException e){Thread.currentThread().interrupt();throw new IllegalStateException(e);}
    }

    void installTrigger(String name) throws Exception {
        String migration=Files.readString(Path.of("src/main/resources/db/migration/V6__sync_and_deletion_jobs.sql"));
        int start=migration.indexOf("CREATE TRIGGER "+name+" ");
        jdbc.execute(migration.substring(start,migration.indexOf("$$",start)));
    }
    com.ksh321.songrecord.api.jobs.JobQueue jobQueue(java.time.Clock clock) throws Exception {
        String migration=Files.readString(Path.of("src/main/resources/db/migration/V6__sync_and_deletion_jobs.sql"));
        int start=migration.indexOf("CREATE TABLE job (");jdbc.execute(migration.substring(start,migration.indexOf(';',start)));
        installTrigger("trg_job_before_update");
        return new com.ksh321.songrecord.api.jobs.JobQueue(jdbc,access,new DataSourceTransactionManager(jdbc.getDataSource()),clock,java.time.Duration.ofSeconds(10),3);
    }
    @Test void mysqlJobClaimRecoveryAndFencedCompletionWithRealTrigger() throws Exception {
        var time=new java.util.concurrent.atomic.AtomicReference<>(java.time.Instant.now());
        var clock=new java.time.Clock(){public java.time.ZoneId getZone(){return java.time.ZoneOffset.UTC;}public java.time.Clock withZone(java.time.ZoneId z){return this;}public java.time.Instant instant(){return time.get();}};
        var queue=jobQueue(clock);var manager=new DataSourceTransactionManager(jdbc.getDataSource());
        var aggregate=UUID.randomUUID();var operation=UUID.randomUUID();var type=com.ksh321.songrecord.api.jobs.JobQueue.Type.UPLOAD_VERIFY;
        var firstId=new org.springframework.transaction.support.TransactionTemplate(manager).execute(s->queue.enqueue(account,type,aggregate,operation,"{}"));
        var secondId=new org.springframework.transaction.support.TransactionTemplate(manager).execute(s->queue.enqueue(account,type,aggregate,operation,"{}"));assertThat(secondId).isEqualTo(firstId);
        try(var pool=Executors.newFixedThreadPool(2)) {
            var gate=new CountDownLatch(1);Callable<java.util.Optional<com.ksh321.songrecord.api.jobs.JobQueue.Lease>> call=()->{gate.await();return queue.claim(type);};
            var a=pool.submit(call);var b=pool.submit(call);gate.countDown();var x=a.get(10,TimeUnit.SECONDS);var y=b.get(10,TimeUnit.SECONDS);
            assertThat(x.isPresent()).isNotEqualTo(y.isPresent());var old=x.isPresent()?x.get():y.get();
            time.set(time.get().plusSeconds(10));var next=queue.claim(type).orElseThrow();
            assertThat(queue.complete(old,()->effect())).isFalse();assertThat(queue.renew(old)).isFalse();
            assertThat(queue.complete(next,()->effect())).isTrue();assertThat(queue.complete(next,()->effect())).isFalse();
            assertThat(jdbc.queryForObject("SELECT value_count FROM mutation_effect",Integer.class)).isEqualTo(1);
        }
    }
    @Test void receiptTriggerStaysImmutableAndJobRegistrationRollsBackWithDomain() throws Exception {
        run("{}");
        assertThatThrownBy(()->jdbc.update("UPDATE mutation_receipt SET response_status=202")).isInstanceOf(org.springframework.dao.DataAccessException.class);
        var queue=jobQueue(Clock.systemUTC());
        assertThatThrownBy(()->service.execute(account,UUID.randomUUID().toString(),"POST","/v1/songs","{}",()->{
            effect();queue.enqueue(account,com.ksh321.songrecord.api.jobs.JobQueue.Type.ASSET_DELETE,UUID.randomUUID(),UUID.randomUUID(),"{}");throw new IllegalStateException();
        })).isInstanceOf(IllegalStateException.class);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM job",Integer.class)).isZero();
        assertThat(jdbc.queryForObject("SELECT value_count FROM mutation_effect",Integer.class)).isEqualTo(1);
    }

    @Test void globalBeforeSyncWorksAndReverseOrderRollsBackOnMySql() throws Exception {
        var sync=syncService();
        String migration=Files.readString(Path.of("src/main/resources/db/migration/V5__retention_and_storage.sql"));
        int start=migration.indexOf("CREATE TABLE global_storage_usage (");jdbc.execute(migration.substring(start,migration.indexOf(';',start)));
        jdbc.update("INSERT INTO global_storage_usage(id) VALUES(1)");
        var manager=new DataSourceTransactionManager(jdbc.getDataSource());
        var locks=new com.ksh321.songrecord.api.locking.StorageLocks(jdbc,access,manager);
        new org.springframework.transaction.support.TransactionTemplate(manager).executeWithoutResult(s->{
            locks.global();sync.write(account,()->new com.ksh321.songrecord.api.sync.AccountChanges.Batch<>(1,java.util.List.of(change(1))));
        });
        assertThatThrownBy(()->new org.springframework.transaction.support.TransactionTemplate(manager).execute(s->sync.write(account,()->{
            effect();locks.global();return new com.ksh321.songrecord.api.sync.AccountChanges.Batch<>(2,java.util.List.of(change(2)));
        }))).isInstanceOf(IllegalStateException.class);
        assertThat(jdbc.queryForObject("SELECT value_count FROM mutation_effect",Integer.class)).isZero();
        assertThat(jdbc.queryForObject("SELECT last_change_seq FROM user_sync_state",Long.class)).isEqualTo(1);
    }
    @Test void mysqlLeaseCanTransferDuringEffectsAndStaleEffectsRollback() throws Exception {
        var time=new java.util.concurrent.atomic.AtomicReference<>(java.time.Instant.now());
        var clock=new java.time.Clock(){public java.time.ZoneId getZone(){return java.time.ZoneOffset.UTC;}public java.time.Clock withZone(java.time.ZoneId z){return this;}public java.time.Instant instant(){return time.get();}};
        var queue=jobQueue(clock);var manager=new DataSourceTransactionManager(jdbc.getDataSource());
        var type=com.ksh321.songrecord.api.jobs.JobQueue.Type.UPLOAD_VERIFY;
        new org.springframework.transaction.support.TransactionTemplate(manager).executeWithoutResult(s->queue.enqueue(account,type,UUID.randomUUID(),UUID.randomUUID(),"{}"));
        var old=queue.claim(type).orElseThrow();var inside=new CountDownLatch(1);var release=new CountDownLatch(1);
        try(var pool=Executors.newSingleThreadExecutor()) {
            var completion=pool.submit(()->queue.complete(old,()->{
                com.ksh321.songrecord.api.locking.LockOrder.before(com.ksh321.songrecord.api.locking.LockOrder.Rank.AGGREGATE,"effect");
                effect();inside.countDown();gate(release);
            }));
            try {
                assertThat(inside.await(5,TimeUnit.SECONDS)).isTrue();time.set(time.get().plusSeconds(10));
                var next=queue.claim(type).orElseThrow();release.countDown();
                assertThatThrownBy(()->completion.get(5,TimeUnit.SECONDS)).isInstanceOf(ExecutionException.class);
                assertThat(jdbc.queryForObject("SELECT value_count FROM mutation_effect",Integer.class)).isZero();
                assertThat(queue.complete(next,()->effect())).isTrue();
                assertThat(jdbc.queryForObject("SELECT value_count FROM mutation_effect",Integer.class)).isEqualTo(1);
            } finally {release.countDown();}
        }
    }
    @Test void mysqlPageCountAndRowsShareReadViewThenOldCursorIsRejected() throws Exception {
        syncService();
        var user=access.revalidate(account).userId();
        jdbc.execute("CREATE TABLE page_item(id BINARY(16) PRIMARY KEY,user_id BINARY(16),rank_no INT) ENGINE=InnoDB");
        for(int i=1;i<=3;i++) jdbc.update("INSERT INTO page_item VALUES(?,?,1)",
                com.ksh321.songrecord.api.pagination.PageTestSource.bytes(new UUID(0,i)),com.ksh321.songrecord.api.pagination.PageTestSource.bytes(user));
        var manager=new DataSourceTransactionManager(jdbc.getDataSource());
        var codec=new com.ksh321.songrecord.api.pagination.PageCursor(new byte[32],Clock.systemUTC(),java.time.Duration.ofMinutes(5));
        var pages=new com.ksh321.songrecord.api.pagination.KeysetPages(jdbc,access,manager,codec);
        var query=new com.ksh321.songrecord.api.pagination.PageCursor.Query("test/items","RANK_DESC","1","{}",2);
        var source=new com.ksh321.songrecord.api.pagination.PageTestSource();
        // The other connection commits after COUNT, before the first page SELECT.
        try(var pool=Executors.newSingleThreadExecutor()) {
            source.afterCount=()->{
                try {pool.submit(()->new org.springframework.transaction.support.TransactionTemplate(manager).executeWithoutResult(status->{
                    jdbc.update("INSERT INTO page_item VALUES(?,?,2)",com.ksh321.songrecord.api.pagination.PageTestSource.bytes(new UUID(0,4)),com.ksh321.songrecord.api.pagination.PageTestSource.bytes(user));
                    jdbc.update("UPDATE user_sync_state SET last_change_seq=last_change_seq+1 WHERE user_id=?",com.ksh321.songrecord.api.pagination.PageTestSource.bytes(user));
                })).get(5,TimeUnit.SECONDS);} catch(Exception e){throw new IllegalStateException(e);}
            };
            var first=pages.query(account,query,null,source);
            assertThat(first.count()).isEqualTo(3);assertThat(first.items()).containsExactly(new UUID(0,1),new UUID(0,2));
            source.afterCount=()->{};
            assertThatThrownBy(()->pages.query(account,query,first.next_cursor(),source))
                .isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("LIST_CURSOR_EXPIRED"));
            var fresh=pages.query(account,query,null,source);assertThat(fresh.count()).isEqualTo(4);
            assertThat(fresh.items()).containsExactly(new UUID(0,4),new UUID(0,1));
        }
    }

}
