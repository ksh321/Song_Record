package com.ksh321.songrecord.api.operations;

import java.time.*;
import java.sql.Timestamp;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/** User-selected 30-day DB observation policy. No content/control/backup table deletion. */
public final class OperationsRetention {
 public static final Duration RETENTION=Duration.ofDays(30);
 private final JdbcTemplate db;private final TransactionTemplate tx;private final int batch;
 public OperationsRetention(JdbcTemplate db,PlatformTransactionManager manager,int batch){
  if(batch<1||batch>500)throw new IllegalArgumentException("Bounded observation retention batch required");
  this.db=db;this.batch=batch;tx=new TransactionTemplate(manager);tx.setTimeout(30);
 }
 public int prune(Instant now){
  var cutoff=Timestamp.from(now.minus(RETENTION));
  return tx.execute(s->{
   // Non-locking bounded selection avoids locking a full scan. Each PK delete rechecks age.
   var ids=db.query("SELECT id FROM operations_observation WHERE observed_at<? ORDER BY observed_at,id LIMIT ?",(rs,n)->rs.getBytes(1),cutoff,batch);
   int removed=0;for(var id:ids)removed+=db.update("DELETE FROM operations_observation WHERE id=? AND observed_at<?",id,cutoff);
   return removed;
  });
 }
}
