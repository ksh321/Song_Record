package com.ksh321.songrecord.api.operations;

import java.util.Map;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;

class PrivateOperationsDataSourceTests {
    @Test void preservesExistingLocalDefaultAndSelectsExplicitExperimentScope() {
        assertThat(PrivateOperationsDataSource.database(Map.of())).isEqualTo("song_record_validation");
        assertThat(PrivateOperationsDataSource.database(Map.of(
                "DB_NAME", "song_record_experiment", "DB_USER", "song_record_experiment",
                "DB_HOST", "mysql", "DB_PORT", "3306"))).isEqualTo("song_record_experiment");
    }

    @Test void refusesProductionInjectionAndPartialOrMismatchedConfiguration() {
        for (var environment : java.util.List.of(
                Map.of("DB_NAME", "song_record_prod", "DB_USER", "song_record_prod"),
                Map.of("DB_NAME", "song_record_experiment"),
                Map.of("DB_USER", "song_record_experiment"),
                Map.of("DB_NAME", "song_record_experiment", "DB_USER", "song_record_validation"),
                Map.of("DB_NAME", "song_record_experiment?allowLoadLocalInfile=true", "DB_USER", "root"),
                Map.of("DB_HOST", "external.example"), Map.of("DB_PORT", "3307"),
                Map.of("DB_NAME", "", "DB_USER", ""))) {
            assertThatThrownBy(() -> PrivateOperationsDataSource.database(environment))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessage("OPERATIONS_DATABASE_SCOPE_REJECTED");
        }
    }
}
