package com.ksh321.songrecord.api.retention;

import com.ksh321.songrecord.api.auth.AccountAccess;
import java.util.*;
import java.util.function.Supplier;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.*;
import org.springframework.transaction.support.TransactionTemplate;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;

/** Account-scoped, coherent policy and physical-storage views. Reads never schedule file deletion. */
@Component @Profile("!bootstrap")
public final class RetentionQueries {
    private final JdbcTemplate db;private final AccountAccess access;private final TransactionTemplate read;
    public RetentionQueries(JdbcTemplate db,AccountAccess access,PlatformTransactionManager manager){
        this.db=db;this.access=access;read=new TransactionTemplate(manager);read.setReadOnly(true);read.setIsolationLevel(TransactionDefinition.ISOLATION_REPEATABLE_READ);
    }
    public Map<String,Object> retention(String auth,String device,String text){
        var account=access.authenticate(auth,device);UUID id;try{id=PinSlots.parse(text);}catch(com.ksh321.songrecord.api.web.ApiException e){throw PinSlots.missing();}
        UUID owner=account.principal().userId();return view(account,()->{
            var records=db.queryForList("SELECT song_id,lifecycle_state,metadata_state FROM recording WHERE user_id=? AND id=?",bytes(owner),bytes(id));
            if(records.isEmpty())throw PinSlots.missing();var record=records.getFirst();var roles=new ArrayList<String>();
            if("ACTIVE".equals(record.get("lifecycle_state")) && "SAVED".equals(record.get("metadata_state")) && record.get("song_id")!=null){
                var selected=db.queryForList("SELECT sc.representative_id,sc.latest_id,sc.lowest_tier_id FROM song_cloud_selection sc JOIN song s ON s.id=sc.song_id AND s.user_id=sc.user_id WHERE sc.user_id=? AND sc.song_id=? AND s.lifecycle_state='ACTIVE'",bytes(owner),record.get("song_id"));
                if(!selected.isEmpty())for(var pair:List.of(new String[]{"representative_id","REPRESENTATIVE"},new String[]{"latest_id","LATEST"},new String[]{"lowest_tier_id","LOWEST_TIER"}))if(Arrays.equals((byte[])selected.getFirst().get(pair[0]),bytes(id)))roles.add(pair[1]);
            }
            var slots=db.query("SELECT slot_no,current_recording_id,pending_recording_id,revision FROM pin_slot WHERE user_id=? AND (current_recording_id=? OR pending_recording_id=?) ORDER BY slot_no",(r,n)->new PinSlots.Slot(r.getInt(1),PinSlots.id(r.getBytes(2)),PinSlots.id(r.getBytes(3)),r.getLong(4)).wire(),bytes(owner),bytes(id),bytes(id));
            var holds=db.queryForList("SELECT DISTINCT reason FROM cloud_hold WHERE user_id=? AND recording_id=? ORDER BY reason",String.class,bytes(owner),bytes(id));
            var assets=db.queryForList("SELECT cloud_state,blocked_reason,verified_size,cloud_revision FROM recording_asset WHERE user_id=? AND recording_id=?",bytes(owner),bytes(id));
            var cloud=new LinkedHashMap<String,Object>();cloud.put("state",assets.isEmpty()?"NONE":assets.getFirst().get("cloud_state"));cloud.put("stored","STORED".equals(cloud.get("state")));cloud.put("blocked_reason",assets.isEmpty()?null:assets.getFirst().get("blocked_reason"));cloud.put("verified_size",assets.isEmpty()?null:assets.getFirst().get("verified_size"));cloud.put("cloud_revision",assets.isEmpty()?null:assets.getFirst().get("cloud_revision"));
            var reasons=new LinkedHashSet<String>(roles);if(!slots.isEmpty())reasons.add("PINNED");reasons.addAll(holds);
            var result=new LinkedHashMap<String,Object>();result.put("recording_id",id.toString());result.put("automatic_roles",roles);result.put("pin_slots",slots);result.put("hold_reasons",holds);result.put("desired_reasons",List.copyOf(reasons));result.put("cloud",cloud);return result;
        });
    }
    public Map<String,Object> storage(String auth,String device){
        var account=access.authenticate(auth,device);UUID owner=account.principal().userId();return view(account,()->{
            var rows=db.queryForList("SELECT s.used_bytes,s.reserved_bytes,e.quota_bytes,e.pinned_limit,e.revision AS entitlement_revision FROM storage_usage s JOIN user_entitlement e ON e.user_id=s.user_id WHERE s.user_id=?",bytes(owner));
            if(rows.size()!=1)throw new IllegalStateException("Storage state missing");var result=new LinkedHashMap<String,Object>();
            for(String key:List.of("used_bytes","reserved_bytes","quota_bytes","pinned_limit","entitlement_revision"))result.put(key,rows.getFirst().get(key));
            result.put("pinned_used",number("SELECT COUNT(*) FROM pin_slot WHERE user_id=? AND (current_recording_id IS NOT NULL OR pending_recording_id IS NOT NULL)",owner));
            result.put("pinned_pending",number("SELECT COUNT(*) FROM pin_slot WHERE user_id=? AND pending_recording_id IS NOT NULL",owner));
            result.put("physical_file_count",number("SELECT COUNT(*) FROM recording_asset WHERE user_id=? AND cloud_state IN ('STORED','DELETING')",owner));
            result.put("trash_bytes",number("SELECT COALESCE(SUM(a.verified_size),0) FROM recording_asset a JOIN recording r ON r.user_id=a.user_id AND r.id=a.recording_id WHERE a.user_id=? AND a.cloud_state IN ('STORED','DELETING') AND r.lifecycle_state IN ('TRASHED','PURGE_PENDING','PURGED')",owner));
            // These are overlapping subsets of used_bytes, never amounts to add to used_bytes.
            result.put("cleanup_pending_bytes",number("SELECT COALESCE(SUM(a.verified_size),0) FROM recording_asset a WHERE a.user_id=? AND a.cloud_state IN ('STORED','DELETING') AND (a.cloud_state='DELETING' OR EXISTS(SELECT 1 FROM cloud_hold h WHERE h.user_id=a.user_id AND h.recording_id=a.recording_id AND h.reason IN ('PENDING_REPLACEMENT','WAITING_LOCAL_CONFIRM')))",owner));
            result.put("hold_bytes",number("SELECT COALESCE(SUM(a.verified_size),0) FROM recording_asset a WHERE a.user_id=? AND a.cloud_state IN ('STORED','DELETING') AND EXISTS(SELECT 1 FROM cloud_hold h WHERE h.user_id=a.user_id AND h.recording_id=a.recording_id)",owner));
            var waiting=new TreeMap<String,Long>();db.query("SELECT blocked_reason,COUNT(*) FROM recording_asset WHERE user_id=? AND blocked_reason IS NOT NULL AND cloud_state IN ('NONE','QUEUED','UPLOADING','VERIFYING') GROUP BY blocked_reason",r->{waiting.put(r.getString(1),r.getLong(2));},bytes(owner));
            result.put("waiting_by_reason",waiting);return result;
        });
    }
    private long number(String sql,UUID owner){return db.queryForObject(sql,Long.class,bytes(owner));}
    private <T>T view(AccountAccess.Account account,Supplier<T> body){return read.execute(s->{access.revalidate(account);return body.get();});}
}
