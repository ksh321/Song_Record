package com.ksh321.songrecord.api.songs;

import java.time.Clock;
import org.springframework.context.annotation.*;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;

@Configuration(proxyBeanMethods=false)
public class CandidateConfiguration {
    @Bean CandidateVerifier candidateVerifier(Environment environment) {
        boolean fixtures=environment.acceptsProfiles(Profiles.of("candidate-fixtures"));
        if(fixtures) {
            if(!environment.acceptsProfiles(Profiles.of("dev"))
                    || environment.acceptsProfiles(Profiles.of("prod","production")))
                throw new IllegalStateException("Candidate fixtures require dev and forbid production profiles");
            return new DevelopmentCandidates(Clock.systemUTC());
        }
        // P15 replaces this with a real source-token verifier. Never trust bare client numbers.
        return token->{throw TjCandidates.unavailable();};
    }
    @Bean TjCandidates tjCandidates(CandidateVerifier verifier){return new TjCandidates(verifier,Clock.systemUTC());}
}
