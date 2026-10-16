package com.ksh321.songrecord.api.account;

import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.ConnectionCallback;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;

/** Erase owner-linked observation identifiers in the same account-purge transaction. */
final class DeletionObservations {
 private final JdbcTemplate db;private final boolean available;private final List<String> targets;
 DeletionObservations(JdbcTemplate db,List<String> reviewedTables){
  this.db=db;
  var columns=db.execute((ConnectionCallback<Map<String,Set<String>>>) connection->{
   var result=new HashMap<String,Set<String>>();
   try(var rows=connection.getMetaData().getColumns(connection.getCatalog(),connection.getSchema(),"%","%")){
    while(rows.next())result.computeIfAbsent(rows.getString("TABLE_NAME").toLowerCase(Locale.ROOT),k->new HashSet<>()).add(rows.getString("COLUMN_NAME").toLowerCase(Locale.ROOT));
   }return result;
  });
  available=columns.containsKey("operations_observation");
  // Reviewed owner tables only; never interpolate a request or unrestricted metadata name.
  var allowed=new HashSet<>(reviewedTables);allowed.addAll(Set.of("job","deletion_ledger","account_deletion_status","operational_backup_fence"));
  targets=allowed.stream().filter(t->columns.getOrDefault(t,Set.of()).containsAll(Set.of("id","user_id"))).sorted().toList();
 }
 void beforePurge(UUID owner){
  if(!available)return;
  clearDirect(owner);
  for(var column:List.of("target_id","previous_target_id")){
   var query="UPDATE operations_observation SET "+column+"=NULL WHERE "+column+"=?";
   var parameters=new ArrayList<Object>();parameters.add(bytes(owner));
   if(!targets.isEmpty()){
    query+=" OR "+column+" IN ("+String.join(" UNION ALL ",targets.stream().map(table->"SELECT id FROM "+table+" WHERE user_id=?").toList())+")";
    for(var ignored:targets)parameters.add(bytes(owner));
   }
   db.update(query,parameters.toArray());
  }
 }
 void clearDirect(UUID owner){
  if(!available)return;
  db.update("DELETE FROM operations_observation WHERE actor_id=? OR job_id IN (SELECT id FROM job WHERE user_id=?)",bytes(owner),bytes(owner));
 }
 boolean hasDirectReferences(UUID owner){
  return available && db.queryForObject("SELECT COUNT(*) FROM operations_observation WHERE actor_id=? OR job_id IN (SELECT id FROM job WHERE user_id=?)",Long.class,bytes(owner),bytes(owner))!=0;
 }
}
