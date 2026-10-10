package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.karaoke.*;
import com.ksh321.songrecord.api.songs.*;
import com.ksh321.songrecord.api.songs.CandidateVerifier.Brand;
import com.ksh321.songrecord.api.revision.CreationGuard;
import com.ksh321.songrecord.api.sync.AccountChanges;
import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.http.HttpStatus;
import static org.assertj.core.api.Assertions.*;

/** Real encrypted source evidence and registration services; only upstream data is controlled. */
class KaraokeRegistrationTests {
    final SongCreationTests fixture=new SongCreationTests();
    SourceTokens tokens;SongCreation creation;boolean outage;String refreshed="00123";int requests;
    @BeforeEach void setup() throws Exception {
        fixture.setup();var f=fixture.f;tokens=new SourceTokens(new byte[32],f.clock);
        var live=new LiveCandidates(tokens,(brand,kind,number)->{
            requests++;assertThat(brand).isEqualTo(Brand.TJ);assertThat(kind).isEqualTo(MananaSearchAdapter.Kind.NUMBER);
            assertThat(number).isEqualTo("00123");
            if(outage)throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE,"CANDIDATE_VERIFICATION_UNAVAILABLE","upstream unavailable",true,Map.of());
            return List.of(candidate(Brand.TJ,refreshed));
        },new SearchLimit(f.clock),f.clock);
        creation=new SongCreation(f.jdbc,f.access,f.mutations,new CreationGuard(f.jdbc,f.access,f.manager),new AccountChanges(f.jdbc,f.access,f.manager,f.clock),new TjCandidates(live,f.clock),f.clock);
    }
    @AfterEach void close() throws Exception {fixture.close();}
    MananaSearchAdapter.Candidate candidate(Brand brand,String number){return new MananaSearchAdapter.Candidate(brand,number,"원본 (LIVE)","원본 가수","MANANA","manana:"+(brand==Brand.TJ?"tj":"kumyoung")+":"+number);}
    String token(Brand brand,String number,boolean expired){var c=candidate(brand,number);var end=fixture.f.clock.instant;return tokens.encode(expired?new SourceTokens.Proof(c,end.minusSeconds(86400),end):tokens.issueProof(c));}
    String body(UUID id,String token,String title){return "{\"id\":\""+id+"\",\"source_type\":\"TJ\",\"source_token\":\""+token+"\",\"title\":\""+title+"\",\"artist\":\"내 가수\",\"version_code\":\"MR\",\"note\":\"offline draft\"}";}
    com.ksh321.songrecord.api.idempotency.IdempotentMutations.Reply send(String op,String body){var f=fixture.f;return creation.create("Bearer "+f.tokens.accessToken(),f.registration.deviceId().toString(),op,body);}
    int count(String table){return fixture.count(table);}
    @Test void sameNumberReusesCanonicalAndPreservesEditsDifferentNumberRemainsDistinct(){
        var first=UUID.randomUUID();var proof=token(Brand.TJ,"00123",false);
        assertThat(send(UUID.randomUUID().toString(),body(first,proof,"내 편집값")).status()).isEqualTo(201);
        var duplicate=send(UUID.randomUUID().toString(),body(UUID.randomUUID(),proof,"다른 표기").replace("내 가수","다른 가수").replace("MR","LIVE"));
        assertThat(duplicate.status()).isEqualTo(200);assertThat(duplicate.body()).contains(first.toString(),"내 편집값","내 가수","MR","offline draft");
        assertThat(count("song")).isEqualTo(1);assertThat(count("change_log")).isEqualTo(1);
        assertThat(send(UUID.randomUUID().toString(),body(UUID.randomUUID(),token(Brand.TJ,"00124",false),"내 편집값")).status()).isEqualTo(201);
        assertThat(count("song")).isEqualTo(2);assertThat(count("song_source")).isEqualTo(2);
        assertThat(fixture.f.jdbc.queryForObject("SELECT source_title FROM song_source LIMIT 1",String.class)).isEqualTo("원본 (LIVE)");
    }
    @Test void kyAndTamperedProofCannotCreateAnyMetadata(){
        var valid=token(Brand.TJ,"00123",false);var forged=valid.substring(0,8)+(valid.charAt(8)=='A'?"B":"A")+valid.substring(9);
        assertThatThrownBy(()->send(UUID.randomUUID().toString(),body(UUID.randomUUID(),token(Brand.KY,"00123",false),"입력"))).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("SONG_TJ_REQUIRED"));
        assertThatThrownBy(()->send(UUID.randomUUID().toString(),body(UUID.randomUUID(),forged,"입력"))).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("SOURCE_TOKEN_INVALID"));
        for(var table:List.of("song","song_source","mutation_receipt","change_log"))assertThat(count(table)).isZero();
        assertThat(requests).isZero();
    }
    @Test void expiredProofOutagePreservesRequestAndSameOperationCanRetryAndReplay(){
        var op=UUID.randomUUID().toString();var draft=body(UUID.randomUUID(),token(Brand.TJ,"00123",true),"오프라인 입력");outage=true;
        assertThatThrownBy(()->send(op,draft)).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("CANDIDATE_VERIFICATION_UNAVAILABLE"));
        for(var table:List.of("song","song_source","mutation_receipt","change_log"))assertThat(count(table)).isZero();
        outage=false;var first=send(op,draft);assertThat(first.status()).isEqualTo(201);assertThat(first.body()).contains("오프라인 입력","00123","offline draft");
        assertThat(send(op,draft)).isEqualTo(first);assertThat(requests).isEqualTo(2);assertThat(count("song")).isEqualTo(1);assertThat(count("change_log")).isEqualTo(1);
    }
    @Test void expiredProofCannotSwitchOriginalNumber(){
        refreshed="123";assertThatThrownBy(()->send(UUID.randomUUID().toString(),body(UUID.randomUUID(),token(Brand.TJ,"00123",true),"입력"))).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("SOURCE_CANDIDATE_NOT_FOUND"));
        for(var table:List.of("song","song_source","mutation_receipt","change_log"))assertThat(count(table)).isZero();
    }
}
