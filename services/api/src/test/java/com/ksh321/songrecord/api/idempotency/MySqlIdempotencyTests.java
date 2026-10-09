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
            UUID deviceId=UUID.randomUUID(),recordingId=UUID.randomUUID();
            db.update("INSERT INTO device(id,user_id,display_name,last_seen_at) VALUES(?,?,'upgrade',UTC_TIMESTAMP(3))",com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(deviceId),com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(user));
            db.update("INSERT INTO recording(id,user_id,origin_device_id,title_snapshot,note,recorded_at,timezone_id,timezone_offset_minutes) VALUES(?,?,?,'곡02','keep',UTC_TIMESTAMP(3),'UTC',0)",com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(recordingId),com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(user),com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(deviceId));
            db.update("UPDATE recording SET condition_code='GOOD' WHERE id=?",com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(recordingId));
            var beforeRecording=db.queryForMap("SELECT * FROM recording");
            var before=db.queryForMap("SELECT title,artist,note,version_code,revision,updated_at FROM song");
            var flyway=org.flywaydb.core.Flyway.configure().dataSource(ds).locations("classpath:db/migration").load();
            assertThat(flyway.migrate().migrationsExecuted).isEqualTo(9);flyway.validate();
            assertThat(db.queryForObject("SELECT title_key FROM recording_query_key",byte[].class)).isEqualTo(com.ksh321.songrecord.api.domain.DomainOrdering.sortKeyBytes("곡02"));
            assertThat(db.queryForMap("SELECT * FROM recording")).usingRecursiveComparison().isEqualTo(beforeRecording);
            assertThat(db.queryForObject("SELECT title_key FROM song_query_key",byte[].class)).isEqualTo(com.ksh321.songrecord.api.domain.DomainOrdering.sortKeyBytes("노래02"));
            assertThat(db.queryForMap("SELECT title,artist,note,version_code,revision,updated_at FROM song")).isEqualTo(before);
            assertThat(db.queryForObject("SELECT COUNT(*) FROM condition_definition WHERE user_id=?",Integer.class,com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(user))).isEqualTo(4);
            UUID fresh=UUID.randomUUID();db.update("INSERT INTO app_user(id) VALUES(?)",com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(fresh));
            assertThat(db.queryForObject("SELECT COUNT(*) FROM condition_definition WHERE user_id=?",Integer.class,com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(fresh))).isEqualTo(4);
            assertThat(db.queryForObject("SELECT condition_name_snapshot FROM recording WHERE id=?",String.class,com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(recordingId))).isEqualTo("좋음");
            assertThat(flyway.migrate().migrationsExecuted).isZero();
        } finally {admin.execute("DROP DATABASE "+name);}
    }

    @Test void mysqlSongEditRaceKeyRefreshAndRollbackPreservePastRecording() throws Exception {
        var changes=syncService();String core=Files.readString(Path.of("src/main/resources/db/migration/V2__account_song_recording.sql"));
        for(String table:java.util.List.of("device","song","recording")){
            int start=core.indexOf("CREATE TABLE "+table+" (");jdbc.execute(core.substring(start,core.indexOf(';',start)));
        }
        installSongQueryKeys();var principal=access.revalidate(account);
        when(access.authenticate("Bearer test","device")).thenReturn(account);when(account.principal()).thenReturn(principal);
        byte[] owner=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(principal.userId()),device=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(principal.deviceId());
        UUID song=UUID.randomUUID();byte[] songBytes=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(song);
        jdbc.update("INSERT INTO device(id,user_id,display_name,last_seen_at) VALUES(?,?,'test',UTC_TIMESTAMP(3))",device,owner);
        jdbc.update("INSERT INTO song(id,user_id,source_type,title,artist,version_code,note) VALUES(?,?,'MANUAL','before','artist','NORMAL','')",songBytes,owner);
        com.ksh321.songrecord.api.songs.SongQueryKeys.insert(jdbc,principal.userId(),song,"before","artist");
        jdbc.update("INSERT INTO recording(id,user_id,origin_device_id,song_id,title_snapshot,artist_snapshot,version_code,key_mode,key_shift,tier,note,recorded_at,timezone_id,timezone_offset_minutes,metadata_state) VALUES(?,?,?,?,'past','past artist','LIVE','FEMALE',-2,'D','keep',UTC_TIMESTAMP(3),'UTC',0,'SAVED')",com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(UUID.randomUUID()),owner,device,songBytes);
        var recordingBefore=jdbc.queryForMap("SELECT * FROM recording");var clock=Clock.systemUTC();var manager=new DataSourceTransactionManager(jdbc.getDataSource());
        var editing=new com.ksh321.songrecord.api.songs.SongEditing(jdbc,access,service,new com.ksh321.songrecord.api.revision.RevisionChanges(jdbc,access,manager,clock),changes);
        String aKey=UUID.randomUUID().toString(),bKey=UUID.randomUUID().toString();
        String aBody="{\"base_revision\":1,\"title\":\"alpha\"}",bBody="{\"base_revision\":1,\"title\":\"beta\"}";Object a,b;
        try(var pool=Executors.newFixedThreadPool(2)){
            var ready=new CountDownLatch(2);var go=new CountDownLatch(1);
            var fa=pool.submit(()->{ready.countDown();go.await();try{return (Object)editing.patch("Bearer test","device",aKey,song.toString(),aBody);}catch(ApiException e){return e;}});
            var fb=pool.submit(()->{ready.countDown();go.await();try{return (Object)editing.patch("Bearer test","device",bKey,song.toString(),bBody);}catch(ApiException e){return e;}});
            try{assertThat(ready.await(5,TimeUnit.SECONDS)).isTrue();}finally{go.countDown();}
            a=fa.get(15,TimeUnit.SECONDS);b=fb.get(15,TimeUnit.SECONDS);
        }
        var winner=(IdempotentMutations.Reply)(a instanceof IdempotentMutations.Reply?a:b);var loser=(ApiException)(a instanceof ApiException?a:b);
        assertThat(winner.status()).isEqualTo(200);assertThat(loser.code()).isEqualTo("REVISION_CONFLICT");
        assertThat(editing.patch("Bearer test","device",a instanceof IdempotentMutations.Reply?aKey:bKey,song.toString(),a instanceof IdempotentMutations.Reply?aBody:bBody)).isEqualTo(winner);
        String title=jdbc.queryForObject("SELECT title FROM song",String.class);
        assertThat(jdbc.queryForObject("SELECT title_key FROM song_query_key",byte[].class)).isEqualTo(com.ksh321.songrecord.api.domain.DomainOrdering.sortKeyBytes(title));
        assertThat(jdbc.queryForObject("SELECT revision FROM song",Long.class)).isEqualTo(2);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Integer.class)).isEqualTo(1);
        var json=new tools.jackson.databind.json.JsonMapper();
        assertThat(editing.patch("Bearer test","device",UUID.randomUUID().toString(),song.toString(),json.writeValueAsString(java.util.Map.of("base_revision",2,"note","😀".repeat(2000),"version_code","MR","tier","A","representative_key_mode","MALE","representative_key_shift",3))).status()).isEqualTo(200);
        assertThat(jdbc.queryForObject("SELECT CHAR_LENGTH(note) FROM song",Integer.class)).isEqualTo(2000);
        var before=jdbc.queryForMap("SELECT * FROM song");var beforeKey=jdbc.queryForMap("SELECT HEX(title_key) AS title_key,HEX(artist_key) AS artist_key FROM song_query_key");
        jdbc.execute("ALTER TABLE song_query_key ADD CONSTRAINT reject_edit_key CHECK(title_search<>X'626c6f636b6564')");
        String retryKey=UUID.randomUUID().toString(),retryBody="{\"base_revision\":3,\"title\":\"blocked\"}";
        assertThatThrownBy(()->editing.patch("Bearer test","device",retryKey,song.toString(),retryBody)).hasRootCauseInstanceOf(java.sql.SQLException.class).hasStackTraceContaining("reject_edit_key");
        assertThat(jdbc.queryForMap("SELECT * FROM song")).usingRecursiveComparison().isEqualTo(before);assertThat(jdbc.queryForMap("SELECT HEX(title_key) AS title_key,HEX(artist_key) AS artist_key FROM song_query_key")).isEqualTo(beforeKey);
        jdbc.execute("ALTER TABLE song_query_key DROP CHECK reject_edit_key");
        jdbc.execute("CREATE TRIGGER reject_song_edit_log BEFORE INSERT ON change_log FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='injected edit log failure'");
        assertThatThrownBy(()->editing.patch("Bearer test","device",retryKey,song.toString(),retryBody)).hasRootCauseInstanceOf(java.sql.SQLException.class).hasStackTraceContaining("injected edit log failure");
        assertThat(jdbc.queryForMap("SELECT * FROM song")).usingRecursiveComparison().isEqualTo(before);assertThat(jdbc.queryForMap("SELECT HEX(title_key) AS title_key,HEX(artist_key) AS artist_key FROM song_query_key")).isEqualTo(beforeKey);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Integer.class)).isEqualTo(2);assertThat(jdbc.queryForObject("SELECT last_change_seq FROM user_sync_state",Long.class)).isEqualTo(2);
        jdbc.execute("DROP TRIGGER reject_song_edit_log");
        assertThat(editing.patch("Bearer test","device",retryKey,song.toString(),retryBody).status()).isEqualTo(200);
        assertThat(jdbc.queryForObject("SELECT revision FROM song",Long.class)).isEqualTo(4);assertThat(jdbc.queryForMap("SELECT * FROM recording")).usingRecursiveComparison().isEqualTo(recordingBefore);
    }

    @Test void mysqlRepresentativeRaceCompositeFkAndAtomicRollback() throws Exception {
        jobQueue(Clock.systemUTC()); // representative changes now schedule policy recalculation
        var changes=syncService();String core=Files.readString(Path.of("src/main/resources/db/migration/V2__account_song_recording.sql"));
        for(String table:java.util.List.of("device","song","recording")){
            int start=core.indexOf("CREATE TABLE "+table+" (");jdbc.execute(core.substring(start,core.indexOf(';',start)));
        }
        int fk=core.indexOf("ALTER TABLE song");jdbc.execute(core.substring(fk,core.indexOf(';',fk)));
        var principal=access.revalidate(account);when(access.authenticate("Bearer test","device")).thenReturn(account);when(account.principal()).thenReturn(principal);
        byte[] owner=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(principal.userId()),device=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(principal.deviceId());
        UUID song=UUID.randomUUID(),otherSong=UUID.randomUUID(),recording=UUID.randomUUID();
        byte[] songBytes=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(song),recordingBytes=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(recording);
        jdbc.update("INSERT INTO device(id,user_id,display_name,last_seen_at) VALUES(?,?,'test',UTC_TIMESTAMP(3))",device,owner);
        for(UUID id:java.util.List.of(song,otherSong))jdbc.update("INSERT INTO song(id,user_id,source_type,title,artist,note) VALUES(?,?,'MANUAL','song','artist','')",com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(id),owner);
        jdbc.update("INSERT INTO recording(id,user_id,origin_device_id,song_id,title_snapshot,artist_snapshot,key_mode,key_shift,note,recorded_at,timezone_id,timezone_offset_minutes,metadata_state) VALUES(?,?,?,?,'past','artist','ORIGINAL',0,'keep',UTC_TIMESTAMP(3),'UTC',0,'SAVED')",recordingBytes,owner,device,songBytes);
        var beforeRecording=jdbc.queryForMap("SELECT * FROM recording");
        var manager=new DataSourceTransactionManager(jdbc.getDataSource());var selecting=new com.ksh321.songrecord.api.songs.SongRepresentative(jdbc,access,service,new com.ksh321.songrecord.api.revision.RevisionChanges(jdbc,access,manager,Clock.systemUTC()),changes);
        String body="{\"base_revision\":1,\"recording_id\":\""+recording+"\"}",clear="{\"base_revision\":1,\"recording_id\":null}";
        String aKey=UUID.randomUUID().toString(),bKey=UUID.randomUUID().toString();Object a,b;
        try(var pool=Executors.newFixedThreadPool(2)){
            var ready=new CountDownLatch(2);var go=new CountDownLatch(1);
            var fa=pool.submit(()->{ready.countDown();go.await();try{return (Object)selecting.put("Bearer test","device",aKey,song.toString(),body);}catch(ApiException e){return e;}});
            var fb=pool.submit(()->{ready.countDown();go.await();try{return (Object)selecting.put("Bearer test","device",bKey,song.toString(),clear);}catch(ApiException e){return e;}});
            try{assertThat(ready.await(5,TimeUnit.SECONDS)).isTrue();}finally{go.countDown();}
            a=fa.get(15,TimeUnit.SECONDS);b=fb.get(15,TimeUnit.SECONDS);
        }
        var winner=(IdempotentMutations.Reply)(a instanceof IdempotentMutations.Reply?a:b);var loser=(ApiException)(a instanceof ApiException?a:b);
        assertThat(winner.status()).isEqualTo(200);assertThat(loser.code()).isEqualTo("REVISION_CONFLICT");
        assertThat(selecting.put("Bearer test","device",a instanceof IdempotentMutations.Reply?aKey:bKey,song.toString(),a instanceof IdempotentMutations.Reply?body:clear)).isEqualTo(winner);
        assertThat(jdbc.queryForObject("SELECT revision FROM song WHERE id=?",Long.class,songBytes)).isEqualTo(2);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Integer.class)).isEqualTo(1);
        // Actual V2 composite FK, including owner and song, is exercised rather than a test-only approximation.
        assertThatThrownBy(()->jdbc.update("UPDATE song SET representative_recording_id=? WHERE id=?",recordingBytes,com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(otherSong))).isInstanceOf(org.springframework.dao.DataIntegrityViolationException.class);
        assertThatThrownBy(()->selecting.put("Bearer test","device",UUID.randomUUID().toString(),otherSong.toString(),body)).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("REPRESENTATIVE_NOT_ELIGIBLE"));
        var before=jdbc.queryForMap("SELECT * FROM song WHERE id=?",songBytes);
        jdbc.execute("CREATE TRIGGER reject_representative_log BEFORE INSERT ON change_log FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='injected representative failure'");
        String retryKey=UUID.randomUUID().toString(),retryBody=body.replace("\"base_revision\":1","\"base_revision\":2");
        assertThatThrownBy(()->selecting.put("Bearer test","device",retryKey,song.toString(),retryBody)).hasRootCauseInstanceOf(java.sql.SQLException.class).hasStackTraceContaining("injected representative failure");
        assertThat(jdbc.queryForMap("SELECT * FROM song WHERE id=?",songBytes)).usingRecursiveComparison().isEqualTo(before);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Integer.class)).isEqualTo(1);assertThat(jdbc.queryForObject("SELECT last_change_seq FROM user_sync_state",Long.class)).isEqualTo(1);
        jdbc.execute("DROP TRIGGER reject_representative_log");assertThat(selecting.put("Bearer test","device",retryKey,song.toString(),retryBody).status()).isEqualTo(200);
        assertThat(jdbc.queryForObject("SELECT representative_recording_id FROM song WHERE id=?",byte[].class,songBytes)).isEqualTo(recordingBytes);
        assertThat(jdbc.queryForMap("SELECT * FROM recording")).usingRecursiveComparison().isEqualTo(beforeRecording);
        assertThat(selecting.put("Bearer test","device",UUID.randomUUID().toString(),song.toString(),clear.replace("\"base_revision\":1","\"base_revision\":3")).status()).isEqualTo(200);
        jdbc.update("UPDATE recording SET lifecycle_state='TRASHED',deleted_at=UTC_TIMESTAMP(3) WHERE id=?",recordingBytes);
        assertThatThrownBy(()->selecting.put("Bearer test","device",UUID.randomUUID().toString(),song.toString(),body.replace("\"base_revision\":1","\"base_revision\":4"))).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("REPRESENTATIVE_NOT_ELIGIBLE"));
        assertThat(jdbc.queryForObject("SELECT representative_recording_id FROM song WHERE id=?",byte[].class,songBytes)).isNull();
        assertThat(jdbc.queryForObject("SELECT revision FROM song WHERE id=?",Long.class,songBytes)).isEqualTo(4);
    }

    @Test void mysqlTrashNumberReservationAndPurgedUuidProtection() throws Exception {
        var changes=syncService();String core=Files.readString(Path.of("src/main/resources/db/migration/V2__account_song_recording.sql"));
        for(String table:java.util.List.of("song","song_source")){int start=core.indexOf("CREATE TABLE "+table+" (");jdbc.execute(core.substring(start,core.indexOf(';',start)));}
        installSongQueryKeys();
        String sync=Files.readString(Path.of("src/main/resources/db/migration/V6__sync_and_deletion_jobs.sql"));int start=sync.indexOf("CREATE TABLE deletion_ledger (");jdbc.execute(sync.substring(start,sync.indexOf(';',start)));
        var principal=access.revalidate(account);when(access.authenticate("Bearer test","device")).thenReturn(account);when(account.principal()).thenReturn(principal);
        var clock=Clock.systemUTC();var manager=new DataSourceTransactionManager(jdbc.getDataSource());
        var candidates=new com.ksh321.songrecord.api.songs.TjCandidates(token->new com.ksh321.songrecord.api.songs.CandidateVerifier.Verified("FIXTURE",com.ksh321.songrecord.api.songs.CandidateVerifier.Brand.TJ,token,"original","artist",clock.instant(),clock.instant().plusSeconds(3600)),clock);
        var creation=new com.ksh321.songrecord.api.songs.SongCreation(jdbc,access,service,new com.ksh321.songrecord.api.revision.CreationGuard(jdbc,access,manager),changes,candidates,clock);
        com.ksh321.songrecord.api.songs.SongLifecycleDatabaseChecks.verify(jdbc,creation,"Bearer test","device",principal.userId(),"00990001");
    }

    @Test void mysqlSameTjNumberAndOperationKeyRemainAccountScoped() throws Exception {
        var changes=syncService();String core=Files.readString(Path.of("src/main/resources/db/migration/V2__account_song_recording.sql"));
        for(String table:java.util.List.of("song","song_source")){int start=core.indexOf("CREATE TABLE "+table+" (");jdbc.execute(core.substring(start,core.indexOf(';',start)));}
        installSongQueryKeys();String sync=Files.readString(Path.of("src/main/resources/db/migration/V6__sync_and_deletion_jobs.sql"));int start=sync.indexOf("CREATE TABLE deletion_ledger (");jdbc.execute(sync.substring(start,sync.indexOf(';',start)));
        var principal=access.revalidate(account);when(access.authenticate("Bearer a","device")).thenReturn(account);when(account.principal()).thenReturn(principal);
        UUID otherOwner=UUID.randomUUID();var other=mock(AccountAccess.Account.class);var otherPrincipal=new SessionService.Principal(otherOwner,UUID.randomUUID(),UUID.randomUUID());
        when(access.authenticate("Bearer b","device")).thenReturn(other);when(access.revalidate(other)).thenReturn(otherPrincipal);when(other.principal()).thenReturn(otherPrincipal);
        byte[] otherBytes=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(otherOwner);
        jdbc.update("INSERT INTO app_user(id) VALUES(?)",otherBytes);jdbc.update("INSERT INTO user_sync_state(user_id) VALUES(?)",otherBytes);
        var clock=Clock.systemUTC();var manager=new DataSourceTransactionManager(jdbc.getDataSource());
        var candidates=new com.ksh321.songrecord.api.songs.TjCandidates(token->new com.ksh321.songrecord.api.songs.CandidateVerifier.Verified("FIXTURE",com.ksh321.songrecord.api.songs.CandidateVerifier.Brand.TJ,token,"same title","same artist",clock.instant(),clock.instant().plusSeconds(3600)),clock);
        var creation=new com.ksh321.songrecord.api.songs.SongCreation(jdbc,access,service,new com.ksh321.songrecord.api.revision.CreationGuard(jdbc,access,manager),changes,candidates,clock);
        var json=new tools.jackson.databind.json.JsonMapper();UUID aId=UUID.randomUUID(),bId=UUID.randomUUID();String sharedKey=UUID.randomUUID().toString();
        String aBody=json.writeValueAsString(java.util.Map.of("id",aId.toString(),"source_type","TJ","source_token","00990001"));
        String bBody=aBody.replace(aId.toString(),bId.toString());
        var a=creation.create("Bearer a","device",sharedKey,aBody);var b=creation.create("Bearer b","device",sharedKey,bBody);
        assertThat(a.status()).isEqualTo(201);assertThat(b.status()).isEqualTo(201);
        assertThat(json.readTree(a.body()).get("canonical_song_id").asText()).isEqualTo(aId.toString());assertThat(json.readTree(b.body()).get("canonical_song_id").asText()).isEqualTo(bId.toString());
        assertThat(creation.create("Bearer a","device",sharedKey,aBody)).isEqualTo(a);assertThat(creation.create("Bearer b","device",sharedKey,bBody)).isEqualTo(b);
        jdbc.update("UPDATE song SET lifecycle_state='TRASHED',deleted_at=UTC_TIMESTAMP(3) WHERE id=?",com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(aId));
        String retryA=aBody.replace(aId.toString(),UUID.randomUUID().toString());
        assertThatThrownBy(()->creation.create("Bearer a","device",UUID.randomUUID().toString(),retryA)).isInstanceOfSatisfying(ApiException.class,e->{assertThat(e.code()).isEqualTo("SONG_RESTORE_REQUIRED");assertThat(e.details().get("canonical_song_id")).isEqualTo(aId.toString());});
        var duplicateB=creation.create("Bearer b","device",UUID.randomUUID().toString(),bBody.replace(bId.toString(),UUID.randomUUID().toString()));assertThat(duplicateB.status()).isEqualTo(200);assertThat(json.readTree(duplicateB.body()).get("canonical_song_id").asText()).isEqualTo(bId.toString());
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM song WHERE reserved_tj_number='00990001'",Integer.class)).isEqualTo(2);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM change_log",Integer.class)).isEqualTo(2);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Integer.class)).isEqualTo(3);
        assertThat(jdbc.queryForList("SELECT last_change_seq FROM user_sync_state",Long.class)).containsExactlyInAnyOrder(1L,1L);
    }

    @Test void mysqlDraftCreationWithoutFileSupportsConcurrentUuidAndRollback() throws Exception {
        var changes=syncService();String core=Files.readString(Path.of("src/main/resources/db/migration/V2__account_song_recording.sql"));
        for(String table:java.util.List.of("device","song","recording")){int start=core.indexOf("CREATE TABLE "+table+" (");jdbc.execute(core.substring(start,core.indexOf(';',start)));}
        String sync=Files.readString(Path.of("src/main/resources/db/migration/V6__sync_and_deletion_jobs.sql"));int start=sync.indexOf("CREATE TABLE deletion_ledger (");jdbc.execute(sync.substring(start,sync.indexOf(';',start)));
        // This narrow V2 fixture also needs the V4 nullable condition columns used by DRAFT.
        jdbc.execute("ALTER TABLE recording ADD condition_code VARCHAR(36), ADD condition_name_snapshot VARCHAR(50)");
        var principal=access.revalidate(account);when(access.authenticate("Bearer test","device")).thenReturn(account);when(account.principal()).thenReturn(principal);
        byte[] owner=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(principal.userId()),device=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(principal.deviceId());
        jdbc.update("INSERT INTO device(id,user_id,display_name,last_seen_at) VALUES(?,?,'test',UTC_TIMESTAMP(3))",device,owner);
        var manager=new DataSourceTransactionManager(jdbc.getDataSource());installRecordingQueryKeys();var drafts=new com.ksh321.songrecord.api.recordings.RecordingDrafts(jdbc,access,service,new com.ksh321.songrecord.api.revision.CreationGuard(jdbc,access,manager),changes,Clock.systemUTC());
        var json=new tools.jackson.databind.json.JsonMapper();UUID id=UUID.randomUUID();
        String body=json.writeValueAsString(java.util.Map.of("id",id.toString(),"metadata_state","DRAFT","recorded_at","2026-09-28T07:00:00.123Z","timezone_id","Asia/Seoul","timezone_offset_minutes",540));
        String aKey=UUID.randomUUID().toString(),bKey=UUID.randomUUID().toString();IdempotentMutations.Reply a,b;
        try(var pool=Executors.newFixedThreadPool(2)){
            var ready=new CountDownLatch(2);var go=new CountDownLatch(1);
            var fa=pool.submit(()->{ready.countDown();go.await();return drafts.create("Bearer test","device",aKey,body);});
            var fb=pool.submit(()->{ready.countDown();go.await();return drafts.create("Bearer test","device",bKey,body);});
            try{assertThat(ready.await(5,TimeUnit.SECONDS)).isTrue();}finally{go.countDown();}a=fa.get(15,TimeUnit.SECONDS);b=fb.get(15,TimeUnit.SECONDS);
        }
        assertThat(java.util.List.of(a.status(),b.status())).containsExactlyInAnyOrder(200,201);
        assertThat(drafts.create("Bearer test","device",aKey,body)).isEqualTo(a);assertThat(drafts.create("Bearer test","device",bKey,body)).isEqualTo(b);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM recording",Integer.class)).isEqualTo(1);assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM change_log",Integer.class)).isEqualTo(1);
        assertThat(jdbc.queryForObject("SELECT title_snapshot FROM recording",String.class)).isNull();assertThat(jdbc.queryForObject("SELECT version_code FROM recording",String.class)).isEqualTo("NORMAL");assertThat(jdbc.queryForObject("SELECT origin_device_id FROM recording",byte[].class)).isEqualTo(device);
        jdbc.execute("CREATE TRIGGER reject_draft_log BEFORE INSERT ON change_log FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='injected draft failure'");
        String next=body.replace(id.toString(),UUID.randomUUID().toString()),retry=UUID.randomUUID().toString();
        assertThatThrownBy(()->drafts.create("Bearer test","device",retry,next)).hasRootCauseInstanceOf(java.sql.SQLException.class).hasStackTraceContaining("injected draft failure");
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM recording",Integer.class)).isEqualTo(1);assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Integer.class)).isEqualTo(2);assertThat(jdbc.queryForObject("SELECT last_change_seq FROM user_sync_state",Long.class)).isEqualTo(1);
        jdbc.execute("DROP TRIGGER reject_draft_log");assertThat(drafts.create("Bearer test","device",retry,next).status()).isEqualTo(201);
    }

    @Test void mysqlDeletedSongDraftPreservesIdentityAndNeverRecreatesParent() throws Exception {
        var changes=syncService();String core=Files.readString(Path.of("src/main/resources/db/migration/V2__account_song_recording.sql"));
        for(String table:java.util.List.of("device","song","recording")){int start=core.indexOf("CREATE TABLE "+table+" (");jdbc.execute(core.substring(start,core.indexOf(';',start)));}
        String sync=Files.readString(Path.of("src/main/resources/db/migration/V6__sync_and_deletion_jobs.sql"));int start=sync.indexOf("CREATE TABLE deletion_ledger (");jdbc.execute(sync.substring(start,sync.indexOf(';',start)));
        jdbc.execute("ALTER TABLE recording ADD condition_code VARCHAR(36), ADD condition_name_snapshot VARCHAR(50)");
        var principal=access.revalidate(account);when(access.authenticate("Bearer test","device")).thenReturn(account);when(account.principal()).thenReturn(principal);
        byte[] owner=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(principal.userId()),device=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(principal.deviceId());
        jdbc.update("INSERT INTO device(id,user_id,display_name,last_seen_at) VALUES(?,?,'test',UTC_TIMESTAMP(3))",device,owner);
        var manager=new DataSourceTransactionManager(jdbc.getDataSource());installRecordingQueryKeys();var drafts=new com.ksh321.songrecord.api.recordings.RecordingDrafts(jdbc,access,service,new com.ksh321.songrecord.api.revision.CreationGuard(jdbc,access,manager),changes,Clock.systemUTC());
        var json=new tools.jackson.databind.json.JsonMapper();int expected=0;
        for(String state:java.util.List.of("TRASHED","PURGE_PENDING","PURGED","LEDGER")){
            UUID song=UUID.randomUUID(),recording=UUID.randomUUID();byte[] songBytes=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(song);
            if(state.equals("LEDGER"))jdbc.update("INSERT INTO deletion_ledger(id,user_id,entity_type,entity_id,revision) VALUES(?,?,'SONG',?,2)",com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(UUID.randomUUID()),owner,songBytes);
            else jdbc.update("INSERT INTO song(id,user_id,source_type,title,artist,note,lifecycle_state,deleted_at) VALUES(?,?,'MANUAL','title','artist','',?,UTC_TIMESTAMP(3))",songBytes,owner,state);
            String body=json.writeValueAsString(java.util.Map.of("id",recording.toString(),"metadata_state","DRAFT","song_id",song.toString(),"title_snapshot","offline title","note","keep note","recorded_at","2026-09-28T07:00:00Z","timezone_id","UTC","timezone_offset_minutes",0));
            String requestId=UUID.randomUUID().toString();var reply=drafts.create("Bearer test","device",requestId,body);
            assertThat(reply.status()).isEqualTo(201);assertThat(drafts.create("Bearer test","device",requestId,body)).isEqualTo(reply);
            var saved=json.readTree(reply.body());assertThat(saved.get("id").asText()).isEqualTo(recording.toString());assertThat(saved.get("song_id").isNull()).isTrue();assertThat(saved.get("note").asText()).isEqualTo("keep note");
            assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM recording WHERE song_id IS NULL",Integer.class)).isEqualTo(++expected);
            assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM change_log",Integer.class)).isEqualTo(expected);
            assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Integer.class)).isEqualTo(expected);
            if(state.equals("LEDGER"))assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM song WHERE id=?",Integer.class,songBytes)).isZero();
            else assertThat(jdbc.queryForObject("SELECT lifecycle_state FROM song WHERE id=?",String.class,songBytes)).isEqualTo(state);
        }
    }

    @Test void mysqlSavedTransitionTriggersRaceAndRollbackWithoutCloud() throws Exception {
        var changes=syncService();String core=Files.readString(Path.of("src/main/resources/db/migration/V2__account_song_recording.sql"));
        for(String table:java.util.List.of("device","song","recording","recording_file_spec")){int start=core.indexOf("CREATE TABLE "+table+" (");jdbc.execute(core.substring(start,core.indexOf(';',start)));}
        for(String trigger:java.util.List.of("trg_recording_before_insert","trg_recording_before_update","trg_recording_file_spec_before_update","trg_recording_file_spec_before_delete")){int start=core.indexOf("CREATE TRIGGER "+trigger);jdbc.execute(core.substring(start,core.indexOf("$$",start)));}
        // RevisionChanges exposes V4 fields; no classification API is exercised here.
        jdbc.execute("ALTER TABLE recording ADD condition_code VARCHAR(16), ADD condition_name_snapshot VARCHAR(50)");
        String sync=Files.readString(Path.of("src/main/resources/db/migration/V6__sync_and_deletion_jobs.sql"));int start=sync.indexOf("CREATE TABLE deletion_ledger (");jdbc.execute(sync.substring(start,sync.indexOf(';',start)));
        var principal=access.revalidate(account);when(access.authenticate("Bearer test","device")).thenReturn(account);when(account.principal()).thenReturn(principal);
        byte[] owner=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(principal.userId()),device=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(principal.deviceId());
        jdbc.update("INSERT INTO device(id,user_id,display_name,last_seen_at) VALUES(?,?,'test',UTC_TIMESTAMP(3))",device,owner);
        var manager=new DataSourceTransactionManager(jdbc.getDataSource());installRecordingQueryKeys();var drafts=new com.ksh321.songrecord.api.recordings.RecordingDrafts(jdbc,access,service,new com.ksh321.songrecord.api.revision.CreationGuard(jdbc,access,manager),changes,Clock.systemUTC());
        var saving=new com.ksh321.songrecord.api.recordings.RecordingSaving(jdbc,access,service,new com.ksh321.songrecord.api.revision.RevisionChanges(jdbc,access,manager,Clock.systemUTC()),changes,drafts);
        var json=new tools.jackson.databind.json.JsonMapper();UUID id=UUID.randomUUID();byte[] recording=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(id);
        String draft=json.writeValueAsString(java.util.Map.of("id",id.toString(),"metadata_state","DRAFT","recorded_at","2026-09-28T07:00:00Z","timezone_id","UTC","timezone_offset_minutes",0));
        assertThat(drafts.create("Bearer test","device",UUID.randomUUID().toString(),draft).status()).isEqualTo(201);
        var file=java.util.Map.of("size_bytes",6291456,"duration_ms",361000,"sha256","a".repeat(64),"codec","AAC_LC","sample_rate",48000,"channels",1,"capture_integrity","VALIDATED");
        String body=json.writeValueAsString(java.util.Map.of("base_revision",1,"metadata_state","SAVED","title_snapshot","title","artist_snapshot","artist","key_mode","ORIGINAL","key_shift",0,"file",file));
        assertThatThrownBy(()->jdbc.update("UPDATE recording SET title_snapshot='t',artist_snapshot='a',key_mode='ORIGINAL',key_shift=0,metadata_state='SAVED' WHERE id=?",recording)).hasRootCauseInstanceOf(java.sql.SQLException.class).hasStackTraceContaining("file specification is required");
        jdbc.execute("CREATE TRIGGER reject_saved_log BEFORE INSERT ON change_log FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='injected saved failure'");String aKey=UUID.randomUUID().toString();
        assertThatThrownBy(()->saving.save("Bearer test","device",aKey,id.toString(),body)).hasRootCauseInstanceOf(java.sql.SQLException.class).hasStackTraceContaining("injected saved failure");
        assertThat(jdbc.queryForObject("SELECT metadata_state FROM recording",String.class)).isEqualTo("DRAFT");assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM recording_file_spec",Integer.class)).isZero();assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Integer.class)).isEqualTo(1);
        jdbc.execute("DROP TRIGGER reject_saved_log");String bKey=UUID.randomUUID().toString();Object a,b;
        try(var pool=Executors.newFixedThreadPool(2)){
            var ready=new CountDownLatch(2);var go=new CountDownLatch(1);
            var fa=pool.submit(()->{ready.countDown();go.await();try{return (Object)saving.save("Bearer test","device",aKey,id.toString(),body);}catch(ApiException e){return e;}});
            var fb=pool.submit(()->{ready.countDown();go.await();try{return (Object)saving.save("Bearer test","device",bKey,id.toString(),body);}catch(ApiException e){return e;}});
            try{assertThat(ready.await(5,TimeUnit.SECONDS)).isTrue();}finally{go.countDown();}a=fa.get(15,TimeUnit.SECONDS);b=fb.get(15,TimeUnit.SECONDS);
        }
        var winner=(IdempotentMutations.Reply)(a instanceof IdempotentMutations.Reply?a:b);var loser=(ApiException)(a instanceof ApiException?a:b);assertThat(winner.status()).isEqualTo(200);assertThat(loser.code()).isEqualTo("REVISION_CONFLICT");
        assertThat(saving.save("Bearer test","device",a instanceof IdempotentMutations.Reply?aKey:bKey,id.toString(),body)).isEqualTo(winner);
        assertThat(jdbc.queryForObject("SELECT revision FROM recording",Long.class)).isEqualTo(2);assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM recording_file_spec",Integer.class)).isEqualTo(1);assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM change_log",Integer.class)).isEqualTo(2);
        assertThatThrownBy(()->jdbc.update("UPDATE recording SET metadata_state='DRAFT' WHERE id=?",recording)).hasRootCauseInstanceOf(java.sql.SQLException.class).hasStackTraceContaining("cannot return to DRAFT");
        assertThatThrownBy(()->jdbc.update("UPDATE recording_file_spec SET size_bytes=1 WHERE recording_id=?",recording)).hasRootCauseInstanceOf(java.sql.SQLException.class).hasStackTraceContaining("immutable");
        assertThatThrownBy(()->jdbc.update("DELETE FROM recording_file_spec WHERE recording_id=?",recording)).hasRootCauseInstanceOf(java.sql.SQLException.class).hasStackTraceContaining("cannot be deleted");
    }

    void installRecordingQueryKeys() throws Exception {
        String ddl=Files.readString(Path.of("src/main/resources/db/migration/V12__recording_query_keys.sql"));int start=ddl.indexOf("CREATE TABLE recording_query_key (");jdbc.execute(ddl.substring(start,ddl.indexOf(';',start)));
    }

    @Test void mysqlRecordingListingMatchesRulesOnFullyMigratedDatabase() throws Exception {
        String name=database+"_lists";admin.execute("CREATE DATABASE "+name);
        try {
            var ds=new DriverManagerDataSource("jdbc:mysql://127.0.0.1:3306/"+name+"?allowPublicKeyRetrieval=true&useSSL=false","root",System.getenv("P07_MYSQL_PASSWORD"));
            var flyway=org.flywaydb.core.Flyway.configure().dataSource(ds).locations("classpath:db/migration").load();flyway.migrate();flyway.validate();
            var db=new JdbcTemplate(ds);var principal=access.revalidate(account);byte[] owner=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(principal.userId()),device=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(principal.deviceId());
            db.update("INSERT INTO app_user(id) VALUES(?)",owner);db.update("INSERT INTO user_sync_state(user_id) VALUES(?)",owner);db.update("INSERT INTO device(id,user_id,display_name,last_seen_at) VALUES(?,?,'test',UTC_TIMESTAMP(3))",device,owner);
            var pages=new com.ksh321.songrecord.api.pagination.KeysetPages(db,access,new DataSourceTransactionManager(ds),new com.ksh321.songrecord.api.pagination.PageCursor(new byte[32],Clock.systemUTC(),java.time.Duration.ofMinutes(30)));
            com.ksh321.songrecord.api.recordings.RecordingListingDatabaseChecks.verify(db,pages,account,principal.userId(),principal.deviceId());
            assertThat(flyway.migrate().migrationsExecuted).isZero();
        }finally{admin.execute("DROP DATABASE "+name);}
    }

    @Test void mysqlRecordingEditingIsAtomicAndPreservesHistoricalNames() throws Exception {
        String name=database+"_edits";admin.execute("CREATE DATABASE "+name);
        try {
            var ds=new DriverManagerDataSource("jdbc:mysql://127.0.0.1:3306/"+name+"?allowPublicKeyRetrieval=true&useSSL=false","root",System.getenv("P07_MYSQL_PASSWORD"));
            var flyway=org.flywaydb.core.Flyway.configure().dataSource(ds).locations("classpath:db/migration").load();flyway.migrate();flyway.validate();
            var db=new JdbcTemplate(ds);var principal=access.revalidate(account);
            when(account.principal()).thenReturn(principal);when(access.authenticate("Bearer test",principal.deviceId().toString())).thenReturn(account);
            byte[] owner=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(principal.userId()),device=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(principal.deviceId());
            db.update("INSERT INTO app_user(id) VALUES(?)",owner);db.update("INSERT INTO user_sync_state(user_id) VALUES(?)",owner);db.update("INSERT INTO device(id,user_id,display_name,last_seen_at) VALUES(?,?,'test',UTC_TIMESTAMP(3))",device,owner);
            var manager=new DataSourceTransactionManager(ds);var clock=Clock.systemUTC();
            var mutations=new IdempotentMutations(db,access,manager,clock);
            var changes=new com.ksh321.songrecord.api.sync.AccountChanges(db,access,manager,clock);
            var revisions=new com.ksh321.songrecord.api.revision.RevisionChanges(db,access,manager,clock);
            var drafts=new com.ksh321.songrecord.api.recordings.RecordingDrafts(db,access,mutations,new com.ksh321.songrecord.api.revision.CreationGuard(db,access,manager),changes,clock);
            var saving=new com.ksh321.songrecord.api.recordings.RecordingSaving(db,access,mutations,revisions,changes,drafts);
            var jobs=new com.ksh321.songrecord.api.jobs.JobQueue(db,access,manager,clock,java.time.Duration.ofMinutes(2),5);
            var editing=new com.ksh321.songrecord.api.recordings.RecordingEditing(db,access,mutations,revisions,changes,drafts,saving,jobs);
            com.ksh321.songrecord.api.recordings.RecordingEditingDatabaseChecks.verify(db,drafts,editing,"Bearer test",principal.deviceId().toString(),principal.userId());
            assertThat(flyway.migrate().migrationsExecuted).isZero();
        } finally {admin.execute("DROP DATABASE "+name);}
    }

    @Test void mysqlRecordingRatingIsAtomicAndIndependentOfSongTier() throws Exception {
        String name=database+"_ratings";admin.execute("CREATE DATABASE "+name);
        try {
            var ds=new DriverManagerDataSource("jdbc:mysql://127.0.0.1:3306/"+name+"?allowPublicKeyRetrieval=true&useSSL=false","root",System.getenv("P07_MYSQL_PASSWORD"));
            var flyway=org.flywaydb.core.Flyway.configure().dataSource(ds).locations("classpath:db/migration").load();flyway.migrate();flyway.validate();
            var db=new JdbcTemplate(ds);var principal=access.revalidate(account);
            when(account.principal()).thenReturn(principal);when(access.authenticate("Bearer test",principal.deviceId().toString())).thenReturn(account);
            byte[] owner=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(principal.userId()),device=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(principal.deviceId());
            db.update("INSERT INTO app_user(id) VALUES(?)",owner);db.update("INSERT INTO user_sync_state(user_id) VALUES(?)",owner);db.update("INSERT INTO device(id,user_id,display_name,last_seen_at) VALUES(?,?,'test',UTC_TIMESTAMP(3))",device,owner);
            var manager=new DataSourceTransactionManager(ds);var clock=Clock.systemUTC();
            var mutations=new IdempotentMutations(db,access,manager,clock);
            var changes=new com.ksh321.songrecord.api.sync.AccountChanges(db,access,manager,clock);
            var revisions=new com.ksh321.songrecord.api.revision.RevisionChanges(db,access,manager,clock);
            var drafts=new com.ksh321.songrecord.api.recordings.RecordingDrafts(db,access,mutations,new com.ksh321.songrecord.api.revision.CreationGuard(db,access,manager),changes,clock);
            var saving=new com.ksh321.songrecord.api.recordings.RecordingSaving(db,access,mutations,revisions,changes,drafts);
            var jobs=new com.ksh321.songrecord.api.jobs.JobQueue(db,access,manager,clock,java.time.Duration.ofMinutes(2),5);
            var editing=new com.ksh321.songrecord.api.recordings.RecordingEditing(db,access,mutations,revisions,changes,drafts,saving,jobs);
            var rating=new com.ksh321.songrecord.api.recordings.RecordingRating(db,access,mutations,revisions,changes,editing,jobs);
            com.ksh321.songrecord.api.recordings.RecordingRatingDatabaseChecks.verify(db,drafts,editing,rating,"Bearer test",principal.deviceId().toString(),principal.userId());
            assertThat(flyway.migrate().migrationsExecuted).isZero();
        } finally {admin.execute("DROP DATABASE "+name);}
    }

    @Test void mysqlRecordingRelinkClearsCompositeForeignKeysAtomically() throws Exception {
        String name=database+"_relinks";admin.execute("CREATE DATABASE "+name);
        try {
            var ds=new DriverManagerDataSource("jdbc:mysql://127.0.0.1:3306/"+name+"?allowPublicKeyRetrieval=true&useSSL=false","root",System.getenv("P07_MYSQL_PASSWORD"));
            var flyway=org.flywaydb.core.Flyway.configure().dataSource(ds).locations("classpath:db/migration").load();flyway.migrate();flyway.validate();
            var db=new JdbcTemplate(ds);var principal=access.revalidate(account);
            when(account.principal()).thenReturn(principal);when(access.authenticate("Bearer test",principal.deviceId().toString())).thenReturn(account);
            byte[] owner=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(principal.userId()),device=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(principal.deviceId());
            db.update("INSERT INTO app_user(id) VALUES(?)",owner);db.update("INSERT INTO user_sync_state(user_id) VALUES(?)",owner);db.update("INSERT INTO device(id,user_id,display_name,last_seen_at) VALUES(?,?,'test',UTC_TIMESTAMP(3))",device,owner);
            var manager=new DataSourceTransactionManager(ds);var clock=Clock.systemUTC();
            var mutations=new IdempotentMutations(db,access,manager,clock);
            var changes=new com.ksh321.songrecord.api.sync.AccountChanges(db,access,manager,clock);
            var revisions=new com.ksh321.songrecord.api.revision.RevisionChanges(db,access,manager,clock);
            var drafts=new com.ksh321.songrecord.api.recordings.RecordingDrafts(db,access,mutations,new com.ksh321.songrecord.api.revision.CreationGuard(db,access,manager),changes,clock);
            var saving=new com.ksh321.songrecord.api.recordings.RecordingSaving(db,access,mutations,revisions,changes,drafts);
            var jobs=new com.ksh321.songrecord.api.jobs.JobQueue(db,access,manager,clock,java.time.Duration.ofMinutes(2),5);
            var editing=new com.ksh321.songrecord.api.recordings.RecordingEditing(db,access,mutations,revisions,changes,drafts,saving,jobs);
            var linking=new com.ksh321.songrecord.api.recordings.RecordingLinking(db,access,mutations,revisions,changes,editing,jobs);
            com.ksh321.songrecord.api.recordings.RecordingLinkingDatabaseChecks.verify(db,drafts,editing,linking,"Bearer test",principal.deviceId().toString(),principal.userId(),jobs);
            assertThat(flyway.migrate().migrationsExecuted).isZero();
        } finally {admin.execute("DROP DATABASE "+name);}
    }

    @Test void mysqlTagsPreserveHistoricalNamesAndEnforceActiveUniqueness() throws Exception {
        String name=database+"_tags";admin.execute("CREATE DATABASE "+name);
        try {
            var ds=new DriverManagerDataSource("jdbc:mysql://127.0.0.1:3306/"+name+"?allowPublicKeyRetrieval=true&useSSL=false","root",System.getenv("P07_MYSQL_PASSWORD"));
            var flyway=org.flywaydb.core.Flyway.configure().dataSource(ds).locations("classpath:db/migration").load();flyway.migrate();flyway.validate();
            var db=new JdbcTemplate(ds);var principal=access.revalidate(account);
            when(account.principal()).thenReturn(principal);when(access.authenticate("Bearer test",principal.deviceId().toString())).thenReturn(account);
            byte[] owner=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(principal.userId()),device=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(principal.deviceId());
            db.update("INSERT INTO app_user(id) VALUES(?)",owner);db.update("INSERT INTO user_sync_state(user_id) VALUES(?)",owner);db.update("INSERT INTO device(id,user_id,display_name,last_seen_at) VALUES(?,?,'test',UTC_TIMESTAMP(3))",device,owner);
            var manager=new DataSourceTransactionManager(ds);var clock=Clock.systemUTC();
            var mutations=new IdempotentMutations(db,access,manager,clock);
            var changes=new com.ksh321.songrecord.api.sync.AccountChanges(db,access,manager,clock);
            var revisions=new com.ksh321.songrecord.api.revision.RevisionChanges(db,access,manager,clock);
            var drafts=new com.ksh321.songrecord.api.recordings.RecordingDrafts(db,access,mutations,new com.ksh321.songrecord.api.revision.CreationGuard(db,access,manager),changes,clock);
            var saving=new com.ksh321.songrecord.api.recordings.RecordingSaving(db,access,mutations,revisions,changes,drafts);
            var jobs=new com.ksh321.songrecord.api.jobs.JobQueue(db,access,manager,clock,java.time.Duration.ofMinutes(2),5);
            var editing=new com.ksh321.songrecord.api.recordings.RecordingEditing(db,access,mutations,revisions,changes,drafts,saving,jobs);
            var pages=new com.ksh321.songrecord.api.pagination.KeysetPages(db,access,manager,new com.ksh321.songrecord.api.pagination.PageCursor(new byte[32],clock,java.time.Duration.ofMinutes(30)));
            var tags=new com.ksh321.songrecord.api.classifications.TagService(db,access,mutations,new com.ksh321.songrecord.api.revision.CreationGuard(db,access,manager),revisions,changes,pages,clock);
            com.ksh321.songrecord.api.classifications.TagDatabaseChecks.verify(db,tags,drafts,editing,"Bearer test",principal.deviceId().toString(),principal.userId());
            assertThat(flyway.migrate().migrationsExecuted).isZero();
        } finally {admin.execute("DROP DATABASE "+name);}
    }

    @Test void mysqlConditionsPreserveV15DataAndEnforceD06AfterUpgrade() throws Exception {
        String name=database+"_conditions";admin.execute("CREATE DATABASE "+name);
        try {
            var ds=new DriverManagerDataSource("jdbc:mysql://127.0.0.1:3306/"+name+"?allowPublicKeyRetrieval=true&useSSL=false","root",System.getenv("P07_MYSQL_PASSWORD"));
            var flyway=org.flywaydb.core.Flyway.configure().dataSource(ds).locations("classpath:db/migration").target("15").load();flyway.migrate();flyway.validate();
            var db=new JdbcTemplate(ds);var principal=access.revalidate(account);
            when(account.principal()).thenReturn(principal);when(access.authenticate("Bearer test",principal.deviceId().toString())).thenReturn(account);
            byte[] owner=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(principal.userId()),device=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(principal.deviceId());
            db.update("INSERT INTO app_user(id) VALUES(?)",owner);db.update("INSERT INTO user_sync_state(user_id) VALUES(?)",owner);db.update("INSERT INTO device(id,user_id,display_name,last_seen_at) VALUES(?,?,'test',UTC_TIMESTAMP(3))",device,owner);
            var manager=new DataSourceTransactionManager(ds);var clock=Clock.systemUTC();
            var mutations=new IdempotentMutations(db,access,manager,clock);
            var changes=new com.ksh321.songrecord.api.sync.AccountChanges(db,access,manager,clock);
            var revisions=new com.ksh321.songrecord.api.revision.RevisionChanges(db,access,manager,clock);
            var drafts=new com.ksh321.songrecord.api.recordings.RecordingDrafts(db,access,mutations,new com.ksh321.songrecord.api.revision.CreationGuard(db,access,manager),changes,clock);
            var saving=new com.ksh321.songrecord.api.recordings.RecordingSaving(db,access,mutations,revisions,changes,drafts);
            var jobs=new com.ksh321.songrecord.api.jobs.JobQueue(db,access,manager,clock,java.time.Duration.ofMinutes(2),5);
            var editing=new com.ksh321.songrecord.api.recordings.RecordingEditing(db,access,mutations,revisions,changes,drafts,saving,jobs);
            var pages=new com.ksh321.songrecord.api.pagination.KeysetPages(db,access,manager,new com.ksh321.songrecord.api.pagination.PageCursor(new byte[32],clock,java.time.Duration.ofMinutes(30)));
            UUID legacy=UUID.randomUUID(),custom=UUID.randomUUID();
            drafts.create("Bearer test",principal.deviceId().toString(),UUID.randomUUID().toString(),"{\"id\":\""+legacy+"\",\"metadata_state\":\"DRAFT\",\"recorded_at\":\"2026-09-28T07:00:00Z\",\"timezone_id\":\"UTC\",\"timezone_offset_minutes\":0}");
            db.update("INSERT INTO condition_definition(id,user_id,code,name,normalized_name_key) VALUES(?,?,?,?,?)",com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(custom),owner,custom.toString(),"😀".repeat(50),new byte[]{1});
            db.update("UPDATE recording SET condition_code=? WHERE id=?",custom.toString(),com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(legacy));
            db.update("UPDATE condition_definition SET name='과거 수정',archived_at=UTC_TIMESTAMP(3) WHERE code='GOOD' OR code=?",custom.toString());
            var oldRecordings=db.queryForList("SELECT * FROM recording ORDER BY id");
            var oldDefinitions=db.queryForList("SELECT * FROM condition_definition ORDER BY id");
            flyway=org.flywaydb.core.Flyway.configure().dataSource(ds).locations("classpath:db/migration").load();flyway.migrate();flyway.validate();
            assertThat(db.queryForList("SELECT * FROM recording ORDER BY id")).usingRecursiveComparison().isEqualTo(oldRecordings);
            assertThat(db.queryForList("SELECT * FROM condition_definition ORDER BY id")).usingRecursiveComparison().isEqualTo(oldDefinitions);
            assertThat(db.queryForObject("SELECT condition_name_snapshot FROM recording_condition_history WHERE recording_id=?",String.class,com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(legacy))).isEqualTo("😀".repeat(50));
            db.update("UPDATE recording SET condition_name_snapshot='tamper' WHERE id=?",com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(legacy));
            assertThat(db.queryForObject("SELECT condition_name_snapshot FROM recording WHERE id=?",String.class,com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(legacy))).isEqualTo("😀".repeat(50));
            for(String assignment:java.util.List.of("condition_name_snapshot='tamper'","condition_code='BAD'","source_revision=999")) {
                assertThatThrownBy(()->db.update("UPDATE recording_condition_history SET "+assignment+" WHERE recording_id=?",com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(legacy))).isInstanceOf(org.springframework.dao.DataAccessException.class);
            }
            assertThat(db.queryForObject("SELECT condition_name_snapshot FROM recording_condition_history WHERE recording_id=? AND source_revision=1",String.class,com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(legacy))).isEqualTo("😀".repeat(50));
            assertThatThrownBy(()->db.update("DELETE FROM recording_condition_history WHERE recording_id=?",com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(legacy))).isInstanceOf(org.springframework.dao.DataAccessException.class);
            assertThat(db.queryForObject("SELECT COUNT(*) FROM recording_condition_history WHERE recording_id=?",Integer.class,com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(legacy))).isEqualTo(1);
            var conditions=new com.ksh321.songrecord.api.classifications.ConditionService(access);
            com.ksh321.songrecord.api.classifications.ConditionDatabaseChecks.verify(db,conditions,drafts,editing,"Bearer test",principal.deviceId().toString(),principal.userId(),legacy);
            assertThatThrownBy(()->db.update("UPDATE recording SET condition_code=? WHERE id=?",custom.toString(),com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(legacy))).isInstanceOf(org.springframework.dao.DataAccessException.class);
            assertThat(flyway.migrate().migrationsExecuted).isZero();
            // Isolated fixture: a retained PURGED metadata row keeps its history. Physical
            // owner cleanup cascades after other references are cleaned, never independently.
            db.update("UPDATE recording SET lifecycle_state='PURGED',deleted_at=UTC_TIMESTAMP(3) WHERE id=?",com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(legacy));
            assertThat(db.queryForObject("SELECT COUNT(*) FROM recording_condition_history WHERE recording_id=?",Integer.class,com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(legacy))).isGreaterThan(0);
            db.update("DELETE FROM recording_query_key WHERE recording_id=?",com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(legacy));
            db.update("DELETE FROM recording WHERE id=?",com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(legacy));
            assertThat(db.queryForObject("SELECT COUNT(*) FROM recording_condition_history WHERE recording_id=?",Integer.class,com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(legacy))).isZero();
        } finally {admin.execute("DROP DATABASE "+name);}
    }

    @Test void mysqlStorageRestrictionsDoNotBlockRecordingMetadata() throws Exception {
        String name=database+"_metadata_boundary";admin.execute("CREATE DATABASE "+name);
        try {
            var ds=new DriverManagerDataSource("jdbc:mysql://127.0.0.1:3306/"+name+"?allowPublicKeyRetrieval=true&useSSL=false","root",System.getenv("P07_MYSQL_PASSWORD"));
            var flyway=org.flywaydb.core.Flyway.configure().dataSource(ds).locations("classpath:db/migration").load();flyway.migrate();flyway.validate();
            var db=new JdbcTemplate(ds);var principal=access.revalidate(account);
            when(account.principal()).thenReturn(principal);when(access.authenticate("Bearer test",principal.deviceId().toString())).thenReturn(account);
            byte[] owner=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(principal.userId()),device=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(principal.deviceId());
            db.update("INSERT INTO app_user(id) VALUES(?)",owner);db.update("INSERT INTO user_sync_state(user_id) VALUES(?)",owner);db.update("INSERT INTO device(id,user_id,display_name,last_seen_at) VALUES(?,?,'test',UTC_TIMESTAMP(3))",device,owner);
            var manager=new DataSourceTransactionManager(ds);var clock=Clock.systemUTC();
            var mutations=new IdempotentMutations(db,access,manager,clock);
            var changes=new com.ksh321.songrecord.api.sync.AccountChanges(db,access,manager,clock);
            var revisions=new com.ksh321.songrecord.api.revision.RevisionChanges(db,access,manager,clock);
            var drafts=new com.ksh321.songrecord.api.recordings.RecordingDrafts(db,access,mutations,new com.ksh321.songrecord.api.revision.CreationGuard(db,access,manager),changes,clock);
            var saving=new com.ksh321.songrecord.api.recordings.RecordingSaving(db,access,mutations,revisions,changes,drafts);
            var jobs=new com.ksh321.songrecord.api.jobs.JobQueue(db,access,manager,clock,java.time.Duration.ofMinutes(2),5);
            var editing=new com.ksh321.songrecord.api.recordings.RecordingEditing(db,access,mutations,revisions,changes,drafts,saving,jobs);
            var pages=new com.ksh321.songrecord.api.pagination.KeysetPages(db,access,manager,new com.ksh321.songrecord.api.pagination.PageCursor(new byte[32],clock,java.time.Duration.ofMinutes(30)));
            var rating=new com.ksh321.songrecord.api.recordings.RecordingRating(db,access,mutations,revisions,changes,editing,jobs);
            var linking=new com.ksh321.songrecord.api.recordings.RecordingLinking(db,access,mutations,revisions,changes,editing,jobs);
            var listing=new com.ksh321.songrecord.api.recordings.RecordingListing(access,pages);
            for(String reason:java.util.List.of("QUOTA","PIN_LIMIT","BUDGET"))
                com.ksh321.songrecord.api.recordings.RecordingMetadataBoundaryChecks.verify(db,drafts,editing,rating,linking,listing,"Bearer test",principal.deviceId().toString(),principal.userId(),reason);
            assertThat(flyway.migrate().migrationsExecuted).isZero();
        } finally {admin.execute("DROP DATABASE "+name);}
    }
    @Test void mysqlRetentionCandidatesRespectAccountSongAndCompletedFileBoundaries() {
        String name=database+"_retention_candidates";admin.execute("CREATE DATABASE "+name);
        try {
            var ds=new DriverManagerDataSource("jdbc:mysql://127.0.0.1:3306/"+name+"?allowPublicKeyRetrieval=true&useSSL=false&connectionTimeZone=UTC","root",System.getenv("P07_MYSQL_PASSWORD"));
            var flyway=org.flywaydb.core.Flyway.configure().dataSource(ds).locations("classpath:db/migration").load();
            flyway.migrate();flyway.validate();
            com.ksh321.songrecord.api.retention.RetentionCandidateDatabaseChecks.verify(new JdbcTemplate(ds));
            com.ksh321.songrecord.api.retention.RetentionCandidateDatabaseChecks.verifyRepresentative(new JdbcTemplate(ds));
            com.ksh321.songrecord.api.retention.RetentionCandidateDatabaseChecks.verifyLatest(new JdbcTemplate(ds));
            com.ksh321.songrecord.api.retention.RetentionCandidateDatabaseChecks.verifyLowestTier(new JdbcTemplate(ds));
            com.ksh321.songrecord.api.retention.RetentionCandidateDatabaseChecks.verifySelectionStore(new JdbcTemplate(ds));
            com.ksh321.songrecord.api.retention.RetentionExampleDatabaseChecks.verify(new JdbcTemplate(ds));
            com.ksh321.songrecord.api.retention.RetentionJobDatabaseChecks.verify(new JdbcTemplate(ds));
            com.ksh321.songrecord.api.retention.RetentionJobDatabaseChecks.verifyPins(new JdbcTemplate(ds));
            com.ksh321.songrecord.api.retention.RetentionJobDatabaseChecks.verifyRelease(new JdbcTemplate(ds));
            assertThat(flyway.migrate().migrationsExecuted).isZero();
        } finally {admin.execute("DROP DATABASE "+name);}
    }

    @Test void mysqlUploadReservationsEnforcePersonalAndGlobalCapacityAtomically() throws Exception {
        String name=database+"_upload_capacity";admin.execute("CREATE DATABASE "+name);
        try {
            var ds=new DriverManagerDataSource("jdbc:mysql://127.0.0.1:3306/"+name+"?allowPublicKeyRetrieval=true&useSSL=false&connectionTimeZone=UTC","root",System.getenv("P07_MYSQL_PASSWORD"));
            var flyway=org.flywaydb.core.Flyway.configure().dataSource(ds).locations("classpath:db/migration").load();flyway.migrate();flyway.validate();
            com.ksh321.songrecord.api.retention.UploadReservationDatabaseChecks.verify(new JdbcTemplate(ds));
        }finally{admin.execute("DROP DATABASE "+name);}
    }
    @Test void mysqlUploadApprovalChecksCurrentPolicyAndSharedLimits() throws Exception {
        String name=database+"_upload_approval";admin.execute("CREATE DATABASE "+name);
        try {
            var ds=new DriverManagerDataSource("jdbc:mysql://127.0.0.1:3306/"+name+"?allowPublicKeyRetrieval=true&useSSL=false&connectionTimeZone=UTC","root",System.getenv("P07_MYSQL_PASSWORD"));
            var flyway=org.flywaydb.core.Flyway.configure().dataSource(ds).locations("classpath:db/migration").load();flyway.migrate();flyway.validate();
            com.ksh321.songrecord.api.retention.UploadApprovalDatabaseChecks.verify(new JdbcTemplate(ds));
        }finally{admin.execute("DROP DATABASE "+name);}
    }
    @Test void mysqlUploadCompletionAndVerificationBytes()throws Exception{
        String name="p1206_"+java.util.UUID.randomUUID().toString().replace("-","");admin.execute("CREATE DATABASE "+name);
        try{
            var ds=new DriverManagerDataSource("jdbc:mysql://127.0.0.1:3306/"+name+"?allowPublicKeyRetrieval=true&useSSL=false&connectionTimeZone=UTC","root",System.getenv("P07_MYSQL_PASSWORD"));
            var flyway=org.flywaydb.core.Flyway.configure().dataSource(ds).locations("classpath:db/migration").load();flyway.migrate();flyway.validate();
            com.ksh321.songrecord.api.retention.UploadCompletionDatabaseChecks.verify(new JdbcTemplate(ds));
        }finally{admin.execute("DROP DATABASE "+name);}
    }

    @Test void mysqlVerifiedUploadFinalization()throws Exception {
        String name=database+"_upload_finalization";admin.execute("CREATE DATABASE "+name);
        try {var ds=new DriverManagerDataSource("jdbc:mysql://127.0.0.1:3306/"+name+"?allowPublicKeyRetrieval=true&useSSL=false&connectionTimeZone=UTC","root",System.getenv("P07_MYSQL_PASSWORD"));org.flywaydb.core.Flyway.configure().dataSource(ds).locations("classpath:db/migration").load().migrate();com.ksh321.songrecord.api.retention.UploadFinalizationDatabaseChecks.verify(new JdbcTemplate(ds));com.ksh321.songrecord.api.retention.UploadRecoveryDatabaseChecks.verify(new JdbcTemplate(ds));}finally{admin.execute("DROP DATABASE "+name);}
    }
    @Test void mysqlUploadObjectInventoryGuard()throws Exception {
        String name=database+"_upload_inventory";admin.execute("CREATE DATABASE "+name);
        try {var ds=new DriverManagerDataSource("jdbc:mysql://127.0.0.1:3306/"+name+"?allowPublicKeyRetrieval=true&useSSL=false&connectionTimeZone=UTC","root",System.getenv("P07_MYSQL_PASSWORD"));org.flywaydb.core.Flyway.configure().dataSource(ds).locations("classpath:db/migration").load().migrate();com.ksh321.songrecord.api.retention.UploadInventoryDatabaseChecks.verify(new JdbcTemplate(ds));}finally{admin.execute("DROP DATABASE "+name);}
    }
    @Test void mysqlFailedUploadPreservesPreviousServerFiles()throws Exception {
        String name=database+"_upload_failures";admin.execute("CREATE DATABASE "+name);
        try {var ds=new DriverManagerDataSource("jdbc:mysql://127.0.0.1:3306/"+name+"?allowPublicKeyRetrieval=true&useSSL=false&connectionTimeZone=UTC","root",System.getenv("P07_MYSQL_PASSWORD"));org.flywaydb.core.Flyway.configure().dataSource(ds).locations("classpath:db/migration").load().migrate();com.ksh321.songrecord.api.retention.UploadFailureDatabaseChecks.verify(new JdbcTemplate(ds));}finally{admin.execute("DROP DATABASE "+name);}
    }

    @Test void mysqlCleanupConfirmationIdentityAndExpiry() throws Exception {
        String name=database+"_cleanup_confirm";admin.execute("CREATE DATABASE "+name);
        try {var ds=new DriverManagerDataSource("jdbc:mysql://127.0.0.1:3306/"+name+"?allowPublicKeyRetrieval=true&useSSL=false&connectionTimeZone=UTC","root",System.getenv("P07_MYSQL_PASSWORD"));org.flywaydb.core.Flyway.configure().dataSource(ds).locations("classpath:db/migration").load().migrate();com.ksh321.songrecord.api.retention.CleanupConfirmationDatabaseChecks.verify(new JdbcTemplate(ds));}finally{admin.execute("DROP DATABASE "+name);}
    }
    @Test void mysqlCleanupAuthorizationSerializesPinsAndDeletion() throws Exception {
        String name=database+"_cleanup_confirm";admin.execute("CREATE DATABASE "+name);
        try {var ds=new DriverManagerDataSource("jdbc:mysql://127.0.0.1:3306/"+name+"?allowPublicKeyRetrieval=true&useSSL=false&connectionTimeZone=UTC","root",System.getenv("P07_MYSQL_PASSWORD"));org.flywaydb.core.Flyway.configure().dataSource(ds).locations("classpath:db/migration").load().migrate();com.ksh321.songrecord.api.retention.CleanupAuthorizationDatabaseChecks.verify(new JdbcTemplate(ds));}finally{admin.execute("DROP DATABASE "+name);}
    }
    @Test void mysqlCleanupDeletionConfirmsAbsenceAndDebitsOnce() throws Exception {
        String name=database+"_cleanup_delete";admin.execute("CREATE DATABASE "+name);
        try {var ds=new DriverManagerDataSource("jdbc:mysql://127.0.0.1:3306/"+name+"?allowPublicKeyRetrieval=true&useSSL=false&connectionTimeZone=UTC","root",System.getenv("P07_MYSQL_PASSWORD"));org.flywaydb.core.Flyway.configure().dataSource(ds).locations("classpath:db/migration").load().migrate();com.ksh321.songrecord.api.retention.CleanupDeletionDatabaseChecks.verify(new JdbcTemplate(ds));}finally{admin.execute("DROP DATABASE "+name);}
    }
    @Test void mysqlCleanupCandidateReasons() throws Exception {
        String name=database+"_cleanup_candidates";admin.execute("CREATE DATABASE "+name);
        try {var ds=new DriverManagerDataSource("jdbc:mysql://127.0.0.1:3306/"+name+"?allowPublicKeyRetrieval=true&useSSL=false&connectionTimeZone=UTC","root",System.getenv("P07_MYSQL_PASSWORD"));org.flywaydb.core.Flyway.configure().dataSource(ds).locations("classpath:db/migration").load().migrate();com.ksh321.songrecord.api.retention.CleanupCandidateDatabaseChecks.verify(new JdbcTemplate(ds));}finally{admin.execute("DROP DATABASE "+name);}
    }
    @Test void mysqlAutomaticReplacementProtection()throws Exception {
        String name=database+"_replacement_protection";admin.execute("CREATE DATABASE "+name);
        try {var ds=new DriverManagerDataSource("jdbc:mysql://127.0.0.1:3306/"+name+"?allowPublicKeyRetrieval=true&useSSL=false&connectionTimeZone=UTC","root",System.getenv("P07_MYSQL_PASSWORD"));org.flywaydb.core.Flyway.configure().dataSource(ds).locations("classpath:db/migration").load().migrate();com.ksh321.songrecord.api.retention.ReplacementProtectionDatabaseChecks.verify(new JdbcTemplate(ds));}finally{admin.execute("DROP DATABASE "+name);}
    }

}
