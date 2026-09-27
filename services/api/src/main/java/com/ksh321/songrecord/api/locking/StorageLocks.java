package com.ksh321.songrecord.api.locking;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.web.ApiException;
import java.nio.ByteBuffer;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.*;
import org.springframework.transaction.support.*;

/** Domain services acquire needed rows only, in LockOrder rank/key order. */
public final class StorageLocks {
    public enum Target {
        ENTITLEMENT(LockOrder.Rank.ENTITLEMENT,"SELECT user_id FROM user_entitlement WHERE user_id=? FOR UPDATE"),
        USAGE(LockOrder.Rank.STORAGE_USAGE,"SELECT user_id FROM storage_usage WHERE user_id=? FOR UPDATE"),
        SELECTION(LockOrder.Rank.SONG_SELECTION,"SELECT song_id FROM song_cloud_selection WHERE user_id=? AND song_id=? FOR UPDATE"),
        ASSET(LockOrder.Rank.RECORDING_ASSET,"SELECT recording_id FROM recording_asset WHERE user_id=? AND recording_id=? FOR UPDATE");
        final LockOrder.Rank rank;final String sql;
        Target(LockOrder.Rank rank,String sql){this.rank=rank;this.sql=sql;}
    }
    private final JdbcTemplate jdbc;private final AccountAccess access;private final TransactionTemplate joined;
    public StorageLocks(JdbcTemplate jdbc,AccountAccess access,PlatformTransactionManager manager){
        this.jdbc=jdbc;this.access=access;joined=new TransactionTemplate(manager);joined.setPropagationBehavior(TransactionDefinition.PROPAGATION_MANDATORY);
    }
    public void global() {
        transaction();joined.executeWithoutResult(s->{
            LockOrder.before(LockOrder.Rank.GLOBAL_STORAGE,"1");
            if(jdbc.queryForList("SELECT id FROM global_storage_usage WHERE id=1 FOR UPDATE").size()!=1)
                throw new IllegalStateException("Global storage row is missing");
        });
    }
    public void owned(AccountAccess.Account account,Target target,UUID resource) {
        transaction();joined.executeWithoutResult(s->{
            var user=access.revalidate(account).userId();
            boolean personal=target==Target.ENTITLEMENT || target==Target.USAGE;
            if(!personal)Objects.requireNonNull(resource);
            String key=user+"/"+(personal?"":resource);
            LockOrder.before(target.rank,key);
            Object[] args=personal?new Object[]{bytes(user)}:new Object[]{bytes(user),bytes(resource)};
            if(jdbc.query(target.sql,(rs,n)->1,args).isEmpty())throw missing();
        });
    }
    public void pin(AccountAccess.Account account,int slot) {
        transaction();joined.executeWithoutResult(s->{
            var user=access.revalidate(account).userId();if(slot<1)throw new IllegalArgumentException("Invalid pin slot");
            LockOrder.before(LockOrder.Rank.PIN_SLOT,user+"/"+String.format(Locale.ROOT,"%010d",slot));
            if(jdbc.query("SELECT slot_no FROM pin_slot WHERE user_id=? AND slot_no=? FOR UPDATE",(rs,n)->1,bytes(user),slot).isEmpty())throw missing();
        });
    }
    private void transaction(){if(!TransactionSynchronizationManager.isActualTransactionActive() || !TransactionSynchronizationManager.hasResource(Objects.requireNonNull(jdbc.getDataSource())))throw new IllegalStateException("Storage locks require the domain transaction");}
    private static byte[] bytes(UUID id){return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();}
    private static ApiException missing(){return new ApiException(HttpStatus.NOT_FOUND,"RESOURCE_NOT_FOUND","요청한 자료를 찾을 수 없습니다.",false,Map.of());}
}
