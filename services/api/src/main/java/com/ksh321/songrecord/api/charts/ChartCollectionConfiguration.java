package com.ksh321.songrecord.api.charts;

import java.nio.charset.StandardCharsets;
import java.time.Clock;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;

/** Explicit development fixtures only; default and production create no collection worker. */
@Configuration(proxyBeanMethods=false) @Profile("dev & !prod & !bootstrap")
@ConditionalOnProperty(name="songrecord.charts.fixture-enabled",havingValue="true")
public class ChartCollectionConfiguration {
    @Bean ChartStaging chartStaging(JdbcTemplate db,PlatformTransactionManager manager){return new ChartStaging(db,manager);}
    @Bean ChartValidation chartValidation(){return new ChartValidation();}
    @Bean ChartStoredValidation chartStoredValidation(JdbcTemplate db,ChartValidation validation){return new ChartStoredValidation(db,validation);}
    @Bean ChartPublication chartPublication(JdbcTemplate jdbc,PlatformTransactionManager manager,ChartStoredValidation validation){return new ChartPublication(jdbc,manager,validation,Clock.systemUTC());}
    @Bean ChartCollection chartCollection(ChartStaging staging,ChartStoredValidation validation,ChartPublication publication){return new ChartCollection((scope,remaining)->("[{\"brand\":\""+scope.providerBrand()+"\",\"no\":\"00123\",\"title\":\"개발 검증 곡\",\"singer\":\"검증 가수\"}]").getBytes(StandardCharsets.UTF_8),(scope,payload,time)->{var id=staging.stage(scope,payload,time);validation.validate(id);return id;},Clock.systemUTC(),true,new ChartCollection.Lifecycle(){public java.util.UUID begin(ChartScope s){return publication.begin(s);}public void success(ChartScope s,java.util.UUID a,java.util.UUID id){publication.publish(s,a,id);}});}
}
