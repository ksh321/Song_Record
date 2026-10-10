package com.ksh321.songrecord.api.charts;

import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/** Trusted background tick only; no user-request handler calls a provider. */
public final class ChartCollection {
    @FunctionalInterface public interface Source {byte[] fetch(ChartScope scope,Duration remaining);}
    @FunctionalInterface public interface Sink {UUID stage(ChartScope scope,byte[] payload,Instant fetchedAt);}
    public interface Lifecycle {UUID begin(ChartScope scope);void success(ChartScope scope,UUID attempt,UUID staged);}
    private static final Lifecycle NO_PUBLICATION=new Lifecycle(){public UUID begin(ChartScope s){return UUID.randomUUID();}public void success(ChartScope s,UUID a,UUID id){}};
    public enum Failure { TIMEOUT, NETWORK, INVALID_RESPONSE, BUSY, LIVE_STORAGE_NOT_APPROVED }
    public static final class CollectionFailure extends RuntimeException {
        private final Failure kind;public CollectionFailure(Failure kind){super(kind.name());this.kind=kind;}public Failure kind(){return kind;}
    }
    private final Source source;private final Sink staging;private final Clock clock;private final boolean fixture;
    private final Semaphore slots=new Semaphore(2), fetchSlots=new Semaphore(2);
    private final Duration budget;private final Lifecycle lifecycle;
    private final ExecutorService fetching=Executors.newVirtualThreadPerTaskExecutor();
    public ChartCollection(Source source,Sink staging,Clock clock,boolean fixture){this(source,staging,clock,fixture,Duration.ofSeconds(30),NO_PUBLICATION);}
    ChartCollection(Source source,Sink staging,Clock clock,boolean fixture,Duration budget){this(source,staging,clock,fixture,budget,NO_PUBLICATION);}
    public ChartCollection(Source source,Sink staging,Clock clock,boolean fixture,Lifecycle lifecycle){this(source,staging,clock,fixture,Duration.ofSeconds(30),lifecycle);}
    private ChartCollection(Source source,Sink staging,Clock clock,boolean fixture,Duration budget,Lifecycle lifecycle){this.source=source;this.staging=staging;this.clock=clock;this.fixture=fixture;this.budget=budget;this.lifecycle=Objects.requireNonNull(lifecycle);}
    public UUID run(ChartScope scope){
        Objects.requireNonNull(scope);
        // Until an approved provider-storage contract exists, no live payload is persisted.
        if(!fixture)throw new CollectionFailure(Failure.LIVE_STORAGE_NOT_APPROVED);
        if(TransactionSynchronizationManager.isActualTransactionActive())throw new IllegalStateException("Provider fetch inside database transaction");
        if(!slots.tryAcquire())throw new CollectionFailure(Failure.BUSY);
        // Reserve the staging transaction limit inside the total 30-second job budget.
        long wholeEnd=System.nanoTime()+budget.toNanos();
        long end=wholeEnd-Math.min(Duration.ofSeconds(10).toNanos(),budget.toNanos()/3);
        Long previous=ChartJobDeadline.END.get();ChartJobDeadline.END.set(previous==null?wholeEnd:Math.min(previous,wholeEnd));
        try {
            UUID ticket=lifecycle.begin(scope);
            for(int attempt=0;attempt<2;attempt++){
                long left=end-System.nanoTime();if(left<=0)throw new CollectionFailure(Failure.TIMEOUT);
                try {
                    byte[] payload=fetch(scope,left);
                    if(System.nanoTime()>=end)throw new CollectionFailure(Failure.TIMEOUT);
                    if(payload==null || payload.length==0 || payload.length>ChartStaging.MAX_BYTES)throw new CollectionFailure(Failure.INVALID_RESPONSE);
                    var id=staging.stage(scope,payload.clone(),clock.instant());lifecycle.success(scope,ticket,id);ChartJobDeadline.check();return id;
                }catch(CollectionFailure e){if(attempt==1 || e.kind()!=Failure.NETWORK && e.kind()!=Failure.TIMEOUT)throw e;}
            }
            throw new CollectionFailure(Failure.TIMEOUT);
        }finally{if(previous==null)ChartJobDeadline.END.remove();else ChartJobDeadline.END.set(previous);slots.release();}
    }
    private byte[] fetch(ChartScope scope,long left){
        // A hung adapter cannot occupy the caller. Its permit remains held until it really exits.
        Future<byte[]> future=fetching.submit(()->{
            if(!fetchSlots.tryAcquire())throw new CollectionFailure(Failure.BUSY);
            try{return source.fetch(scope,Duration.ofNanos(left));}finally{fetchSlots.release();}
        });
        try{return future.get(left,TimeUnit.NANOSECONDS);}
        catch(TimeoutException e){future.cancel(true);throw new CollectionFailure(Failure.TIMEOUT);}
        catch(InterruptedException e){future.cancel(true);Thread.currentThread().interrupt();throw new CollectionFailure(Failure.TIMEOUT);}
        catch(ExecutionException e){if(e.getCause() instanceof RuntimeException r)throw r; if(e.getCause() instanceof Error error)throw error;throw new CollectionFailure(Failure.NETWORK);}
    }
}
