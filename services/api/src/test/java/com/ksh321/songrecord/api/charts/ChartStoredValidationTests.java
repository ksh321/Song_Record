package com.ksh321.songrecord.api.charts;
import com.ksh321.songrecord.api.songs.CandidateVerifier.Brand;
import java.nio.charset.StandardCharsets;import java.time.*;import java.util.*;
import org.junit.jupiter.api.Test;import static org.assertj.core.api.Assertions.*;
class ChartStoredValidationTests {
    final ChartScope scope=new ChartScope(Brand.TJ,ChartScope.Period.WEEKLY);final Instant time=Instant.parse("2026-10-10T00:00:00Z");
    byte[] payload(String tail){return ("[{\"brand\":\"tj\",\"no\":\"00123\",\"title\":\"원본\",\"singer\":\"가수\"}"+tail+"]").getBytes(StandardCharsets.UTF_8);}
    @Test void validationOfStoredWholeArrayHasNoPublishingSideEffects()throws Exception{
        try(var f=new ChartDatabaseFixture()){
            var id=f.staging.stage(scope,payload(""),time);var result=f.validation.validate(id);
            assertThat(result.id()).isEqualTo(id);assertThat(result.scope()).isEqualTo(scope);assertThat(result.fetchedAt()).isEqualTo(time);assertThat(result.revision()).isEqualTo(1);assertThat(result.items().getFirst().number()).isEqualTo("00123");
            var bad=f.staging.stage(scope,payload(",{}"),time);assertThatThrownBy(()->f.validation.validate(bad)).isInstanceOf(ChartValidation.InvalidChart.class);
            assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM chart_item",Integer.class)).isZero();assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM chart_publication WHERE snapshot_id IS NOT NULL",Integer.class)).isZero();
            assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM chart_snapshot WHERE state='STAGING'",Integer.class)).isEqualTo(2);
            assertThatThrownBy(()->f.validation.validate(UUID.randomUUID())).isInstanceOf(IllegalStateException.class);
        }
    }
    @Test void metadataMismatchCannotTurnInvalidSourceIntoTrustedChart()throws Exception{
        try(var f=new ChartDatabaseFixture()){var id=f.staging.stage(scope,payload(""),time);f.jdbc.update("UPDATE chart_snapshot SET source_url='https://example.invalid/' WHERE id=?",ChartStaging.bytes(id));assertThatThrownBy(()->f.validation.validate(id)).isInstanceOf(IllegalStateException.class);}
    }
}
