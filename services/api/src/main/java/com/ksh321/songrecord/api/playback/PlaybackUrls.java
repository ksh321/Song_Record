package com.ksh321.songrecord.api.playback;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.retention.PreservationDownloadSigner;
import com.ksh321.songrecord.api.storage.StorageObjectKeys;
import com.ksh321.songrecord.api.web.ApiException;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;

/** Issues internal, short-lived URLs; never a public product share link. */
@Component
@Profile("!bootstrap")
@ConditionalOnProperty(name="songrecord.storage.enabled", havingValue="true")
public final class PlaybackUrls {
    private final JdbcTemplate db;
    private final AccountAccess access;
    private final PreservationDownloadSigner signer;
    private final TransactionTemplate read;

    public PlaybackUrls(JdbcTemplate db, AccountAccess access,
            PlatformTransactionManager manager, PreservationDownloadSigner signer) {
        this.db = db; this.access = access; this.signer = signer;
        read = new TransactionTemplate(manager);
        read.setReadOnly(true);
    }

    public Map<String, Object> issue(String auth, String device, UUID recording) {
        var account = access.authenticate(auth, device);
        UUID owner = account.principal().userId();
        return read.execute(status -> {
            access.revalidate(account);
            var rows = db.queryForList("""
                SELECT a.generation,a.object_key,a.sha256,a.verified_size,a.cloud_revision
                FROM recording_asset a JOIN recording r
                  ON r.id=a.recording_id AND r.user_id=a.user_id
                WHERE r.user_id=? AND r.id=? AND r.lifecycle_state='ACTIVE'
                  AND a.cloud_state='STORED'
                """, bytes(owner), bytes(recording));
            if (rows.isEmpty()) throw unavailable();
            var asset = rows.getFirst();
            UUID generation = uuid((byte[]) asset.get("generation"));
            var key = new StorageObjectKeys.Final(owner, recording, generation);
            Object hash = asset.get("sha256"), size = asset.get("verified_size"), revision = asset.get("cloud_revision");
            if (!key.value().equals(asset.get("object_key")) || !(hash instanceof String checksum)
                    || !checksum.matches("[0-9a-f]{64}") || !(size instanceof Number length)
                    || length.longValue() < 1 || length.longValue() > 6291456
                    || !(revision instanceof Number version) || version.longValue() < 1) {
                throw new IllegalStateException("Invalid playback object identity");
            }
            // Signing is local (no object I/O); existing R2 signer fixes expiry at five minutes.
            var signed = signer.sign(key);
            access.revalidate(account);
            var result = new LinkedHashMap<String, Object>();
            result.put("user_id", owner.toString()); result.put("recording_id", recording.toString());
            result.put("generation", generation.toString()); result.put("sha256", hash);
            result.put("size_bytes", size); result.put("cloud_revision", revision);
            result.put("url", signed.url()); result.put("expires_at", signed.expiresAt().toString());
            return result;
        });
    }

    private static ApiException unavailable() {
        return new ApiException(HttpStatus.CONFLICT, "AUDIO_UNAVAILABLE",
                "현재 계정에서 재생할 서버 파일이 없습니다.", false, Map.of());
    }
}
