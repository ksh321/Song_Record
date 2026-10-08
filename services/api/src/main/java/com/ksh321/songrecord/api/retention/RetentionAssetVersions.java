package com.ksh321.songrecord.api.retention;

import com.ksh321.songrecord.api.locking.LockOrder;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;

/** Policy fencing only: never change file state, physical bytes or storage identity. */
public final class RetentionAssetVersions {
    private RetentionAssetVersions(){}
    public static void bump(JdbcTemplate db,UUID owner,Collection<UUID> recordings){
        for(UUID id:recordings.stream().distinct().sorted(Comparator.comparing(UUID::toString)).toList()){
            LockOrder.before(LockOrder.Rank.RECORDING_ASSET,owner+"/"+id);
            bumpLocked(db,owner,id,db.queryForList("SELECT cloud_revision FROM recording_asset WHERE user_id=? AND recording_id=? FOR UPDATE",bytes(owner),bytes(id)));
        }
    }
    static void bumpLocked(JdbcTemplate db,UUID owner,UUID id,List<Map<String,Object>> rows){
        if(rows.isEmpty())return;long revision=((Number)rows.getFirst().get("cloud_revision")).longValue();
        long next=PinSlots.increment(revision);
        if(db.update("UPDATE recording_asset SET cloud_revision=?,updated_at=CURRENT_TIMESTAMP(3) WHERE user_id=? AND recording_id=? AND cloud_revision=?",next,bytes(owner),bytes(id),revision)!=1)throw new IllegalStateException("Asset policy version changed");
    }
}
