package com.ksh321.songrecord.api.uploads;

import java.io.*;
import java.nio.*;
import java.nio.file.*;
import java.security.*;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;
import tools.jackson.databind.json.JsonMapper;

/** Actual bytes, container metadata and complete decode must agree. Never publishes an asset. */
public final class AudioValidator {
    private static final int MAX_BYTES=6*1024*1024;
    private static final long MAX_SAMPLES=361L*48000+1024;
    private final String ffmpeg,ffprobe,python;
    public AudioValidator(String ffmpeg,String ffprobe){this(ffmpeg,ffprobe,System.getProperty("os.name").startsWith("Windows")?"python":"python3");}
    public AudioValidator(String ffmpeg,String ffprobe,String python){this.ffmpeg=Objects.requireNonNull(ffmpeg);this.ffprobe=Objects.requireNonNull(ffprobe);this.python=Objects.requireNonNull(python);}
    public static final class Invalid extends Exception {
        public final String code;
        private Invalid(String code){super(code);this.code=code;}
    }
    public static final class Validated {
        private final byte[] bytes;private final String sha256;private final double seconds;
        private Validated(byte[] bytes,String hash,double seconds){this.bytes=bytes;sha256=hash;this.seconds=seconds;}
        public ByteBuffer bytes(){return ByteBuffer.wrap(bytes).asReadOnlyBuffer();}
        public String sha256(){return sha256;}
        public double durationSeconds(){return seconds;}
        @Override public String toString(){return "ValidatedAudio[REDACTED]";}
    }
    /** P12-09 supplies final writing/DB effects; callers cannot substitute a new GET after validation. */
    @FunctionalInterface public interface Next { Runnable prepare(com.ksh321.songrecord.api.jobs.JobQueue.Lease lease,Validated audio)throws Exception; }
    public UploadVerification.Consumer then(Next next){Objects.requireNonNull(next);return (lease,captured)->next.prepare(lease,validate(captured.bytes(),captured.expectedSize(),captured.expectedSha256()));}
    public Validated validate(ByteBuffer source,long expectedSize,String expectedHash)throws Invalid{
        try(var budget=ValidationBudget.enter()){return validateInside(source,expectedSize,expectedHash,budget);}
        catch(IOException e){throw invalid(e.getMessage().equals("UPLOAD_WORKER_BUSY")?"UPLOAD_WORKER_BUSY":"FILE_VALIDATION_TIMEOUT");}
    }
    private Validated validateInside(ByteBuffer source,long expectedSize,String expectedHash,ValidationBudget budget)throws Invalid{
        Objects.requireNonNull(source);var view=source.asReadOnlyBuffer();int length=view.remaining();
        if(length<1 || length>MAX_BYTES || length!=expectedSize)throw invalid("FILE_SIZE_MISMATCH");
        var bytes=new byte[length];view.get(bytes);String hash;
        try{hash=HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));}catch(NoSuchAlgorithmException e){throw new IllegalStateException(e);}
        if(expectedHash==null || !expectedHash.matches("[0-9a-f]{64}") || !hash.equals(expectedHash))throw invalid("FILE_CHECKSUM_MISMATCH");
        Path directory=null,input=null,helper=null;long deadline=budget.deadline();
        try{
            directory=Files.createTempDirectory("song-record-audio-");input=directory.resolve("input.m4a");Files.write(input,bytes,StandardOpenOption.CREATE_NEW);
            helper=directory.resolve("sandbox.py");
            try(var script=AudioValidator.class.getResourceAsStream("/audio/sandbox.py")){if(script==null)throw invalid("FILE_SANDBOX_UNAVAILABLE");Files.copy(script,helper);}
            budget.check();
            var probe=run(helper,List.of(ffprobe,"-max_alloc","16777216","-v","error","-protocol_whitelist","file,pipe","-f","mov","-enable_drefs","0","-show_entries","format=format_name,duration:format_tags=major_brand:stream=codec_type,codec_name,profile,sample_rate,channels,duration","-of","json",input.toString()),65536,true,deadline);
            var tree=new JsonMapper().readTree(probe.text());var streams=tree.path("streams");
            if(!streams.isArray() || streams.size()!=1)throw invalid("FILE_AUDIO_FORMAT");
            var audio=streams.get(0);var format=tree.path("format");
            String name=format.path("format_name").asText("");String brand=format.path("tags").path("major_brand").asText("");
            if(!Arrays.asList(name.split(",")).contains("mp4") || !Set.of("M4A ","isom","iso2","mp41","mp42").contains(brand)
                || !audio.path("codec_type").asText("").equals("audio") || !audio.path("codec_name").asText("").equals("aac")
                || !audio.path("profile").asText("").equals("LC") || !audio.path("sample_rate").asText("").equals("48000") || audio.path("channels").asInt()!=1)throw invalid("FILE_AUDIO_FORMAT");
            double seconds=duration(audio.path("duration").asText("")),container=duration(format.path("duration").asText(""));
            if(Math.abs(seconds-container)>1024.0/48000+0.001)throw invalid("FILE_AUDIO_DURATION");
            var decoded=run(helper,List.of(ffmpeg,"-max_alloc","16777216","-nostdin","-v","error","-xerror","-err_detect","explode","-threads","1","-protocol_whitelist","file,pipe","-f","mov","-enable_drefs","0","-i",input.toString(),"-map","0:a:0","-vn","-sn","-dn","-threads","1","-c:a","pcm_s16le","-f","s16le","pipe:1"),MAX_SAMPLES*2,false,deadline);
            long samples=decoded.length()/2;
            // AAC's final decoded frame may include up to one frame of encoder padding.
            if(decoded.length()%2!=0 || samples<1 || samples<Math.floor(seconds*48000)-1024 || samples>Math.ceil(seconds*48000)+1024)throw invalid("FILE_AUDIO_DURATION");
            budget.check();return new Validated(bytes,hash,seconds);
        }catch(Invalid e){throw e;}catch(IOException e){throw invalid("FILE_VALIDATION_TIMEOUT".equals(e.getMessage())?"FILE_VALIDATION_TIMEOUT":"FILE_VALIDATION_FAILED");}catch(Exception e){throw invalid("FILE_VALIDATION_FAILED");}
        finally{
            try{if(helper!=null)Files.deleteIfExists(helper);if(input!=null)Files.deleteIfExists(input);if(directory!=null)Files.deleteIfExists(directory);}catch(IOException e){throw invalid("FILE_WORKSPACE_CLEANUP_FAILED");}
        }
    }
    private static double duration(String value)throws Invalid{
        try{double n=Double.parseDouble(value);if(!Double.isFinite(n)||n<=0||n>361)throw invalid("FILE_AUDIO_DURATION");return n;}
        catch(NumberFormatException e){throw invalid("FILE_AUDIO_DURATION");}
    }
    record Output(byte[] text,long length){}
    Output run(Path helper,List<String> command,long limit,boolean capture,long deadline)throws Invalid{
        Process process=null;ExecutorService readers=Executors.newVirtualThreadPerTaskExecutor();
        try{
            var wrapped=new ArrayList<String>();wrapped.add(python);wrapped.add(helper.toString());wrapped.addAll(command);
            var builder=new ProcessBuilder(wrapped).redirectError(ProcessBuilder.Redirect.DISCARD);
            builder.environment().put("OPENBLAS_NUM_THREADS","1");builder.environment().put("OMP_NUM_THREADS","1");
            process=builder.start();process.getOutputStream().close();
            Process running=process;
            var output=readers.submit(()->{
                try(var stream=running.getInputStream();var data=new ByteArrayOutputStream()){
                    var buffer=new byte[16384];long total=0;int n;
                    while((n=stream.read(buffer))!=-1){total+=n;if(total>limit){terminate(running);throw invalid("FILE_VALIDATION_TIMEOUT");}if(capture)data.write(buffer,0,n);}
                    return new Output(data.toByteArray(),total);
                }
            });
            long left=deadline-System.nanoTime();if(left<=0 || !process.waitFor(left,TimeUnit.NANOSECONDS))throw invalid("FILE_VALIDATION_TIMEOUT");
            left=deadline-System.nanoTime();if(left<=0)throw invalid("FILE_VALIDATION_TIMEOUT");
            Output result=output.get(left,TimeUnit.NANOSECONDS);
            if(process.exitValue()==124)throw invalid("FILE_VALIDATION_TIMEOUT");if(process.exitValue()==126)throw invalid("FILE_VALIDATOR_UNAVAILABLE");if(process.exitValue()==125)throw invalid("FILE_SANDBOX_UNAVAILABLE");if(process.exitValue()!=0)throw invalid("FILE_DECODE_FAILED");return result;
        }catch(Invalid e){throw e;}catch(InterruptedException e){Thread.currentThread().interrupt();throw invalid("FILE_VALIDATION_INTERRUPTED");}
        catch(TimeoutException e){throw invalid("FILE_VALIDATION_TIMEOUT");}
        catch(ExecutionException e){if(e.getCause() instanceof Invalid invalid)throw invalid;throw invalid("FILE_DECODE_FAILED");}
        catch(IOException e){throw invalid("FILE_VALIDATOR_UNAVAILABLE");}
        finally{if(process!=null){terminate(process);try{process.getInputStream().close();}catch(IOException ignored){}}readers.shutdownNow();}
    }
    private static void terminate(Process process){
        process.descendants().forEach(ProcessHandle::destroyForcibly);process.destroyForcibly();
        try{process.waitFor(1,TimeUnit.SECONDS);}catch(InterruptedException e){Thread.currentThread().interrupt();}
    }
    private static Invalid invalid(String code){return new Invalid(code);}
}
