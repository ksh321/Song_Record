package com.ksh321.songrecord.api.retention;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.idempotency.*;
import com.ksh321.songrecord.api.locking.LockOrder;
import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import java.util.*;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;

/** Authenticated, receipt-backed pin mutations. File transfer is a separate operation. */
@Component @Profile("!bootstrap")
public final class PinSlots {
    private static final JsonMapper JSON=new JsonMapper();
    private final JdbcTemplate db;private final AccountAccess access;private final IdempotentMutations mutations;
    public PinSlots(JdbcTemplate db,AccountAccess access,IdempotentMutations mutations){this.db=db;this.access=access;this.mutations=mutations;}
    public IdempotentMutations.Reply reserve(String auth,String device,String operation,String body) {
        var account=access.authenticate(auth,device);CanonicalRequest.canonical(body);var root=JSON.readTree(body);
        if(!root.isObject() || root.size()!=2 || !root.has("recording_id") || !root.has("entitlement_revision") || !root.get("recording_id").isTextual())throw invalid();
        UUID recording=parse(root.get("recording_id").asText());var revision=root.get("entitlement_revision");
        if(!revision.isIntegralNumber() || !revision.canConvertToLong() || revision.asLong()<1)throw invalid();
        UUID owner=account.principal().userId();
        return mutations.execute(account,operation,"POST","/v1/pins",body,()->{
            lockAccount(account);var entitlement=entitlement(owner);
            if(((Number)entitlement.get("revision")).longValue()!=revision.asLong())throw error(HttpStatus.CONFLICT,"ENTITLEMENT_REVISION_CONFLICT","최신 고정 한도를 다시 확인해 주세요.");
            LockOrder.before(LockOrder.Rank.AGGREGATE,owner+"/1/"+recording);
            var recordings=db.queryForList("SELECT lifecycle_state,metadata_state FROM recording WHERE user_id=? AND id=? FOR UPDATE",bytes(owner),bytes(recording));
            if(recordings.isEmpty())throw missing();var metadata=recordings.getFirst();
            if(!"ACTIVE".equals(metadata.get("lifecycle_state")) || !"SAVED".equals(metadata.get("metadata_state")))throw error(HttpStatus.CONFLICT,"PIN_NOT_ELIGIBLE","활성 상태의 저장 완료 녹음만 고정할 수 있습니다.");
            // USER_SYNC and entitlement serialize discovery, including the not-yet-created slot.
            var slots=slots(owner);
            for(var slot:slots)if(recording.equals(slot.current()) || recording.equals(slot.pending()))return reply(slot,200);
            int limit=((Number)entitlement.get("pinned_limit")).intValue();
            long occupied=slots.stream().filter(Slot::occupied).count();
            if(occupied>=limit)throw error(HttpStatus.CONFLICT,"PIN_LIMIT_REACHED","고정 한도에 도달했습니다. 대기 고정을 취소하거나 기존 고정을 해제해 주세요.");
            int number=1;var byNumber=new HashMap<Integer,Slot>();for(var s:slots)byNumber.put(s.number(),s);
            while(number<=limit && byNumber.containsKey(number) && byNumber.get(number).occupied())number++;
            if(number>limit)throw error(HttpStatus.CONFLICT,"PIN_LIMIT_REACHED","사용 가능한 고정 슬롯이 없습니다.");
            LockOrder.before(LockOrder.Rank.PIN_SLOT,owner+"/"+String.format(Locale.ROOT,"%010d",number));
            var prior=byNumber.get(number);
            if(prior!=null)db.queryForList("SELECT slot_no FROM pin_slot WHERE user_id=? AND slot_no=? FOR UPDATE",bytes(owner),number);
            LockOrder.before(LockOrder.Rank.RECORDING_ASSET,owner+"/"+recording);
            var assets=db.queryForList("SELECT cloud_state,cloud_revision FROM recording_asset WHERE user_id=? AND recording_id=? FOR UPDATE",bytes(owner),bytes(recording));
            String state=assets.isEmpty()?"NONE":(String)assets.getFirst().get("cloud_state");
            if("DELETING".equals(state))throw error(HttpStatus.CONFLICT,"FILE_CLEANUP_IN_PROGRESS","서버 파일 정리가 끝난 뒤 다시 고정해 주세요.");
            long next=prior==null?1:increment(prior.revision());boolean stored="STORED".equals(state);
            Object current=stored?bytes(recording):null,pending=stored?null:bytes(recording);
            if(prior==null)db.update("INSERT INTO pin_slot(user_id,slot_no,current_recording_id,pending_recording_id,revision,operation_id,requested_at) VALUES(?,?,?,?,?,?,CURRENT_TIMESTAMP(3))",bytes(owner),number,current,pending,next,bytes(parse(operation)));
            else db.update("UPDATE pin_slot SET current_recording_id=?,pending_recording_id=?,revision=?,operation_id=?,requested_at=CURRENT_TIMESTAMP(3),updated_at=CURRENT_TIMESTAMP(3) WHERE user_id=? AND slot_no=?",current,pending,next,bytes(parse(operation)),bytes(owner),number);
            RetentionAssetVersions.bumpLocked(db,owner,recording,assets);
            return reply(new Slot(number,stored?recording:null,stored?null:recording,next),201);
        });
    }
    /** Replacement never releases current or reserves upload quota optimistically. */
    public IdempotentMutations.Reply replace(String auth,String device,String operation,String number,String body){
        var account=access.authenticate(auth,device);int slot=slotNumber(number);CanonicalRequest.canonical(body);var root=JSON.readTree(body);
        if(!root.isObject() || root.size()!=2 || !root.has("recording_id") || !root.has("base_revision") || !root.get("recording_id").isTextual())throw invalid();
        UUID target=parse(root.get("recording_id").asText());var base=root.get("base_revision");if(!base.isIntegralNumber() || !base.canConvertToLong() || base.asLong()<1)throw invalid();UUID owner=account.principal().userId();
        return mutations.execute(account,operation,"POST","/v1/pins/"+slot+"/replacement",body,()->{
            lockAccount(account);entitlement(owner);
            LockOrder.before(LockOrder.Rank.AGGREGATE,owner+"/1/"+target);var records=db.queryForList("SELECT lifecycle_state,metadata_state FROM recording WHERE user_id=? AND id=? FOR UPDATE",bytes(owner),bytes(target));if(records.isEmpty())throw missing();var metadata=records.getFirst();if(!"ACTIVE".equals(metadata.get("lifecycle_state")) || !"SAVED".equals(metadata.get("metadata_state")))throw error(HttpStatus.CONFLICT,"PIN_NOT_ELIGIBLE","활성 상태의 저장 완료 녹음만 교체할 수 있습니다.");
            LockOrder.before(LockOrder.Rank.PIN_SLOT,owner+"/"+String.format(Locale.ROOT,"%010d",slot));var rows=db.query("SELECT slot_no,current_recording_id,pending_recording_id,revision FROM pin_slot WHERE user_id=? AND slot_no=? FOR UPDATE",(r,n)->new Slot(r.getInt(1),id(r.getBytes(2)),id(r.getBytes(3)),r.getLong(4)),bytes(owner),slot);if(rows.isEmpty())throw missing();var current=rows.getFirst();requireRevision(current,base.asLong());
            if(current.current()==null)throw error(HttpStatus.CONFLICT,"PIN_REPLACEMENT_REQUIRES_CURRENT","기존 고정이 있는 슬롯을 선택해 주세요.");
            if(target.equals(current.pending()) || target.equals(current.current()))return reply(current,200);
            if(current.pending()!=null)throw error(HttpStatus.CONFLICT,"PIN_REPLACEMENT_IN_PROGRESS","기존 교체 대기를 먼저 취소해 주세요.");
            if(slots(owner).stream().anyMatch(x->target.equals(x.current()) || target.equals(x.pending())))throw error(HttpStatus.CONFLICT,"PIN_ALREADY_IN_SLOT","이미 다른 슬롯에서 고정된 녹음입니다.");
            var affected=new TreeSet<UUID>(Comparator.comparing(UUID::toString));affected.add(current.current());affected.add(target);var assets=new LinkedHashMap<UUID,List<Map<String,Object>>>();
            for(UUID id:affected){LockOrder.before(LockOrder.Rank.RECORDING_ASSET,owner+"/"+id);assets.put(id,db.queryForList("SELECT cloud_state,cloud_revision FROM recording_asset WHERE user_id=? AND recording_id=? FOR UPDATE",bytes(owner),bytes(id)));}
            var targetAssets=assets.get(target);if(!targetAssets.isEmpty() && "DELETING".equals(targetAssets.getFirst().get("cloud_state")))throw error(HttpStatus.CONFLICT,"FILE_CLEANUP_IN_PROGRESS","서버 파일 정리가 끝난 뒤 다시 교체해 주세요.");
            long next=increment(current.revision());db.update("UPDATE pin_slot SET pending_recording_id=?,revision=?,operation_id=?,requested_at=CURRENT_TIMESTAMP(3),updated_at=CURRENT_TIMESTAMP(3) WHERE user_id=? AND slot_no=?",bytes(target),next,bytes(parse(operation)),bytes(owner),slot);
            if(!targetAssets.isEmpty() && "STORED".equals(targetAssets.getFirst().get("cloud_state"))){PinTransitions.promoteLocked(db,owner,List.of(new PinTransitions.Pending(slot,current.current(),target,next,parse(operation))),target,assets,false,Clock.systemUTC());return reply(new Slot(slot,target,null,increment(next)),200);}
            for(UUID id:affected)RetentionAssetVersions.bumpLocked(db,owner,id,assets.get(id));return reply(new Slot(slot,current.current(),target,next),200);
        });
    }
    public IdempotentMutations.Reply cancelReplacement(String auth,String device,String operation,String number,String body){
        var account=access.authenticate(auth,device);int slot=slotNumber(number);CanonicalRequest.canonical(body);var root=JSON.readTree(body);if(!root.isObject() || root.size()!=1 || !root.has("base_revision"))throw invalid();var base=root.get("base_revision");if(!base.isIntegralNumber() || !base.canConvertToLong() || base.asLong()<1)throw invalid();UUID owner=account.principal().userId();
        return mutations.execute(account,operation,"POST","/v1/pins/"+slot+"/replacement/cancel",body,()->{lockAccount(account);entitlement(owner);LockOrder.before(LockOrder.Rank.PIN_SLOT,owner+"/"+String.format(Locale.ROOT,"%010d",slot));var rows=db.query("SELECT slot_no,current_recording_id,pending_recording_id,revision FROM pin_slot WHERE user_id=? AND slot_no=? FOR UPDATE",(r,n)->new Slot(r.getInt(1),id(r.getBytes(2)),id(r.getBytes(3)),r.getLong(4)),bytes(owner),slot);if(rows.isEmpty())throw missing();var current=rows.getFirst();requireRevision(current,base.asLong());if(current.pending()==null)return reply(current,200);if(current.current()==null)throw error(HttpStatus.CONFLICT,"PIN_REPLACEMENT_REQUIRES_CURRENT","일반 대기 고정은 고정 해제로 취소해 주세요.");var pending=PinTransitions.lockPending(db,owner,current.pending(),null);var assets=PinTransitions.lockAssets(db,owner,pending,current.pending());PinTransitions.clearLocked(db,owner,pending,assets,Clock.systemUTC());return reply(new Slot(slot,current.current(),null,increment(current.revision())),200);});
    }
    static int slotNumber(String number){try{int slot=Integer.parseInt(number);if(slot<1 || !Integer.toString(slot).equals(number))throw new IllegalArgumentException();return slot;}catch(IllegalArgumentException e){throw missing();}}
    static void requireRevision(Slot slot,long expected){if(slot.revision()!=expected)throw new ApiException(HttpStatus.CONFLICT,"REVISION_CONFLICT","최신 슬롯 상태를 확인해 주세요.",false,Map.of("current_revision",slot.revision(),"current",slot.wire()));}
    public IdempotentMutations.Reply release(String auth,String device,String operation,String number,String body){
        var account=access.authenticate(auth,device);int slot;
        try{slot=Integer.parseInt(number);if(slot<1 || !Integer.toString(slot).equals(number))throw new IllegalArgumentException();}catch(IllegalArgumentException e){throw missing();}
        CanonicalRequest.canonical(body);var root=JSON.readTree(body);
        if(!root.isObject() || root.size()!=1 || !root.has("base_revision"))throw invalid();var base=root.get("base_revision");
        if(!base.isIntegralNumber() || !base.canConvertToLong() || base.asLong()<1)throw invalid();UUID owner=account.principal().userId();
        return mutations.execute(account,operation,"DELETE","/v1/pins/"+slot,body,()->{
            lockAccount(account);entitlement(owner);
            LockOrder.before(LockOrder.Rank.PIN_SLOT,owner+"/"+String.format(Locale.ROOT,"%010d",slot));
            var rows=db.query("SELECT slot_no,current_recording_id,pending_recording_id,revision FROM pin_slot WHERE user_id=? AND slot_no=? FOR UPDATE",(r,n)->new Slot(r.getInt(1),id(r.getBytes(2)),id(r.getBytes(3)),r.getLong(4)),bytes(owner),slot);
            if(rows.isEmpty())throw missing();var current=rows.getFirst();
            if(current.revision()!=base.asLong())throw new ApiException(HttpStatus.CONFLICT,"REVISION_CONFLICT","최신 슬롯 상태를 확인해 주세요.",false,Map.of("current_revision",current.revision(),"current",current.wire()));
            if(!current.occupied())return reply(current,200);
            long next=increment(current.revision());var affected=new HashSet<UUID>();if(current.current()!=null)affected.add(current.current());if(current.pending()!=null)affected.add(current.pending());
            db.update("UPDATE pin_slot SET current_recording_id=NULL,pending_recording_id=NULL,revision=?,operation_id=NULL,requested_at=NULL,updated_at=CURRENT_TIMESTAMP(3) WHERE user_id=? AND slot_no=?",next,bytes(owner),slot);
            RetentionAssetVersions.bump(db,owner,affected);
            // No physical delete or hold removal. P13 evaluates any later cleanup separately.
            return reply(new Slot(slot,null,null,next),200);
        });
    }
    void lockAccount(AccountAccess.Account account){
        UUID owner=access.revalidate(account).userId();LockOrder.before(LockOrder.Rank.USER_SYNC,owner.toString());
        if(db.queryForList("SELECT user_id FROM user_sync_state WHERE user_id=? FOR UPDATE",bytes(owner)).size()!=1)throw new IllegalStateException("Account sync state missing");
        access.revalidate(account);
    }
    Map<String,Object> entitlement(UUID owner){
        LockOrder.before(LockOrder.Rank.ENTITLEMENT,owner+"/");
        var rows=db.queryForList("SELECT pinned_limit,quota_bytes,revision FROM user_entitlement WHERE user_id=? FOR UPDATE",bytes(owner));
        if(rows.size()!=1)throw new IllegalStateException("Entitlement missing");return rows.getFirst();
    }
    List<Slot> slots(UUID owner){return db.query("SELECT slot_no,current_recording_id,pending_recording_id,revision FROM pin_slot WHERE user_id=? ORDER BY slot_no",(r,n)->new Slot(r.getInt(1),id(r.getBytes(2)),id(r.getBytes(3)),r.getLong(4)),bytes(owner));}
    record Slot(int number,UUID current,UUID pending,long revision){boolean occupied(){return current!=null||pending!=null;}Map<String,Object> wire(){var m=new LinkedHashMap<String,Object>();m.put("slot_no",number);m.put("current_recording_id",current==null?null:current.toString());m.put("pending_recording_id",pending==null?null:pending.toString());m.put("revision",revision);return m;}}
    static IdempotentMutations.Reply reply(Slot slot,int status){return new IdempotentMutations.Reply(status,JSON.writeValueAsString(slot.wire()));}
    static UUID id(byte[] raw){return raw==null?null:uuid(raw);}
    static UUID parse(String text){try{UUID id=UUID.fromString(text);if(!id.toString().equals(text))throw new IllegalArgumentException();return id;}catch(IllegalArgumentException|NullPointerException e){throw invalid();}}
    static long increment(long n){if(n==Long.MAX_VALUE)throw error(HttpStatus.CONFLICT,"REVISION_LIMIT_REACHED","버전 한도에 도달했습니다.");return n+1;}
    static ApiException invalid(){return error(HttpStatus.BAD_REQUEST,"VALIDATION_FAILED","요청 항목과 버전을 확인해 주세요.");}
    static ApiException missing(){return error(HttpStatus.NOT_FOUND,"RESOURCE_NOT_FOUND","요청한 자료를 찾을 수 없습니다.");}
    static ApiException error(HttpStatus status,String code,String message){return new ApiException(status,code,message,false,Map.of());}
}
