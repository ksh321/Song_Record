package com.ksh321.songrecord.api.pagination;

import com.ksh321.songrecord.api.idempotency.CanonicalRequest;
import com.ksh321.songrecord.api.web.ApiException;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.time.*;
import java.util.*;
import javax.crypto.Cipher;
import javax.crypto.spec.*;
import org.springframework.http.HttpStatus;

/** Authenticated, encrypted list cursor. Never a session token or a materialized snapshot. */
public final class PageCursor {
    public static final int MAX_LENGTH = 8192;
    private static final byte[] AAD = "SongRecord:list-cursor:1".getBytes(StandardCharsets.US_ASCII);
    private final SecretKeySpec key;
    private final Clock clock;
    private final SecureRandom random = new SecureRandom();
    private final Duration ttl;

    public record Query(String resource, String sort, String keyVersion, String filters, int limit) {
        public Query {
            if (resource == null || resource.isBlank() || sort == null || sort.isBlank()
                    || keyVersion == null || keyVersion.isBlank()) throw new IllegalArgumentException("Missing query contract");
            limit = pageSize(limit);
            filters = CanonicalRequest.canonical(filters);
        }
        @Override public String toString() { return "Query[REDACTED]"; }
    }
    public record Tuple(List<String> values, UUID id) {
        public Tuple {
            Objects.requireNonNull(id); Objects.requireNonNull(values);
            if (values.size() > 16) throw new IllegalArgumentException("Too many sort fields");
            values = Collections.unmodifiableList(new ArrayList<>(values)); // null sorts are explicit
        }
        @Override public String toString() { return "Tuple[REDACTED]"; }
    }
    public record Position(long generation, Tuple after) {
        @Override public String toString() { return "Position[REDACTED]"; }
    }
    public PageCursor(byte[] key, Clock clock, Duration ttl) {
        if (key == null || key.length != 32) throw new IllegalArgumentException("Cursor key must be 32 bytes");
        if (ttl == null || ttl.compareTo(Duration.ofSeconds(1)) < 0 || ttl.compareTo(Duration.ofHours(1)) > 0)
            throw new IllegalArgumentException("Invalid cursor lifetime");
        this.key = new SecretKeySpec(key.clone(), "AES"); this.clock = Objects.requireNonNull(clock); this.ttl = ttl;
    }
    public static int pageSize(Integer value) {
        if (value == null) return 50;
        if (value < 1 || value > 100) throw new ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "limit는 1~100이어야 합니다.", false, Map.of());
        return value;
    }
    public String issue(UUID owner, Query query, long generation, Tuple after) {
        if (generation < 0) throw new IllegalArgumentException("Invalid query generation");
        try {
            var buffer = new ByteArrayOutputStream(); var out = new DataOutputStream(buffer);
            out.writeLong(clock.instant().plus(ttl).getEpochSecond()); out.write(fingerprint(owner, query));
            out.writeLong(generation); out.writeInt(after.values().size());
            for (var value : after.values()) { out.writeBoolean(value != null); if (value != null) out.writeUTF(value); }
            out.writeLong(after.id().getMostSignificantBits()); out.writeLong(after.id().getLeastSignificantBits());
            byte[] iv = new byte[12]; random.nextBytes(iv);
            var cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, key, new GCMParameterSpec(128, iv)); cipher.updateAAD(AAD);
            var wire = new ByteArrayOutputStream(); wire.write(iv); wire.write(cipher.doFinal(buffer.toByteArray()));
            String result = "p1." + Base64.getUrlEncoder().withoutPadding().encodeToString(wire.toByteArray());
            if (result.length() > MAX_LENGTH) throw new IllegalStateException("Sort tuple exceeds cursor budget");
            return result;
        } catch (IOException | GeneralSecurityException e) { throw new IllegalStateException("Cursor encoding failed"); }
    }
    public Position read(String token, UUID owner, Query query) {
        try {
            if (token == null || token.length() > MAX_LENGTH || !token.startsWith("p1.")) throw invalid();
            String encoded = token.substring(3); byte[] wire = Base64.getUrlDecoder().decode(encoded);
            if (wire.length < 28 || !Base64.getUrlEncoder().withoutPadding().encodeToString(wire).equals(encoded)) throw invalid();
            var cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(128, Arrays.copyOf(wire, 12))); cipher.updateAAD(AAD);
            var in = new DataInputStream(new ByteArrayInputStream(cipher.doFinal(wire, 12, wire.length - 12)));
            long expires = in.readLong();
            if (!MessageDigest.isEqual(in.readNBytes(32), fingerprint(owner, query))) throw invalid();
            long generation = in.readLong(); int size = in.readInt();
            if (generation < 0 || size < 0 || size > 16) throw invalid();
            var values = new ArrayList<String>();
            for (int i = 0; i < size; i++) values.add(in.readBoolean() ? in.readUTF() : null);
            var after = new Tuple(values, new UUID(in.readLong(), in.readLong()));
            if (in.available() != 0) throw invalid();
            if (clock.instant().getEpochSecond() >= expires) throw expired();
            return new Position(generation, after);
        } catch (ApiException e) { throw e; }
        catch (IOException | GeneralSecurityException | IllegalArgumentException e) { throw invalid(); }
    }
    private byte[] fingerprint(UUID owner, Query query) throws IOException, GeneralSecurityException {
        var buffer = new ByteArrayOutputStream(); var out = new DataOutputStream(buffer);
        out.writeUTF(owner.toString()); out.writeUTF(query.resource()); out.writeUTF(query.sort());
        out.writeUTF(query.keyVersion()); out.writeInt(query.limit());
        out.write(query.filters().getBytes(StandardCharsets.UTF_8));
        return MessageDigest.getInstance("SHA-256").digest(buffer.toByteArray());
    }
    public static ApiException invalid() { return new ApiException(HttpStatus.BAD_REQUEST, "INVALID_CURSOR", "목록 조건을 확인하고 첫 페이지부터 다시 조회해 주세요.", false, Map.of()); }
    public static ApiException expired() { return new ApiException(HttpStatus.CONFLICT, "LIST_CURSOR_EXPIRED", "목록이 변경되었거나 조회 시간이 만료되었습니다. 첫 페이지부터 다시 조회해 주세요.", false, Map.of()); }
}
