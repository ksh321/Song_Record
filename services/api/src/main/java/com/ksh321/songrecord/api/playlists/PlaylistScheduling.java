package com.ksh321.songrecord.api.playlists;
import com.ksh321.songrecord.api.jobs.JobRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.*;
import org.springframework.scheduling.annotation.*;
import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;
import org.springframework.jdbc.core.JdbcTemplate;
@Configuration(proxyBeanMethods=false) @Profile("!bootstrap") @EnableScheduling
@ConditionalOnProperty(name="songrecord.playlists.scheduling-enabled",havingValue="true",matchIfMissing=true)
public class PlaylistScheduling {
    private static final org.slf4j.Logger LOG=org.slf4j.LoggerFactory.getLogger(PlaylistScheduling.class);
    private final PlaylistCleanup cleanup;
    public PlaylistScheduling(JobRunner runner,JdbcTemplate jdbc){cleanup=new PlaylistCleanup(runner,jdbc);}
    @Bean ThreadPoolTaskScheduler playlistScheduler(){var s=new ThreadPoolTaskScheduler();s.setPoolSize(1);s.setThreadNamePrefix("playlist-cleanup-");return s;}
    @Scheduled(fixedDelay=1000,initialDelay=1000,scheduler="playlistScheduler")
    public void clean(){try{cleanup.runOnce();}catch(RuntimeException e){LOG.warn("playlist_cleanup_tick_failed type={}",e.getClass().getSimpleName());}}
}
