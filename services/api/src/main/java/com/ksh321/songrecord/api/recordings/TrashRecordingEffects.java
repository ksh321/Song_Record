package com.ksh321.songrecord.api.recordings;

import com.ksh321.songrecord.api.locking.LockOrder;
import com.ksh321.songrecord.api.retention.RetentionAssetVersions;
import com.ksh321.songrecord.api.uploads.UploadRecovery;
import java.time.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;

/** Logical deletion only. Existing objects/used capacity stay until confirmed physical purge. */
public final class TrashRecordingEffects {
    private final JdbcTemplate db;
    private final Clock clock;
    public TrashRecordingEffects(JdbcTemplate db,Clock clock){this.db=db;this.clock=clock;}
    public void lockBudget(UUID owner){
        LockOrder.before(LockOrder.Rank.ENTITLEMENT,owner+"/");db.queryForMap("SELECT user_id FROM user_entitlement WHERE user_id=? FOR UPDATE",bytes(owner));
        LockOrder.before(LockOrder.Rank.STORAGE_USAGE,owner+"/");db.queryForMap("SELECT user_id FROM storage_usage WHERE user_id=? FOR UPDATE",bytes(owner));
    }
    public void apply(UUID owner,Collection<UUID> recordings){
        var targets=new HashSet<>(recordings);var affected=new HashSet<>(targets);
        var slots=db.queryForList("SELECT slot_no,current_recording_id,pending_recording_id,revision FROM pin_slot WHERE user_id=? ORDER BY slot_no",bytes(owner));
        for(var row:slots){
            UUID current=id(row.get("current_recording_id")),pending=id(row.get("pending_recording_id"));
            if(!targets.contains(current) && !targets.contains(pending))continue;
            int slot=((Number)row.get("slot_no")).intValue();
            LockOrder.before(LockOrder.Rank.PIN_SLOT,owner+"/"+String.format(Locale.ROOT,"%010d",slot));
            db.queryForMap("SELECT slot_no FROM pin_slot WHERE user_id=? AND slot_no=? FOR UPDATE",bytes(owner),slot);
            if(current!=null)affected.add(current);if(pending!=null)affected.add(pending);
            // Cancelling a replacement retains its unrelated current pin. Deleting current frees the slot.
            UUID keep=targets.contains(current)?null:current;
            long revision=((Number)row.get("revision")).longValue();
            if(revision==Long.MAX_VALUE)throw new com.ksh321.songrecord.api.web.ApiException(org.springframework.http.HttpStatus.CONFLICT,"PIN_REVISION_LIMIT_REACHED","고정 상태의 버전 한도에 도달했습니다.",false,Map.of());
            long next=revision+1;
            db.update("UPDATE pin_slot SET current_recording_id=?,pending_recording_id=NULL,operation_id=CASE WHEN ? IS NULL THEN NULL ELSE operation_id END,requested_at=CASE WHEN ? IS NULL THEN NULL ELSE requested_at END,revision=?,updated_at=? WHERE user_id=? AND slot_no=?",keep==null?null:bytes(keep),keep==null?null:bytes(keep),keep==null?null:bytes(keep),next,java.sql.Timestamp.from(clock.instant()),bytes(owner),slot);
        }
        RetentionAssetVersions.bump(db,owner,affected);
        var recovery=new UploadRecovery(db,new DataSourceTransactionManager(db.getDataSource()),clock);
        // Account lock serializes attempts; all pin/asset effects precede terminal job locks.
        for(UUID recording:targets.stream().sorted(Comparator.comparing(UUID::toString)).toList()){
            var uploads=db.queryForList("SELECT id FROM recording_upload WHERE user_id=? AND recording_id=? AND state IN ('RESERVED','UPLOADING','VERIFYING') ORDER BY id",byte[].class,bytes(owner),bytes(recording));
            for(byte[] attempt:uploads)recovery.cancel(owner,uuid(attempt));
        }
    }
    private static UUID id(Object value){return value==null?null:uuid((byte[])value);}
}
