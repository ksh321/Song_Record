package com.ksh321.songrecord.api.uploads;

import java.nio.*;
import java.nio.file.*;
import java.security.*;
import java.util.*;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.io.TempDir;
import static org.assertj.core.api.Assertions.*;

class AudioValidatorTests {
    @TempDir static Path temp;
    static final String FFMPEG=System.getenv().getOrDefault("SONG_RECORD_TEST_FFMPEG","ffmpeg");
    static final String FFPROBE=System.getenv().getOrDefault("SONG_RECORD_TEST_FFPROBE","ffprobe");
    final AudioValidator validator=new AudioValidator(FFMPEG,FFPROBE);
    static byte[] normal,lowRate,stereo,wrongRate,alac,main,ogg,longAudio,boundary,truncated,damaged,zero;
    @BeforeAll static void fixtures()throws Exception{
        zero=make("zero.m4a",0,"aac",48000,1,"96k");
        normal=make("normal.m4a",1,"aac",48000,1,"128k");
        lowRate=make("low.m4a",1,"aac",48000,1,"64k");
        stereo=make("stereo.m4a",1,"aac",48000,2,"96k");
        wrongRate=make("rate.m4a",1,"aac",44100,1,"96k");
        alac=make("alac.m4a",1,"alac",48000,1,"96k");
        // Change the AudioSpecificConfig object type to AAC Main; the validator must reject it before decoding.
        main=normal.clone();boolean patched=false;
        for(int i=0;i<main.length-6;i++)if(main[i]==5 && main[i+1]==(byte)0x80 && main[i+2]==(byte)0x80 && main[i+3]==(byte)0x80 && main[i+4]==5 && main[i+5]==0x11){main[i+5]=0x09;patched=true;break;}
        assertThat(patched).as("AAC AudioSpecificConfig fixture located").isTrue();
        ogg=make("other.ogg",1,"libopus",48000,1,"64k");
        boundary=make("boundary.m4a",361,"aac",48000,1,"96k");
        longAudio=make("long.m4a",361.1,"aac",48000,1,"96k");
        // Faststart retains the headers when the media tail is truncated.
        truncated=Arrays.copyOf(normal,normal.length-512);
        damaged=normal.clone();
        for(int i=4;i<damaged.length-4;i++)if(damaged[i]=='m'&&damaged[i+1]=='d'&&damaged[i+2]=='a'&&damaged[i+3]=='t'){
            Arrays.fill(damaged,i+4,Math.min(damaged.length,i+1024),(byte)0xff);break;
        }
    }
    static byte[] make(String name,double duration,String codec,int rate,int channels,String bitrate,String... extra)throws Exception{
        Path path=temp.resolve(name);var args=new ArrayList<>(List.of(FFMPEG,"-nostdin","-v","error","-f","lavfi","-i","sine=frequency=440:sample_rate="+rate,"-t",Double.toString(duration),"-ac",Integer.toString(channels),"-c:a",codec,"-b:a",bitrate));
        if(name.endsWith(".m4a"))args.addAll(List.of("-movflags","+faststart"));args.addAll(List.of(extra));args.add(path.toString());
        var process=new ProcessBuilder(args).redirectOutput(ProcessBuilder.Redirect.DISCARD).redirectError(ProcessBuilder.Redirect.DISCARD).start();
        try{assertThat(process.waitFor(45,TimeUnit.SECONDS)).as("fixture encoder completed").isTrue();assertThat(process.exitValue()).as("fixture encoder exit").isZero();}finally{process.destroyForcibly();}
        return Files.readAllBytes(path);
    }
    static String hash(byte[] data)throws Exception{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(data));}
    AudioValidator.Validated validate(byte[] data)throws Exception{return validator.validate(ByteBuffer.wrap(data),data.length,hash(data));}
    void rejected(byte[] data)throws Exception{assertThatThrownBy(()->validate(data)).isInstanceOf(AudioValidator.Invalid.class);}
    @Test void actualAacLcMono48kAndNon96kBitratesPassWithoutMutatingInput()throws Exception{
        for(var data:List.of(normal,lowRate)){
            var result=validate(data);assertThat(result.bytes().isReadOnly()).isTrue();var copied=new byte[result.bytes().remaining()];result.bytes().get(copied);assertThat(copied).isEqualTo(data);assertThat(result.sha256()).isEqualTo(hash(data));assertThat(result.durationSeconds()).isBetween(0.99,1.01);
            assertThat(result.toString()).isEqualTo("ValidatedAudio[REDACTED]");
        }
    }
    @Test void presentationDurationBoundaryPassesButLongerAudioFails()throws Exception{assertThat(validate(boundary).durationSeconds()).isEqualTo(361);rejected(longAudio);}
    @Test void stereoAndOtherSamplingRateAreRejected()throws Exception{rejected(stereo);rejected(wrongRate);}
    @Test void nonLcAndNonAacAndWrongContainersAreRejected()throws Exception{assertThatThrownBy(()->validate(main)).isInstanceOfSatisfying(AudioValidator.Invalid.class,e->assertThat(e.code).isEqualTo("FILE_AUDIO_FORMAT"));rejected(alac);rejected(ogg);}
    @Test void wholeDecodeRejectsDamagedAndTruncatedMediaDespiteReadableHeader()throws Exception{rejected(damaged);rejected(truncated);}
    @Test void invalidBytesAndSizeAndChecksumCannotReachSuccessfulValidation()throws Exception{
        rejected(zero);rejected(new byte[0]);rejected(new byte[]{1,2,3});rejected(new byte[6*1024*1024+1]);
        assertThatThrownBy(()->validator.validate(ByteBuffer.wrap(normal),normal.length+1,hash(normal))).isInstanceOfSatisfying(AudioValidator.Invalid.class,e->assertThat(e.code).isEqualTo("FILE_SIZE_MISMATCH"));
        assertThatThrownBy(()->validator.validate(ByteBuffer.wrap(normal),normal.length,"0".repeat(64))).isInstanceOfSatisfying(AudioValidator.Invalid.class,e->assertThat(e.code).isEqualTo("FILE_CHECKSUM_MISMATCH"));
    }
    @Test void unavailableToolFailsClosedWithoutLeakingPath()throws Exception{
        var missing=new AudioValidator("private-missing-tool","private-missing-tool");
        assertThatThrownBy(()->missing.validate(ByteBuffer.wrap(normal),normal.length,hash(normal))).isInstanceOfSatisfying(AudioValidator.Invalid.class,e->assertThat(e.code).isEqualTo("FILE_VALIDATOR_UNAVAILABLE")).hasMessageNotContaining("private-missing-tool");
    }
    @Test void consumerOnlyPassesVerifiedCapturedBytesToNextStage()throws Exception{
        var captured=org.mockito.Mockito.mock(UploadVerification.Captured.class);
        var original=normal.clone();
        org.mockito.Mockito.when(captured.bytes()).thenAnswer(call->ByteBuffer.wrap(original));
        org.mockito.Mockito.when(captured.expectedSize()).thenReturn((long)normal.length);
        org.mockito.Mockito.when(captured.expectedSha256()).thenReturn(hash(normal));
        var called=new java.util.concurrent.atomic.AtomicInteger();
        var consumer=validator.then((lease,audio)->{called.incrementAndGet();return ()->assertThat(audio.sha256()).isNotBlank();});
        var effects=consumer.prepare(null,captured);assertThat(called.get()).isEqualTo(1);
        original[0]^=1;
        assertThatThrownBy(()->consumer.prepare(null,captured)).isInstanceOf(AudioValidator.Invalid.class);
        assertThat(called.get()).isEqualTo(1);effects.run();
    }

}
