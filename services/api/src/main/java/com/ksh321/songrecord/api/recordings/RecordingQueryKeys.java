package com.ksh321.songrecord.api.recordings;

import com.ksh321.songrecord.api.domain.DomainOrdering;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;

/** Versioned derived data, maintained in the recording mutation transaction. */
public final class RecordingQueryKeys {
    public static final String VERSION=DomainOrdering.SORT_KEY_VERSION+"/"+DomainOrdering.SORT_BYTES_VERSION;
    private RecordingQueryKeys(){}
    public static void insert(JdbcTemplate jdbc,UUID owner,UUID id,String title){jdbc.update("INSERT INTO recording_query_key(recording_id,user_id,key_version,title_key) VALUES(?,?,?,?)",bytes(id),bytes(owner),VERSION,DomainOrdering.sortKeyBytes(title==null?"":title));}
    public static void replace(JdbcTemplate jdbc,UUID owner,UUID id,String title){jdbc.update("DELETE FROM recording_query_key WHERE user_id=? AND recording_id=?",bytes(owner),bytes(id));insert(jdbc,owner,id,title);}
}
