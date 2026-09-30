package com.ksh321.songrecord.api.sync;

import com.ksh321.songrecord.api.auth.*;
import java.sql.Connection;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

/** InnoDB, not H2 REPEATABLE READ, provides D09's cross-table consistent view. */
@EnabledIfEnvironmentVariable(named="P07_MYSQL_CI", matches="true")
class MySqlSnapshotReadViewTests extends SnapshotReadViewTests {
    JdbcTemplate admin;
    String database;
    @Override @BeforeEach void setup() {
        String port=System.getenv().getOrDefault("P10_MYSQL_PORT","3306");
        if(!port.matches("[0-9]{1,5}"))throw new IllegalArgumentException("Invalid test port");
        String base="jdbc:mysql://127.0.0.1:"+port+"/";
        String options="?allowPublicKeyRetrieval=true&useSSL=false";
        String password=System.getenv("P07_MYSQL_PASSWORD");
        admin=new JdbcTemplate(new DriverManagerDataSource(base+options,"root",password));
        database="p10_snapshot_test_"+UUID.randomUUID().toString().replace("-","");
        admin.execute("CREATE DATABASE "+database);
        source=new DriverManagerDataSource(base+database+options,"root",password);
        jdbc=new JdbcTemplate(source);
        jdbc.execute("CREATE TABLE user_sync_state(user_id BINARY(16) PRIMARY KEY,last_change_seq BIGINT) ENGINE=InnoDB");
        jdbc.execute("CREATE TABLE song(user_id BINARY(16),note VARCHAR(100)) ENGINE=InnoDB");
        jdbc.update("INSERT INTO user_sync_state VALUES(?,7)",bytes(owner));
        jdbc.update("INSERT INTO song VALUES(?,'before')",bytes(owner));
        access=mock(AccountAccess.class);account=mock(AccountAccess.Account.class);
        when(access.revalidate(account)).thenReturn(new SessionService.Principal(owner,UUID.randomUUID(),UUID.randomUUID()));
        view=new SnapshotReadView(source,access,Clock.fixed(now,ZoneOffset.UTC));
    }
    @Override @AfterEach void cleanup() {
        // Only the unique database created by this test, never an application DB.
        if(admin!=null && database!=null && database.matches("p10_snapshot_test_[0-9a-f]{32}"))
            admin.execute("DROP DATABASE "+database);
    }
    @Test void sequenceAndRowsRemainInOneReadViewWhileAnotherConnectionCommits() throws Exception {
        var captured=view.capture(account,now,(connection,id)->{
            assertThat(connection.getTransactionIsolation()).isEqualTo(Connection.TRANSACTION_REPEATABLE_READ);
            assertThat(connection.getAutoCommit()).isFalse();
            try(var writer=source.getConnection()) {
                writer.setAutoCommit(false);
                try(var update=writer.createStatement()) {
                    update.executeUpdate("UPDATE song SET note='after'");
                    update.executeUpdate("UPDATE user_sync_state SET last_change_seq=8");
                }
                writer.commit();
            }
            return note(connection,id);
        });
        assertThat(captured.cursor()).isEqualTo(7);
        assertThat(captured.value()).isEqualTo("before");
        assertThat(captured.capturedAt()).isEqualTo(now);
        var fresh=view.capture(account,now,this::note);
        assertThat(fresh.cursor()).isEqualTo(8);
        assertThat(fresh.value()).isEqualTo("after");
    }
}
