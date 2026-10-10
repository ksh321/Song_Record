package com.ksh321.songrecord.api.charts;
import java.sql.Connection;import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;import org.springframework.jdbc.datasource.*;
final class ChartDatabaseFixture implements AutoCloseable {
    final DriverManagerDataSource ds=new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL","sa","");
    final Connection keeper;final JdbcTemplate jdbc=new JdbcTemplate(ds);final DataSourceTransactionManager manager=new DataSourceTransactionManager(ds);
    final ChartStaging staging=new ChartStaging(jdbc,manager);final ChartStoredValidation validation=new ChartStoredValidation(jdbc,new ChartValidation());
    ChartDatabaseFixture()throws Exception{
        keeper=ds.getConnection();
        jdbc.execute("CREATE TABLE chart_snapshot(id BINARY(16) PRIMARY KEY,brand VARCHAR(2) NOT NULL,period VARCHAR(8) NOT NULL,provider VARCHAR(16) NOT NULL,source_url VARCHAR(512) NOT NULL,fetched_at TIMESTAMP NOT NULL,revision BIGINT NOT NULL,state VARCHAR(16) NOT NULL,item_count INT NOT NULL,published_at TIMESTAMP,UNIQUE(brand,period,id),UNIQUE(brand,period,revision),CHECK((state='STAGING' AND published_at IS NULL AND item_count=0) OR (state='PUBLISHED' AND published_at>=fetched_at AND item_count>0)))");
        jdbc.execute("CREATE TABLE chart_publication(brand VARCHAR(2),period VARCHAR(8),snapshot_id BINARY(16),collection_attempt_id BINARY(16),published_attempt_id BINARY(16),PRIMARY KEY(brand,period),FOREIGN KEY(brand,period,snapshot_id) REFERENCES chart_snapshot(brand,period,id))");
        jdbc.execute("CREATE TABLE chart_item(snapshot_id BINARY(16),position INT NOT NULL,brand VARCHAR(2),period VARCHAR(8),number VARCHAR(20) NOT NULL,title VARCHAR(200) NOT NULL,artist VARCHAR(200) NOT NULL,PRIMARY KEY(snapshot_id,position),UNIQUE(snapshot_id,number),FOREIGN KEY(brand,period,snapshot_id) REFERENCES chart_snapshot(brand,period,id),CHECK(position>0),CHECK(LENGTH(TRIM(title))>0 AND LENGTH(TRIM(artist))>0))");
        jdbc.execute("CREATE TABLE chart_collection_payload(snapshot_id BINARY(16) PRIMARY KEY,payload BLOB NOT NULL,FOREIGN KEY(snapshot_id) REFERENCES chart_snapshot(id) ON DELETE CASCADE)");
        for(var b:com.ksh321.songrecord.api.songs.CandidateVerifier.Brand.values())for(var p:ChartScope.Period.values())jdbc.update("INSERT INTO chart_publication(brand,period) VALUES(?,?)",b.name(),p.name());
    }
    public void close()throws Exception{keeper.close();}
}
