package com.ksh321.songrecord.api.operations;
import java.nio.file.*;
import java.time.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
/** Private, aggregate-only validation operator. No public monitoring/admin endpoint. */
public final class OperationsOperator {
 public static void main(String[] args){try{
  if(args.length!=0)throw new IllegalArgumentException();
  var source=new DriverManagerDataSource("jdbc:mysql://mysql:3306/song_record_validation?connectionTimeZone=UTC&forceConnectionTimeZoneToSession=true","song_record_validation",Files.readString(Path.of("/run/runtime/DB_PASSWORD")).strip());
  System.out.println(new tools.jackson.databind.json.JsonMapper().writeValueAsString(OperationsMetrics.snapshot(new JdbcTemplate(source),Instant.now())));
 }catch(Exception error){System.err.println("OPERATIONS_SNAPSHOT_UNCONFIRMED: values suppressed");System.exit(2);}}
}
