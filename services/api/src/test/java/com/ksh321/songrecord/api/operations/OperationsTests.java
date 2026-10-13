package com.ksh321.songrecord.api.operations;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.mock.web.*;
import static org.mockito.Mockito.*;
import static org.assertj.core.api.Assertions.*;
class OperationsTests {
 @Test void countsUniqueAccountsDistinctSavedTargetsAndCommittedEventsOnly(){
  var db=new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:obs_"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa",""));
  db.execute("CREATE TABLE operations_observation(id BINARY(16) PRIMARY KEY,actor_id BINARY(16),target_id BINARY(16),actor_kind VARCHAR(16),action VARCHAR(32),result VARCHAR(32),status_code INT,duration_ms BIGINT,observed_at TIMESTAMP,sync_change_backlog BIGINT)");OperationsObservationDatabaseChecks.verify(db);
 }
 @Test void requestBodyAndUrlSecretsNeverReachRecorderAndThreadStateClears()throws Exception{
  var writer=mock(OperationsRecorder.class);var filter=new OperationsFilter(writer);var request=new MockHttpServletRequest("POST","/v1/pins/1/replacement");request.setContent("{\"memo\":\"synthetic-private-note\",\"token\":\"synthetic-token\"}".getBytes());request.setQueryString("X-Amz-Signature=synthetic-private-signature");var response=new MockHttpServletResponse();var owner=UUID.randomUUID();var target=UUID.randomUUID();
  filter.doFilter(request,response,(r,s)->{OperationsContext.actor(owner);OperationsContext.target(target);OperationsContext.failure("QUOTA_EXCEEDED");response.setStatus(409);});
  verify(writer).record(eq(owner),eq(target),eq("USER"),eq(OperationsContext.Action.PIN_REPLACE),eq(OperationsContext.Result.QUOTA_EXCEEDED),eq(409),anyLong(),any());
  var fresh=OperationsContext.begin();assertThat(fresh.actor).isNull();assertThat(fresh.target).isNull();OperationsContext.clear();
 }
 @Test void playbackUrlIssuanceIsNotPlaybackAndThrownFailureIsNotSuccess()throws Exception{
  assertThat(OperationsContext.route("POST","/v1/recordings/"+UUID.randomUUID()+"/playback-url")).isEqualTo(OperationsContext.Action.PLAYBACK_URL);
  var writer=mock(OperationsRecorder.class);var filter=new OperationsFilter(writer);var request=new MockHttpServletRequest("GET","/v1/sync/changes");
  assertThatThrownBy(()->filter.doFilter(request,new MockHttpServletResponse(),(r,s)->{throw new IllegalStateException("synthetic-private-detail");})).isInstanceOf(IllegalStateException.class);
  verify(writer).record(isNull(),isNull(),eq("ANONYMOUS"),eq(OperationsContext.Action.SYNC),eq(OperationsContext.Result.FAILURE),eq(500),anyLong(),any());
 }
}
