package com.ksh321.songrecord.api.songs;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.domain.DomainOrdering;
import com.ksh321.songrecord.api.domain.DomainTypes.*;
import com.ksh321.songrecord.api.pagination.*;
import com.ksh321.songrecord.api.web.ApiException;
import java.sql.*;
import java.time.*;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.util.MultiValueMap;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;

public final class SongListing {
    private final AccountAccess access; private final KeysetPages pages;
    public SongListing(AccountAccess access,KeysetPages pages){this.access=access;this.pages=pages;}
    public KeysetPages.Page<Map<String,Object>> list(String auth,String device,MultiValueMap<String,String> params){
        var account=access.authenticate(auth,device);
        for(var entry:params.entrySet())if(!Set.of("q","sort","view","limit","cursor").contains(entry.getKey()) || entry.getValue().size()!=1)throw invalid();
        Integer limit=null;String raw=params.getFirst("limit");
        if(raw!=null){try{if(!raw.matches("[0-9]{1,3}"))throw invalid();limit=Integer.valueOf(raw);}catch(NumberFormatException e){throw invalid();}}
        var query=SongListRules.Query.parse(params.getFirst("q"),params.getFirst("sort"),params.getFirst("view"),limit);
        return pages.query(account,query.cursorQuery(),params.getFirst("cursor"),new Source(query));
    }
    public static final class Source implements KeysetPages.Source<Map<String,Object>> {
        private final SongListRules.Query query;
        public Source(SongListRules.Query query){this.query=query;}
        private String from(){return " FROM song s JOIN song_query_key k ON k.song_id=s.id AND k.user_id=s.user_id WHERE s.user_id=? AND s.lifecycle_state='ACTIVE' AND k.key_version=?"+(query.q().isEmpty()?"":" AND (LOCATE(?,k.title_search)>0 OR LOCATE(?,k.artist_search)>0)");}
        private ArrayList<Object> args(UUID owner){var args=new ArrayList<Object>();args.add(bytes(owner));args.add(VERSION);if(!query.q().isEmpty()){args.add(search(query.q()));args.add(search(query.q()));}return args;}
        @Override public long count(JdbcTemplate jdbc,UUID owner){
            long missing=jdbc.queryForObject("SELECT COUNT(*) FROM song s LEFT JOIN song_query_key k ON k.song_id=s.id AND k.user_id=s.user_id WHERE s.user_id=? AND s.lifecycle_state='ACTIVE' AND (k.song_id IS NULL OR k.key_version<>?)",Long.class,bytes(owner),VERSION);
            if(missing!=0)throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE,"SONG_INDEX_NOT_READY","곡 검색 정보를 준비 중입니다.",true,Map.of());
            return jdbc.queryForObject("SELECT COUNT(*)"+from(),Long.class,args(owner).toArray());
        }
        @Override public List<KeysetPages.Entry<Map<String,Object>>> fetch(JdbcTemplate jdbc,UUID owner,PageCursor.Tuple after,int maximum){
            var columns=columns(after);var args=args(owner);String boundary="";
            if(after!=null){
                var terms=new ArrayList<String>();
                for(int i=0;i<columns.size();i++){
                    var column=columns.get(i);if(column.value==null)continue;
                    var parts=new ArrayList<String>();
                    for(int j=0;j<i;j++){var prefix=columns.get(j);parts.add(prefix.sql+(prefix.value==null?" IS NULL":"=?"));if(prefix.value!=null)args.add(prefix.value);}
                    parts.add(column.sql+(column.desc?"<?":">?"));args.add(column.value);terms.add("("+String.join(" AND ",parts)+")");
                }
                boundary=" WHERE ("+String.join(" OR ",terms)+")";
            }
            String order=String.join(",",columns.stream().map(c->c.sql+(c.desc?" DESC":" ASC")).toList());
            String rank="CASE s.song_tier WHEN 'S' THEN 0 WHEN 'A' THEN 1 WHEN 'B' THEN 2 WHEN 'C' THEN 3 WHEN 'D' THEN 4 ELSE 5 END";
            String recent="(SELECT MAX(r.recorded_at) FROM recording r WHERE r.user_id=s.user_id AND r.song_id=s.id AND r.lifecycle_state='ACTIVE' AND r.metadata_state='SAVED')";
            String sql="SELECT p.* FROM (SELECT s.*,k.title_key,k.artist_key,"+rank+" AS tier_rank,"+recent+" AS latest_recorded_at"+from()+") p"+boundary+" ORDER BY "+order+" LIMIT ?";
            args.add(maximum);
            return jdbc.query(sql,(rs,n)->{
                var id=uuid(rs.getBytes("id"));var tier=rs.getString("song_tier");
                var row=new SongListRules.Row(id,owner,rs.getString("title"),rs.getString("artist"),tier==null?null:SongTier.valueOf(tier),instant(rs,"created_at"),instant(rs,"latest_recorded_at"),LifecycleState.ACTIVE);
                return new KeysetPages.Entry<>(snapshot(rs),SongListRules.tuple(query,row));
            },args.toArray());
        }
        private record Column(String sql,boolean desc,Object value){}
        private List<Column> columns(PageCursor.Tuple after){
            var values=after==null?null:after.values();
            if(after!=null)order().compare(after,after); // Validate tuple arity before translating its values.
            var result=new ArrayList<Column>();int at=0;
            if(query.view()==SongListRules.View.TIER_GROUPED)result.add(new Column("p.tier_rank",false,after==null?null:Integer.valueOf(values.get(at++))));
            switch(query.sort()){
                case ADDED_DESC -> result.add(new Column("p.created_at",true,after==null?null:timestamp(values.get(at))));
                case RECORDED_DESC -> {
                    String time=after==null?null:values.get(at);
                    result.add(new Column("CASE WHEN p.latest_recorded_at IS NULL THEN 1 ELSE 0 END",false,after==null?null:time==null?1:0));
                    result.add(new Column("p.latest_recorded_at",true,time==null?null:timestamp(time)));
                }
                case TIER -> {result.add(new Column("p.tier_rank",false,after==null?null:Integer.valueOf(values.get(at++))));result.add(new Column("p.title_key",false,after==null?null:DomainOrdering.sortKeyBytes(values.get(at))));}
                case TITLE -> result.add(new Column("p.title_key",false,after==null?null:DomainOrdering.sortKeyBytes(values.get(at))));
                case ARTIST -> {result.add(new Column("p.artist_key",false,after==null?null:DomainOrdering.sortKeyBytes(values.get(at++))));result.add(new Column("p.title_key",false,after==null?null:DomainOrdering.sortKeyBytes(values.get(at))));}
            }
            result.add(new Column("p.id",false,after==null?null:bytes(after.id())));return result;
        }
        @Override public Comparator<PageCursor.Tuple> order(){return SongListRules.tupleOrder(query);}
    }
    private static LocalDateTime timestamp(String value){return LocalDateTime.ofInstant(Instant.parse(value),ZoneOffset.UTC);}
    private static Instant instant(ResultSet rs,String column)throws SQLException{var value=rs.getTimestamp(column);return value==null?null:value.toLocalDateTime().toInstant(ZoneOffset.UTC);}
    private static Map<String,Object> snapshot(ResultSet rs)throws SQLException{
        var map=new LinkedHashMap<String,Object>();map.put("id",uuid(rs.getBytes("id")).toString());map.put("revision",rs.getLong("revision"));
        for(String name:List.of("source_type","tj_number","title","artist","version_code","note","lifecycle_state"))map.put(name,rs.getString(name));
        map.put("tier",rs.getString("song_tier"));map.put("representative_key_mode",rs.getString("representative_key_mode"));map.put("representative_key_shift",rs.getObject("representative_key_shift"));
        for(String name:List.of("updated_at","created_at","latest_recorded_at")){var value=instant(rs,name);map.put(name,value==null?null:value.toString());}
        return map;
    }
    private static ApiException invalid(){return new ApiException(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR","곡 검색 조건을 확인해 주세요.",false,Map.of());}
}
