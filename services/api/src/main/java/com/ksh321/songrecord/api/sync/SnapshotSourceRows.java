package com.ksh321.songrecord.api.sync;

import java.nio.ByteBuffer;
import java.sql.*;
import java.time.*;
import java.util.*;
import java.util.function.Consumer;
import tools.jackson.databind.json.JsonMapper;

/** Explicit personal-metadata allowlist. Never selects auth, audio bytes or object-store keys. */
public final class SnapshotSourceRows {
    private record Source(String table,String key,String order,String columns,Set<String> json) {}
    private static Source source(String table,String key,String order,String columns,String... json) {
        return new Source(table,key,order,columns,Set.of(json));
    }
    private static final Map<SnapshotPages.Entity,Source> SOURCES=Map.ofEntries(
        Map.entry(SnapshotPages.Entity.SONG,source("song","id","id","id,user_id,source_type,tj_number,title,artist,version_code,note,representative_key_mode,representative_key_shift,song_tier AS tier,representative_recording_id,lifecycle_state,deleted_at,revision,created_at,updated_at")),
        Map.entry(SnapshotPages.Entity.SONG_SOURCE,source("song_source","song_id","song_id","song_id,user_id,provider,source_title,source_artist,source_ref,verified_at,created_at")),
        Map.entry(SnapshotPages.Entity.RECORDING,source("recording","id","id","id,user_id,origin_device_id,song_id,title_snapshot,artist_snapshot,version_code,key_mode,key_shift,tier,note,recorded_at,timezone_id,timezone_offset_minutes,metadata_state,lifecycle_state,revision,link_revision,deleted_at,delete_batch_id,created_at,updated_at,condition_code,condition_name_snapshot")),
        Map.entry(SnapshotPages.Entity.RECORDING_FILE_SPEC,source("recording_file_spec","recording_id","recording_id","recording_id,user_id,sha256,size_bytes,duration_ms,codec,sample_rate,channels,capture_integrity,created_at")),
        Map.entry(SnapshotPages.Entity.RECORDING_ASSET,source("recording_asset","recording_id","recording_id","recording_id,user_id,cloud_state,blocked_reason,generation,verified_size,sha256,stored_at,cloud_revision,created_at,updated_at")),
        Map.entry(SnapshotPages.Entity.PLAYLIST,source("playlist","id","id","id,user_id,name,revision,deleted_at,created_at,updated_at")),
        Map.entry(SnapshotPages.Entity.PLAYLIST_ITEM,source("playlist_item","id","id","id,user_id,playlist_id,song_id,candidate_brand,candidate_number,candidate_snapshot,entry_key,position,hidden_by_batch_id,created_at,updated_at","candidate_snapshot")),
        Map.entry(SnapshotPages.Entity.TAG,source("tag","id","id","id,user_id,name,archived_at,revision,created_at,updated_at")),
        Map.entry(SnapshotPages.Entity.RECORDING_TAG,source("recording_tag","recording_id","recording_id,tag_id","user_id,recording_id,tag_id,name_snapshot,created_at")),
        Map.entry(SnapshotPages.Entity.RECORDING_CONDITION,source("condition_definition","id","id","id,user_id,code,name,archived_at,revision,created_at,updated_at")),
        Map.entry(SnapshotPages.Entity.USER_ENTITLEMENT,source("user_entitlement","user_id","user_id","user_id,plan_code,pinned_limit,quota_bytes,revision,created_at,updated_at")),
        Map.entry(SnapshotPages.Entity.STORAGE_USAGE,source("storage_usage","user_id","user_id","user_id,used_bytes,reserved_bytes,revision,updated_at")),
        Map.entry(SnapshotPages.Entity.SONG_CLOUD_SELECTION,source("song_cloud_selection","song_id","song_id","song_id,user_id,representative_id,latest_id,lowest_tier_id,selection_revision,updated_at")),
        Map.entry(SnapshotPages.Entity.PIN_SLOT,source("pin_slot","user_id","slot_no","user_id,slot_no,current_recording_id,pending_recording_id,revision,operation_id,requested_at,updated_at")),
        Map.entry(SnapshotPages.Entity.USER_SYNC_STATE,source("user_sync_state","user_id","user_id","user_id,last_change_seq,retained_from_seq,updated_at")),
        Map.entry(SnapshotPages.Entity.CHANGE_LOG,source("change_log","entity_id","change_seq","user_id,change_seq,entity_type,entity_id,revision,operation,payload,created_at,expires_at","payload")),
        Map.entry(SnapshotPages.Entity.DELETION_BATCH,source("deletion_batch","id","id","id,user_id,op_id,mode,deleted_at,purge_after")),
        Map.entry(SnapshotPages.Entity.DELETION_ITEM,source("deletion_item","entity_id","batch_id,entity_type,entity_id","batch_id,user_id,entity_type,entity_id,previous_song_id,previous_list_id,detached_link_revision,original_deleted_at,created_at")),
        Map.entry(SnapshotPages.Entity.DELETION_LEDGER,source("deletion_ledger","id","id","id,user_id,entity_type,entity_id,object_generation,revision,purged_at"))
    );
    private final Clock clock;
    private final JsonMapper json=new JsonMapper();
    public SnapshotSourceRows(Clock clock){this.clock=Objects.requireNonNull(clock);}

    /** Called only inside SnapshotReadView. Consumer persists each batch on a separate connection. */
    public Map<SnapshotPages.Entity,Long> extract(Connection connection,UUID owner,Instant deadline,
                                                Consumer<List<SnapshotBuildStore.Entry>> consume) throws SQLException {
        Objects.requireNonNull(consume);Objects.requireNonNull(owner);Objects.requireNonNull(deadline);
        if(!SOURCES.keySet().equals(EnumSet.allOf(SnapshotPages.Entity.class)))throw new IllegalStateException("Incomplete snapshot source contract");
        var counts=new EnumMap<SnapshotPages.Entity,Long>(SnapshotPages.Entity.class);
        for(var entity:SnapshotPages.Entity.values()) {
            var source=SOURCES.get(entity);
            // Identifiers come solely from the static allowlist; owner is bound.
            try(var query=connection.prepareStatement("SELECT "+source.columns+" FROM "+source.table+" WHERE user_id=? ORDER BY "+source.order)) {
                query.setBytes(1,bytes(owner));query.setQueryTimeout(remaining(deadline));
                // Connector/J streaming prevents buffering an entire account in memory.
                if(connection.getMetaData().getDatabaseProductName().equals("MySQL"))query.setFetchSize(Integer.MIN_VALUE);
                long ordinal=0;var batch=new ArrayList<SnapshotBuildStore.Entry>(100);
                try(var rows=query.executeQuery()) {
                    var metadata=rows.getMetaData();
                    while(rows.next()) {
                        remaining(deadline);
                        var payload=new LinkedHashMap<String,Object>();
                        for(int i=1;i<=metadata.getColumnCount();i++) {
                            String column=metadata.getColumnLabel(i);Object value=rows.getObject(i);
                            if(value instanceof byte[] raw)value=uuid(raw).toString();
                            else if(value instanceof Timestamp time)value=time.toLocalDateTime().toInstant(ZoneOffset.UTC).toString();
                            else if(value instanceof LocalDateTime time)value=time.toInstant(ZoneOffset.UTC).toString();
                            if(value!=null&&source.json.contains(column))value=json.readTree(rows.getString(i));
                            payload.put(column,value);
                        }
                        if(!owner.toString().equals(payload.get("user_id")))throw new IllegalStateException("Snapshot source owner mismatch");
                        UUID resource=UUID.fromString((String)payload.get(source.key));
                        batch.add(new SnapshotBuildStore.Entry(entity,++ordinal,resource,json.writeValueAsString(payload)));
                        if(batch.size()==100){consume.accept(List.copyOf(batch));batch.clear();}
                    }
                }
                if(!batch.isEmpty())consume.accept(List.copyOf(batch));
                counts.put(entity,ordinal);
            }
        }
        if(counts.get(SnapshotPages.Entity.USER_SYNC_STATE)!=1)throw new IllegalStateException("Incomplete account baseline");
        remaining(deadline);
        return Collections.unmodifiableMap(counts);
    }
    private int remaining(Instant deadline) {
        long millis=Duration.between(clock.instant(),deadline).toMillis();
        if(millis<=0)throw new IllegalStateException("Snapshot extraction deadline exceeded");
        return (int)Math.min(600,Math.max(1,(millis+999)/1000));
    }
    private static byte[] bytes(UUID id){return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();}
    private static UUID uuid(byte[] bytes){if(bytes.length!=16)throw new IllegalStateException("Unexpected binary snapshot field");var b=ByteBuffer.wrap(bytes);return new UUID(b.getLong(),b.getLong());}
}
