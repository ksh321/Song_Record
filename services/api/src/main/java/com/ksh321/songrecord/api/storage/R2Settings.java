package com.ksh321.songrecord.api.storage;

import java.net.URI;
import org.springframework.core.env.Environment;

/** Secrets are selected for ONE environment and role; never use default AWS credentials. */
final class R2Settings {
    final String environment,role,temporaryBucket,finalBucket,accessKey,secretKey;
    final URI endpoint;
    private R2Settings(String env,String role,String account,String temporary,String target,String access,String secret) {
        if(!env.matches("dev|prod") || !role.matches("api|worker|playback") || !account.matches("[a-f0-9]{32}"))throw invalid();
        if(!temporary.matches("[a-z0-9][a-z0-9-]{1,61}[a-z0-9]") || !target.matches("[a-z0-9][a-z0-9-]{1,61}[a-z0-9]")
            || !temporary.endsWith("-"+env+"-temporary") || !target.endsWith("-"+env+"-final"))throw invalid();
        if(access.isBlank() || secret.isBlank())throw invalid();
        this.environment=env;this.role=role;temporaryBucket=temporary;finalBucket=target;accessKey=access;secretKey=secret;
        endpoint=URI.create("https://"+account+".r2.cloudflarestorage.com");
    }
    static R2Settings from(Environment env) {
        String name=required(env,"songrecord.storage.environment"),role=required(env,"songrecord.storage.role");
        if(!name.matches("dev|prod") || !role.matches("api|worker|playback"))throw invalid();
        String prefix="songrecord.storage."+name+".";
        return new R2Settings(name,role,required(env,prefix+"account-id"),required(env,prefix+"temporary-bucket"),
            required(env,prefix+"final-bucket"),required(env,prefix+role+".access-key"),required(env,prefix+role+".secret-key"));
    }
    static R2Settings playbackFrom(Environment env) {
        String name=required(env,"songrecord.storage.environment");
        if(!name.matches("dev|prod"))throw invalid();
        String prefix="songrecord.storage."+name+".";
        // Dedicated final reader: no fallback to an uploader or worker.
        return new R2Settings(name,"playback",required(env,prefix+"account-id"),
            required(env,prefix+"temporary-bucket"),required(env,prefix+"final-bucket"),
            required(env,prefix+"playback.access-key"),required(env,prefix+"playback.secret-key"));
    }
    private static String required(Environment e,String k){String v=e.getProperty(k);if(v==null)throw invalid();return v;}
    private static IllegalStateException invalid(){return new IllegalStateException("R2 configuration missing or invalid; inspect server-only environment/role settings");}
    @Override public String toString(){return "R2Settings[REDACTED]";}
}
