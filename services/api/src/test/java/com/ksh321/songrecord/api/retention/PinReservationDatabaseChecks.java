package com.ksh321.songrecord.api.retention;

import java.util.*;
import java.util.concurrent.*;
import org.springframework.jdbc.core.JdbcTemplate;
import com.ksh321.songrecord.api.web.ApiException;
import static com.ksh321.songrecord.api.retention.RetentionCandidateDatabaseChecks.*;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;

/** Same pending-limit race and receipt assertions on H2 and fully migrated MySQL. */
public final class PinReservationDatabaseChecks {
    public static void verify(JdbcTemplate db,PinSlots pins,String auth,String device,UUID owner){
        UUID dev=UUID.fromString(device);var ids=new ArrayList<UUID>();
        for(int i=0;i<11;i++)ids.add(recording(db,owner,dev,null,true,true,"VALIDATED"));
        db.update("INSERT INTO recording_asset(recording_id,user_id,cloud_state,object_key,generation,verified_size,sha256,stored_at) VALUES(?,?,'STORED','fixture/pin',?,6291456,?,CURRENT_TIMESTAMP)",bytes(ids.get(0)),bytes(owner),bytes(UUID.randomUUID()),"a".repeat(64));
        for(int i=0;i<9;i++)assertThat(pins.reserve(auth,device,UUID.randomUUID().toString(),body(ids.get(i),1)).status()).isEqualTo(201);
        assertThat(db.queryForObject("SELECT COUNT(*) FROM pin_slot WHERE user_id=? AND pending_recording_id IS NOT NULL",Long.class,bytes(owner))).isEqualTo(8);
        String op=UUID.randomUUID().toString();var response=pins.reserve(auth,device,op,body(ids.get(0),1));assertThat(response.status()).isEqualTo(200);
        assertThat(pins.reserve(auth,device,op,body(ids.get(0),1))).isEqualTo(response);
        try(var pool=Executors.newFixedThreadPool(2)){
            var go=new CountDownLatch(1);var results=new ArrayList<Future<String>>();
            for(int i=9;i<11;i++){UUID id=ids.get(i);results.add(pool.submit(()->{go.await();try{return Integer.toString(pins.reserve(auth,device,UUID.randomUUID().toString(),body(id,1)).status());}catch(ApiException e){return e.code();}}));}
            go.countDown();assertThat(List.of(results.get(0).get(15,TimeUnit.SECONDS),results.get(1).get(15,TimeUnit.SECONDS))).containsExactlyInAnyOrder("201","PIN_LIMIT_REACHED");
        }catch(Exception e){throw new AssertionError(e);}
        assertThat(db.queryForObject("SELECT COUNT(*) FROM pin_slot WHERE user_id=? AND (current_recording_id IS NOT NULL OR pending_recording_id IS NOT NULL)",Long.class,bytes(owner))).isEqualTo(10);
        assertThat(db.queryForObject("SELECT COUNT(*) FROM recording_asset WHERE user_id=?",Long.class,bytes(owner))).isEqualTo(1);
        assertThat(db.queryForObject("SELECT cloud_revision FROM recording_asset WHERE recording_id=?",Long.class,bytes(ids.get(0)))).isEqualTo(2);
        assertThat(db.queryForObject("SELECT current_recording_id FROM pin_slot WHERE user_id=? AND slot_no=1",byte[].class,bytes(owner))).isEqualTo(bytes(ids.get(0)));
        assertThat(db.queryForObject("SELECT COUNT(*) FROM recording WHERE user_id=?",Long.class,bytes(owner))).isEqualTo(11);
        assertThat(pins.reserve(auth,device,UUID.randomUUID().toString(),body(ids.get(0),1)).status()).isEqualTo(200); // duplicate works even at limit
    }
    public static String body(UUID id,long revision){return "{\"recording_id\":\""+id+"\",\"entitlement_revision\":"+revision+"}";}
}
