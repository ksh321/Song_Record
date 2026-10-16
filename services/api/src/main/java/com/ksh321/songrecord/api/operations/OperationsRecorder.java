package com.ksh321.songrecord.api.operations;
import java.util.UUID;
import java.time.*;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.*;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
@Component @Profile({"staging","prod"})
public final class OperationsRecorder {
 private static final org.slf4j.Logger LOG=org.slf4j.LoggerFactory.getLogger(OperationsRecorder.class);
 private final JdbcTemplate db;private final TransactionTemplate tx;
 public OperationsRecorder(JdbcTemplate db,PlatformTransactionManager manager){this.db=db;tx=new TransactionTemplate(manager);tx.setPropagationBehavior(org.springframework.transaction.TransactionDefinition.PROPAGATION_REQUIRES_NEW);}
 public void record(UUID actor,UUID target,String kind,OperationsContext.Action action,OperationsContext.Result result,int status,long duration,Instant at){
  if(!java.util.Set.of("USER","WORKER","ANONYMOUS").contains(kind)||status<0||status>599||duration<0)throw new IllegalArgumentException();
  var event=UUID.randomUUID();
  try{tx.executeWithoutResult(s->{
   // Serialize with account purge, so a late response cannot recreate erased identifiers.
   boolean active=actor!=null && activeOwner(bytes(actor));
   var observedTarget=active && result==OperationsContext.Result.SUCCESS && (status==0 || status>=200&&status<300)?target:null;
   db.update("INSERT INTO operations_observation(id,actor_id,target_id,actor_kind,action,result,status_code,duration_ms,observed_at,sync_change_backlog) VALUES(?,?,?,?,?,?,?,?,?,?)",bytes(event),active?bytes(actor):null,observedTarget==null?null:bytes(observedTarget),active?kind:"ANONYMOUS",action.name(),result.name(),status,duration,java.sql.Timestamp.from(at),OperationsContext.syncBacklog());
  });LOG.info("operations_observation id={} action={} result={} status={} duration_ms={}",event,action.name(),result.name(),status,duration);}
  catch(Exception error){LOG.error("operations_observation_failed action={} result={}",action.name(),result.name());}
 }
 public void afterCommit(UUID actor,UUID target,OperationsContext.Action action,Instant at){
  Runnable actionRecord=()->record(actor,target,"WORKER",action,OperationsContext.Result.SUCCESS,0,0,at);
  if(TransactionSynchronizationManager.isSynchronizationActive())TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization(){@Override public void afterCommit(){actionRecord.run();}});else actionRecord.run();
 }
 public void job(com.ksh321.songrecord.api.jobs.JobQueue.Observation event){
  var result=event.action()==OperationsContext.Action.JOB_FAILURE||event.action()==OperationsContext.Action.JOB_RETRY?"FAILURE":"SUCCESS";
  try{tx.executeWithoutResult(s->{
   var owners=db.queryForList("SELECT user_id FROM job WHERE id=?",bytes(event.job()));
   if(owners.size()!=1)return;var owner=(byte[])owners.getFirst().get("user_id");
   if(owner!=null && !activeOwner(owner))return;
   // Global jobs have no personal owner, so do not retain their arbitrary aggregate ID.
   db.update("INSERT INTO operations_observation(id,actor_id,target_id,job_id,attempt_count,actor_kind,action,result,status_code,duration_ms,observed_at) VALUES(?,?,?,?,?,'WORKER',?,?,0,0,?)",bytes(UUID.randomUUID()),bytes(event.worker()),owner==null?null:bytes(event.target()),bytes(event.job()),event.attempt(),event.action().name(),result,java.sql.Timestamp.from(event.at()));
  });}
  catch(Exception error){LOG.error("operations_job_observation_failed action={}",event.action().name());}
 }
 private boolean activeOwner(byte[] owner){var rows=db.queryForList("SELECT status FROM app_user WHERE id=? FOR UPDATE",owner);return rows.size()==1&&"ACTIVE".equals(rows.getFirst().get("status"));}
}
