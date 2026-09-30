package com.ksh321.songrecord.api.sync;

import com.ksh321.songrecord.api.jobs.JobQueue;
import java.time.Clock;
import org.springframework.jdbc.core.JdbcTemplate;

/** One durable worker tick. No login credentials are read from the job payload. */
public final class SnapshotWorker {
    private final JdbcTemplate jdbc;
    private final JobQueue jobs;
    private final SnapshotBuildStore builds;
    private final SnapshotReadView views;
    private final SnapshotSourceRows sources;
    private final Clock clock;
    public SnapshotWorker(JdbcTemplate jdbc,JobQueue jobs,SnapshotBuildStore builds,SnapshotReadView views,SnapshotSourceRows sources,Clock clock) {
        this.jdbc=jdbc;this.jobs=jobs;this.builds=builds;this.views=views;this.sources=sources;this.clock=clock;
    }
    public boolean runOnce() {
        var claimed=jobs.claim(JobQueue.Type.SNAPSHOT_BUILD);if(claimed.isEmpty())return false;
        var lease=claimed.get();
        try {
            var authority=SnapshotAuthority.job(jdbc,lease,clock);
            var state=builds.current(authority,lease.aggregateId());
            if(state.attempt().status().equals("READY")||state.attempt().status().equals("EXPIRED")) {
                jobs.complete(lease,()->{});return true;
            }
            if(!state.attempt().status().equals("BUILDING")){jobs.fail(lease,false);return true;}
            var attempt=state.captured()||!clock.instant().isBefore(state.leaseUntil())
                    ?builds.restartOwned(authority,state.attempt()):state.attempt();
            var captured=views.capture(authority,attempt.startedAt(),
                    (cursor,time)->builds.capture(authority,attempt,cursor,time),
                    (connection,owner)->sources.extract(connection,owner,attempt.startedAt().plusSeconds(600),batch->builds.append(authority,attempt,batch)));
            builds.publish(authority,attempt,captured.value());
            jobs.complete(lease,()->{});
        }catch(Exception failure){
            // Queue failures use fixed codes, never exception messages or account payloads.
            jobs.fail(lease,true);
        }
        return true;
    }
}
