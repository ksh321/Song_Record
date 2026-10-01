package com.ksh321.songrecord.api.sync;

import java.sql.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;
import javax.sql.DataSource;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.*;
import org.springframework.transaction.support.TransactionTemplate;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

@EnabledIfEnvironmentVariable(named="P07_MYSQL_CI",matches="true")
class MySqlChangeReadViewTests extends ChangeReadViewTests {
    JdbcTemplate admin;String database;
    @Override @BeforeEach void setup(){
        String port=System.getenv().getOrDefault("P10_MYSQL_PORT","3306");
        if(!port.matches("[0-9]{1,5}"))throw new IllegalArgumentException("Invalid test port");
        String base="jdbc:mysql://127.0.0.1:"+port+"/",options="?allowPublicKeyRetrieval=true&useSSL=false&connectionTimeZone=UTC";
        String password=System.getenv("P07_MYSQL_PASSWORD");
        admin=new JdbcTemplate(new DriverManagerDataSource(base+options,"root",password));
        database="p10_change_test_"+UUID.randomUUID().toString().replace("-","");
        admin.execute("CREATE DATABASE "+database);
        source=new DriverManagerDataSource(base+database+options,"root",password);initialize();
    }
    @Override @AfterEach void cleanup(){if(admin!=null&&database!=null&&database.matches("p10_change_test_[0-9a-f]{32}"))admin.execute("DROP DATABASE "+database);}
    @Test void headAndRowsRemainConsistentAcrossConcurrentCommit()throws Exception{
        DataSource intercepted=mock(DataSource.class);var fired=new AtomicBoolean();
        when(intercepted.getConnection()).thenAnswer(invocation->{
            Connection actual=source.getConnection(),wrapped=mock(Connection.class,org.mockito.AdditionalAnswers.delegatesTo(actual));
            doAnswer(call->{
                String sql=call.getArgument(0);
                if(sql.contains("MAX(change_seq)")&&fired.compareAndSet(false,true)){
                    new TransactionTemplate(new DataSourceTransactionManager(source)).execute(s->{
                        insert(owner,4,now.plusSeconds(100));jdbc.update("UPDATE user_sync_state SET last_change_seq=4 WHERE user_id=?",bytes(owner));return null;
                    });
                }
                return actual.prepareStatement(sql);
            }).when(wrapped).prepareStatement(anyString());
            return wrapped;
        });
        var consistent=new ChangeReadView(intercepted,access,Clock.fixed(now,ZoneOffset.UTC));
        var old=consistent.read(account,0,100);assertThat(old.head()).isEqualTo(3);assertThat(old.entries()).hasSize(3);
        var next=view.read(account,3,100);assertThat(next.head()).isEqualTo(4);assertThat(next.entries()).extracting(ChangeWindow.Entry::sequence).containsExactly(4L);
    }
}
