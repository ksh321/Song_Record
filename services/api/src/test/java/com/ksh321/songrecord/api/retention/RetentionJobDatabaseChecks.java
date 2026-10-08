package com.ksh321.songrecord.api.retention;

import com.ksh321.songrecord.api.auth.*;
import com.ksh321.songrecord.api.jobs.JobQueue;
import com.ksh321.songrecord.api.revision.RevisionChanges;
import com.ksh321.songrecord.api.sync.AccountChanges;
import java.time.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import static com.ksh321.songrecord.api.retention.RetentionCandidateDatabaseChecks.*;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

/** Real migrated MySQL: domain event, lease fencing and current-state calculation compose atomically. */
public final class RetentionJobDatabaseChecks {
    public static void verify(JdbcTemplate db) {
        UUID owner=account(db),dev=device(db,owner),song=song(db,owner);
        db.update("INSERT INTO user_sync_state(user_id) VALUES(?)",bytes(owner));
        UUID recording=recording(db,owner,dev,song,true,true,"VALIDATED");
        var access=mock(AccountAccess.class);var account=mock(AccountAccess.Account.class);
        var principal=new SessionService.Principal(owner,dev,UUID.randomUUID());
        when(access.revalidate(account)).thenReturn(principal);when(account.principal()).thenReturn(principal);
        var manager=new DataSourceTransactionManager(db.getDataSource());var clock=Clock.systemUTC();
        var jobs=new JobQueue(db,access,manager,clock,Duration.ofMinutes(2),3);
        var changes=new AccountChanges(db,access,manager,clock);var revisions=new RevisionChanges(db,access,manager,clock);
        var store=new RetentionSelectionStore(db,manager);
        new TransactionTemplate(manager).execute(s->jobs.enqueue(account,JobQueue.Type.POLICY_RECALCULATE,song,UUID.randomUUID(),"{}"));
        var old=jobs.claim(JobQueue.Type.POLICY_RECALCULATE).orElseThrow();
        new TransactionTemplate(manager).execute(s->changes.write(account,()->{
            var row=revisions.change(account,RevisionChanges.Resource.RECORDING,recording.toString(),1L,before->db.update("UPDATE recording SET tier='D' WHERE id=?",bytes(recording)));
            return new AccountChanges.Batch<>(1,List.of(new AccountChanges.Change(AccountChanges.Entity.RECORDING,recording,((Number)row.get("revision")).longValue(),AccountChanges.Operation.UPSERT,"{}")));
        }));
        assertThat(new RetentionWorker(jobs,store).runOnce()).isTrue();
        var latest=store.recalculate(owner,song).orElseThrow();assertThat(latest.ids().lowestTier()).isEqualTo(recording);
        assertThat(jobs.complete(old,()->store.recalculateInJob(owner,song))).isTrue();
        assertThat(store.recalculate(owner,song)).contains(latest);
        assertThat(db.queryForObject("SELECT COUNT(*) FROM job WHERE user_id=? AND state='SUCCEEDED'",Long.class,bytes(owner))).isEqualTo(2);
    }
    public static void verifyPins(JdbcTemplate db) {
        UUID owner=account(db),dev=device(db,owner);
        db.update("INSERT INTO user_sync_state(user_id) VALUES(?)",bytes(owner));
        db.update("INSERT INTO user_entitlement(user_id) VALUES(?)",bytes(owner));
        var access=mock(AccountAccess.class);var account=mock(AccountAccess.Account.class);
        var principal=new SessionService.Principal(owner,dev,UUID.randomUUID());
        when(access.revalidate(account)).thenReturn(principal);when(account.principal()).thenReturn(principal);
        when(access.authenticate("Bearer fixture",dev.toString())).thenReturn(account);
        var manager=new DataSourceTransactionManager(db.getDataSource());
        var mutations=new com.ksh321.songrecord.api.idempotency.IdempotentMutations(db,access,manager,Clock.systemUTC());
        UUID second=device(db,owner);
        var secondAccount=mock(AccountAccess.Account.class);
        var secondPrincipal=new SessionService.Principal(owner,second,UUID.randomUUID());
        when(secondAccount.principal()).thenReturn(secondPrincipal);when(access.revalidate(secondAccount)).thenReturn(secondPrincipal);
        when(access.authenticate("Bearer second-fixture",second.toString())).thenReturn(secondAccount);
        PinReservationDatabaseChecks.verify(db,new PinSlots(db,access,mutations),"Bearer fixture",dev.toString(),owner,"Bearer second-fixture",second.toString());
    }

    public static void verifyRelease(JdbcTemplate db) {
        UUID owner=account(db),dev=device(db,owner);
        db.update("INSERT INTO user_sync_state(user_id) VALUES(?)",bytes(owner));db.update("INSERT INTO user_entitlement(user_id) VALUES(?)",bytes(owner));db.update("INSERT INTO storage_usage(user_id) VALUES(?)",bytes(owner));
        var access=mock(AccountAccess.class);var account=mock(AccountAccess.Account.class);var principal=new SessionService.Principal(owner,dev,UUID.randomUUID());
        when(access.revalidate(account)).thenReturn(principal);when(account.principal()).thenReturn(principal);when(access.authenticate("Bearer fixture",dev.toString())).thenReturn(account);
        var manager=new DataSourceTransactionManager(db.getDataSource());var mutations=new com.ksh321.songrecord.api.idempotency.IdempotentMutations(db,access,manager,Clock.systemUTC());
        PinReleaseDatabaseChecks.verify(db,new PinSlots(db,access,mutations),new RetentionQueries(db,access,manager),"Bearer fixture",dev.toString(),owner);
    }

}
