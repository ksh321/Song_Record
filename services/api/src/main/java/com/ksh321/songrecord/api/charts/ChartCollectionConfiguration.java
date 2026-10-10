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
    @Bean ChartCollection chartCollection(ChartStaging staging){return new ChartCollection((scope,remaining)->("[{\"brand\":\""+scope.providerBrand()+"\",\"no\":\"00123\",\"title\":\"개발 검증 곡\",\"singer\":\"검증 가수\"}]").getBytes(StandardCharsets.UTF_8),staging::stage,Clock.systemUTC(),true);}
}
