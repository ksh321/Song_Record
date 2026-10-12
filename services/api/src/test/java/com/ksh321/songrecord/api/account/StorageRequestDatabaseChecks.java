package com.ksh321.songrecord.api.account;
import com.ksh321.songrecord.api.auth.*;
import com.ksh321.songrecord.api.idempotency.IdempotentMutations;
import com.ksh321.songrecord.api.pagination.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import static com.ksh321.songrecord.api.retention.RetentionCandidateDatabaseChecks.*;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

/** Only a newly created, fully migrated disposable MySQL database. */
public final class StorageRequestDatabaseChecks {
 public static void verify(JdbcTemplate db)throws Exception{
  UUID owner=account(db),dev=device(db,owner);db.update("INSERT INTO user_sync_state(user_id) VALUES(?)",bytes(owner));
  db.update("INSERT INTO user_entitlement(user_id,pinned_limit,quota_bytes) VALUES(?,3,1000)",bytes(owner));db.update("INSERT INTO storage_usage(user_id,used_bytes) VALUES(?,222)",bytes(owner));
  var access=mock(AccountAccess.class);var account=mock(AccountAccess.Account.class);var principal=new SessionService.Principal(owner,dev,UUID.randomUUID());
  when(account.principal()).thenReturn(principal);when(access.authenticate("fixture",dev.toString())).thenReturn(account);when(access.revalidate(account)).thenReturn(principal);
  var instant=new AtomicReference<>(Instant.now());var clock=new Clock(){public ZoneId getZone(){return ZoneOffset.UTC;}public Clock withZone(ZoneId z){return this;}public Instant instant(){return instant.get();}};
  var manager=new DataSourceTransactionManager(db.getDataSource());var mutations=new IdempotentMutations(db,access,manager,clock);
  var requests=new StorageRequests(db,access,mutations,new KeysetPages(db,access,manager,new PageCursor(new byte[32],clock,Duration.ofMinutes(30))),clock);
  String id=UUID.randomUUID().toString(),op=UUID.randomUUID().toString(),body="{\"id\":\""+id+"\",\"types\":[\"PIN_LIMIT\",\"STORAGE_QUOTA\"]}";
  var receipt=requests.create("fixture",dev.toString(),op,body);assertThat(requests.create("fixture",dev.toString(),op,body)).isEqualTo(receipt);
  assertThat(requests.create("fixture",dev.toString(),UUID.randomUUID().toString(),body).status()).isEqualTo(200);
  assertThat(db.queryForObject("SELECT request_total FROM storage_request_daily",Long.class)).isEqualTo(1);
  assertThat(db.queryForMap("SELECT pinned_used,pinned_limit,used_bytes,quota_bytes FROM storage_request_body")).containsEntry("pinned_used",0).containsEntry("pinned_limit",3).containsEntry("used_bytes",222L).containsEntry("quota_bytes",1000L);
  var pool=Executors.newFixedThreadPool(2);
  try{var a=pool.submit(()->requests.create("fixture",dev.toString(),UUID.randomUUID().toString(),"{\"id\":\""+UUID.randomUUID()+"\",\"types\":[\"PIN_LIMIT\"]}"));var b=pool.submit(()->requests.create("fixture",dev.toString(),UUID.randomUUID().toString(),"{\"id\":\""+UUID.randomUUID()+"\",\"types\":[\"PIN_LIMIT\"]}"));assertThat(a.get(15,TimeUnit.SECONDS).status()).isEqualTo(201);assertThat(b.get(15,TimeUnit.SECONDS).status()).isEqualTo(201);}finally{pool.shutdownNow();}
  assertThat(db.queryForObject("SELECT request_total FROM storage_request_daily",Long.class)).isEqualTo(3);
  assertThat(db.queryForObject("SELECT unique_users FROM storage_request_daily",Long.class)).isEqualTo(1);
  assertThat(db.queryForObject("SELECT used_bytes FROM storage_usage WHERE user_id=?",Long.class,bytes(owner))).isEqualTo(222);
  assertThat(db.queryForObject("SELECT pinned_limit FROM user_entitlement WHERE user_id=?",Integer.class,bytes(owner))).isEqualTo(3);
  instant.set(instant.get().plus(Duration.ofDays(90)));requests.pruneExpired();
  assertThat(db.queryForObject("SELECT COUNT(*) FROM storage_request_body",Long.class)).isZero();assertThat(db.queryForObject("SELECT COUNT(*) FROM storage_request_operation",Long.class)).isZero();assertThat(db.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Long.class)).isZero();
  assertThat(db.queryForObject("SELECT COUNT(*) FROM storage_request_ledger",Long.class)).isEqualTo(3);
  assertThatThrownBy(()->requests.create("fixture",dev.toString(),UUID.randomUUID().toString(),body)).isInstanceOfSatisfying(com.ksh321.songrecord.api.web.ApiException.class,e->assertThat(e.code()).isEqualTo("STORAGE_REQUEST_EXPIRED"));
 }
}
