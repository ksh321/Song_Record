package com.ksh321.songrecord.api.uploads;

import com.ksh321.songrecord.api.jobs.JobQueue;
import com.ksh321.songrecord.api.locking.LockOrder;
import com.ksh321.songrecord.api.storage.StorageObjectKeys;
import java.io.*;
import java.nio.ByteBuffer;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import org.springframework.jdbc.core.JdbcTemplate;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;

/** P12-06 byte-acquisition stage. It cannot complete a job or write STORED by itself. */
public final class UploadVerification {
    public static final int MAX_BYTES=6*1024*1024;
    private final JdbcTemplate db; private final UploadByteSource source; private final Clock clock;
    public UploadVerification(JdbcTemplate db,UploadByteSource source,Clock clock){this.db=db;this.source=source;this.clock=clock;}
    public static final class Captured {
        private final byte[] bytes; private final long expectedSize; private final String expectedSha256;
        private Captured(byte[] bytes,long size,String hash){this.bytes=bytes;expectedSize=size;expectedSha256=hash;}
        public ByteBuffer bytes(){return ByteBuffer.wrap(bytes).asReadOnlyBuffer();}
        public long expectedSize(){return expectedSize;}
        public String expectedSha256(){return expectedSha256;}
        @Override public String toString(){return "CapturedUpload[REDACTED]";}
    }
    /** Consumer validates and writes these same bytes in later stages, never re-fetches the temporary object. */
    @FunctionalInterface public interface Consumer { Runnable prepare(JobQueue.Lease lease,Captured bytes) throws Exception; }
    public Runnable prepare(JobQueue.Lease lease,Consumer consumer)throws Exception{
        LockOrder.requireOutsideTransaction();Objects.requireNonNull(consumer);
        try(var budget=ValidationBudget.enter()) {
            long deadline=budget.deadline();
            var row=current(lease);UUID recording=uuid((byte[])row.get("recording_id"));
            var key=new StorageObjectKeys.Temporary(lease.userId(),recording,lease.aggregateId());
            if(!key.value().equals(row.get("temp_key")))throw new IOException("UPLOAD_KEY_MISMATCH");
            var inputRef=new AtomicReference<InputStream>();var cancelled=new AtomicBoolean();
            var readers=Executors.newVirtualThreadPerTaskExecutor();
            var download=new CompletableFuture<byte[]>();var releaseReader=budget.holdUntilReaderStops();
            readers.execute(()->{try{
                var opened=source.open(key);inputRef.set(opened);byte[] captured;
                try(var input=opened;var output=new ByteArrayOutputStream()){
                    if(cancelled.get())throw new IOException("FILE_VALIDATION_TIMEOUT");
                    var buffer=new byte[32768];int total=0;
                    while(true){
                        if(Thread.currentThread().isInterrupted() || System.nanoTime()>=deadline)throw new IOException("FILE_VALIDATION_TIMEOUT");
                        current(lease);
                        int n=input.read(buffer,0,Math.min(buffer.length,MAX_BYTES-total+1));
                        if(n<0)break;
                        if(n==0)throw new IOException("UPLOAD_EMPTY_READ");
                        total+=n;if(total>MAX_BYTES)throw new IOException("UPLOAD_TOO_LARGE");
                        output.write(buffer,0,n);
                    }
                    captured=output.toByteArray();
                }
                download.complete(captured);
            }catch(Throwable e){download.completeExceptionally(e);}finally{releaseReader.run();}});
            byte[] bytes;
            try{bytes=download.get(budget.remaining(),TimeUnit.NANOSECONDS);}
            catch(TimeoutException e){throw new IOException("FILE_VALIDATION_TIMEOUT");}
            catch(InterruptedException e){Thread.currentThread().interrupt();throw new IOException("FILE_VALIDATION_TIMEOUT");}
            catch(ExecutionException e){
                if(e.getCause() instanceof IOException cause){if("FILE_VALIDATION_TIMEOUT".equals(cause.getMessage()) || "UPLOAD_TOO_LARGE".equals(cause.getMessage()))throw cause;throw new IOException("UPLOAD_BYTES_UNAVAILABLE");}
                if(e.getCause() instanceof RuntimeException cause)throw cause;
                throw new IOException("UPLOAD_BYTES_UNAVAILABLE");
            }
            finally{cancelled.set(true);download.cancel(true);var input=inputRef.get();if(input!=null)try{input.close();}catch(IOException ignored){}readers.shutdownNow();}
            current(lease);
            budget.check();if(bytes.length==0)throw new IOException("UPLOAD_BYTES_UNAVAILABLE");
            var captured=new Captured(bytes,((Number)row.get("expected_size")).longValue(),(String)row.get("expected_sha256"));
            Runnable effects=Objects.requireNonNull(consumer.prepare(lease,captured));
            budget.check();current(lease);
            // JobRunner fences the final transaction too. This stage never claims validation succeeded.
            return ()->{current(lease);effects.run();};
        }
    }
    private Map<String,Object> current(JobQueue.Lease lease){
        if(lease.type()!=JobQueue.Type.UPLOAD_VERIFY || lease.userId()==null)throw new IllegalStateException("UPLOAD_AUTHORITY_LOST");
        var now=java.sql.Timestamp.from(clock.instant());
        var rows=db.queryForList("SELECT a.recording_id,a.temp_key,a.expected_size,a.expected_sha256 FROM job j JOIN app_user u ON u.id=j.user_id JOIN recording_upload a ON a.id=j.aggregate_id AND a.user_id=j.user_id JOIN recording r ON r.id=a.recording_id AND r.user_id=a.user_id WHERE j.id=? AND j.lease_token=? AND j.state='RUNNING' AND j.type='UPLOAD_VERIFY' AND j.lease_until>? AND j.user_id=? AND j.aggregate_id=? AND u.status='ACTIVE' AND a.state='VERIFYING' AND a.expires_at>? AND r.lifecycle_state='ACTIVE' AND r.metadata_state='SAVED'",bytes(lease.id()),bytes(lease.token()),LocalDateTime.ofInstant(clock.instant(),ZoneOffset.UTC),bytes(lease.userId()),bytes(lease.aggregateId()),now);
        if(rows.size()!=1)throw new IllegalStateException("UPLOAD_AUTHORITY_LOST");return rows.getFirst();
    }
}
