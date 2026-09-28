package com.ksh321.songrecord.api.recordings;

import com.ksh321.songrecord.api.domain.DomainOrdering;
import com.ksh321.songrecord.api.domain.DomainTypes.*;
import com.ksh321.songrecord.api.pagination.*;
import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.util.MultiValueMap;
import tools.jackson.databind.json.JsonMapper;

/** P09-03a contract; the subsequent SQL adapter must filter before counting or paging. */
public final class RecordingListRules {
    public static final String VERSION="SR-RECORDING-LIST-1/"+DomainOrdering.SORT_KEY_VERSION+"/"+DomainOrdering.SORT_BYTES_VERSION;
    public enum Sort { RECORDED_DESC, RECORDED_ASC, TITLE, TIER }
    private static final JsonMapper JSON=new JsonMapper();
    private static final Set<String> PARAMS=Set.of("from","to","song_id","key_mode","key_shift","version_code","tier","condition_code","tag_ids","server_file","metadata_state","sort","limit","cursor");
    private RecordingListRules(){}
    public static final class Query {
        private final Map<String,String> filters;
        private final Sort sort;private final int limit;private final String cursor;
        private Query(Map<String,String> filters,Sort sort,int limit,String cursor){this.filters=Collections.unmodifiableMap(new TreeMap<>(filters));this.sort=sort;this.limit=limit;this.cursor=cursor;}
        public Map<String,String> filters(){return filters;}public Sort sort(){return sort;}public int limit(){return limit;}public String cursor(){return cursor;}
        public PageCursor.Query cursorQuery(){return new PageCursor.Query("recordings",sort.name(),VERSION,JSON.writeValueAsString(filters),limit);}
        public boolean includes(UUID owner,Row row){
            if(!owner.equals(row.owner) || row.lifecycle!=LifecycleState.ACTIVE)return false;
            for(var entry:filters.entrySet()){
                String value=entry.getValue();
                boolean matches=switch(entry.getKey()){
                    case "from" -> !row.recordedAt.isBefore(Instant.parse(value));
                    case "to" -> row.recordedAt.isBefore(Instant.parse(value));
                    case "song_id" -> value.equals("UNLINKED")?row.songId==null:row.songId!=null && row.songId.toString().equals(value);
                    case "key_mode" -> value.equals(row.keyMode);
                    case "key_shift" -> row.keyShift!=null && row.keyShift==Integer.parseInt(value);
                    case "version_code" -> value.equals(row.version);
                    case "tier" -> value.equals("NONE")?row.tier==null:row.tier!=null && row.tier.name().equals(value);
                    case "condition_code" -> value.equals("NONE")?row.condition==null:value.equals(row.condition);
                    case "tag_ids" -> Arrays.stream(value.split(",")).map(UUID::fromString).allMatch(row.tags::contains);
                    case "server_file" -> row.serverStored==value.equals("PRESENT");
                    case "metadata_state" -> row.metadata.name().equals(value);
                    default -> throw new IllegalStateException("Unknown recording filter");
                };
                if(!matches)return false;
            }
            return true;
        }
        @Override public String toString(){return "RecordingListQuery[REDACTED]";}
    }
    public static Query parse(MultiValueMap<String,String> params){
        var filters=new TreeMap<String,String>();Sort sort=Sort.RECORDED_DESC;int limit=50;String cursor=null;
        for(var entry:params.entrySet()){
            String name=entry.getKey();if(!PARAMS.contains(name) || entry.getValue()==null || entry.getValue().size()!=1)throw invalid();
            String value=entry.getValue().getFirst();if(value==null || value.isBlank())throw invalid();
            switch(name){
                case "sort" -> {try{sort=Sort.valueOf(value);}catch(IllegalArgumentException e){throw invalid();}}
                case "limit" -> {if(!value.matches("[0-9]{1,3}"))throw invalid();limit=PageCursor.pageSize(Integer.valueOf(value));}
                case "cursor" -> {if(value.length()>PageCursor.MAX_LENGTH)throw invalid();cursor=value;}
                case "from","to" -> filters.put(name,time(value).toString());
                case "song_id" -> filters.put(name,value.equals("UNLINKED")?value:uuid(value).toString());
                case "key_mode" -> filters.put(name,choice(value,Set.of("ORIGINAL","MALE","FEMALE")));
                case "key_shift" -> {if(!value.matches("-?(?:0|[1-9][0-9]?)"))throw invalid();int shift=Integer.parseInt(value);if(shift < -12 || shift>12)throw invalid();filters.put(name,Integer.toString(shift));}
                case "version_code" -> filters.put(name,choice(value,Set.of("NORMAL","MR","LIVE")));
                case "tier" -> {if(!value.equals("ALL"))filters.put(name,choice(value,Set.of("S","A","B","C","D","NONE")));}
                case "condition_code" -> {if(!value.equals("ALL"))filters.put(name,choice(value,Set.of("VERY_GOOD","GOOD","NORMAL","BAD","NONE")));}
                case "metadata_state" -> {if(!value.equals("ALL"))filters.put(name,choice(value,Set.of("DRAFT","SAVED")));}
                case "server_file" -> {if(!value.equals("ALL"))filters.put(name,choice(value,Set.of("PRESENT","ABSENT")));}
                case "tag_ids" -> {
                    var ids=value.split(",",-1);if(ids.length>20)throw invalid();var sorted=new TreeSet<String>();
                    for(String id:ids)sorted.add(uuid(id).toString());filters.put(name,String.join(",",sorted));
                }
                default -> throw invalid();
            }
        }
        if(filters.containsKey("from") && filters.containsKey("to") && !Instant.parse(filters.get("from")).isBefore(Instant.parse(filters.get("to"))))throw invalid();
        return new Query(filters,sort,limit,cursor);
    }
    /** Server presence is authoritative storage metadata; local-device availability is deliberately absent. */
    public record Row(UUID id,UUID owner,UUID songId,String title,Instant recordedAt,String keyMode,Integer keyShift,
                      String version,RecordingTier tier,String condition,Set<UUID> tags,MetadataState metadata,LifecycleState lifecycle,boolean serverStored){
        public Row{Objects.requireNonNull(id);Objects.requireNonNull(owner);Objects.requireNonNull(recordedAt);Objects.requireNonNull(version);Objects.requireNonNull(metadata);Objects.requireNonNull(lifecycle);tags=Set.copyOf(tags);}
    }
    public static int tierRank(RecordingTier tier){return tier==null?5:tier.ordinal();}
    public static PageCursor.Tuple tuple(Query query,Row row){
        var values=new ArrayList<String>();
        switch(query.sort){
            case RECORDED_DESC,RECORDED_ASC -> values.add(row.recordedAt.toString());
            case TITLE -> values.add(row.title==null?"":row.title);
            case TIER -> {values.add(Integer.toString(tierRank(row.tier)));values.add(row.recordedAt.toString());}
        }
        return new PageCursor.Tuple(values,row.id);
    }
    public static Comparator<Row> order(Query query){return (a,b)->tupleOrder(query).compare(tuple(query,a),tuple(query,b));}
    public static Comparator<PageCursor.Tuple> tupleOrder(Query query){return (a,b)->{
        int count=query.sort==Sort.TIER?2:1;if(a.values().size()!=count || b.values().size()!=count)throw PageCursor.invalid();
        try{
            int compared=switch(query.sort){
                case RECORDED_DESC -> Instant.parse(b.values().getFirst()).compareTo(Instant.parse(a.values().getFirst()));
                case RECORDED_ASC -> Instant.parse(a.values().getFirst()).compareTo(Instant.parse(b.values().getFirst()));
                case TITLE -> DomainOrdering.compareSortText(a.values().getFirst(),b.values().getFirst());
                case TIER -> {int rank=Integer.compare(rank(a.values().getFirst()),rank(b.values().getFirst()));yield rank!=0?rank:Instant.parse(b.values().get(1)).compareTo(Instant.parse(a.values().get(1)));}
            };
            return compared!=0?compared:KeysetPages.compareUuid(a.id(),b.id());
        }catch(IllegalArgumentException|NullPointerException|DateTimeException e){throw PageCursor.invalid();}
    };}
    private static int rank(String value){int rank=Integer.parseInt(value);if(rank<0 || rank>5)throw PageCursor.invalid();return rank;}
    private static String choice(String value,Set<String> choices){if(!choices.contains(value))throw invalid();return value;}
    private static UUID uuid(String value){try{var id=UUID.fromString(value);if(!id.toString().equals(value))throw invalid();return id;}catch(IllegalArgumentException e){throw invalid();}}
    private static Instant time(String value){
        if(!value.matches("\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:\\.\\d{1,3})?Z"))throw invalid();
        try{var date=OffsetDateTime.parse(value);if(date.getYear()<1000)throw invalid();return date.toInstant();}catch(DateTimeException e){throw invalid();}
    }
    private static ApiException invalid(){return new ApiException(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR","녹음 목록 조건을 확인해 주세요.",false,Map.of());}
}
