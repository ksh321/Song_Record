package com.ksh321.songrecord.api.karaoke;

import com.ksh321.songrecord.api.songs.CandidateVerifier.Brand;
import com.ksh321.songrecord.api.web.ApiException;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.time.*;
import java.util.*;
import javax.crypto.*;
import javax.crypto.spec.*;
import org.springframework.http.HttpStatus;

/** Authenticated source evidence, never an account/session authority. */
public final class SourceTokens {
    private static final byte[] AAD="SongRecord:karaoke-source:1".getBytes(StandardCharsets.US_ASCII);
    private final SecretKeySpec key;private final Clock clock;private final SecureRandom random=new SecureRandom();
    public SourceTokens(byte[] key,Clock clock){if(key!=null && key.length!=32)throw new IllegalArgumentException("Source key must be 32 bytes");this.key=key==null?null:new SecretKeySpec(key.clone(),"AES");this.clock=Objects.requireNonNull(clock);}
    public record Proof(MananaSearchAdapter.Candidate candidate,Instant issuedAt,Instant expiresAt){@Override public String toString(){return "SourceProof[REDACTED]";}}
    public void requireAvailable(){if(key==null)throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE,"SEARCH_SIGNING_UNAVAILABLE","검색 검증 설정을 준비 중입니다.",true,Map.of());}
    public Proof issueProof(MananaSearchAdapter.Candidate c){validate(c);var now=clock.instant().truncatedTo(java.time.temporal.ChronoUnit.MILLIS);return new Proof(c,now,now.plus(Duration.ofHours(24)));}
    public String encode(Proof proof){
        requireAvailable();validate(proof.candidate());
        if(!proof.expiresAt().equals(proof.issuedAt().plus(Duration.ofHours(24))))throw new IllegalArgumentException("Invalid proof lifetime");
        try {
            var bytes=new ByteArrayOutputStream();var out=new DataOutputStream(bytes);var c=proof.candidate();
            out.writeUTF(c.provider());out.writeUTF(c.brand().name());out.writeUTF(c.number());out.writeUTF(c.title());out.writeUTF(c.artist());out.writeUTF(c.sourceRef());out.writeLong(proof.issuedAt().toEpochMilli());out.writeLong(proof.expiresAt().toEpochMilli());
            var iv=new byte[12];random.nextBytes(iv);var cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.ENCRYPT_MODE,key,new GCMParameterSpec(128,iv));cipher.updateAAD(AAD);
            var wire=new ByteArrayOutputStream();wire.write(iv);wire.write(cipher.doFinal(bytes.toByteArray()));return "s1."+Base64.getUrlEncoder().withoutPadding().encodeToString(wire.toByteArray());
        }catch(GeneralSecurityException|IOException e){throw new IllegalStateException("Source encoding unavailable");}
    }
    public Proof read(String token){
        requireAvailable();
        try {
            if(token==null || token.length()>8192 || !token.startsWith("s1."))throw invalid();var encoded=token.substring(3);var wire=Base64.getUrlDecoder().decode(encoded);
            if(wire.length<28 || !encoded.equals(Base64.getUrlEncoder().withoutPadding().encodeToString(wire)))throw invalid();
            var cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.DECRYPT_MODE,key,new GCMParameterSpec(128,Arrays.copyOf(wire,12)));cipher.updateAAD(AAD);
            var in=new DataInputStream(new ByteArrayInputStream(cipher.doFinal(wire,12,wire.length-12)));
            var provider=in.readUTF();var brand=Brand.valueOf(in.readUTF());var number=in.readUTF();var title=in.readUTF();var artist=in.readUTF();var source=in.readUTF();var issued=Instant.ofEpochMilli(in.readLong());var expires=Instant.ofEpochMilli(in.readLong());
            var candidate=new MananaSearchAdapter.Candidate(brand,number,title,artist,provider,source);validate(candidate);
            if(in.available()!=0 || issued.isAfter(clock.instant()) || !expires.equals(issued.plus(Duration.ofHours(24))))throw invalid();
            // Expiration is preserved for P15-04's exact-number re-verification.
            return new Proof(candidate,issued,expires);
        }catch(ApiException e){throw e;}catch(Exception e){throw invalid();}
    }
    private static void validate(MananaSearchAdapter.Candidate c){if(c==null || c.brand()==null || !"MANANA".equals(c.provider()) || c.number()==null || !c.number().matches("[0-9]{1,20}") || c.title()==null || c.title().isBlank() || c.artist()==null || c.artist().isBlank() || c.title().codePointCount(0,c.title().length())>200 || c.artist().codePointCount(0,c.artist().length())>200 || !("manana:"+(c.brand()==Brand.TJ?"tj":"kumyoung")+":"+c.number()).equals(c.sourceRef()))throw invalid();}
    private static ApiException invalid(){return new ApiException(HttpStatus.BAD_REQUEST,"SOURCE_TOKEN_INVALID","검색 후보를 다시 확인해 주세요.",false,Map.of());}
}
