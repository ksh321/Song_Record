package com.ksh321.songrecord.api.jobs;

/** One worker tick. Preparation is outside a transaction; returned DB effects are fenced. */
public final class JobRunner {
    @FunctionalInterface public interface Handler { Runnable prepare(JobQueue.Lease lease) throws Exception; }
    private final JobQueue queue;
    public JobRunner(JobQueue queue){this.queue=queue;}
    public boolean runOnce(JobQueue.Type type,Handler handler) {
        var claimed=queue.claim(type);if(claimed.isEmpty())return false;
        var lease=claimed.get();
        try {queue.complete(lease,java.util.Objects.requireNonNull(handler.prepare(lease)));}
        catch(InterruptedException e){Thread.currentThread().interrupt();queue.fail(lease,true);}
        catch(Exception e){queue.fail(lease,true);} // Never persist exception messages or payload secrets.
        return true;
    }
}
