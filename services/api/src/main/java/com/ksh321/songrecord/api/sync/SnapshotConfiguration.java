package com.ksh321.songrecord.api.sync;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.idempotency.IdempotentMutations;
import com.ksh321.songrecord.api.jobs.JobQueue;
import java.time.*;
import java.util.Base64;
import javax.sql.DataSource;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.*;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpMethod;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.transaction.PlatformTransactionManager;

@Configuration(proxyBeanMethods=false)
@Profile("!bootstrap")
public class SnapshotConfiguration {
    @Bean SnapshotPageCursor snapshotPageCursor(@Value("${songrecord.pagination.key-base64:}") String encoded) {
        try{return new SnapshotPageCursor(Base64.getDecoder().decode(encoded),Clock.systemUTC());}
        catch(IllegalArgumentException e){throw new IllegalStateException("Snapshots require a valid 32-byte Base64 pagination key");}
    }
    @Bean SnapshotBuildStore snapshotBuildStore(JdbcTemplate jdbc,AccountAccess access,PlatformTransactionManager manager){return new SnapshotBuildStore(jdbc,access,manager,Clock.systemUTC());}
    @Bean SnapshotPages snapshotPages(JdbcTemplate jdbc,AccountAccess access,SnapshotPageCursor cursor){return new SnapshotPages(jdbc,access,cursor,Clock.systemUTC());}
    @Bean SnapshotQueries snapshotQueries(JdbcTemplate jdbc,AccountAccess access,SnapshotPages pages){return new SnapshotQueries(jdbc,access,pages,Clock.systemUTC());}
    @Bean SnapshotRequests snapshotRequests(AccountAccess access,IdempotentMutations receipts,SnapshotBuildStore builds,JobQueue jobs){return new SnapshotRequests(access,receipts,builds,jobs);}
    @Bean SnapshotCleanup snapshotCleanup(JdbcTemplate jdbc,PlatformTransactionManager manager){return new SnapshotCleanup(jdbc,manager,Clock.systemUTC());}
    @Bean SnapshotWorker snapshotWorker(JdbcTemplate jdbc,DataSource source,AccountAccess access,PlatformTransactionManager manager,SnapshotBuildStore builds){
        var clock=Clock.systemUTC();
        // Dedicated lease policy; leave the ordinary job queue's two-minute lease unchanged.
        var jobs=new JobQueue(jdbc,access,manager,clock,Duration.ofMinutes(10),5);
        return new SnapshotWorker(jdbc,jobs,builds,new SnapshotReadView(source,access,clock),new SnapshotSourceRows(clock),clock);
    }
    @Bean @Order(7) SecurityFilterChain snapshotSecurity(HttpSecurity http) throws Exception {
        // AccountAccess authenticates and revalidates both permitted request handlers.
        http.securityMatcher("/v1/sync/snapshots","/v1/sync/snapshots/**").csrf(c->c.disable())
                .sessionManagement(s->s.sessionCreationPolicy(SessionCreationPolicy.STATELESS)).requestCache(c->c.disable())
                .authorizeHttpRequests(a->a.requestMatchers(HttpMethod.POST,"/v1/sync/snapshots").permitAll()
                        .requestMatchers(HttpMethod.GET,"/v1/sync/snapshots/*").permitAll().anyRequest().denyAll());
        return http.build();
    }
}
