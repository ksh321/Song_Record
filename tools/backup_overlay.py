"""Closed-schema deletion replay SQL for a NEW disposable restore database only."""
import datetime as dt
import re
import uuid
from backup_ledger import valid, subject
from backup_store import BackupError

PERSONAL=set('account_deletion_challenge auth_identity auth_session change_log cloud_cleanup cloud_hold condition_definition deletion_batch_work deletion_item export_session mutation_receipt pin_slot playlist_item recording_asset recording_condition_history recording_file_spec recording_query_key recording_tag recording_time_correction recording_upload song_cloud_selection song_query_key song_source storage_request_body storage_request_operation storage_usage upload_approval_daily upload_url_issue deletion_batch playlist recording snapshot_header storage_request_ledger tag user_entitlement user_sync_state device song'.split())
CONTROL={'deletion_ledger','job','account_deletion_status','operational_backup_fence'}


def require_database(name):
    if not re.fullmatch(r'song_record_restore_[0-9a-f]{32}',name):
        raise BackupError('RESTORE_TARGET_SCOPE')


def binary(value):
    value=str(uuid.UUID(value))
    if uuid.UUID(value).int==0:raise BackupError('RESTORE_SUBJECT_INVALID')
    return "UNHEX('"+value.replace('-','')+"')"


def order(tables):
    dependencies={}
    for table,row in tables.items():
        if 'user_id' not in row['columns'] or table in CONTROL:continue
        if table not in PERSONAL:raise BackupError('UNREVIEWED_RESTORE_TABLE')
        dependencies[table]=set(row['parents'])
    if 'song' in dependencies:dependencies['song'].discard('recording')
    result=[]
    while dependencies:
        leaves=[name for name in sorted(dependencies) if not any(name in parents for other,parents in dependencies.items() if other!=name)]
        if not leaves:raise BackupError('RESTORE_FOREIGN_KEY_CYCLE')
        for leaf in leaves:result.append(leaf);del dependencies[leaf]
    return result


def statements(database, tables, entries):
    require_database(database)
    sequence=order(tables)
    rows=[valid(row) for row in entries if row.get('state')!='CANCELLED']
    sql=['START TRANSACTION;']
    def present(table):return table in tables
    def columns(table):return set(tables.get(table,{}).get('columns',[]))
    def add(table,text):
        if present(table):sql.append(text)
    if present('operations_observation') and not {'actor_id','target_id','previous_target_id','job_id'}<=columns('operations_observation'):
        raise BackupError('RESTORE_OBSERVATION_SCHEMA_UNCONFIRMED')
    observation_owners=set()
    def clear_observation_actor(user):
        if not {'actor_id','target_id','previous_target_id','job_id'}<=columns('operations_observation'):return
        jobs=f' OR job_id IN (SELECT id FROM job WHERE user_id={user})' if {'id','user_id'}<=columns('job') else ''
        sql.append(f'DELETE FROM operations_observation WHERE actor_id={user}'+jobs+';')
    def clear_observation_targets(user):
        if not {'target_id','previous_target_id'}<=columns('operations_observation'):return
        reviewed=PERSONAL|CONTROL
        selections=[f'SELECT id FROM `{table}` WHERE user_id={user}' for table in sorted(reviewed) if {'id','user_id'}<=columns(table)]
        for column in ('target_id','previous_target_id'):
            linked=f' OR {column} IN ('+' UNION ALL '.join(selections)+')' if selections else ''
            sql.append(f'UPDATE operations_observation SET {column}=NULL WHERE {column}={user}'+linked+';')
    for row in rows:
        owner,kind,entity,generation=subject(row)
        user,target=binary(owner),binary(entity)
        def clear_pin_target(extra=''):
            if not {'current_recording_id','pending_recording_id'}<=columns('pin_slot'):return
            sql.append(f'UPDATE pin_slot SET current_recording_id=NULL WHERE user_id={user} AND current_recording_id={target} AND pending_recording_id IS NOT NULL AND pending_recording_id<>{target}'+extra+';')
            sql.append(f'UPDATE pin_slot SET pending_recording_id=NULL WHERE user_id={user} AND pending_recording_id={target} AND current_recording_id IS NOT NULL AND current_recording_id<>{target}'+extra+';')
            sql.append(f'DELETE FROM pin_slot WHERE user_id={user} AND (current_recording_id={target} OR pending_recording_id={target})'+extra+';')
        if kind=='USER':
            observation_owners.add(user)
            clear_observation_actor(user);clear_observation_targets(user)
            add('song',f'UPDATE song SET representative_recording_id=NULL WHERE user_id={user};')
            for table in sequence:sql.append(f'DELETE FROM `{table}` WHERE user_id={user};')
            add('app_user',f'DELETE FROM app_user WHERE id={user};')
        elif kind=='RECORDING':
            add('song',f'UPDATE song SET representative_recording_id=NULL WHERE user_id={user} AND representative_recording_id={target};')
            clear_pin_target()
            for table in ('song_cloud_selection',):
                refs=columns(table)&{'current_recording_id','pending_recording_id','representative_id','latest_id','lowest_tier_id'}
                if refs:add(table,f"DELETE FROM `{table}` WHERE user_id={user} AND ("+' OR '.join(f'`{name}`={target}' for name in sorted(refs))+');')
            for table in sequence:
                if 'recording_id' in columns(table):sql.append(f'DELETE FROM `{table}` WHERE user_id={user} AND recording_id={target};')
            add('recording',f'DELETE FROM recording WHERE user_id={user} AND id={target};')
        elif kind=='RECORDING_ASSET':
            gen=binary(generation)
            extra=f' AND EXISTS(SELECT 1 FROM recording_asset a WHERE a.user_id={user} AND a.recording_id={target} AND a.generation={gen})'
            clear_pin_target(extra)
            # Identity is generation-bound: a newer copy of the same recording remains intact.
            add('recording_asset',f"UPDATE recording_asset SET cloud_state='NONE',blocked_reason=NULL,object_key=NULL,generation=NULL,verified_size=NULL,sha256=NULL,stored_at=NULL,cloud_revision=cloud_revision+1 WHERE user_id={user} AND recording_id={target} AND generation={gen};")
        elif kind=='SONG':
            if present('recording') and present('song'):
                sql.append(f'UPDATE recording r JOIN song s ON s.id=r.song_id AND s.user_id=r.user_id SET r.title_snapshot=COALESCE(r.title_snapshot,s.title),r.artist_snapshot=COALESCE(r.artist_snapshot,s.artist),r.song_id=NULL WHERE r.user_id={user} AND r.song_id={target};')
            for table in sequence:
                if table!='recording' and 'song_id' in columns(table):sql.append(f'DELETE FROM `{table}` WHERE user_id={user} AND song_id={target};')
            add('song',f'DELETE FROM song WHERE user_id={user} AND id={target};')
        else:
            table={'PLAYLIST':'playlist','PLAYLIST_ITEM':'playlist_item','TAG':'tag','CONDITION':'condition_definition'}[kind]
            if kind=='PLAYLIST':add('playlist_item',f'DELETE FROM playlist_item WHERE user_id={user} AND playlist_id={target};')
            if kind=='TAG':add('recording_tag',f'DELETE FROM recording_tag WHERE user_id={user} AND tag_id={target};')
            if kind in ('TAG','CONDITION') and 'deleted_at' in columns(table):
                stamp=dt.datetime.fromisoformat(row['at']).astimezone(dt.timezone.utc).strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]
                add(table,f"UPDATE `{table}` SET deleted_at=COALESCE(deleted_at,'{stamp}') WHERE user_id={user} AND id={target};")
            else:add(table,f'DELETE FROM `{table}` WHERE user_id={user} AND id={target};')
        # Confirmed external tombstones are added to the restored server's own permanent ledger.
        if row['state']=='COMMITTED' and present('deletion_ledger'):
            stamp=dt.datetime.fromisoformat(row['at']).astimezone(dt.timezone.utc).strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]
            gen='NULL' if generation is None else binary(generation)
            identity='object_generation IS NULL' if generation is None else 'object_generation='+gen
            sql.append(f"INSERT INTO deletion_ledger(id,user_id,entity_type,entity_id,object_generation,revision,purged_at) SELECT {binary(str(uuid.uuid4()))},{user},'{kind}',{target},{gen},{row['revision']},'{stamp}' WHERE NOT EXISTS(SELECT 1 FROM deletion_ledger WHERE user_id={user} AND entity_type='{kind}' AND entity_id={target} AND {identity});")
    # Replay inserts can emit new audit rows through the permanent-ledger trigger.
    for user in sorted(observation_owners):clear_observation_actor(user)
    # Restored counters reflect actual remaining assets, never the deleted copy's old byte count.
    if present('recording_asset'):
        add('storage_usage',"UPDATE storage_usage s SET used_bytes=(SELECT COALESCE(SUM(a.verified_size),0) FROM recording_asset a WHERE a.user_id=s.user_id AND a.cloud_state IN ('STORED','DELETING')),revision=revision+1;")
        reserved=",reserved_bytes=(SELECT COALESCE(SUM(reserved_bytes),0) FROM storage_usage)" if present('storage_usage') else ''
        add('global_storage_usage',"UPDATE global_storage_usage SET used_bytes=(SELECT COALESCE(SUM(verified_size),0) FROM recording_asset WHERE cloud_state IN ('STORED','DELETING'))"+reserved+",revision=revision+1 WHERE id=1;")
    sql.append('COMMIT;')
    return '\n'.join(sql).encode()
