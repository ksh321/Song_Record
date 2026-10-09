package com.ksh321.songrecord.api.songs;

import java.time.Clock;
import org.springframework.context.annotation.*;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.beans.factory.ObjectProvider;
import com.ksh321.songrecord.api.karaoke.LiveCandidates;

@Configuration(proxyBeanMethods=false)
public class CandidateConfiguration {
    @Bean @Primary CandidateVerifier candidateVerifier(Environment environment, ObjectProvider<LiveCandidates> live) {
        boolean fixtures=environment.acceptsProfiles(Profiles.of("candidate-fixtures"));
        if(fixtures) {
            if(!environment.acceptsProfiles(Profiles.of("dev"))
                    || environment.acceptsProfiles(Profiles.of("prod","production")))
                throw new IllegalStateException("Candidate fixtures require dev and forbid production profiles");
            return new DevelopmentCandidates(Clock.systemUTC());
        }
        var source=live.getIfAvailable();
        return source==null?token->{throw TjCandidates.unavailable();}:source;
    }
    @Bean TjCandidates tjCandidates(CandidateVerifier verifier){return new TjCandidates(verifier,Clock.systemUTC());}
}
