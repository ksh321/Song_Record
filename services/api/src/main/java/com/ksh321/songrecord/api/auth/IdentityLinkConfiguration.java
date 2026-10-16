package com.ksh321.songrecord.api.auth;

import java.net.URI;
import java.time.Clock;
import java.util.Set;
import com.nimbusds.jose.jwk.source.JWKSourceBuilder;
import com.nimbusds.jose.proc.SecurityContext;
import com.nimbusds.jose.util.DefaultResourceRetriever;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;

@Configuration(proxyBeanMethods=false)
@Profile("!bootstrap")
public class IdentityLinkConfiguration {
    @Bean(destroyMethod="close")
    LinkVerifierRegistry linkVerifierRegistry(@Value("${auth.google.server-client-id:}") String google,
                                             @Value("${auth.kakao.native-app-key:}") String kakao,
                                             @Value("${auth.kakao.beta-native-app-key:}") String betaKakao) throws Exception {
        return new LinkVerifierRegistry(google,kakao,betaKakao);
    }
    @Bean IdentityLinkService identityLinkService(JdbcTemplate jdbc, PlatformTransactionManager tx,
                                                 SessionService sessions,LinkVerifierRegistry proofs) {
        return new IdentityLinkService(jdbc,tx,sessions,proofs,Clock.systemUTC());
    }
    static final class LinkVerifierRegistry implements LinkProofVerifier,AutoCloseable {
        private final java.util.Map<String,LinkOidcVerifier> verifiers=new java.util.HashMap<>();
        private final java.util.List<com.nimbusds.jose.jwk.source.JWKSource<SecurityContext>> sources=new java.util.ArrayList<>();
        LinkVerifierRegistry(String google,String kakao) throws Exception {
            this(google,kakao,"");
        }
        LinkVerifierRegistry(String google,String kakao,String betaKakao) throws Exception {
            if(!betaKakao.isBlank() && (kakao.isBlank() || !betaKakao.matches("[a-fA-F0-9]{32}")))
                throw new IllegalArgumentException("Explicit beta native key requires existing native key");
            if(!google.isBlank()) add("GOOGLE",Set.of(google),Set.of("accounts.google.com","https://accounts.google.com"),"https://www.googleapis.com/oauth2/v3/certs");
            if(!kakao.isBlank()) {
                var audiences=new java.util.HashSet<String>();audiences.add(kakao);
                if(!betaKakao.isBlank())audiences.add(betaKakao);
                add("KAKAO",audiences,Set.of("https://kauth.kakao.com"),"https://kauth.kakao.com/.well-known/jwks.json");
            }
        }
        private void add(String provider,Set<String> audiences,Set<String> issuers,String url) throws Exception {
            var keys=JWKSourceBuilder.<SecurityContext>create(URI.create(url).toURL(),new DefaultResourceRetriever(2000,3000,65536))
                    .cache(300000,5000).refreshAheadCache(false).retrying(false).build();
            sources.add(keys);verifiers.put(provider,new LinkOidcVerifier(provider,audiences,issuers,keys,Clock.systemUTC()));
        }
        public VerifiedProviderIdentity verify(String provider,String proof,byte[] nonceHash,java.time.Instant startedAt) {
            var verifier=verifiers.get(provider);if(verifier==null)throw ProofErrors.unavailable();
            return verifier.verify(proof,nonceHash,startedAt);
        }
        public void close() throws Exception {for(var source:sources) if(source instanceof AutoCloseable c)c.close();}
    }
}
