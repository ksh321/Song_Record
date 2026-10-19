package com.ksh321.songrecord.api.charts;

import com.ksh321.songrecord.api.songs.CandidateVerifier.Brand;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.*;
import org.springframework.scheduling.annotation.*;
import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;

/** One worker, six independent scopes. Six hours is our polling policy, not provider freshness. */
@Configuration(proxyBeanMethods=false) @EnableScheduling
@Profile("(staging | prod) & !dev & !bootstrap")
@ConditionalOnProperty(prefix="songrecord.charts",name={"live-enabled","storage-approved","scheduling-enabled"},havingValue="true")
public class LiveChartCollectionScheduling {
    private final ChartCollection collection;
    public LiveChartCollectionScheduling(ChartCollection collection,
            @Value("${songrecord.charts.live-fixed-delay-ms:21600000}")long delay,
            @Value("${songrecord.charts.live-initial-delay-ms:5000}")long initial){
        if(delay<300000 || delay>86400000 || initial<1000 || initial>300000)throw new IllegalArgumentException("Invalid chart collection schedule");
        this.collection=collection;
    }
    @Bean ThreadPoolTaskScheduler chartLiveScheduler(){var scheduler=new ThreadPoolTaskScheduler();scheduler.setPoolSize(1);scheduler.setThreadNamePrefix("chart-live-");return scheduler;}
    @Scheduled(fixedDelayString="${songrecord.charts.live-fixed-delay-ms:21600000}",initialDelayString="${songrecord.charts.live-initial-delay-ms:5000}",scheduler="chartLiveScheduler")
    public void tick(){for(var brand:Brand.values())for(var period:ChartScope.Period.values()){
        try{collection.run(new ChartScope(brand,period));}
        catch(RuntimeException failure){org.slf4j.LoggerFactory.getLogger(LiveChartCollectionScheduling.class).warn("chart_live_collection_failed brand={} period={}",brand,period);}
    }}
}
