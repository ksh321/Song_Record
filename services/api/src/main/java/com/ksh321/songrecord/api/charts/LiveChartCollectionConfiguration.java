package com.ksh321.songrecord.api.charts;

import java.time.Clock;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;

/** Opt-in free-service operation under D12's recorded user decision; not provider terms approval. */
@Configuration(proxyBeanMethods=false)
@Profile("(staging | prod) & !dev & !bootstrap")
@ConditionalOnProperty(prefix="songrecord.charts",name={"live-enabled","storage-approved"},havingValue="true")
public class LiveChartCollectionConfiguration {
    @Bean MananaChartSource liveChartSource(){return new MananaChartSource();}
    @Bean ChartStaging chartStaging(JdbcTemplate db,PlatformTransactionManager manager){return new ChartStaging(db,manager);}
    @Bean ChartValidation chartValidation(){return new ChartValidation();}
    @Bean ChartStoredValidation chartStoredValidation(JdbcTemplate db,ChartValidation validation){return new ChartStoredValidation(db,validation);}
    @Bean ChartPublication chartPublication(JdbcTemplate db,PlatformTransactionManager manager,ChartStoredValidation validation){return new ChartPublication(db,manager,validation,Clock.systemUTC());}
    @Bean ChartCollection liveChartCollection(MananaChartSource source,ChartStaging staging,ChartStoredValidation validation,ChartPublication publication){
        return ChartCollection.approvedLive(source,(scope,payload,time)->{var id=staging.stage(scope,payload,time);validation.validate(id);return id;},Clock.systemUTC(),new ChartCollection.Lifecycle(){
            public java.util.UUID begin(ChartScope scope){return publication.begin(scope);}
            public void success(ChartScope scope,java.util.UUID attempt,java.util.UUID staged){publication.publish(scope,attempt,staged);}
        });
    }
}
