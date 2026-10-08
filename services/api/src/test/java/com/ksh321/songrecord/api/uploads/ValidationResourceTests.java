package com.ksh321.songrecord.api.uploads;

import java.io.*;
import java.nio.file.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.jdbc.core.JdbcTemplate;
import com.ksh321.songrecord.api.jobs.JobQueue;
import com.ksh321.songrecord.api.storage.StorageObjectKeys;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

class ValidationResourceTests {
    @TempDir Path temp;
    String python=System.getProperty("os.name").startsWith("Windows")?"python":"python3";
    AudioValidator validator=new AudioValidator("unused","unused",python);
    Path helper()throws Exception{
        var file=temp.resolve("sandbox.py");
        try(var stream=AudioValidator.class.getResourceAsStream("/audio/sandbox.py")){Files.copy(stream,file);}
        return file;
    }
    @Test void nativeMemoryLimitRejectsAllocationAndAllowsNextProcess()throws Exception{
        var script=helper();
        assertThatThrownBy(()->validator.run(script,List.of(python,"-c","data=bytearray(768*1024*1024)"),65536,true,System.nanoTime()+TimeUnit.SECONDS.toNanos(15)))
            .isInstanceOfSatisfying(AudioValidator.Invalid.class,e->assertThat(e.code).isEqualTo("FILE_VALIDATION_TIMEOUT"));
        assertThat(validator.run(script,List.of(python,"-c","print('ready')"),65536,true,System.nanoTime()+TimeUnit.SECONDS.toNanos(10)).text()).asString().contains("ready");
    }
    @Test void outputLimitAbortsBeforeRetainingUnboundedData()throws Exception{
        var script=helper();
        assertThatThrownBy(()->validator.run(script,List.of(python,"-c","import sys; sys.stdout.write('x'*1000000);sys.stdout.flush()"),1024,true,System.nanoTime()+TimeUnit.SECONDS.toNanos(10)))
            .isInstanceOfSatisfying(AudioValidator.Invalid.class,e->assertThat(e.code).isEqualTo("FILE_VALIDATION_TIMEOUT"));
    }
    @Test void stalledDecoderIsKilledIncludingChildAndNextProcessRuns()throws Exception{
        var script=helper();var pid=temp.resolve("decoder.pid");
        String code="import os,time;open("+quote(pid.toString())+",'w').write(str(os.getpid()));time.sleep(20)";
        assertThatThrownBy(()->validator.run(script,List.of(python,"-c",code),1024,true,System.nanoTime()+TimeUnit.SECONDS.toNanos(2)))
            .isInstanceOfSatisfying(AudioValidator.Invalid.class,e->assertThat(e.code).isEqualTo("FILE_VALIDATION_TIMEOUT"));
        assertThat(pid).exists();long id=Long.parseLong(Files.readString(pid));
        for(int i=0;i<20 && ProcessHandle.of(id).map(ProcessHandle::isAlive).orElse(false);i++)Thread.sleep(25);
        assertThat(ProcessHandle.of(id).map(ProcessHandle::isAlive).orElse(false)).isFalse();
        assertThat(validator.run(script,List.of(python,"-c","print('recovered')"),1024,true,System.nanoTime()+TimeUnit.SECONDS.toNanos(10)).text()).asString().contains("recovered");
    }
    @Test void unavailableSandboxNeverFallsBackToUnboundedExecution()throws Exception{
        var missing=new AudioValidator("unused","unused","missing-python-fixture");
        assertThatThrownBy(()->missing.run(helper(),List.of(python,"-c","print('bad')"),1024,true,System.nanoTime()+TimeUnit.SECONDS.toNanos(5)))
            .isInstanceOfSatisfying(AudioValidator.Invalid.class,e->assertThat(e.code).isEqualTo("FILE_VALIDATOR_UNAVAILABLE"));
    }
    @Test void sharedTwoSlotsRejectThirdAndRecoverAfterFailure()throws Exception{
        var entered=new CountDownLatch(2);var release=new CountDownLatch(1);
        try(var workers=Executors.newFixedThreadPool(2)){
            Callable<Void> task=()->{try(var budget=ValidationBudget.enter()){entered.countDown();release.await(5,TimeUnit.SECONDS);}return null;};
            var a=workers.submit(task);var b=workers.submit(task);
            try{assertThat(entered.await(3,TimeUnit.SECONDS)).isTrue();assertThatThrownBy(ValidationBudget::enter).isInstanceOf(IOException.class).hasMessage("UPLOAD_WORKER_BUSY");}
            finally{release.countDown();}
            a.get(5,TimeUnit.SECONDS);b.get(5,TimeUnit.SECONDS);
        }
        try(var recovered=ValidationBudget.enter()){recovered.check();}
    }
    @Test void unfinishedReaderRetainsSlotAfterCoordinatorTimesOut()throws Exception{
        Runnable release;
        try(var outer=ValidationBudget.enter()){release=outer.holdUntilReaderStops();}
        try(var second=ValidationBudget.enter()){
            // The expired coordinator's reader still occupies the first global slot.
            try(var workers=Executors.newSingleThreadExecutor()){
                assertThat(workers.submit(()->{try(var third=ValidationBudget.enter()){return "unexpected";}catch(IOException e){return e.getMessage();}}).get()).isEqualTo("UPLOAD_WORKER_BUSY");
            }
        }
        release.run();release.run();
        try(var next=ValidationBudget.enter()){next.check();}
    }
    @Test void nestedStagesShareOriginalDeadlineAndUseOnlyOneSlot()throws Exception{
        try(var download=ValidationBudget.enter(Duration.ofMillis(100));var decoder=ValidationBudget.enter()){
            assertThat(decoder.deadline()).isEqualTo(download.deadline());Thread.sleep(120);
            assertThatThrownBy(decoder::check).isInstanceOf(IOException.class).hasMessage("FILE_VALIDATION_TIMEOUT");
            assertThatThrownBy(ValidationBudget::enter).isInstanceOf(IOException.class).hasMessage("FILE_VALIDATION_TIMEOUT");
        }
        try(var recovered=ValidationBudget.enter()){recovered.check();}
    }
    @Test void blockedDownloadIsAbortedWithoutCallingConsumer()throws Exception{
        var db=mock(JdbcTemplate.class);UUID user=UUID.randomUUID(),recording=UUID.randomUUID(),attempt=UUID.randomUUID();
        var key=new StorageObjectKeys.Temporary(user,recording,attempt);
        when(db.queryForList(anyString(),any(Object[].class))).thenReturn(List.of(Map.of("recording_id",com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(recording),"temp_key",key.value(),"expected_size",3,"expected_sha256","a".repeat(64))));
        var closed=new AtomicBoolean();var consumed=new AtomicBoolean();
        var stream=new InputStream(){
            public int read()throws IOException{try{Thread.sleep(10000);return -1;}catch(InterruptedException e){throw new IOException("fixture interrupted");}}
            public void close(){closed.set(true);}
        };
        var verification=new UploadVerification(db,unused->stream,Clock.systemUTC());
        var lease=new JobQueue.Lease(UUID.randomUUID(),UUID.randomUUID(),user,JobQueue.Type.UPLOAD_VERIFY,attempt,"{}",1);
        try(var budget=ValidationBudget.enter(Duration.ofMillis(250))){
            assertThatThrownBy(()->verification.prepare(lease,(l,bytes)->{consumed.set(true);return ()->{};}))
                .isInstanceOf(IOException.class).hasMessage("FILE_VALIDATION_TIMEOUT");
        }
        assertThat(closed).isTrue();assertThat(consumed).isFalse();
        var next=new UploadVerification(db,unused->new ByteArrayInputStream(new byte[]{1,2,3}),Clock.systemUTC());
        assertThat(next.prepare(lease,(l,bytes)->()->{})).isNotNull();
    }
    static String quote(String text){return "'"+text.replace("\\","\\\\").replace("'","\\'")+"'";}
}
