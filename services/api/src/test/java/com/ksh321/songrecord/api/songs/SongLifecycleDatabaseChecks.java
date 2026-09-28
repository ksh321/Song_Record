package com.ksh321.songrecord.api.songs;

import com.ksh321.songrecord.api.web.ApiException;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;

/** Shared H2/MySQL contract. SQL state transitions stand in for the later deletion worker. */
public final class SongLifecycleDatabaseChecks {
    private static final JsonMapper JSON=new JsonMapper();
    private SongLifecycleDatabaseChecks(){}
    public static void verify(JdbcTemplate db,SongCreation creation,String auth,String device,UUID owner,String proof){
        UUID old=UUID.randomUUID(),replacement=UUID.randomUUID();String original=body(old,proof),originalKey=UUID.randomUUID().toString();
        var first=creation.create(auth,device,originalKey,original);assertThat(first.status()).isEqualTo(201);
        String number=JSON.readTree(first.body()).get("song").get("tj_number").asText();
        String retryKey=UUID.randomUUID().toString(),retryBody=body(replacement,proof);
        for(String state:List.of("TRASHED","PURGE_PENDING")){
            db.update("UPDATE song SET lifecycle_state=?,deleted_at=CURRENT_TIMESTAMP,revision=revision+1 WHERE id=?",state,bytes(old));
            var before=db.queryForMap("SELECT * FROM song WHERE id=?",bytes(old));
            String expected=state.equals("TRASHED")?"SONG_RESTORE_REQUIRED":"SONG_PURGE_PENDING";
            for(UUID requested:List.of(old,replacement))assertThatThrownBy(()->creation.create(auth,device,retryKey,body(requested,proof)))
                .isInstanceOfSatisfying(ApiException.class,e->{
                    assertThat(e.code()).isEqualTo(expected);assertThat(e.status().value()).isEqualTo(409);assertThat(e.retryable()).isFalse();
                    assertThat(e.details().get("canonical_song_id")).isEqualTo(old.toString());assertThat(e.details().get("lifecycle_state")).isEqualTo(state);
                    assertThat(((Number)e.details().get("current_revision")).longValue()).isEqualTo(((Number)before.get("revision")).longValue());
                });
            assertThat(db.queryForObject("SELECT reserved_tj_number FROM song WHERE id=?",String.class,bytes(old))).isEqualTo(number);
            // The database also rejects an application-bypassing insert while the number is reserved.
            assertThatThrownBy(()->db.update("INSERT INTO song(id,user_id,source_type,tj_number,title,artist,note,lifecycle_state) VALUES(?,?,'TJ',?,'x','y','','ACTIVE')",bytes(replacement),bytes(owner),number)).isInstanceOf(org.springframework.dao.DuplicateKeyException.class);
            assertThat(db.queryForMap("SELECT * FROM song WHERE id=?",bytes(old))).usingRecursiveComparison().isEqualTo(before);
            assertThat(db.queryForObject("SELECT COUNT(*) FROM mutation_receipt WHERE user_id=?",Integer.class,bytes(owner))).isEqualTo(1);
            assertThat(db.queryForObject("SELECT last_change_seq FROM user_sync_state WHERE user_id=?",Long.class,bytes(owner))).isEqualTo(1);
        }
        db.update("UPDATE song SET lifecycle_state='PURGED',revision=revision+1 WHERE id=?",bytes(old));
        assertThat(db.queryForObject("SELECT reserved_tj_number FROM song WHERE id=?",String.class,bytes(old))).isNull();
        assertPurged(()->creation.create(auth,device,UUID.randomUUID().toString(),original));
        // A failed request left no receipt: the exact same operation can now succeed with a new UUID.
        var fresh=creation.create(auth,device,retryKey,retryBody);assertThat(fresh.status()).isEqualTo(201);
        assertThat(JSON.readTree(fresh.body()).get("canonical_song_id").asText()).isEqualTo(replacement.toString());
        assertThat(creation.create(auth,device,retryKey,retryBody)).isEqualTo(fresh);
        // Old UUID wins over number deduplication, even though an ACTIVE replacement now owns the number.
        assertPurged(()->creation.create(auth,device,UUID.randomUUID().toString(),original));
        // Retained success receipts replay history, never resurrect the purged row.
        assertThat(creation.create(auth,device,originalKey,original)).isEqualTo(first);
        assertThat(db.queryForObject("SELECT lifecycle_state FROM song WHERE id=?",String.class,bytes(old))).isEqualTo("PURGED");
        db.update("INSERT INTO deletion_ledger(id,user_id,entity_type,entity_id,revision) VALUES(?,?,'SONG',?,4)",bytes(UUID.randomUUID()),bytes(owner),bytes(old));
        db.update("DELETE FROM song_source WHERE song_id=?",bytes(old));db.update("DELETE FROM song_query_key WHERE song_id=?",bytes(old));db.update("DELETE FROM song WHERE id=?",bytes(old));
        // Receipt expiry and physical row cleanup still cannot resurrect the old UUID.
        db.update("DELETE FROM mutation_receipt WHERE user_id=?",bytes(owner));
        assertPurged(()->creation.create(auth,device,originalKey,original));
        assertThat(db.queryForObject("SELECT COUNT(*) FROM song WHERE user_id=?",Integer.class,bytes(owner))).isEqualTo(1);
        assertThat(db.queryForObject("SELECT COUNT(*) FROM deletion_ledger WHERE user_id=?",Integer.class,bytes(owner))).isEqualTo(1);
        assertThat(db.queryForObject("SELECT COUNT(*) FROM mutation_receipt WHERE user_id=?",Integer.class,bytes(owner))).isZero();
        assertThat(db.queryForObject("SELECT last_change_seq FROM user_sync_state WHERE user_id=?",Long.class,bytes(owner))).isEqualTo(2);
    }
    private static String body(UUID id,String proof){return JSON.writeValueAsString(Map.of("id",id.toString(),"source_type","TJ","source_token",proof));}
    private static void assertPurged(org.assertj.core.api.ThrowableAssert.ThrowingCallable call){assertThatThrownBy(call).isInstanceOfSatisfying(ApiException.class,e->{assertThat(e.code()).isEqualTo("RESOURCE_PURGED");assertThat(e.status().value()).isEqualTo(409);});}
}
