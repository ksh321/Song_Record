package com.ksh321.songrecord.api.recordings;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.domain.DomainTypes.*;
import com.ksh321.songrecord.api.pagination.*;
import java.time.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.util.LinkedMultiValueMap;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;

/** Same comparison oracle runs against H2 and fully migrated MySQL, including real triggers. */
public final class RecordingListingDatabaseChecks {
    private RecordingListingDatabaseChecks(){}
    public static void verify(JdbcTemplate db,KeysetPages pages,AccountAccess.Account account,UUID owner,UUID device){
        UUID song=UUID.randomUUID(),tagA=UUID.randomUUID(),tagB=UUID.randomUUID();
        db.update("INSERT INTO song(id,user_id,source_type,title,artist,note,lifecycle_state) VALUES(?,?,'MANUAL','song','artist','','ACTIVE')",bytes(song),bytes(owner));
        for(UUID tag:List.of(tagA,tagB))db.update("INSERT INTO tag(id,user_id,name,normalized_name_key) VALUES(?,?,?,?)",bytes(tag),bytes(owner),tag.toString(),tag.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8));
        var rows=new ArrayList<RecordingListRules.Row>();Instant base=Instant.parse("2026-09-28T00:00:00Z");
        for(int i=0;i<7;i++){
            UUID id=i==6?UUID.fromString("ffffffff-ffff-ffff-ffff-ffffffffffff"):new UUID(0,100+i);String title=switch(i){case 0->"곡10";case 1->"곡2";case 4->null;default->"같은 제목";};
            Instant time=base.plusSeconds(i==2 || i==6?3:i);var tier=i<4?RecordingTier.values()[i]:null;UUID linked=i%2==0?song:null;
            var tags=i==0?Set.of(tagA,tagB):i==1?Set.of(tagA):Set.<UUID>of();boolean saved=i!=4;var state=i==5?LifecycleState.TRASHED:LifecycleState.ACTIVE;
            db.update("INSERT INTO recording(id,user_id,origin_device_id,song_id,title_snapshot,artist_snapshot,version_code,key_mode,key_shift,tier,note,recorded_at,timezone_id,timezone_offset_minutes,metadata_state,lifecycle_state,condition_code) VALUES(?,?,?,?,?,?,'LIVE','MALE',-2,?,'',?,'UTC',0,'DRAFT','ACTIVE',?)",bytes(id),bytes(owner),bytes(device),linked==null?null:bytes(linked),title,"artist",tier==null?null:tier.name(),LocalDateTime.ofInstant(time,ZoneOffset.UTC),i==0?"GOOD":null);
            if(saved){db.update("INSERT INTO recording_file_spec(recording_id,user_id,sha256,size_bytes,duration_ms,codec,sample_rate,channels,capture_integrity) VALUES(?,?,?,10,1000,'AAC_LC',48000,1,'VALIDATED')",bytes(id),bytes(owner),"a".repeat(64));db.update("UPDATE recording SET metadata_state='SAVED' WHERE id=?",bytes(id));}
            if(state==LifecycleState.TRASHED)db.update("UPDATE recording SET lifecycle_state='TRASHED',deleted_at=CURRENT_TIMESTAMP WHERE id=?",bytes(id));
            RecordingQueryKeys.insert(db,owner,id,title);
            for(UUID tag:tags)db.update("INSERT INTO recording_tag(user_id,recording_id,tag_id,name_snapshot) VALUES(?,?,?,'tag')",bytes(owner),bytes(id),bytes(tag));
            if(i==0)db.update("INSERT INTO recording_asset(recording_id,user_id,cloud_state,object_key,generation,verified_size,sha256,stored_at) VALUES(?,?,'STORED','test/object',?,10,?,CURRENT_TIMESTAMP)",bytes(id),bytes(owner),bytes(UUID.randomUUID()),"a".repeat(64));
            if(i==1)db.update("INSERT INTO recording_asset(recording_id,user_id,cloud_state) VALUES(?,?,'QUEUED')",bytes(id),bytes(owner));
            rows.add(new RecordingListRules.Row(id,owner,linked,title,time,"MALE",-2,"LIVE",tier,i==0?"GOOD":null,tags,saved?MetadataState.SAVED:MetadataState.DRAFT,state,i==0));
        }
        db.update("INSERT INTO song_cloud_selection(song_id,user_id,representative_id,latest_id,lowest_tier_id) VALUES(?,?,?,?,?)",bytes(song),bytes(owner),bytes(rows.getFirst().id()),bytes(rows.getFirst().id()),bytes(rows.getFirst().id()));
        List<Map<String,String>> filters=List.of(Map.of(),Map.of("song_id","UNLINKED"),Map.of("song_id",song.toString()),Map.of("metadata_state","DRAFT"),Map.of("metadata_state","SAVED"),Map.of("tier","NONE"),Map.of("condition_code","NONE"),Map.of("condition_code","GOOD"),Map.of("server_file","PRESENT"),Map.of("server_file","ABSENT"),Map.of("tag_ids",tagB+","+tagA),Map.of("from",base.plusSeconds(1).toString(),"to",base.plusSeconds(4).toString()),Map.of("key_mode","MALE","key_shift","-2","version_code","LIVE"),Map.of("tier","D"));
        for(var sort:RecordingListRules.Sort.values())for(var filter:filters){
            var params=new LinkedMultiValueMap<String,String>();filter.forEach(params::add);params.add("sort",sort.name());params.add("limit","2");var query=RecordingListRules.parse(params);
            var expected=rows.stream().filter(r->query.includes(owner,r)).sorted(RecordingListRules.order(query)).map(RecordingListRules.Row::id).toList();
            var actual=new ArrayList<UUID>();String cursor=null;int iterations=0;
            do{var page=pages.query(account,query.cursorQuery(),cursor,new RecordingListing.Source(query));assertThat(page.count()).as(sort+" "+filter).isEqualTo(expected.size());for(var item:page.items()){
                UUID id=UUID.fromString((String)item.get("id"));actual.add(id);var row=rows.stream().filter(r->r.id().equals(id)).findFirst().orElseThrow();
                @SuppressWarnings("unchecked") var cloud=(Map<String,Object>)item.get("cloud");assertThat(cloud.get("stored")).isEqualTo(row.serverStored());assertThat(item.get("tag_ids")).isEqualTo(row.tags().stream().map(UUID::toString).sorted().toList());
                if(id.equals(rows.getFirst().id()))assertThat(cloud.get("desired_reasons")).isEqualTo(List.of("REPRESENTATIVE","LATEST","LOWEST_TIER"));
            }cursor=page.next_cursor();assertThat(++iterations).isLessThan(10);}while(cursor!=null);
            assertThat(actual).as(sort+" "+filter).containsExactlyElementsOf(expected);
        }
        var query=RecordingListRules.parse(new LinkedMultiValueMap<>());
        db.update("DELETE FROM recording_query_key WHERE recording_id=?",bytes(rows.getFirst().id()));
        assertThatThrownBy(()->pages.query(account,query.cursorQuery(),null,new RecordingListing.Source(query))).isInstanceOfSatisfying(com.ksh321.songrecord.api.web.ApiException.class,e->assertThat(e.code()).isEqualTo("RECORDING_INDEX_NOT_READY"));
    }
}
