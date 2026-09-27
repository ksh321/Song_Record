package com.ksh321.songrecord.api.locking;

import java.util.*;
import org.springframework.transaction.support.*;

/** Checks participating explicit locks, not arbitrary SQL or implicit FK/trigger locks. */
public final class LockOrder {
    public enum Rank { GLOBAL_STORAGE, USER_SYNC, ENTITLEMENT, STORAGE_USAGE, AGGREGATE, SONG_SELECTION, PIN_SLOT, RECORDING_ASSET, JOB }
    private static final Object KEY=new Object();
    private record Lock(Rank rank,String key) implements Comparable<Lock> {
        public int compareTo(Lock other){int order=rank.compareTo(other.rank);return order!=0?order:key.compareTo(other.key);}
    }
    private static final class State {Lock highest;boolean violated;Set<Lock> held=new HashSet<>();}
    private LockOrder(){}
    /** Call immediately before acquiring a lock. Re-acquiring an already held row is allowed. */
    public static void before(Rank rank,String key) {
        if(!TransactionSynchronizationManager.isActualTransactionActive() || !TransactionSynchronizationManager.isSynchronizationActive())
            throw new IllegalStateException("Lock order requires a transaction");
        Objects.requireNonNull(rank);Objects.requireNonNull(key);
        State state=(State)TransactionSynchronizationManager.getResource(KEY);
        if(state==null) {
            state=new State();final State bound=state;TransactionSynchronizationManager.bindResource(KEY,bound);
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization(){
                public void beforeCommit(boolean readOnly){if(bound.violated)throw new IllegalStateException("Database lock order violation");}
                public void suspend(){TransactionSynchronizationManager.unbindResource(KEY);}
                public void resume(){TransactionSynchronizationManager.bindResource(KEY,bound);}
                public void afterCompletion(int status){TransactionSynchronizationManager.unbindResourceIfPossible(KEY);}
            });
        }
        var requested=new Lock(rank,key);
        if(state.held.contains(requested))return;
        if(state.highest!=null && requested.compareTo(state.highest)<0) {
            state.violated=true;throw new IllegalStateException("Database lock order violation");
        } // No private row IDs in error/log.
        state.held.add(requested);state.highest=requested;
    }
    public static void requireOutsideTransaction() {
        if(TransactionSynchronizationManager.isActualTransactionActive())throw new IllegalStateException("External work must run outside a transaction");
    }
}
