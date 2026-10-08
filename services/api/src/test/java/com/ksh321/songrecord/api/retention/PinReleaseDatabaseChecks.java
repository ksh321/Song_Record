package com.ksh321.songrecord.api.retention;

import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import com.ksh321.songrecord.api.web.ApiException;
import static com.ksh321.songrecord.api.retention.RetentionCandidateDatabaseChecks.*;
import static com.ksh321.songrecord.api.retention.PinReservationDatabaseChecks.body;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;

/** One physical file protected by three automatic roles, a pin and two holds counts only once. */
public final class PinReleaseDatabaseChecks {
    public static void verify(JdbcTemplate db,PinSlots pins,RetentionQueries queries,String auth,String device,UUID owner){
        UUID song=song(db,owner),id=recording(db,owner,UUID.fromString(device),song,true,true,"VALIDATED");
        db.update("INSERT INTO recording_asset(recording_id,user_id,cloud_state,object_key,generation,verified_size,sha256,stored_at) VALUES(?,?,'STORED','fixture/release',?,6291456,?,CURRENT_TIMESTAMP)",bytes(id),bytes(owner),bytes(UUID.randomUUID()),"a".repeat(64));
        db.update("INSERT INTO song_cloud_selection(song_id,user_id,representative_id,latest_id,lowest_tier_id) VALUES(?,?,?,?,?)",bytes(song),bytes(owner),bytes(id),bytes(id),bytes(id));
        for(String reason:List.of("ORPHAN_KEEP","WAITING_LOCAL_CONFIRM"))db.update("INSERT INTO cloud_hold(id,user_id,recording_id,reason) VALUES(?,?,?,?)",bytes(UUID.randomUUID()),bytes(owner),bytes(id),reason);
        db.update("UPDATE storage_usage SET used_bytes=6291456,reserved_bytes=50 WHERE user_id=?",bytes(owner));
        pins.reserve(auth,device,UUID.randomUUID().toString(),body(id,1));
        var view=queries.retention(auth,device,id.toString());
        assertThat((List<?>)view.get("automatic_roles")).hasSize(3);assertThat((List<?>)view.get("pin_slots")).hasSize(1);assertThat((List<?>)view.get("hold_reasons")).hasSize(2);
        var usage=queries.storage(auth,device);assertThat(((Number)usage.get("used_bytes")).longValue()).isEqualTo(6291456);assertThat(((Number)usage.get("reserved_bytes")).longValue()).isEqualTo(50);
        for(String key:List.of("physical_file_count","pinned_used"))assertThat(((Number)usage.get(key)).longValue()).isEqualTo(1);
        assertThat(((Number)usage.get("hold_bytes")).longValue()).isEqualTo(6291456);assertThat(((Number)usage.get("cleanup_pending_bytes")).longValue()).isEqualTo(6291456);
        String op=UUID.randomUUID().toString();var released=pins.release(auth,device,op,"1","{\"base_revision\":1}");
        assertThat(released.body()).contains("\"current_recording_id\":null","\"pending_recording_id\":null","\"revision\":2");
        var after=queries.retention(auth,device,id.toString());assertThat((List<?>)after.get("automatic_roles")).hasSize(3);assertThat((List<?>)after.get("hold_reasons")).hasSize(2);assertThat((List<?>)after.get("pin_slots")).isEmpty();
        assertThat(((Map<?,?>)after.get("cloud")).get("stored")).isEqualTo(true);
        assertThat(db.queryForObject("SELECT cloud_revision FROM recording_asset WHERE recording_id=?",Long.class,bytes(id))).isEqualTo(3);
        assertThat(((Number)queries.storage(auth,device).get("used_bytes")).longValue()).isEqualTo(6291456);
        UUID pending=recording(db,owner,UUID.fromString(device),null,true,true,"VALIDATED");
        var next=pins.reserve(auth,device,UUID.randomUUID().toString(),body(pending,1));assertThat(next.body()).contains("\"slot_no\":1","\"revision\":3");
        assertThat(pins.release(auth,device,op,"1","{\"base_revision\":1}")).isEqualTo(released); // replay cannot release the new occupant
        assertThat(((Number)queries.storage(auth,device).get("pinned_pending")).longValue()).isEqualTo(1);
        assertThat(((Map<?,?>)queries.retention(auth,device,pending.toString()).get("cloud")).get("stored")).isEqualTo(false);
        assertThatThrownBy(()->pins.release(auth,device,UUID.randomUUID().toString(),"1","{\"base_revision\":1}")).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("REVISION_CONFLICT"));
        pins.release(auth,device,UUID.randomUUID().toString(),"1","{\"base_revision\":3}");
        assertThat(((Number)queries.storage(auth,device).get("pinned_used")).longValue()).isZero();
        assertThat(db.queryForObject("SELECT COUNT(*) FROM recording_file_spec WHERE user_id=?",Long.class,bytes(owner))).isEqualTo(2);
    }
}
