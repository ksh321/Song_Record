package com.ksh321.songrecord.api.sync;

import com.ksh321.songrecord.api.web.ApiException;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.time.*;
import java.util.*;
import javax.crypto.Cipher;
import javax.crypto.spec.*;
import org.springframework.http.HttpStatus;

/** D09 page positions. Callers must independently authenticate and check the READY header. */
public final class SnapshotPageCursor {
    private static final byte[] AAD = "SongRecord:snapshot-page:1".getBytes(StandardCharsets.US_ASCII);
    private static final int PLAIN_SIZE = 16 + 16 + 32 + 8 + 8;
    private final SecretKeySpec key;
    private final Clock clock;
    private final SecureRandom random = new SecureRandom();

    public SnapshotPageCursor(byte[] key, Clock clock) {
        if (key == null || key.length != 32) throw new IllegalArgumentException("Expected 32-byte cursor key");
        this.key = new SecretKeySpec(key.clone(), "AES");
        this.clock = Objects.requireNonNull(clock);
    }

    public String issue(UUID owner, UUID snapshot, String entity, long ordinal, Instant expiresAt) {
        if (ordinal < 1) throw new IllegalArgumentException("Expected a consumed row ordinal");
        byte[] scope = scope(owner, snapshot, entity);
        long expiry = Objects.requireNonNull(expiresAt).toEpochMilli();
        if (!clock.instant().isBefore(expiresAt)) throw expired();
        try {
            byte[] plain = ByteBuffer.allocate(PLAIN_SIZE).put(scope).putLong(ordinal).putLong(expiry).array();
            byte[] iv = new byte[12]; random.nextBytes(iv);
            Cipher cipher = cipher(Cipher.ENCRYPT_MODE, iv);
            byte[] encrypted = cipher.doFinal(plain);
            return "sp1." + Base64.getUrlEncoder().withoutPadding().encodeToString(
                    ByteBuffer.allocate(iv.length + encrypted.length).put(iv).put(encrypted).array());
        } catch (GeneralSecurityException e) { throw new IllegalStateException("Snapshot cursor encoding failed"); }
    }

    /** Header expiry is authoritative: issuing a later page never extends it. */
    public long read(String token, UUID owner, UUID snapshot, String entity, Instant expiresAt) {
        byte[] expected = scope(owner, snapshot, entity);
        Objects.requireNonNull(expiresAt);
        try {
            if (token == null || token.length() > 200 || !token.startsWith("sp1.")) throw invalid();
            String encoded = token.substring(4);
            byte[] wire = Base64.getUrlDecoder().decode(encoded);
            if (wire.length != 12 + PLAIN_SIZE + 16 ||
                    !Base64.getUrlEncoder().withoutPadding().encodeToString(wire).equals(encoded)) throw invalid();
            var plain = ByteBuffer.wrap(cipher(Cipher.DECRYPT_MODE, Arrays.copyOf(wire, 12))
                    .doFinal(wire, 12, wire.length - 12));
            byte[] actual = new byte[expected.length]; plain.get(actual);
            long ordinal = plain.getLong(), expiry = plain.getLong();
            if (!MessageDigest.isEqual(actual, expected) || ordinal < 1 || expiry != expiresAt.toEpochMilli()) throw invalid();
            if (!clock.instant().isBefore(expiresAt)) throw expired();
            return ordinal;
        } catch (ApiException e) { throw e; }
        catch (GeneralSecurityException | IllegalArgumentException e) { throw invalid(); }
    }

    private Cipher cipher(int mode, byte[] iv) throws GeneralSecurityException {
        var cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(mode, key, new GCMParameterSpec(128, iv)); cipher.updateAAD(AAD);
        return cipher;
    }
    private static byte[] scope(UUID owner, UUID snapshot, String entity) {
        Objects.requireNonNull(owner); Objects.requireNonNull(snapshot);
        if (entity == null || !entity.matches("[A-Z][A-Z_]{0,31}")) throw new IllegalArgumentException("Invalid entity scope");
        try {
            return ByteBuffer.allocate(64)
                    .putLong(owner.getMostSignificantBits()).putLong(owner.getLeastSignificantBits())
                    .putLong(snapshot.getMostSignificantBits()).putLong(snapshot.getLeastSignificantBits())
                    .put(MessageDigest.getInstance("SHA-256").digest(entity.getBytes(StandardCharsets.US_ASCII))).array();
        } catch (NoSuchAlgorithmException e) { throw new IllegalStateException("SHA-256 unavailable"); }
    }
    private static ApiException invalid() {
        return new ApiException(HttpStatus.BAD_REQUEST, "INVALID_CURSOR", "스냅샷 조회 위치를 확인해 주세요.", false, Map.of());
    }
    private static ApiException expired() {
        return new ApiException(HttpStatus.GONE, "SNAPSHOT_EXPIRED", "미전송 자료를 보존하고 새 스냅샷을 받아 주세요.", false, Map.of());
    }
}
