package com.ksh321.songrecord.api.retention;

import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import static com.ksh321.songrecord.api.retention.RetentionCandidateDatabaseChecks.*;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;

/** P11-09 fixtures run identically on H2 and migrated MySQL. Expected roles come from design 6.1/6.3. */
public final class RetentionExampleDatabaseChecks {
    private RetentionExampleDatabaseChecks() {}
    private record Example(String name,List<String> tiers,List<Integer> days,
            Integer representative,Integer latest,Integer lowest,int files) {}
    private static final List<Example> EXAMPLES=List.of(
        new Example("V08 overlap does not fill next-best slots",List.of("D","A","S"),List.of(3,2,1),0,0,0,1),
        new Example("V44 three song-wide roles across keys and versions",List.of("A","S","D"),List.of(2,3,1),0,1,2,3),
        new Example("V09 all unrated leaves representative and lowest empty",List.of("-","-","-"),List.of(1,3,2),null,1,null,1),
        new Example("V09 same tier/time uses ID; newer unrated only wins latest",List.of("D","D","-"),List.of(2,2,3),null,2,0,2),
        new Example("V09 newest wins same tier before ID",List.of("C","C","S"),List.of(1,3,2),null,1,1,1)
    );
    public static void verify(JdbcTemplate db) {
        var store=new RetentionSelectionStore(db,new DataSourceTransactionManager(db.getDataSource()));
        int scenario=0;
        for(var example:EXAMPLES) {
            UUID owner=account(db),firstDevice=device(db,owner),secondDevice=device(db,owner),song=song(db,owner);
            db.update("INSERT INTO user_sync_state(user_id) VALUES(?)",bytes(owner));
            var ids=new ArrayList<UUID>();
            for(int i=0;i<3;i++)ids.add(new UUID(0x6000000000004000L,0x8000000000000000L+(++scenario)));
            // Reverse insertion order and alternate devices; neither controls tie-breaking.
            for(int i=2;i>=0;i--) {
                recordingWithId(db,owner,i==1?secondDevice:firstDevice,song,true,true,"VALIDATED",ids.get(i));
                db.update("UPDATE recording SET tier=?,recorded_at=?,key_mode=?,key_shift=?,version_code=? WHERE id=?",
                    example.tiers().get(i).equals("-")?null:example.tiers().get(i),
                    "2026-10-0"+example.days().get(i)+" 00:00:00.123",
                    List.of("ORIGINAL","MALE","FEMALE").get(i),i==0?0:i==1?2:-2,
                    List.of("NORMAL","LIVE","MR").get(i),bytes(ids.get(i)));
            }
            UUID representative=id(ids,example.representative());
            db.update("UPDATE song SET representative_recording_id=? WHERE id=?",representative==null?null:bytes(representative),bytes(song));
            var before=db.queryForList("SELECT * FROM recording WHERE user_id=? ORDER BY id",bytes(owner));
            var result=store.recalculate(owner,song).orElseThrow();
            assertThat(result.ids()).as(example.name()).isEqualTo(new RetentionRoles.Ids(representative,id(ids,example.latest()),id(ids,example.lowest())));
            assertThat(result.recordingIds()).as(example.name()).hasSize(example.files());
            assertThat(store.recalculate(owner,song)).as("retry: "+example.name()).contains(result);
            assertThat(db.queryForList("SELECT * FROM recording WHERE user_id=? ORDER BY id",bytes(owner))).usingRecursiveComparison().isEqualTo(before);
            assertThat(db.queryForObject("SELECT COUNT(*) FROM recording_file_spec WHERE user_id=?",Integer.class,bytes(owner))).isEqualTo(3);
            assertThat(db.queryForObject("SELECT COUNT(*) FROM recording_asset WHERE user_id=?",Integer.class,bytes(owner))).isZero();
        }
    }
    private static UUID id(List<UUID> ids,Integer index){return index==null?null:ids.get(index);}
}
