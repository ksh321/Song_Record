package com.ksh321.songrecord.api.operations;

import java.time.*;
import java.sql.Timestamp;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;

public final class OperationsRetentionDatabaseChecks {
 public static void verify(JdbcTemplate db){
  var now=Instant.parse("2026-10-15T00:00:00Z");var cutoff=now.minus(Duration.ofDays(30));
  var recent=UUID.randomUUID();var boundary=UUID.randomUUID();
  insert(db,recent,now);insert(db,boundary,cutoff);
  for(int i=0;i<5;i++)insert(db,UUID.randomUUID(),cutoff.minusSeconds(i+1));
  var retention=new OperationsRetention(db,new DataSourceTransactionManager(db.getDataSource()),2);
  assertThat(retention.prune(now)).isEqualTo(2);assertThat(retention.prune(now)).isEqualTo(2);assertThat(retention.prune(now)).isEqualTo(1);assertThat(retention.prune(now)).isZero();
  assertThat(db.queryForObject("SELECT COUNT(*) FROM operations_observation",Long.class)).isEqualTo(2);
  for(var id:List.of(recent,boundary))assertThat(db.queryForObject("SELECT COUNT(*) FROM operations_observation WHERE id=?",Long.class,bytes(id))).isEqualTo(1);
  assertThatThrownBy(()->new OperationsRetention(db,new DataSourceTransactionManager(db.getDataSource()),501)).isInstanceOf(IllegalArgumentException.class);
 }
 static void insert(JdbcTemplate db,UUID id,Instant at){db.update("INSERT INTO operations_observation(id,actor_kind,action,result,status_code,duration_ms,observed_at) VALUES(?,'ANONYMOUS','OTHER','SUCCESS',200,0,?)",bytes(id),Timestamp.from(at));}
}
