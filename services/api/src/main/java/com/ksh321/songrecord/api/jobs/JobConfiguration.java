package com.ksh321.songrecord.api.jobs;

import com.ksh321.songrecord.api.auth.AccountAccess;
import java.time.*;
import org.springframework.context.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;

@Configuration(proxyBeanMethods=false)
@Profile("!bootstrap")
public class JobConfiguration {
    @Bean JobQueue jobQueue(JdbcTemplate jdbc,AccountAccess access,PlatformTransactionManager manager,org.springframework.beans.factory.ObjectProvider<com.ksh321.songrecord.api.operations.OperationsRecorder> recorder){return new JobQueue(jdbc,access,manager,Clock.systemUTC(),Duration.ofMinutes(2),5,event->{var sink=recorder.getIfAvailable();if(sink!=null)sink.job(event);});}
    @Bean JobRunner jobRunner(JobQueue queue){return new JobRunner(queue);}
}
