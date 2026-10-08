package com.ksh321.songrecord.api.retention;

import com.ksh321.songrecord.api.jobs.JobQueue;

/** Recompute fresh under USER_SYNC; never apply a selection from an old payload. */
public final class RetentionWorker {
    private final JobQueue jobs;private final RetentionSelectionStore store;
    public RetentionWorker(JobQueue jobs,RetentionSelectionStore store){this.jobs=jobs;this.store=store;}
    public boolean runOnce(){
        var claimed=jobs.claim(JobQueue.Type.POLICY_RECALCULATE);if(claimed.isEmpty())return false;
        var lease=claimed.get();
        if(lease.userId()==null){jobs.fail(lease,false);return true;}
        try {jobs.complete(lease,()->store.recalculateInJob(lease.userId(),lease.aggregateId()));}
        catch(RuntimeException error){jobs.fail(lease,true);}
        return true;
    }
}
