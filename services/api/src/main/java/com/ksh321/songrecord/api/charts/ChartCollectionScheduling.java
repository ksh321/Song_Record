package com.ksh321.songrecord.api.charts;

import com.ksh321.songrecord.api.songs.CandidateVerifier.Brand;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.*;
import org.springframework.scheduling.annotation.*;
import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;

@Configuration(proxyBeanMethods=false) @Profile("dev & !prod & !bootstrap") @EnableScheduling
@ConditionalOnProperty(name="songrecord.charts.fixture-enabled",havingValue="true")
public class ChartCollectionScheduling {
    private final ChartCollection collection;public ChartCollectionScheduling(ChartCollection collection){this.collection=collection;}
    @Bean ThreadPoolTaskScheduler chartScheduler(){var scheduler=new ThreadPoolTaskScheduler();scheduler.setPoolSize(1);scheduler.setThreadNamePrefix("chart-fixture-");return scheduler;}
    // Development scheduling interval, never represented as the provider update frequency.
    @Scheduled(fixedDelay=300000,initialDelay=1000,scheduler="chartScheduler")
    public void tick(){for(var brand:Brand.values())for(var period:ChartScope.Period.values()){
        try{collection.run(new ChartScope(brand,period));}
        catch(RuntimeException e){org.slf4j.LoggerFactory.getLogger(ChartCollectionScheduling.class).warn("chart_fixture_collection_failed");}
    }}
}
