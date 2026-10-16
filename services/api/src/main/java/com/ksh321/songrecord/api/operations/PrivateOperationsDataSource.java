package com.ksh321.songrecord.api.operations;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;
import java.util.Set;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

/** Private staging observation only; never accepts a production DB or arbitrary JDBC URL. */
final class PrivateOperationsDataSource {
    private static final Set<String> DATABASES = Set.of("song_record_validation", "song_record_experiment");

    static DriverManagerDataSource open() throws IOException {
        // Validate the destination before reading its credential.
        var database = database(System.getenv());
        var password = Files.readString(Path.of("/run/runtime/DB_PASSWORD")).strip();
        if (password.isEmpty()) throw new IllegalArgumentException("OPERATIONS_CREDENTIAL_UNAVAILABLE");
        return new DriverManagerDataSource(
                "jdbc:mysql://mysql:3306/" + database + "?connectionTimeZone=UTC&forceConnectionTimeZoneToSession=true",
                database, password);
    }

    static String database(Map<String, String> environment) {
        var database = environment.getOrDefault("DB_NAME", "song_record_validation");
        var user = environment.getOrDefault("DB_USER", "song_record_validation");
        if (!DATABASES.contains(database) || !database.equals(user)
                || !environment.getOrDefault("DB_HOST", "mysql").equals("mysql")
                || !environment.getOrDefault("DB_PORT", "3306").equals("3306")) {
            throw new IllegalArgumentException("OPERATIONS_DATABASE_SCOPE_REJECTED");
        }
        return database;
    }

    private PrivateOperationsDataSource() {}
}
