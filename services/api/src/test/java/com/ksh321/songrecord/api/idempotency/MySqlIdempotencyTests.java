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
}
