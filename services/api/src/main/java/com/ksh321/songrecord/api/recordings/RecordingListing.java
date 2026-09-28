package com.ksh321.songrecord.api.recordings;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.domain.DomainOrdering;
import com.ksh321.songrecord.api.pagination.*;
import com.ksh321.songrecord.api.web.ApiException;
import java.sql.*;
import java.time.*;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.util.MultiValueMap;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;

public final class RecordingListing {
    private final AccountAccess access;private final KeysetPages pages;
    public RecordingListing(AccountAccess access,KeysetPages pages){this.access=access;this.pages=pages;}
    public KeysetPages.Page<Map<String,Object>> list(String auth,String device,MultiValueMap<String,String> params){var account=access.authenticate(auth,device);var query=RecordingListRules.parse(params);return pages.query(account,query.cursorQuery(),query.cursor(),new Source(query));}
    public static final class Source implements KeysetPages.Source<Map<String,Object>> {
        private static final String STORED="(a.cloud_state IN ('STORED','DELETING') AND a.stored_at IS NOT NULL)";
        private final RecordingListRules.Query query;
        public Source(RecordingListRules.Query query){this.query=query;}
        private record Filter(String sql,List<Object> args){}
        private Filter filter(UUID owner){
            var args=new ArrayList<Object>();args.add(bytes(owner));args.add(RecordingQueryKeys.VERSION);
            var sql=new StringBuilder(" FROM recording r JOIN recording_query_key k ON k.recording_id=r.id AND k.user_id=r.user_id LEFT JOIN recording_asset a ON a.recording_id=r.id AND a.user_id=r.user_id WHERE r.user_id=? AND r.lifecycle_state='ACTIVE' AND k.key_version=?");
            for(var e:query.filters().entrySet()){
                String value=e.getValue();
                switch(e.getKey()){
                    case "from","to" -> {sql.append(" AND r.recorded_at").append(e.getKey().equals("from")?">= ?":"< ?");args.add(timestamp(value));}
                    case "song_id" -> {if(value.equals("UNLINKED"))sql.append(" AND r.song_id IS NULL");else{sql.append(" AND r.song_id=?");args.add(bytes(UUID.fromString(value)));}}
                    case "tier","condition_code" -> {sql.append(" AND r.").append(e.getKey());if(value.equals("NONE"))sql.append(" IS NULL");else{sql.append("=?");args.add(value);}}
                    case "key_mode","version_code","metadata_state" -> {sql.append(" AND r.").append(e.getKey()).append("=?");args.add(value);}
                    case "key_shift" -> {sql.append(" AND r.key_shift=?");args.add(Integer.valueOf(value));}
                    case "server_file" -> sql.append(value.equals("PRESENT")?" AND "+STORED:" AND (a.cloud_state IS NULL OR NOT "+STORED+")");
                    case "tag_ids" -> {for(String tag:value.split(",")){sql.append(" AND EXISTS (SELECT 1 FROM recording_tag rt WHERE rt.user_id=r.user_id AND rt.recording_id=r.id AND rt.tag_id=?)");args.add(bytes(UUID.fromString(tag)));}}
                    default -> throw new IllegalStateException("Unknown recording filter");
                }
            }
            return new Filter(sql.toString(),args);
        }
        @Override public long count(JdbcTemplate jdbc,UUID owner){
            long missing=jdbc.queryForObject("SELECT COUNT(*) FROM recording r LEFT JOIN recording_query_key k ON k.recording_id=r.id AND k.user_id=r.user_id WHERE r.user_id=? AND r.lifecycle_state='ACTIVE' AND (k.recording_id IS NULL OR k.key_version<>?)",Long.class,bytes(owner),RecordingQueryKeys.VERSION);
            if(missing!=0)throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE,"RECORDING_INDEX_NOT_READY","녹음 정렬 정보를 준비 중입니다.",true,Map.of());
            var f=filter(owner);return jdbc.queryForObject("SELECT COUNT(*)"+f.sql,Long.class,f.args.toArray());
        }
        private record Column(String sql,boolean desc,Object value){}
        private List<Column> columns(PageCursor.Tuple after){
            if(after!=null)order().compare(after,after);var values=after==null?null:after.values();var columns=new ArrayList<Column>();
            switch(query.sort()){
                case RECORDED_DESC,RECORDED_ASC -> columns.add(new Column("p.recorded_at",query.sort()==RecordingListRules.Sort.RECORDED_DESC,after==null?null:timestamp(values.getFirst())));
                case TITLE -> columns.add(new Column("p.title_key",false,after==null?null:DomainOrdering.sortKeyBytes(values.getFirst())));
                case TIER -> {columns.add(new Column("p.tier_rank",false,after==null?null:Integer.valueOf(values.getFirst())));columns.add(new Column("p.recorded_at",true,after==null?null:timestamp(values.get(1))));}
            }
            columns.add(new Column("p.id",false,after==null?null:bytes(after.id())));return columns;
        }
        @Override public List<KeysetPages.Entry<Map<String,Object>>> fetch(JdbcTemplate jdbc,UUID owner,PageCursor.Tuple after,int maximum){
            var f=filter(owner);var args=new ArrayList<>(f.args);var cols=columns(after);String boundary="";
            if(after!=null){var alternatives=new ArrayList<String>();for(int i=0;i<cols.size();i++){var parts=new ArrayList<String>();for(int j=0;j<i;j++){parts.add(cols.get(j).sql+"=?");args.add(cols.get(j).value);}var c=cols.get(i);parts.add(c.sql+(c.desc?"<?":">?"));args.add(c.value);alternatives.add("("+String.join(" AND ",parts)+")");}boundary=" WHERE ("+String.join(" OR ",alternatives)+")";}
            String rank="CASE r.tier WHEN 'S' THEN 0 WHEN 'A' THEN 1 WHEN 'B' THEN 2 WHEN 'C' THEN 3 WHEN 'D' THEN 4 ELSE 5 END";
            String roles=",EXISTS(SELECT 1 FROM song_cloud_selection sc WHERE sc.user_id=r.user_id AND sc.song_id=r.song_id AND sc.representative_id=r.id) AS role_rep,EXISTS(SELECT 1 FROM song_cloud_selection sc WHERE sc.user_id=r.user_id AND sc.song_id=r.song_id AND sc.latest_id=r.id) AS role_latest,EXISTS(SELECT 1 FROM song_cloud_selection sc WHERE sc.user_id=r.user_id AND sc.song_id=r.song_id AND sc.lowest_tier_id=r.id) AS role_lowest,EXISTS(SELECT 1 FROM pin_slot ps WHERE ps.user_id=r.user_id AND (ps.current_recording_id=r.id OR ps.pending_recording_id=r.id)) AS role_pin";
            String sql="SELECT p.* FROM (SELECT r.*,k.title_key,"+rank+" AS tier_rank,a.cloud_state,a.blocked_reason,"+STORED+" AS server_stored"+roles+f.sql+") p"+boundary+" ORDER BY "+String.join(",",cols.stream().map(c->c.sql+(c.desc?" DESC":" ASC")).toList())+" LIMIT ?";args.add(maximum);
            var rows=jdbc.query(sql,(rs,n)->{
                var item=snapshot(rs);var values=new ArrayList<String>();switch(query.sort()){
                    case RECORDED_ASC,RECORDED_DESC -> values.add((String)item.get("recorded_at"));
                    case TITLE -> values.add(Objects.toString(item.get("title_snapshot"),""));
                    case TIER -> {values.add(Integer.toString(rs.getInt("tier_rank")));values.add((String)item.get("recorded_at"));}
                }
                return new KeysetPages.Entry<Map<String,Object>>(item,new PageCursor.Tuple(values,uuid(rs.getBytes("id"))));
            },args.toArray());
            if(!rows.isEmpty()){
                var byId=new HashMap<UUID,Map<String,Object>>();var tagArgs=new ArrayList<Object>();tagArgs.add(bytes(owner));for(var row:rows){byId.put(row.key().id(),row.item());tagArgs.add(bytes(row.key().id()));}
                jdbc.query("SELECT recording_id,tag_id FROM recording_tag WHERE user_id=? AND recording_id IN ("+String.join(",",Collections.nCopies(rows.size(),"?"))+") ORDER BY recording_id,tag_id",(org.springframework.jdbc.core.RowCallbackHandler)rs->{@SuppressWarnings("unchecked") var tags=(List<String>)byId.get(uuid(rs.getBytes(1))).get("tag_ids");tags.add(uuid(rs.getBytes(2)).toString());},tagArgs.toArray());
            }
            return rows;
        }
        @Override public Comparator<PageCursor.Tuple> order(){return RecordingListRules.tupleOrder(query);}
    }
    private static Map<String,Object> snapshot(ResultSet rs)throws SQLException{
        var m=new LinkedHashMap<String,Object>();m.put("id",uuid(rs.getBytes("id")).toString());var song=rs.getBytes("song_id");m.put("song_id",song==null?null:uuid(song).toString());m.put("revision",rs.getLong("revision"));
        for(String name:List.of("metadata_state","title_snapshot","artist_snapshot","key_mode","version_code","tier","condition_code","condition_name_snapshot","note","timezone_id","lifecycle_state"))m.put(name,rs.getString(name));
        m.put("key_shift",rs.getObject("key_shift"));m.put("timezone_offset_minutes",rs.getInt("timezone_offset_minutes"));for(String name:List.of("recorded_at","updated_at"))m.put(name,rs.getTimestamp(name).toLocalDateTime().toInstant(ZoneOffset.UTC).toString());
        m.put("tag_ids",new ArrayList<String>());var cloud=new LinkedHashMap<String,Object>();cloud.put("state",Objects.toString(rs.getString("cloud_state"),"NONE"));cloud.put("blocked_reason",rs.getString("blocked_reason"));cloud.put("stored",rs.getBoolean("server_stored"));
        var reasons=new ArrayList<String>();for(var pair:List.of(new String[]{"role_rep","REPRESENTATIVE"},new String[]{"role_latest","LATEST"},new String[]{"role_lowest","LOWEST_TIER"},new String[]{"role_pin","PINNED"}))if(rs.getBoolean(pair[0]))reasons.add(pair[1]);cloud.put("desired_reasons",reasons);m.put("cloud",cloud);return m;
    }
    private static LocalDateTime timestamp(String value){return LocalDateTime.ofInstant(Instant.parse(value),ZoneOffset.UTC);}
}
