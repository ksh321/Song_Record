package com.ksh321.songrecord.api.recordings;

import com.ksh321.songrecord.api.domain.DomainTypes.*;
import com.ksh321.songrecord.api.pagination.*;
import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.util.LinkedMultiValueMap;
import static org.assertj.core.api.Assertions.*;

class RecordingListRulesTests {
    final UUID owner=new UUID(0,1),song=new UUID(0,2),tagA=new UUID(0,3),tagB=new UUID(0,4);
    final Instant time=Instant.parse("2026-09-28T07:00:00Z");
    RecordingListRules.Query query(String... pairs){var p=new LinkedMultiValueMap<String,String>();for(int i=0;i<pairs.length;i+=2)p.add(pairs[i],pairs[i+1]);return RecordingListRules.parse(p);}
    RecordingListRules.Row row(long id,String title,Instant at,RecordingTier tier){return new RecordingListRules.Row(new UUID(0,id),owner,song,title,at,"MALE",-2,"LIVE",tier,"GOOD",Set.of(tagA,tagB),MetadataState.SAVED,LifecycleState.ACTIVE,false);}
    @Test void defaultsKeepMetadataWithoutFilesAndRejectForeignOrTrash(){
        var q=query();assertThat(q.sort()).isEqualTo(RecordingListRules.Sort.RECORDED_DESC);assertThat(q.limit()).isEqualTo(50);
        var saved=row(10,"title",time,null);assertThat(q.includes(owner,saved)).isTrue();assertThat(q.includes(UUID.randomUUID(),saved)).isFalse();
        var draft=new RecordingListRules.Row(new UUID(0,11),owner,null,null,time,null,null,"NORMAL",null,null,Set.of(),MetadataState.DRAFT,LifecycleState.ACTIVE,false);
        assertThat(q.includes(owner,draft)).isTrue();assertThat(query("metadata_state","SAVED").includes(owner,draft)).isFalse();assertThat(query("server_file","ABSENT").includes(owner,draft)).isTrue();
        for(var state:List.of(LifecycleState.TRASHED,LifecycleState.PURGE_PENDING,LifecycleState.PURGED))assertThat(q.includes(owner,new RecordingListRules.Row(saved.id(),owner,song,"title",time,"MALE",-2,"LIVE",null,"GOOD",saved.tags(),MetadataState.SAVED,state,false))).isFalse();
    }
    @Test void combinesFiltersWithHalfOpenPeriodAndAllSelectedTags(){
        var q=query("from","2026-09-28T07:00:00Z","to","2026-09-29T00:00:00Z","song_id",song.toString(),"key_mode","MALE","key_shift","-2","version_code","LIVE","tier","A","condition_code","GOOD","tag_ids",tagB+","+tagA,"server_file","ABSENT","metadata_state","SAVED");
        assertThat(q.includes(owner,row(10,"title",time,RecordingTier.A))).isTrue();
        assertThat(q.includes(owner,row(10,"title",time.minusMillis(1),RecordingTier.A))).isFalse();assertThat(q.includes(owner,row(10,"title",Instant.parse("2026-09-29T00:00:00Z"),RecordingTier.A))).isFalse();
        assertThat(q.includes(owner,row(10,"title",time,RecordingTier.B))).isFalse();
        assertThat(query("tag_ids",tagA+","+new UUID(0,99)).includes(owner,row(10,"title",time,null))).isFalse();
        assertThat(query("song_id","UNLINKED").includes(owner,row(10,"title",time,null))).isFalse();assertThat(query("server_file","PRESENT").includes(owner,row(10,"title",time,null))).isFalse();
    }
    @Test void unsetTierAndConditionAreDifferentFromNoFilterAndFilePresenceIsIndependent(){
        var r=new RecordingListRules.Row(new UUID(0,10),owner,null,null,time,null,null,"NORMAL",null,null,Set.of(),MetadataState.DRAFT,LifecycleState.ACTIVE,true);
        assertThat(query("song_id","UNLINKED","tier","NONE","condition_code","NONE","server_file","PRESENT").includes(owner,r)).isTrue();
        assertThat(query("tier","NONE").includes(owner,row(11,"title",time,RecordingTier.S))).isFalse();assertThat(query("condition_code","NONE").includes(owner,row(11,"title",time,null))).isFalse();
        assertThat(query("server_file","ABSENT").includes(owner,r)).isFalse();assertThat(query().includes(owner,r)).isTrue();
    }
    @Test void fourSortsUseCorrectTieBreaksAndNullTitleLast(){
        var a=row(10,"곡10",time,RecordingTier.A);var b=row(11,"곡2",time.plusSeconds(1),RecordingTier.S);var c=row(12,null,time.minusSeconds(1),null);var d=row(13,"곡2",time.plusSeconds(1),RecordingTier.S);var rows=List.of(c,d,b,a);
        assertOrder(rows,"RECORDED_DESC",11,13,10,12);assertOrder(rows,"RECORDED_ASC",12,10,11,13);assertOrder(rows,"TITLE",11,13,10,12);assertOrder(rows,"TIER",11,13,10,12);
        var laterS=row(14,"irrelevant",time.plusSeconds(2),RecordingTier.S);assertOrder(List.of(b,laterS),"TIER",14,11);
    }
    void assertOrder(List<RecordingListRules.Row> rows,String sort,long... ids){var q=query("sort",sort);assertThat(rows.stream().sorted(RecordingListRules.order(q)).map(r->r.id().getLeastSignificantBits()).toList()).containsExactly(Arrays.stream(ids).boxed().toArray(Long[]::new));}
    @Test void unsignedUuidFinalTieAndCursorTuplesMatchRowOrdering(){
        var a=row(1,"곡",time,null);var b=new RecordingListRules.Row(UUID.fromString("ffffffff-ffff-ffff-ffff-ffffffffffff"),owner,song,"곡",time,"MALE",-2,"LIVE",null,"GOOD",Set.of(),MetadataState.SAVED,LifecycleState.ACTIVE,false);
        for(var sort:RecordingListRules.Sort.values()){
            var q=query("sort",sort.name());assertThat(RecordingListRules.order(q).compare(a,b)).isNegative();
            assertThat(RecordingListRules.tupleOrder(q).compare(RecordingListRules.tuple(q,a),RecordingListRules.tuple(q,b))).isNegative();
            assertThatThrownBy(()->RecordingListRules.tupleOrder(q).compare(new PageCursor.Tuple(List.of(),a.id()),RecordingListRules.tuple(q,a))).isInstanceOf(ApiException.class);
        }
    }
    @Test void canonicalFiltersShareCursorAndChangedFiltersOrOwnerDoNot(){
        var a=query("tag_ids",tagB+","+tagA+","+tagA,"from","2026-09-28T07:00:00.000Z","tier","ALL","server_file","ALL");
        var b=query("tag_ids",tagA+","+tagB,"from","2026-09-28T07:00:00Z");assertThat(a.cursorQuery()).isEqualTo(b.cursorQuery());
        var cursors=new PageCursor(new byte[32],Clock.fixed(time,ZoneOffset.UTC),Duration.ofMinutes(30));String token=cursors.issue(owner,a.cursorQuery(),3,RecordingListRules.tuple(a,row(10,"title",time,null)));
        assertThat(cursors.read(token,owner,b.cursorQuery()).generation()).isEqualTo(3);
        for(var q:List.of(query("tag_ids",tagA.toString()),query("sort","TITLE"),query("limit","1"),query("server_file","PRESENT")))assertThatThrownBy(()->cursors.read(token,owner,q.cursorQuery())).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("INVALID_CURSOR"));
        assertThatThrownBy(()->cursors.read(token,UUID.randomUUID(),a.cursorQuery())).isInstanceOf(ApiException.class);
    }
    @Test void invalidUnknownRepeatedAndOutOfRangeParametersAreRejected(){
        for(String[] pair:List.of(new String[]{"q","x"},new String[]{"local_file","PRESENT"},new String[]{"limit","0"},new String[]{"limit","101"},new String[]{"key_shift","13"},new String[]{"key_shift","1.5"},new String[]{"key_mode","BAD"},new String[]{"song_id","1-1-1-1-1"},new String[]{"from","2026-02-30T00:00:00Z"},new String[]{"to","2026-09-28T00:00:00+09:00"},new String[]{"tag_ids",tagA+","},new String[]{"tier","null"},new String[]{"server_file","QUEUED"},new String[]{"cursor",""}))assertThatThrownBy(()->query(pair)).as(Arrays.toString(pair)).isInstanceOf(ApiException.class);
        assertThatThrownBy(()->query("sort","TITLE","sort","TIER")).isInstanceOf(ApiException.class);
        assertThatThrownBy(()->query("from",time.toString(),"to",time.toString())).isInstanceOf(ApiException.class);
        assertThatThrownBy(()->query("tag_ids",String.join(",",Collections.nCopies(21,tagA.toString())))).isInstanceOf(ApiException.class);
    }
}
