package com.ksh321.songrecord.api.uploads;

import java.io.IOException;
import java.time.Duration;
import java.util.concurrent.Semaphore;
import java.util.concurrent.atomic.*;

/** One worker process, two slots shared by every downloader/validator instance, one end-to-end deadline. */
final class ValidationBudget implements AutoCloseable {
    private static final Semaphore SLOTS=new Semaphore(2);
    private static final ThreadLocal<ValidationBudget> CURRENT=new ThreadLocal<>();
    private final long deadline;private final boolean root;private ValidationBudget owner;private final AtomicInteger holds=new AtomicInteger(1);
    private ValidationBudget(long deadline,boolean root){this.deadline=deadline;this.root=root;owner=this;}
    static ValidationBudget enter()throws IOException{return enter(Duration.ofSeconds(60));}
    static ValidationBudget enter(Duration duration)throws IOException{
        var current=CURRENT.get();
        if(current!=null){current.check();var nested=new ValidationBudget(current.deadline,false);nested.owner=current.owner;return nested;}
        if(duration.isNegative() || duration.isZero() || duration.compareTo(Duration.ofSeconds(60))>0)throw new IllegalArgumentException("Invalid validation limit");
        if(!SLOTS.tryAcquire())throw new IOException("UPLOAD_WORKER_BUSY");
        var budget=new ValidationBudget(System.nanoTime()+duration.toNanos(),true);CURRENT.set(budget);return budget;
    }
    long deadline(){return deadline;}
    long remaining()throws IOException{check();return deadline-System.nanoTime();}
    void check()throws IOException{if(Thread.currentThread().isInterrupted() || System.nanoTime()>=deadline)throw new IOException("FILE_VALIDATION_TIMEOUT");}
    Runnable holdUntilReaderStops(){
        var held=owner;held.holds.incrementAndGet();var released=new AtomicBoolean();
        return ()->{if(released.compareAndSet(false,true))held.release();};
    }
    private void release(){if(holds.decrementAndGet()==0)SLOTS.release();}
    @Override public void close(){if(root){CURRENT.remove();release();}}
}
