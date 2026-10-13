package com.ksh321.songrecord.api.auth;
import com.ksh321.songrecord.api.web.ApiException;
import java.time.Clock;
import java.util.ArrayList;
import java.util.concurrent.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;
/** Same last-seat race and existing-account assertions on H2 and migrated InnoDB. */
public final class OperationsRegistrationDatabaseChecks {
 public static void verify(JdbcTemplate db)throws Exception {
  var manager=new DataSourceTransactionManager(db.getDataSource());
        var policy=new com.ksh321.songrecord.api.operations.OperationsPolicy(2,1,100,500,100,1,1,100,1,5);
        var bounded=new AccountRegistrationService(db,manager,Clock.systemUTC(),policy);
        var first=bounded.register(new VerifiedProviderIdentity("KAKAO","123"),null,"first");
        try(var pool=Executors.newFixedThreadPool(2)){
            var ready=new CountDownLatch(2);var go=new CountDownLatch(1);
            var results=new ArrayList<java.util.concurrent.Future<String>>();
            for(var subject:new String[]{"second","third"})results.add(pool.submit(()->{ready.countDown();go.await();try{bounded.register(new VerifiedProviderIdentity("GOOGLE",subject),null,"race");return "CREATED";}catch(ApiException e){return e.code();}}));
            assertThat(ready.await(5,TimeUnit.SECONDS)).isTrue();go.countDown();
            assertThat(java.util.List.of(results.get(0).get(10,TimeUnit.SECONDS),results.get(1).get(10,TimeUnit.SECONDS))).containsExactlyInAnyOrder("CREATED","BETA_CAPACITY_REACHED");
        }
        assertThat(db.queryForObject("SELECT COUNT(*) FROM app_user",Integer.class)).isEqualTo(2);
        assertThat(bounded.register(new VerifiedProviderIdentity("KAKAO","123"),first.deviceId(),"existing").newUser()).isFalse();
        assertThat(db.queryForObject("SELECT pinned_limit FROM user_entitlement WHERE user_id=?",Integer.class,bytes(first.userId()))).isEqualTo(1);
        assertThat(db.queryForObject("SELECT quota_bytes FROM user_entitlement WHERE user_id=?",Long.class,bytes(first.userId()))).isEqualTo(100);
 }
}
