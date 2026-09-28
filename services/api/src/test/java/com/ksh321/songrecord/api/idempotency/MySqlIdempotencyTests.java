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

    @Test void mysqlExpiredReceiptUuidRetryAndPermanentTombstone() throws Exception {
        syncService();
        String migration=Files.readString(Path.of("src/main/resources/db/migration/V6__sync_and_deletion_jobs.sql"));
        int start=migration.indexOf("CREATE TABLE deletion_ledger (");jdbc.execute(migration.substring(start,migration.indexOf(';',start)));
        jdbc.execute("CREATE TABLE song(id BINARY(16) PRIMARY KEY,user_id BINARY(16),revision BIGINT,lifecycle_state VARCHAR(32),title VARCHAR(200)) ENGINE=InnoDB");
        var owner=access.revalidate(account).userId();var id=UUID.randomUUID();
        var manager=new DataSourceTransactionManager(jdbc.getDataSource());
        var guard=new com.ksh321.songrecord.api.revision.CreationGuard(jdbc,access,manager);
        java.util.function.Supplier<IdempotentMutations.Reply> command=()->{
            var result=guard.create(account,com.ksh321.songrecord.api.revision.CreationGuard.Resource.SONG,id,()->{
                jdbc.update("INSERT INTO song VALUES(?,?,1,'ACTIVE','initial')",com.ksh321.songrecord.api.pagination.PageTestSource.bytes(id),com.ksh321.songrecord.api.pagination.PageTestSource.bytes(owner));return 1;
            });
            return new IdempotentMutations.Reply(result.created()?201:200,"{\"created\":"+result.created()+",\"revision\":"+(result.created()?1:result.existing().revision())+"}");
        };
        var first=service.execute(account,key,"POST","/v1/songs","{}",command);
        assertThat(service.execute(account,key,"POST","/v1/songs","{}",command)).isEqualTo(first);
        jdbc.update("UPDATE song SET title='newer',revision=7 WHERE id=?",com.ksh321.songrecord.api.pagination.PageTestSource.bytes(id));
        var later=java.time.Instant.now().plus(java.time.Duration.ofDays(91));
        jdbc.update("DELETE FROM mutation_receipt WHERE expires_at<=?",java.time.LocalDateTime.ofInstant(later,java.time.ZoneOffset.UTC));
        service=new IdempotentMutations(jdbc,access,manager,Clock.fixed(later,java.time.ZoneOffset.UTC));
        // Distinct request keys must still serialize on account/UUID after receipts are gone.
        try(var pool=Executors.newFixedThreadPool(2)) {
            var gate=new CountDownLatch(1);
            var a=pool.submit(()->{gate.await();return service.execute(account,key,"POST","/v1/songs","{}",command);});
            var b=pool.submit(()->{gate.await();return service.execute(account,UUID.randomUUID().toString(),"POST","/v1/songs","{}",command);});
            gate.countDown();assertThat(a.get(10,TimeUnit.SECONDS).status()).isEqualTo(200);assertThat(b.get(10,TimeUnit.SECONDS).status()).isEqualTo(200);
        }
        assertThat(jdbc.queryForObject("SELECT title FROM song",String.class)).isEqualTo("newer");
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM song",Integer.class)).isEqualTo(1);
        jdbc.update("INSERT INTO deletion_ledger(id,user_id,entity_type,entity_id,revision) VALUES(?,?,'SONG',?,8)",
                com.ksh321.songrecord.api.pagination.PageTestSource.bytes(UUID.randomUUID()),com.ksh321.songrecord.api.pagination.PageTestSource.bytes(owner),com.ksh321.songrecord.api.pagination.PageTestSource.bytes(id));
        jdbc.update("DELETE FROM song WHERE id=?",com.ksh321.songrecord.api.pagination.PageTestSource.bytes(id));
        jdbc.update("DELETE FROM mutation_receipt WHERE expires_at<=?",java.time.LocalDateTime.ofInstant(later.plus(java.time.Duration.ofDays(91)),java.time.ZoneOffset.UTC));
        assertThatThrownBy(()->service.execute(account,key,"POST","/v1/songs","{}",command))
                .isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("RESOURCE_PURGED"));
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM song",Integer.class)).isZero();
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Integer.class)).isZero();
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM deletion_ledger",Integer.class)).isEqualTo(1);
    }

    @Test void mysqlSongCreationUsesRealSourceConstraintsAndAtomicChangeLog() throws Exception {
        var changes=syncService();String core=Files.readString(Path.of("src/main/resources/db/migration/V2__account_song_recording.sql"));
        for(String table:java.util.List.of("song","song_source")){int from=core.indexOf("CREATE TABLE "+table+" (");jdbc.execute(core.substring(from,core.indexOf(';',from)));}
        installSongQueryKeys();
        int trigger=core.indexOf("CREATE TRIGGER trg_song_source_before_insert");jdbc.execute(core.substring(trigger,core.indexOf("$$",trigger)));
        String sync=Files.readString(Path.of("src/main/resources/db/migration/V6__sync_and_deletion_jobs.sql"));int from=sync.indexOf("CREATE TABLE deletion_ledger (");jdbc.execute(sync.substring(from,sync.indexOf(';',from)));
        when(access.authenticate("Bearer test","device")).thenReturn(account);
        var principal = access.revalidate(account);
        when(account.principal()).thenReturn(principal);
        var clock=Clock.systemUTC();var manager=new DataSourceTransactionManager(jdbc.getDataSource());
        var candidates=new com.ksh321.songrecord.api.songs.TjCandidates(token->new com.ksh321.songrecord.api.songs.CandidateVerifier.Verified("FIXTURE",com.ksh321.songrecord.api.songs.CandidateVerifier.Brand.TJ,token,"original","artist",clock.instant(),clock.instant().plusSeconds(3600)),clock);
        var creation=new com.ksh321.songrecord.api.songs.SongCreation(jdbc,access,service,new com.ksh321.songrecord.api.revision.CreationGuard(jdbc,access,manager),changes,candidates,clock);
        String body="{\"id\":\""+UUID.randomUUID()+"\",\"source_type\":\"TJ\",\"source_token\":\"990001\",\"title\":\"edited\"}";
        var first=creation.create("Bearer test","device",key,body);assertThat(first.status()).isEqualTo(201);
        assertThat(creation.create("Bearer test","device",key,body)).isEqualTo(first);
        assertThat(jdbc.queryForObject("SELECT source_title FROM song_source",String.class)).isEqualTo("original");
        assertThat(jdbc.queryForObject("SELECT title FROM song",String.class)).isEqualTo("edited");
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM change_log",Integer.class)).isEqualTo(1);
        jdbc.execute("ALTER TABLE song_source ADD CONSTRAINT injected_source CHECK(source_ref <> 'FIXTURE:990002')");
        String next="{\"id\":\""+UUID.randomUUID()+"\",\"source_type\":\"TJ\",\"source_token\":\"990002\"}";
        assertThatThrownBy(()->creation.create("Bearer test","device",UUID.randomUUID().toString(),next))
                .hasRootCauseInstanceOf(java.sql.SQLException.class)
                .satisfies(error -> {
                    Throwable cause = error;
                    while (cause.getCause() != null) cause = cause.getCause();
                    assertThat(((java.sql.SQLException) cause).getErrorCode()).isEqualTo(3819);
                    assertThat(cause.getMessage()).contains("injected_source");
                });
        for(String table:java.util.List.of("song","song_source","change_log","mutation_receipt"))assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM "+table,Integer.class)).isEqualTo(1);
        assertThat(jdbc.queryForObject("SELECT last_change_seq FROM user_sync_state",Long.class)).isEqualTo(1);
    }

    @Test void mysqlConcurrentDifferentUuidsMapToOneSongAndPreserveEdits() throws Exception {
        var changes=syncService();String core=Files.readString(Path.of("src/main/resources/db/migration/V2__account_song_recording.sql"));
        for(String table:java.util.List.of("song","song_source")){int from=core.indexOf("CREATE TABLE "+table+" (");jdbc.execute(core.substring(from,core.indexOf(';',from)));}
        installSongQueryKeys();
        int trigger=core.indexOf("CREATE TRIGGER trg_song_source_before_insert");jdbc.execute(core.substring(trigger,core.indexOf("$$",trigger)));
        String sync=Files.readString(Path.of("src/main/resources/db/migration/V6__sync_and_deletion_jobs.sql"));int from=sync.indexOf("CREATE TABLE deletion_ledger (");jdbc.execute(sync.substring(from,sync.indexOf(';',from)));
        var principal=access.revalidate(account);when(access.authenticate("Bearer test","device")).thenReturn(account);when(account.principal()).thenReturn(principal);
        var clock=Clock.systemUTC();var manager=new DataSourceTransactionManager(jdbc.getDataSource());
        var candidates=new com.ksh321.songrecord.api.songs.TjCandidates(token->new com.ksh321.songrecord.api.songs.CandidateVerifier.Verified("FIXTURE",com.ksh321.songrecord.api.songs.CandidateVerifier.Brand.TJ,"990001","original","artist",clock.instant(),clock.instant().plusSeconds(3600)),clock);
        var creation=new com.ksh321.songrecord.api.songs.SongCreation(jdbc,access,service,new com.ksh321.songrecord.api.revision.CreationGuard(jdbc,access,manager),changes,candidates,clock);
        var json=new tools.jackson.databind.json.JsonMapper();
        String firstBody="{\"id\":\""+UUID.randomUUID()+"\",\"source_type\":\"TJ\",\"source_token\":\"proof\",\"note\":\"first\"}";
        String secondBody="{\"id\":\""+UUID.randomUUID()+"\",\"source_type\":\"TJ\",\"source_token\":\"proof\",\"note\":\"second\"}";
        String aKey=UUID.randomUUID().toString(),bKey=UUID.randomUUID().toString();
        IdempotentMutations.Reply a,b;
        try(var pool=Executors.newFixedThreadPool(2)) {
            var ready=new CountDownLatch(2);var go=new CountDownLatch(1);
            var fa=pool.submit(()->{ready.countDown();go.await();return creation.create("Bearer test","device",aKey,firstBody);});
            var fb=pool.submit(()->{ready.countDown();go.await();return creation.create("Bearer test","device",bKey,secondBody);});
            try {assertThat(ready.await(5,TimeUnit.SECONDS)).isTrue();}finally{go.countDown();}
            a=fa.get(15,TimeUnit.SECONDS);b=fb.get(15,TimeUnit.SECONDS);
        }
        assertThat(java.util.List.of(a.status(),b.status())).containsExactlyInAnyOrder(201,200);
        String canonical=json.readTree(a.body()).get("canonical_song_id").asText();
        assertThat(json.readTree(b.body()).get("canonical_song_id").asText()).isEqualTo(canonical);
        assertThat(jdbc.queryForObject("SELECT note FROM song",String.class)).isEqualTo(a.status()==201?"first":"second");
        for(String table:java.util.List.of("song","song_source","change_log"))assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM "+table,Integer.class)).isEqualTo(1);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Integer.class)).isEqualTo(2);
        assertThat(creation.create("Bearer test","device",aKey,firstBody)).isEqualTo(a);
        assertThat(creation.create("Bearer test","device",bKey,secondBody)).isEqualTo(b);
        jdbc.update("UPDATE song SET note='keep',version_code='LIVE',representative_key_mode='MALE',representative_key_shift=3,revision=7");
        var before=jdbc.queryForMap("SELECT note,version_code,representative_key_mode,representative_key_shift,revision,updated_at FROM song");
        var duplicate=creation.create("Bearer test","device",UUID.randomUUID().toString(),secondBody);
        assertThat(duplicate.status()).isEqualTo(200);assertThat(json.readTree(duplicate.body()).get("song").get("revision").asLong()).isEqualTo(7);
        assertThat(jdbc.queryForMap("SELECT note,version_code,representative_key_mode,representative_key_shift,revision,updated_at FROM song")).isEqualTo(before);
        assertThat(jdbc.queryForObject("SELECT last_change_seq FROM user_sync_state",Long.class)).isEqualTo(1);
        // DB uniqueness remains a second line of defence even for a writer bypassing the service.
        assertThatThrownBy(()->jdbc.update("INSERT INTO song(id,user_id,source_type,tj_number,title,artist,note) VALUES(?,?,'TJ','990001','x','y','')",com.ksh321.songrecord.api.pagination.PageTestSource.bytes(UUID.randomUUID()),com.ksh321.songrecord.api.pagination.PageTestSource.bytes(principal.userId())))
                .isInstanceOf(org.springframework.dao.DuplicateKeyException.class);
    }


    @Test void mysqlManualSongsAllowNullNumbersAndRollbackAtomicChanges() throws Exception {
        var changes=syncService();String core=Files.readString(Path.of("src/main/resources/db/migration/V2__account_song_recording.sql"));
        for(String table:java.util.List.of("song","song_source")){int from=core.indexOf("CREATE TABLE "+table+" (");jdbc.execute(core.substring(from,core.indexOf(';',from)));}
        installSongQueryKeys();
        int trigger=core.indexOf("CREATE TRIGGER trg_song_source_before_insert");jdbc.execute(core.substring(trigger,core.indexOf("$$",trigger)));
        String sync=Files.readString(Path.of("src/main/resources/db/migration/V6__sync_and_deletion_jobs.sql"));int from=sync.indexOf("CREATE TABLE deletion_ledger (");jdbc.execute(sync.substring(from,sync.indexOf(';',from)));
        var principal=access.revalidate(account);when(access.authenticate("Bearer test","device")).thenReturn(account);when(account.principal()).thenReturn(principal);
        var clock=Clock.systemUTC();var manager=new DataSourceTransactionManager(jdbc.getDataSource());
        var candidates=new com.ksh321.songrecord.api.songs.TjCandidates(token->{throw new AssertionError("Manual creation must not access candidate verifier");},clock);
        var creation=new com.ksh321.songrecord.api.songs.SongCreation(jdbc,access,service,new com.ksh321.songrecord.api.revision.CreationGuard(jdbc,access,manager),changes,candidates,clock);
        var json=new tools.jackson.databind.json.JsonMapper();

        String id=UUID.randomUUID().toString();
        String body="{\"id\":\""+id+"\",\"source_type\":\"MANUAL\",\"manual_reason\":\"TJ_NOT_FOUND\",\"title\":\"same\",\"artist\":\"artist\"}";
        String key=UUID.randomUUID().toString();
        var first=creation.create("Bearer test","device",key,body);assertThat(first.status()).isEqualTo(201);
        assertThat(creation.create("Bearer test","device",key,body)).isEqualTo(first);
        assertThat(creation.create("Bearer test","device",UUID.randomUUID().toString(),body).status()).isEqualTo(200);
        String next=body.replace(id,UUID.randomUUID().toString());
        assertThat(creation.create("Bearer test","device",UUID.randomUUID().toString(),next).status()).isEqualTo(201);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM song WHERE source_type='MANUAL' AND tj_number IS NULL AND reserved_tj_number IS NULL",Integer.class)).isEqualTo(2);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM song_source",Integer.class)).isZero();
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM change_log",Integer.class)).isEqualTo(2);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Integer.class)).isEqualTo(3);
        // Reject the next log using a trigger, after song INSERT and sequence allocation.
        jdbc.execute("CREATE TRIGGER reject_manual_change BEFORE INSERT ON change_log FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='injected manual failure'");
        assertThatThrownBy(()->creation.create("Bearer test","device",UUID.randomUUID().toString(),body.replace(id,UUID.randomUUID().toString())))
                .hasRootCauseInstanceOf(java.sql.SQLException.class)
                .hasStackTraceContaining("injected manual failure");
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM song",Integer.class)).isEqualTo(2);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM change_log",Integer.class)).isEqualTo(2);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Integer.class)).isEqualTo(3);
        assertThat(jdbc.queryForObject("SELECT last_change_seq FROM user_sync_state",Long.class)).isEqualTo(2);
    }

    @Test void mysqlBinarySongSortKeysMatchSharedContractAcrossPages() throws Exception {
        com.ksh321.songrecord.api.songs.SongSortDatabaseChecks.verify(jdbc);
    }

    void installSongQueryKeys() throws Exception {
        String ddl=Files.readString(Path.of("src/main/resources/db/migration/V10__song_query_keys.sql"));
        int start=ddl.indexOf("CREATE TABLE song_query_key (");jdbc.execute(ddl.substring(start,ddl.indexOf(';',start)));
    }

    @Test void mysqlSongListingUsesRealSchemaAndKeysetAcrossAllSorts() throws Exception {
        syncService();String core=Files.readString(Path.of("src/main/resources/db/migration/V2__account_song_recording.sql"));
        for(String table:java.util.List.of("device","song","recording")){
            int start=core.indexOf("CREATE TABLE "+table+" (");jdbc.execute(core.substring(start,core.indexOf(';',start)));
        }
        installSongQueryKeys();var principal=access.revalidate(account);
        jdbc.update("INSERT INTO device(id,user_id,display_name,last_seen_at) VALUES(?,?,'test',UTC_TIMESTAMP(3))",com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(principal.deviceId()),com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(principal.userId()));
        var manager=new DataSourceTransactionManager(jdbc.getDataSource());
        var pages=new com.ksh321.songrecord.api.pagination.KeysetPages(jdbc,access,manager,new com.ksh321.songrecord.api.pagination.PageCursor(new byte[32],Clock.systemUTC(),java.time.Duration.ofMinutes(30)));
        com.ksh321.songrecord.api.songs.SongListingDatabaseChecks.verify(jdbc,pages,account,principal.userId(),principal.deviceId());
    }
    @Test void mysqlFlywayDiscoversJavaBackfillAndPreservesPopulatedV9Data() throws Exception {
        String name=database+"_upgrade";admin.execute("CREATE DATABASE "+name);
        try {
            var ds=new DriverManagerDataSource("jdbc:mysql://127.0.0.1:3306/"+name+"?allowPublicKeyRetrieval=true&useSSL=false","root",System.getenv("P07_MYSQL_PASSWORD"));
            org.flywaydb.core.Flyway.configure().dataSource(ds).locations("classpath:db/migration").target("9").load().migrate();
            var db=new JdbcTemplate(ds);UUID user=UUID.randomUUID(),song=UUID.randomUUID();
            db.update("INSERT INTO app_user(id) VALUES(?)",com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(user));
            db.update("INSERT INTO song(id,user_id,source_type,title,artist,version_code,note,revision) VALUES(?,?,'MANUAL','노래02','Artist','LIVE','keep',7)",com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(song),com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(user));
            var before=db.queryForMap("SELECT title,artist,note,version_code,revision,updated_at FROM song");
            var flyway=org.flywaydb.core.Flyway.configure().dataSource(ds).locations("classpath:db/migration").load();
            assertThat(flyway.migrate().migrationsExecuted).isEqualTo(2);flyway.validate();
            assertThat(db.queryForObject("SELECT title_key FROM song_query_key",byte[].class)).isEqualTo(com.ksh321.songrecord.api.domain.DomainOrdering.sortKeyBytes("노래02"));
            assertThat(db.queryForMap("SELECT title,artist,note,version_code,revision,updated_at FROM song")).isEqualTo(before);
            assertThat(flyway.migrate().migrationsExecuted).isZero();
        } finally {admin.execute("DROP DATABASE "+name);}
    }
}
