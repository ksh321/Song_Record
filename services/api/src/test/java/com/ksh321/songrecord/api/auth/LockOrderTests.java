package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.locking.*;
import com.ksh321.songrecord.api.locking.LockOrder.Rank;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.*;
import static org.assertj.core.api.Assertions.*;

class LockOrderTests {
    final IdempotencyTests f=new IdempotencyTests();StorageLocks locks;
    @BeforeEach void setup() throws Exception {
        f.setup();locks=new StorageLocks(f.jdbc,f.access,f.manager);
        f.jdbc.execute("CREATE TABLE global_storage_usage(id INT PRIMARY KEY)");f.jdbc.update("INSERT INTO global_storage_usage VALUES(1)");
        f.jdbc.execute("CREATE TABLE song_cloud_selection(song_id BINARY(16) PRIMARY KEY,user_id BINARY(16))");
        f.jdbc.execute("CREATE TABLE pin_slot(user_id BINARY(16),slot_no INT,PRIMARY KEY(user_id,slot_no))");
        f.jdbc.execute("CREATE TABLE recording_asset(recording_id BINARY(16) PRIMARY KEY,user_id BINARY(16))");
    }
    @AfterEach void close() throws Exception {f.close();}
    void tx(Runnable work){new TransactionTemplate(f.manager).executeWithoutResult(s->work.run());}
    @Test void ascendingLocksAndReacquiringAnOwnedRowAreAllowed() {
        tx(()->{LockOrder.before(Rank.GLOBAL_STORAGE,"1");LockOrder.before(Rank.USER_SYNC,"a");LockOrder.before(Rank.JOB,"z");LockOrder.before(Rank.GLOBAL_STORAGE,"1");});
    }
    @Test void reverseRankRollsBackDomainEffectAndDoesNotLeakKeys() {
        assertThatThrownBy(()->tx(()->{f.effect();LockOrder.before(Rank.JOB,"private-key");LockOrder.before(Rank.USER_SYNC,"private-user");}))
            .isInstanceOf(IllegalStateException.class).hasMessage("Database lock order violation");assertThat(f.count()).isZero();
    }
    @Test void sameRankMustUseStableAscendingKeys() {
        assertThatThrownBy(()->tx(()->{LockOrder.before(Rank.AGGREGATE,"b");LockOrder.before(Rank.AGGREGATE,"a");})).isInstanceOf(IllegalStateException.class);
    }
    @Test void swallowedViolationStillPreventsCommit() {
        assertThatThrownBy(()->tx(()->{f.effect();LockOrder.before(Rank.JOB,"a");try{LockOrder.before(Rank.USER_SYNC,"a");}catch(IllegalStateException ignored){}})).isInstanceOf(IllegalStateException.class);
        assertThat(f.count()).isZero();
    }
    @Test void completionAndRollbackCleanThreadState() {
        tx(()->LockOrder.before(Rank.JOB,"z"));tx(()->LockOrder.before(Rank.GLOBAL_STORAGE,"1"));
        assertThatThrownBy(()->tx(()->{LockOrder.before(Rank.JOB,"z");throw new IllegalStateException();})).isInstanceOf(IllegalStateException.class);
        tx(()->LockOrder.before(Rank.GLOBAL_STORAGE,"1"));
    }
    @Test void suspendedTransactionHasIndependentStateThenRestoresOuterState() {
        tx(()->{
            LockOrder.before(Rank.JOB,"z");var inner=new TransactionTemplate(f.manager);inner.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
            inner.executeWithoutResult(s->LockOrder.before(Rank.GLOBAL_STORAGE,"1"));LockOrder.before(Rank.JOB,"z");
        });
    }
    @Test void requiresTransactionAndExternalWorkRequiresNoTransaction() {
        assertThatThrownBy(()->LockOrder.before(Rank.GLOBAL_STORAGE,"1")).isInstanceOf(IllegalStateException.class);
        LockOrder.requireOutsideTransaction();assertThatThrownBy(()->tx(LockOrder::requireOutsideTransaction)).isInstanceOf(IllegalStateException.class);
    }
    @Test void realStorageLocksRespectOrderAndOwnership() {
        var id=UUID.randomUUID();var owner=OwnershipTests.bytes(f.registration.userId());
        f.jdbc.update("INSERT INTO song_cloud_selection VALUES(?,?)",OwnershipTests.bytes(id),owner);
        f.jdbc.update("INSERT INTO pin_slot VALUES(?,1)",owner);
        f.jdbc.update("INSERT INTO recording_asset VALUES(?,?)",OwnershipTests.bytes(id),owner);
        tx(()->{locks.global();locks.owned(f.account,StorageLocks.Target.ENTITLEMENT,null);locks.owned(f.account,StorageLocks.Target.USAGE,null);locks.owned(f.account,StorageLocks.Target.SELECTION,id);locks.pin(f.account,1);locks.owned(f.account,StorageLocks.Target.ASSET,id);});
        assertThatThrownBy(()->tx(()->locks.owned(f.other,StorageLocks.Target.ASSET,id)))
            .isInstanceOfSatisfying(com.ksh321.songrecord.api.web.ApiException.class,e->{assertThat(e.status().value()).isEqualTo(404);assertThat(e.details()).isEmpty();});
        assertThatThrownBy(()->tx(()->{locks.owned(f.account,StorageLocks.Target.USAGE,null);locks.global();})).isInstanceOf(IllegalStateException.class);
    }
}
