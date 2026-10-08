package com.ksh321.songrecord.api.retention;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.jobs.JobQueue;
import java.util.*;
import org.springframework.transaction.support.*;

/** Transaction-scoped changes; flush only after all domain row locks, before commit. */
public final class RetentionEvents {
    private static final Object KEY=new Object();
    private record Pending(UUID owner,Set<UUID> songs) {}
    private RetentionEvents() {}
    public static void begin(UUID owner) {
        if(TransactionSynchronizationManager.hasResource(KEY))throw new IllegalStateException("Nested change batch");
        var pending=new Pending(owner,new HashSet<>());
        TransactionSynchronizationManager.bindResource(KEY,pending);
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization(){
            private boolean suspended;
            public void suspend(){if(TransactionSynchronizationManager.getResource(KEY)==pending){TransactionSynchronizationManager.unbindResource(KEY);suspended=true;}}
            public void resume(){if(suspended){TransactionSynchronizationManager.bindResource(KEY,pending);suspended=false;}}
            public void afterCompletion(int status){if(TransactionSynchronizationManager.getResource(KEY)==pending)TransactionSynchronizationManager.unbindResource(KEY);}
        });

    }
    public static void end(){TransactionSynchronizationManager.unbindResourceIfPossible(KEY);}
    public static void capture(UUID owner,String resource,Map<String,Object> before,Map<String,Object> after) {
        var pending=(Pending)TransactionSynchronizationManager.getResource(KEY);
        if(pending==null)return; // Standalone revision tests/reads do not submit jobs.
        if(!pending.owner().equals(owner))throw new IllegalStateException("Cross-account change batch");
        var fields=resource.equals("SONG")?List.of("representative_recording_id","lifecycle_state"):
            resource.equals("RECORDING")?List.of("metadata_state","tier","song_id","lifecycle_state"):List.<String>of();
        if(fields.stream().noneMatch(k->!Objects.equals(before.get(k),after.get(k))))return;
        if(resource.equals("SONG"))add(pending,before.get("id"));
        else {add(pending,before.get("song_id"));add(pending,after.get("song_id"));}
    }
    private static void add(Pending pending,Object id){if(id!=null)pending.songs().add(UUID.fromString(id.toString()));}
    public static void flush(JobQueue jobs,AccountAccess.Account account) {
        var pending=(Pending)TransactionSynchronizationManager.getResource(KEY);
        if(pending==null || pending.songs().isEmpty())return;
        UUID operation=UUID.randomUUID();
        var requests=pending.songs().stream().map(song->new JobQueue.Submission(JobQueue.Type.POLICY_RECALCULATE,
            song,operation,"{\"song_id\":\""+song+"\",\"reason\":\"METADATA_CHANGED\"}")).toList();
        jobs.enqueueAll(account,requests);pending.songs().clear();
    }
}
