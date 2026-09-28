package com.ksh321.songrecord.api.songs;

import com.ksh321.songrecord.api.domain.DomainOrdering;
import com.ksh321.songrecord.api.domain.DomainTypes.*;
import com.ksh321.songrecord.api.pagination.PageCursor;
import com.ksh321.songrecord.api.web.ApiException;
import java.nio.file.*;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import tools.jackson.databind.json.JsonMapper;
import static org.assertj.core.api.Assertions.*;
import static com.ksh321.songrecord.api.songs.SongListRules.*;

class SongListRulesTests {
    static final UUID OWNER=UUID.fromString("00000000-0000-4000-8000-000000000001");
    static final UUID OTHER=UUID.fromString("00000000-0000-4000-8000-000000000002");
    static final Instant NOW=Instant.parse("2026-09-28T00:00:00Z");
    static Row row(UUID id,String title,String artist){return new Row(id,OWNER,title,artist,null,NOW,null,LifecycleState.ACTIVE);}
    @Test void allFiveSortsAndBothViewsMatchIndependentSharedFixture() throws Exception {
        var fixture=new JsonMapper().readTree(Files.readString(Path.of("../../fixtures/songs/list-order.json")));
        var rows=new ArrayList<Row>();
        for(var n:fixture.get("rows"))rows.add(new Row(UUID.fromString(n.get("id").asText()),OWNER,n.get("title").asText(),n.get("artist").asText(),n.get("tier").isNull()?null:SongTier.valueOf(n.get("tier").asText()),Instant.parse(n.get("created_at").asText()),n.get("latest_recorded_at").isNull()?null:Instant.parse(n.get("latest_recorded_at").asText()),LifecycleState.ACTIVE));
        for(var view:View.values())for(var sort:Sort.values()){
            var q=new Query("",sort,view,50);var expected=new ArrayList<String>();
            fixture.get("expected").get(view.name()).get(sort.name()).forEach(n->expected.add(n.asText()));
            Collections.shuffle(rows,new Random(17));
            assertThat(rows.stream().sorted(order(q)).map(r->r.id().toString()).toList()).as(view+"/"+sort).containsExactlyElementsOf(expected);
        }
    }
    @Test void searchIsLiteralPartialMatchingAcrossTitleOrArtistWithOwnerAndLifecycleIsolation(){
        var q=Query.parse(" \u3000BLUE\u00a0",null,null,null);
        assertThat(q.q()).isEqualTo("blue");assertThat(q.limit()).isEqualTo(50);assertThat(q.sort()).isEqualTo(Sort.ADDED_DESC);
        assertThat(q.includes(OWNER,row(OWNER,"my Blue song","가수"))).isTrue();
        assertThat(q.includes(OWNER,row(OWNER,"곡","Blue Band"))).isTrue();
        assertThat(q.includes(OTHER,row(OWNER,"Blue","가수"))).isFalse();
        for(var state:List.of(LifecycleState.TRASHED,LifecycleState.PURGE_PENDING,LifecycleState.PURGED))
            assertThat(q.includes(OWNER,new Row(OWNER,OWNER,"Blue","가수",null,NOW,null,state))).isFalse();
        assertThat(Query.parse(" \t",null,null,null).includes(OWNER,row(OWNER,"아무 곡","가수"))).isTrue();
        assertThat(Query.parse("가",null,null,null).includes(OWNER,row(OWNER,"가","x"))).isTrue();
        assertThat(Query.parse("a b",null,null,null).includes(OWNER,row(OWNER,"a  b","x"))).isFalse();
        assertThat(Query.parse("e",null,null,null).includes(OWNER,row(OWNER,"é","x"))).isFalse();
        assertThat(Query.parse("BTS",null,null,null).includes(OWNER,row(OWNER,"곡","방탄소년단"))).isFalse();
        for(String literal:List.of("%","_","!","\\")){
            var search=Query.parse(literal,null,null,null);
            assertThat(search.includes(OWNER,row(OWNER,"plain","artist"))).isFalse();
            assertThat(search.includes(OWNER,row(OWNER,"prefix"+literal+"suffix","artist"))).isTrue();
        }
        assertThat(Query.parse("a!%_\\b",null,null,null).likePattern()).isEqualTo("%a!!!%!_\\b%");
    }
    @Test void latestRecordingExcludesOtherOwnersSongsDraftTrashAndUnlinkedMetadata(){
        var song=UUID.randomUUID();var otherSong=UUID.randomUUID();
        var valid=new Recording(OWNER,song,NOW,MetadataState.SAVED,LifecycleState.ACTIVE);
        var later=new Recording(OWNER,song,NOW.plusSeconds(1),MetadataState.SAVED,LifecycleState.ACTIVE);
        var recordings=new ArrayList<>(List.of(valid,later,
                new Recording(OTHER,song,NOW.plusSeconds(100),MetadataState.SAVED,LifecycleState.ACTIVE),
                new Recording(OWNER,otherSong,NOW.plusSeconds(100),MetadataState.SAVED,LifecycleState.ACTIVE),
                new Recording(OWNER,null,NOW.plusSeconds(100),MetadataState.SAVED,LifecycleState.ACTIVE),
                new Recording(OWNER,song,NOW.plusSeconds(100),MetadataState.DRAFT,LifecycleState.ACTIVE)));
        for(var state:List.of(LifecycleState.TRASHED,LifecycleState.PURGE_PENDING,LifecycleState.PURGED))
            recordings.add(new Recording(OWNER,song,NOW.plusSeconds(100),MetadataState.SAVED,state));
        assertThat(latestRecording(OWNER,song,recordings)).isEqualTo(later.recordedAt());
        assertThat(latestRecording(OWNER,UUID.randomUUID(),recordings)).isNull();
        assertThat(latestRecording(OWNER,song,List.of())).isNull();
    }
    @Test void uuidTieIsUnsignedAndMissingRecordingAlwaysLast(){
        UUID low=UUID.fromString("7fffffff-ffff-4fff-8fff-ffffffffffff"),high=UUID.fromString("80000000-0000-4000-8000-000000000000");
        for(var sort:Sort.values())for(var view:View.values()){
            var q=new Query("",sort,view,1);
            assertThat(order(q).compare(row(low,"노래2","가수"),row(high,"노래02","가수"))).isNegative();
        }
        var missing=row(low,"곡","가수");
        var recorded=new Row(high,OWNER,"곡","가수",null,NOW,Instant.EPOCH,LifecycleState.ACTIVE);
        assertThat(order(Query.parse(null,"RECORDED_DESC",null,null)).compare(recorded,missing)).isNegative();
    }
    @Test void cursorBindsNormalizedSearchViewSortAndLimitAndKeepsLongTextWithinBudget(){
        var cursors=new PageCursor(new byte[32],Clock.fixed(NOW,ZoneOffset.UTC),Duration.ofMinutes(30));
        var q=Query.parse(" APPLE ","ARTIST","TIER_GROUPED",100);
        var r=row(OWNER,"😀".repeat(200),"😀".repeat(200));
        var tuple=tuple(q,r);var token=cursors.issue(OWNER,q.cursorQuery(),3,tuple);
        assertThat(token.length()).isLessThanOrEqualTo(PageCursor.MAX_LENGTH);
        assertThat(cursors.read(token,OWNER,Query.parse("apple","ARTIST","TIER_GROUPED",100).cursorQuery()).after()).isEqualTo(tuple);
        for(var changed:List.of(Query.parse("pear","ARTIST","TIER_GROUPED",100),Query.parse("apple","TITLE","TIER_GROUPED",100),Query.parse("apple","ARTIST","ALL",100),Query.parse("apple","ARTIST","TIER_GROUPED",50)))
            assertThatThrownBy(()->cursors.read(token,OWNER,changed.cursorQuery())).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("INVALID_CURSOR"));
    }
    @Test void invalidQueryValuesAreRejected(){
        for(String sort:List.of("title","","TITLE DESC; DROP TABLE song"))assertThatThrownBy(()->Query.parse(null,sort,null,null)).isInstanceOf(ApiException.class);
        assertThatThrownBy(()->Query.parse(null,null,"tier",null)).isInstanceOf(ApiException.class);
        assertThatThrownBy(()->Query.parse("가".repeat(201),null,null,null)).isInstanceOf(ApiException.class);
        for(int limit:List.of(0,-1,101))assertThatThrownBy(()->Query.parse(null,null,null,limit)).isInstanceOf(ApiException.class);
        assertThat(Query.parse("가".repeat(200),null,null,100).q()).hasSize(200);
    }
    @Test void binaryKeysMatchStructuredOrderForAllPairsIncludingTokenBoundaries(){
        var texts=new ArrayList<>(List.of("","가","가","ㄱ","A"," a ","a0","a00","a0a","a1","a01","a10","a2","a!","0","00","2","02","10","9".repeat(200),"1"+"0".repeat(199),"#","é","é","😀","\uE000","\u0000","a\u0000","a\u0000b"));
        var random=new Random(29);String[] atoms={"가","A","2","00","10","!","é","😀"," "};
        for(int i=0;i<100;i++){var b=new StringBuilder();for(int j=0;j<10;j++)b.append(atoms[random.nextInt(atoms.length)]);texts.add(b.toString());}
        for(var left:texts)for(var right:texts)
            assertThat(Integer.signum(Arrays.compareUnsigned(DomainOrdering.sortKeyBytes(left),DomainOrdering.sortKeyBytes(right))))
                    .as("%s / %s",left,right).isEqualTo(Integer.signum(DomainOrdering.compareSortText(left,right)));
        assertThat(HexFormat.of().formatHex(DomainOrdering.sortKeyBytes("a2"))).isEqualTo("010200006101000000013200");
        assertThat(DomainOrdering.sortKeyBytes("a02")).isEqualTo(DomainOrdering.sortKeyBytes("A2"));
    }
    @Test void actualH2BinaryColumnOrderingAndKeysetMatchSharedExamples() throws Exception {
        var jdbc=new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:sort_"+UUID.randomUUID()+";DB_CLOSE_DELAY=-1"));
        try{SongSortDatabaseChecks.verify(jdbc);}finally{jdbc.execute("SHUTDOWN");}
    }
}
