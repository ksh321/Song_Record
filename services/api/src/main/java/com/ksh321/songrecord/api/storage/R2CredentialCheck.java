package com.ksh321.songrecord.api.storage;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.Properties;
import org.springframework.core.env.PropertiesPropertySource;
import org.springframework.core.env.StandardEnvironment;

/** Private local checker: bounded stdin only, fixed status output, no token/exception logging. */
public final class R2CredentialCheck {
    private R2CredentialCheck() {}
    public static void main(String[] args) {
        // Even SDK logging must not reach the report, terminal, or a raw log.
        PrintStream report=System.out;
        System.setOut(new PrintStream(OutputStream.nullOutputStream()));
        System.setErr(new PrintStream(OutputStream.nullOutputStream()));
        try {
            byte[] input=System.in.readNBytes(16385);
            if(input.length>16384)throw new IllegalArgumentException();
            var properties=new Properties();properties.load(new StringReader(new String(input,StandardCharsets.UTF_8)));
            java.util.Arrays.fill(input,(byte)0);
            var env=new StandardEnvironment();env.getPropertySources().addFirst(new PropertiesPropertySource("private-input",properties));
            try(var storage=new R2StorageConfiguration().r2Storage(env)) {
                String own=properties.getProperty("songrecord.storage.environment");
                if(!"dev".equals(own)&&!"prod".equals(own))throw new IllegalArgumentException();
                boolean full=properties.getProperty("diagnostic.mode", "read").equals("development-write");
                if(full && !own.equals("dev")) throw new IllegalArgumentException();
                if(properties.getProperty("diagnostic.mode", "read").equals("signed-put")){
                    if(!own.equals("dev") || !properties.getProperty("songrecord.storage.role").equals("api"))throw new IllegalArgumentException();
                    try(var signer=new R2StorageConfiguration().r2PutSigner(env)){report.println("signed.temporary="+storage.checkDevelopmentSignedPut(signer));}
                    properties.clear();return;
                }
                if(properties.getProperty("diagnostic.mode", "read").equals("audio-validation")){
                    if(!own.equals("dev") || !properties.getProperty("songrecord.storage.role").equals("worker"))throw new IllegalArgumentException();
                    byte[] synthetic;
                    try(var file=java.nio.file.Files.newInputStream(java.nio.file.Path.of(properties.getProperty("diagnostic.audio-file")))){synthetic=file.readNBytes(6*1024*1024+1);}
                    var validator=new com.ksh321.songrecord.api.uploads.AudioValidator(properties.getProperty("diagnostic.ffmpeg"),properties.getProperty("diagnostic.ffprobe"));
                    report.println("audio.temporary="+storage.checkDevelopmentAudio(validator,synthetic));
                    properties.clear();return;
                }
                // Test an accessible bucket first; four DENIED results cannot pass as isolation.
                for(String name:new String[]{own,"dev".equals(own)?"prod":"dev"})
                    for(String kind:new String[]{"temporary","final"})
                        report.println(name+"."+kind+"="+storage.checkBucketRead("song-record-"+name+"-"+kind));
                if(full) for(String kind:new String[]{"temporary","final"})
                    report.println("write."+kind+"="+storage.checkDevelopmentWrite(kind));
            }
            properties.clear();
        }catch(Exception e){report.println("CHECK_ERROR");System.exit(2);}
    }
}
