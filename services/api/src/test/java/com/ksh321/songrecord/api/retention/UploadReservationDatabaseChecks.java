package com.ksh321.songrecord.api.retention;
import com.ksh321.songrecord.api.auth.*;
import com.ksh321.songrecord.api.uploads.UploadReservations;
import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import static com.ksh321.songrecord.api.retention.RetentionCandidateDatabaseChecks.*;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

/** Identical boundary/race/rollback assertions on H2 and migrated InnoDB. */
public final class UploadReservationDatabaseChecks {
    public static void verify(JdbcTemplate db) throws Exception {
        UUID owner=account(db),dev=device(db,owner),other=account(db),otherDev=device(db,other);
        for(UUID u:List.of(owner,other)){
            db.update("INSERT INTO user_sync_state(user_id) VALUES(?)",bytes(u));
            db.update("INSERT INTO user_entitlement(user_id) VALUES(?)",bytes(u));
            db.update("INSERT INTO storage_usage(user_id) VALUES(?)",bytes(u));
        }
        var access=mock(AccountAccess.class);var a=mock(AccountAccess.Account.class);var b=mock(AccountAccess.Account.class);
        when(access.revalidate(a)).thenReturn(new SessionService.Principal(owner,dev,UUID.randomUUID()));
        when(access.revalidate(b)).thenReturn(new SessionService.Principal(other,otherDev,UUID.randomUUID()));
        var manager=new DataSourceTransactionManager(db.getDataSource());var service=new UploadReservations(db,access,manager,Clock.systemUTC());
        UUID r1=recording(db,owner,dev,null,true,true,"VALIDATED"),r2=recording(db,owner,dev,null,true,true,"VALIDATED"),r3=recording(db,other,otherDev,null,true,true,"VALIDATED");
        db.update("UPDATE global_storage_usage SET used_bytes=0,reserved_bytes=0,primary_quota_bytes=20000000000,upload_locked=FALSE WHERE id=1");
        db.update("UPDATE storage_usage SET used_bytes=999999990 WHERE user_id=?",bytes(owner));
        // Two different recordings contend for the last ten bytes of the personal quota.
        List<Object> race=race(()->service.reserve(a,request(r1,10)),()->service.reserve(a,request(r2,10)));
        assertThat(race.stream().filter(UploadReservations.Reservation.class::isInstance).count()).isEqualTo(1);
        assertThat(race).contains("QUOTA_EXCEEDED");
        var winner=(UploadReservations.Reservation)race.stream().filter(UploadReservations.Reservation.class::isInstance).findFirst().orElseThrow();
        assertThat(service.reserve(a,request(winner.recording(),10))).isEqualTo(winner);
        assertThat(db.queryForObject("SELECT reserved_bytes FROM storage_usage WHERE user_id=?",Long.class,bytes(owner))).isEqualTo(10);
        assertThat(db.queryForObject("SELECT reserved_bytes FROM global_storage_usage WHERE id=1",Long.class)).isEqualTo(10);
        assertThatThrownBy(()->service.reserve(b,request(r1,1))).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("RESOURCE_NOT_FOUND"));
        // Separate accounts serialize on the shared remaining global capacity.
        db.update("UPDATE storage_usage SET used_bytes=0 WHERE user_id=?",bytes(owner));
        db.update("UPDATE global_storage_usage SET used_bytes=19999999980 WHERE id=1");
        UUID loser=winner.recording().equals(r1)?r2:r1;
        race=race(()->service.reserve(a,request(loser,10)),()->service.reserve(b,request(r3,10)));
        assertThat(race.stream().filter(UploadReservations.Reservation.class::isInstance).count()).isEqualTo(1);assertThat(race).contains("QUOTA_EXCEEDED");
        assertThat(db.queryForObject("SELECT used_bytes+reserved_bytes FROM global_storage_usage WHERE id=1",Long.class)).isEqualTo(20000000000L);
        // All records and both counters roll back if the surrounding command fails.
        UUID fresh=account(db),fd=device(db,fresh),fr=recording(db,fresh,fd,null,true,true,"VALIDATED");
        db.update("INSERT INTO user_sync_state(user_id) VALUES(?)",bytes(fresh));db.update("INSERT INTO user_entitlement(user_id) VALUES(?)",bytes(fresh));db.update("INSERT INTO storage_usage(user_id) VALUES(?)",bytes(fresh));
        var c=mock(AccountAccess.Account.class);when(access.revalidate(c)).thenReturn(new SessionService.Principal(fresh,fd,UUID.randomUUID()));
        db.update("UPDATE global_storage_usage SET used_bytes=0 WHERE id=1");long before=db.queryForObject("SELECT reserved_bytes FROM global_storage_usage WHERE id=1",Long.class);
        assertThatThrownBy(()->new TransactionTemplate(manager).execute(s->{service.reserve(c,request(fr,1));throw new IllegalStateException("rollback");})).isInstanceOf(IllegalStateException.class);
        assertThat(db.queryForObject("SELECT COUNT(*) FROM recording_upload WHERE user_id=?",Long.class,bytes(fresh))).isZero();
        assertThat(db.queryForObject("SELECT reserved_bytes FROM storage_usage WHERE user_id=?",Long.class,bytes(fresh))).isZero();
        assertThat(db.queryForObject("SELECT reserved_bytes FROM global_storage_usage WHERE id=1",Long.class)).isEqualTo(before);
        db.update("UPDATE global_storage_usage SET upload_locked=TRUE WHERE id=1");
        assertThatThrownBy(()->service.reserve(c,request(fr,1))).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("UPLOAD_BUDGET_LOCKED"));
        db.update("UPDATE global_storage_usage SET upload_locked=FALSE,used_bytes=9223372036854775807 WHERE id=1");
        assertThatThrownBy(()->service.reserve(c,request(fr,1))).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("QUOTA_EXCEEDED"));
        assertThatThrownBy(()->request(fr,-1)).isInstanceOf(IllegalArgumentException.class);
        assertThat(db.queryForObject("SELECT COUNT(*) FROM storage_usage WHERE used_bytes<0 OR reserved_bytes<0",Long.class)).isZero();
    }
    static UploadReservations.Request request(UUID r,long size){return new UploadReservations.Request(r,size,"a".repeat(64),1);}
    interface Call {Object run();}
    static List<Object> race(Call first,Call second)throws Exception{
        try(var pool=Executors.newFixedThreadPool(2)){
            var go=new CountDownLatch(1);var futures=new ArrayList<Future<Object>>();
            for(var call:List.of(first,second))futures.add(pool.submit(()->{go.await();try{return call.run();}catch(ApiException e){return e.code();}}));
            go.countDown();return List.of(futures.get(0).get(20,TimeUnit.SECONDS),futures.get(1).get(20,TimeUnit.SECONDS));
        }
    }
}
