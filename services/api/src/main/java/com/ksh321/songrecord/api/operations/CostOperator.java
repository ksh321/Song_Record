package com.ksh321.songrecord.api.operations;

import java.nio.file.*;
import java.time.*;
import java.util.Properties;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;

/** Private local operator, never an HTTP endpoint. Non-secret observation on stdin; DB key in tmpfs. */
public final class CostOperator {
    public static void main(String[] args) {
        try {
            if(args.length!=0)throw new IllegalArgumentException();
            var values=new Properties();values.load(System.in);
            if(!values.stringPropertyNames().equals(java.util.Set.of("observed","krw")))throw new IllegalArgumentException();
            var source=PrivateOperationsDataSource.open();
            CostGate.observe(new JdbcTemplate(source),new DataSourceTransactionManager(source),Instant.now(),Instant.parse(values.getProperty("observed")),Long.parseLong(values.getProperty("krw")));
            System.out.println("COST_GATE_APPLIED");
        } catch(Exception error) { System.err.println("COST_GATE_UNCONFIRMED: values suppressed");System.exit(2); }
    }
}
