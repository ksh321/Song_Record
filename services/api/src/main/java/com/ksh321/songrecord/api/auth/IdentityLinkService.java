package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.web.ApiException;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.time.*;
import java.time.temporal.ChronoUnit;
import java.util.*;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.*;
import org.springframework.transaction.support.TransactionTemplate;

public final class IdentityLinkService {
    private final JdbcTemplate jdbc;
    private final TransactionTemplate tx;
    private final SessionService sessions;
    private final LinkProofVerifier proofs;
    private final Clock clock;
    private final SecureRandom random=new SecureRandom();
    public IdentityLinkService(JdbcTemplate jdbc, PlatformTransactionManager manager, SessionService sessions,
                               LinkProofVerifier proofs, Clock clock) {
        this.jdbc=jdbc;this.sessions=sessions;this.proofs=proofs;this.clock=clock;
        tx=new TransactionTemplate(manager);tx.setIsolationLevel(TransactionDefinition.ISOLATION_READ_COMMITTED);
        tx.setTimeout(10);
    }
    public List<Identity> identities(String access, UUID device) {
        var owner=sessions.authenticate(access,device);
        return jdbc.query("SELECT id,provider FROM auth_identity WHERE user_id=? ORDER BY provider,id",
                (rs,n)->new Identity(uuid(rs.getBytes(1)).toString(),rs.getString(2)),bytes(owner.userId()));
    }
    public Challenge begin(String access, UUID device, String provider, String target) {
        provider(provider);provider(target);
        if(provider.equals(target)) throw error("VALIDATION_FAILED","서로 다른 로그인 수단을 선택해 주세요.");
        return tx.execute(s->{
            var owner=lock(access,device);
            if(count("SELECT COUNT(*) FROM auth_identity WHERE user_id=? AND provider=?",bytes(owner.userId()),provider)==0)
                throw error("REAUTH_IDENTITY_MISMATCH","현재 계정의 로그인 수단으로 다시 인증해 주세요.");
            if(count("SELECT COUNT(*) FROM auth_identity WHERE user_id=? AND provider=?",bytes(owner.userId()),target)>0)
                throw error("IDENTITY_ALREADY_LINKED","이미 연결된 로그인 수단이에요.");
            // One pending flow per session. Another device cannot invalidate this device's flow.
            jdbc.update("DELETE FROM auth_link_challenge WHERE session_id=?",bytes(owner.sessionId()));
            return create(owner.sessionId(),"REAUTH",provider,target);
        });
    }
    public Challenge reauthenticate(String access, UUID device, UUID id, String proof) {
        var before=sessions.authenticate(access,device);
        var challenge=read(id,before.sessionId(),"REAUTH",false);
        var identity=proofs.verify(challenge.provider(),proof,challenge.nonceHash(),challenge.created().toInstant(ZoneOffset.UTC));
        return tx.execute(s->{
            var owner=lock(access,device); var current=read(id,owner.sessionId(),"REAUTH",true);
            if(!current.provider().equals(identity.provider()) || count("SELECT COUNT(*) FROM auth_identity WHERE user_id=? AND provider=? AND provider_user_id=?",
                    bytes(owner.userId()),identity.provider(),identity.providerUserId())!=1)
                throw error("REAUTH_IDENTITY_MISMATCH","현재 계정에 연결된 계정으로 다시 인증해 주세요.");
            consume(id);
            return create(owner.sessionId(),"LINK",current.target(),current.target());
        });
    }
    public void link(String access, UUID device, UUID id, String proof) {
        var before=sessions.authenticate(access,device);
        var challenge=read(id,before.sessionId(),"LINK",false);
        var identity=proofs.verify(challenge.provider(),proof,challenge.nonceHash(),challenge.created().toInstant(ZoneOffset.UTC));
        String failure=tx.execute(s->{
            var owner=lock(access,device);var current=read(id,owner.sessionId(),"LINK",true);
            if(!current.provider().equals(identity.provider())) throw ProofErrors.invalid();
            consume(id);
            var existing=jdbc.query("SELECT user_id FROM auth_identity WHERE provider=? AND provider_user_id=?",
                    (rs,n)->uuid(rs.getBytes(1)),identity.provider(),identity.providerUserId());
            if(!existing.isEmpty()) return existing.getFirst().equals(owner.userId())?"IDENTITY_ALREADY_LINKED":"IDENTITY_IN_USE";
            if(count("SELECT COUNT(*) FROM auth_identity WHERE user_id=? AND provider=?",bytes(owner.userId()),identity.provider())>0)
                return "IDENTITY_ALREADY_LINKED";
            try {
                jdbc.update("INSERT INTO auth_identity(id,user_id,provider,provider_user_id,created_at,updated_at) VALUES(?,?,?,?,?,?)",
                        bytes(UUID.randomUUID()),bytes(owner.userId()),identity.provider(),identity.providerUserId(),now(),now());
            } catch(DuplicateKeyException e) {
                // MySQL rolls back the duplicate statement only. Commit consumption, never merge users.
                return "IDENTITY_IN_USE";
            }
            return null;
        });
        if(failure!=null) throw error(failure,"IDENTITY_IN_USE".equals(failure)
                ?"다른 노래기록 계정에서 사용 중인 로그인 수단이에요. 계정은 자동으로 합쳐지지 않아요.":"이미 연결된 로그인 수단이에요.");
    }
    private SessionService.Principal lock(String access, UUID device) {
        var p=sessions.authenticate(access,device);
        jdbc.queryForList("SELECT id FROM app_user WHERE id=? FOR UPDATE",bytes(p.userId()));
        jdbc.queryForList("SELECT id FROM device WHERE id=? FOR UPDATE",bytes(p.deviceId()));
        jdbc.queryForList("SELECT id FROM auth_session WHERE id=? FOR UPDATE",bytes(p.sessionId()));
        return sessions.authenticate(access,device);
    }
    private Challenge create(UUID session,String stage,String provider,String target) {
        byte[] b=new byte[32];random.nextBytes(b);String nonce=Base64.getUrlEncoder().withoutPadding().encodeToString(b);
        UUID id=UUID.randomUUID();var at=now();var expires=at.plusMinutes(5);
        jdbc.update("INSERT INTO auth_link_challenge(id,session_id,stage,provider,target_provider,nonce_hash,created_at,expires_at) VALUES(?,?,?,?,?,?,?,?)",
                bytes(id),bytes(session),stage,provider,target,hash(nonce),at,expires);
        return new Challenge(id.toString(),nonce,expires.toInstant(ZoneOffset.UTC).toString());
    }
    private Row read(UUID id,UUID session,String stage,boolean locking) {
        if(id==null) throw expired();
        var rows=jdbc.query("SELECT provider,target_provider,nonce_hash,created_at,expires_at,consumed_at FROM auth_link_challenge WHERE id=? AND session_id=? AND stage=?"+(locking?" FOR UPDATE":""),
                (rs,n)->new Row(rs.getString(1),rs.getString(2),rs.getBytes(3),rs.getObject(4,LocalDateTime.class),rs.getObject(5,LocalDateTime.class),rs.getObject(6)!=null),
                bytes(id),bytes(session),stage);
        if(rows.size()!=1 || rows.getFirst().consumed() || !rows.getFirst().expires().isAfter(now())) throw expired();
        return rows.getFirst();
    }
    private void consume(UUID id) {jdbc.update("UPDATE auth_link_challenge SET consumed_at=? WHERE id=?",now(),bytes(id));}
    private int count(String sql,Object... args) {return jdbc.queryForObject(sql,Integer.class,args);}
    private LocalDateTime now() {return LocalDateTime.ofInstant(clock.instant(),ZoneOffset.UTC).truncatedTo(ChronoUnit.MILLIS);}
    private static void provider(String value) {if(!"GOOGLE".equals(value) && !"KAKAO".equals(value))throw error("VALIDATION_FAILED","로그인 수단을 확인해 주세요.");}
    private static ApiException expired() {return error("LINK_CHALLENGE_EXPIRED","연결 요청이 만료되었거나 사용됐어요. 처음부터 다시 시도해 주세요.");}
    private static ApiException error(String code,String message) {return new ApiException(HttpStatus.CONFLICT,code,message,false,Map.of());}
    private static byte[] hash(String s) {try{return MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8));}catch(NoSuchAlgorithmException e){throw new IllegalStateException(e);}}
    private static byte[] bytes(UUID id) {return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();}
    private static UUID uuid(byte[] bytes) {var b=ByteBuffer.wrap(bytes);return new UUID(b.getLong(),b.getLong());}
    public record Identity(String id,String provider) {}
    public record Challenge(String challengeId,String nonce,String expiresAt) {
        @Override public String toString(){return "Challenge[REDACTED]";}
    }
    private record Row(String provider,String target,byte[] nonceHash,LocalDateTime created,LocalDateTime expires,boolean consumed) {}
}
