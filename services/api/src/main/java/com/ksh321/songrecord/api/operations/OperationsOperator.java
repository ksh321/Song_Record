package com.ksh321.songrecord.api.operations;
import java.time.*;
import org.springframework.jdbc.core.JdbcTemplate;
/** Private, aggregate-only validation operator. No public monitoring/admin endpoint. */
public final class OperationsOperator {
 public static void main(String[] args){try{
  if(args.length!=0)throw new IllegalArgumentException();
  var source=PrivateOperationsDataSource.open();
  System.out.println(new tools.jackson.databind.json.JsonMapper().writeValueAsString(OperationsMetrics.snapshot(new JdbcTemplate(source),Instant.now())));
 }catch(Exception error){System.err.println("OPERATIONS_SNAPSHOT_UNCONFIRMED: values suppressed");System.exit(2);}}
}
