package com.ksh321.songrecord.api.uploads;

import java.io.IOException;
import java.time.Duration;
import java.util.concurrent.Semaphore;
import java.util.concurrent.atomic.*;

/** One worker process, configured slots shared by every stage, one end-to-end deadline. */
final class ValidationBudget implements AutoCloseable {
    private static volatile Semaphore SLOTS=new Semaphore(2);
    private static volatile int configuredSlots=2,configuredSeconds=60;
    static synchronized void configure(int slots,int seconds){if(slots<1||slots>2||seconds<1||seconds>60)throw new IllegalArgumentException("Invalid validation limit");if(SLOTS.availablePermits()!=configuredSlots)throw new IllegalStateException("Validation work active");SLOTS=new Semaphore(slots);configuredSlots=slots;configuredSeconds=seconds;}
    private static final ThreadLocal<ValidationBudget> CURRENT=new ThreadLocal<>();
    private Semaphore acquired;private final long deadline;private final boolean root;private ValidationBudget owner;private final AtomicInteger holds=new AtomicInteger(1);
    private ValidationBudget(long deadline,boolean root){this.deadline=deadline;this.root=root;owner=this;}
    static ValidationBudget enter()throws IOException{return enter(Duration.ofSeconds(configuredSeconds));}
    static ValidationBudget enter(Duration duration)throws IOException{
        var current=CURRENT.get();
        if(current!=null){current.check();var nested=new ValidationBudget(current.deadline,false);nested.owner=current.owner;return nested;}
        if(duration.isNegative() || duration.isZero() || duration.compareTo(Duration.ofSeconds(60))>0)throw new IllegalArgumentException("Invalid validation limit");
        var slots=SLOTS;if(!slots.tryAcquire())throw new IOException("UPLOAD_WORKER_BUSY");
        var budget=new ValidationBudget(System.nanoTime()+duration.toNanos(),true);budget.acquired=slots;CURRENT.set(budget);return budget;
    }
    long deadline(){return deadline;}
    long remaining()throws IOException{check();return deadline-System.nanoTime();}
    void check()throws IOException{if(Thread.currentThread().isInterrupted() || System.nanoTime()>=deadline)throw new IOException("FILE_VALIDATION_TIMEOUT");}
    Runnable holdUntilReaderStops(){
        var held=owner;held.holds.incrementAndGet();var released=new AtomicBoolean();
        return ()->{if(released.compareAndSet(false,true))held.release();};
    }
    private void release(){if(holds.decrementAndGet()==0)acquired.release();}
    @Override public void close(){if(root){CURRENT.remove();release();}}
}
