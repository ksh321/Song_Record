package com.ksh321.songrecord.api.retention;
import com.ksh321.songrecord.api.jobs.JobQueue;
public final class CleanupWorker {
 private final JobQueue queue;private final CleanupDeletion deletion;public CleanupWorker(JobQueue queue,CleanupDeletion deletion){this.queue=queue;this.deletion=deletion;}
 public boolean runOnce(){var claimed=queue.claim(JobQueue.Type.ASSET_DELETE);if(claimed.isEmpty())return false;var lease=claimed.get();try{queue.complete(lease,deletion.prepare(lease));}catch(Exception e){if(e instanceof InterruptedException)Thread.currentThread().interrupt();try{deletion.retry(lease);}catch(RuntimeException ignored){}queue.fail(lease,true);}return true;}
}
