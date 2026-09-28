package db.migration;

import com.ksh321.songrecord.api.songs.SongQueryKeys;
import com.ksh321.songrecord.api.recordings.RecordingQueryKeys;
import java.util.*;
import org.flywaydb.core.api.migration.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;

/** Bounded-memory upgrade of existing data, on Flyway's connection before serving requests. */
public final class V13__backfill_recording_query_keys extends BaseJavaMigration {
    @Override public Integer getChecksum() { return 13001; }
    @Override public void migrate(Context context) throws Exception {
        var connection=context.getConnection(); boolean own=connection.getAutoCommit();
        if(own)connection.setAutoCommit(false);
        try {
            var jdbc=new JdbcTemplate(new SingleConnectionDataSource(connection,true));
            backfill(jdbc);
            if(own)connection.commit();
        } catch(Exception e) {
            if(own)connection.rollback();
            throw e;
        } finally { if(own)connection.setAutoCommit(true); }
    }
    public static void backfill(JdbcTemplate jdbc) {
        byte[] after=null;
        while(true){
            String sql="SELECT id,user_id,title_snapshot FROM recording"+(after==null?"":" WHERE id>?")+" ORDER BY id LIMIT 250";
            var rows=after==null?jdbc.queryForList(sql):jdbc.queryForList(sql,after);
            if(rows.isEmpty())break;
            for(var row:rows){
                var id=(byte[])row.get("id");
                // Safe if a failed nontransactional migration was repaired and restarted.
                jdbc.update("DELETE FROM recording_query_key WHERE recording_id=?",id);
                RecordingQueryKeys.insert(jdbc,SongQueryKeys.uuid((byte[])row.get("user_id")),SongQueryKeys.uuid(id),(String)row.get("title_snapshot"));
            }
            after=(byte[])rows.getLast().get("id");
        }
    }
}
