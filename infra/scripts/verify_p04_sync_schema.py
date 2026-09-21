"""P04-06 MySQL tests. Disposable databases only; no production data or object I/O.

--seed-upgrade runs at V5; normal execution runs immediately after V6. Concurrency
tests exercise SQL transaction protocols for P07, not implemented API/worker code.
"""
import os
import sys
from concurrent.futures import ThreadPoolExecutor

from verify_p04_extended_schema import query, uid
from verify_p04_retention_schema import wait_for_lock


checks = 0
U, OTHER, DEVICE = map(uid, (8001, 8002, 8003))
SONG, OTHER_SONG, REC, LIST, ITEM = map(uid, (8010, 8011, 8020, 8030, 8031))
BATCH, OTHER_BATCH = map(uid, (8040, 8041))


def value(label, sql, expected):
    global checks
    actual = query(sql)
    assert actual == expected, (label, expected, actual)
    checks += 1
    print('PASS value:', label, flush=True)


def reject(label, sql, code=3819):
    global checks
    query(sql, code)
    checks += 1
    print('PASS reject:', label, flush=True)


def recording(identifier, song=SONG):
    return ("INSERT INTO recording(id,user_id,origin_device_id,song_id,note,recorded_at,timezone_id,timezone_offset_minutes) "
            f"VALUES({uid(identifier)},{U},{DEVICE},{song},'keep',UTC_TIMESTAMP(3),'UTC',0)")


def batch(identifier, user=U, **extra):
    row = dict(id=uid(identifier), user_id=user, op_id=uid(identifier+100), mode="'SONG_ONLY'", preview_version="'preview-1'")
    row.update(extra)
    return f"INSERT INTO deletion_batch({','.join(row)}) VALUES({','.join(row.values())})"


def change(seq, user=U, **extra):
    row = dict(user_id=user, change_seq=str(seq), entity_type="'SONG'", entity_id=SONG, revision='1',
               operation="'UPSERT'", payload="JSON_OBJECT('title','changed')")
    row.update(extra)
    return f"INSERT INTO change_log({','.join(row)}) VALUES({','.join(row.values())})"


def receipt(op, user=U, **extra):
    row = dict(user_id=user, op_id=uid(op), request_hash="REPEAT('a',64)", response_status='201', response_body="JSON_OBJECT('ok',true)")
    row.update(extra)
    return f"INSERT INTO mutation_receipt({','.join(row)}) VALUES({','.join(row.values())})"


def job(identifier, **extra):
    row = dict(id=uid(identifier), user_id=U, type="'PURGE_RECORDING'", aggregate_id=REC,
               dedupe_key=f"'p0406/user/8001/purge/{identifier}'", payload="JSON_OBJECT('recording_id','test')")
    row.update(extra)
    return f"INSERT INTO job({','.join(row)}) VALUES({','.join(row.values())})"


def ledger(identifier, **extra):
    row = dict(id=uid(identifier), user_id=U, entity_type="'RECORDING'", entity_id=REC, revision='2')
    row.update(extra)
    return f"INSERT INTO deletion_ledger({','.join(row)}) VALUES({','.join(row.values())})"


def seed_upgrade():
    value('upgrade fixture starts at V5', "SELECT schema_value FROM app_schema_metadata WHERE schema_key='schema_contract'", '5')
    query("INSERT INTO app_schema_metadata(schema_key,schema_value) "
          "SELECT 'p04_06_usage_before',CONCAT(used_bytes,':',reserved_bytes,':',temp_observed_bytes,':',upload_locked) "
          "FROM global_storage_usage WHERE id=1")
    # Existing V5 users and data must survive unchanged. A simple sentinel is not a mock DB.
    query(f'INSERT INTO app_user(id) VALUES({uid(7901)})')
    query(f"INSERT INTO device(id,user_id,display_name,last_seen_at) VALUES({uid(7902)},{uid(7901)},'upgrade',UTC_TIMESTAMP(3))")
    query(f"INSERT INTO recording(id,user_id,origin_device_id,note,recorded_at,timezone_id,timezone_offset_minutes,lifecycle_state,deleted_at) "
          f"VALUES({uid(7903)},{uid(7901)},{uid(7902)},'preserve-v5',UTC_TIMESTAMP(3),'UTC',0,'TRASHED',UTC_TIMESTAMP(3))")
    print('P04-06 V5 upgrade fixtures inserted.', flush=True)


def main():
    value('schema contract', "SELECT schema_value FROM app_schema_metadata WHERE schema_key='schema_contract'", '6')
    value('all existing users get a zero cursor',
          'SELECT (SELECT COUNT(*) FROM app_user)=(SELECT COUNT(*) FROM user_sync_state WHERE last_change_seq=0 AND retained_from_seq=1)', '1')
    if query("SELECT COUNT(*) FROM app_schema_metadata WHERE schema_key='p04_06_usage_before'") == '1':
        value('upgrade leaves global storage counters unchanged',
              "SELECT CONCAT(used_bytes,':',reserved_bytes,':',temp_observed_bytes,':',upload_locked)="
              "(SELECT schema_value FROM app_schema_metadata WHERE schema_key='p04_06_usage_before') FROM global_storage_usage WHERE id=1", '1')
        value('upgrade preserves legacy trash with no invented batch',
              f'SELECT note,lifecycle_state,delete_batch_id IS NULL FROM recording WHERE id={uid(7903)}', 'preserve-v5\tTRASHED\t1')

    query(f'INSERT INTO app_user(id) VALUES({U}),({OTHER})')
    query(f'INSERT INTO user_sync_state(user_id) VALUES({U}),({OTHER})')
    query(f"INSERT INTO device(id,user_id,display_name,last_seen_at) VALUES({DEVICE},{U},'sync',UTC_TIMESTAMP(3))")
    query(f"INSERT INTO song(id,user_id,source_type,title,artist,note) VALUES({SONG},{U},'MANUAL','sync','artist',''),"
          f"({OTHER_SONG},{OTHER},'MANUAL','other','artist','')")
    query(recording(8020))
    query(f"INSERT INTO playlist(id,user_id,name) VALUES({LIST},{U},'history')")
    query(f"INSERT INTO playlist_item(id,user_id,playlist_id,song_id,position) VALUES({ITEM},{U},{LIST},{SONG},1)")
    reject('sync owner must exist', f'INSERT INTO user_sync_state(user_id) VALUES({uid(8999)})', 1452)
    reject('sync state is one row per user', f'INSERT INTO user_sync_state(user_id) VALUES({U})', 1062)
    reject('sync sequence cannot be negative', f'UPDATE user_sync_state SET last_change_seq=-1 WHERE user_id={U}', 1644)
    reject('retention floor cannot skip unpublished changes', f'UPDATE user_sync_state SET retained_from_seq=2 WHERE user_id={U}')
    reject('retention floor positive', f'UPDATE user_sync_state SET retained_from_seq=0 WHERE user_id={U}', 1644)
    reject('sync owner cannot be changed', f'UPDATE user_sync_state SET user_id={uid(8999)} WHERE user_id={U}', 1644)

    # Each writer locks the same counter until its change row commits.
    transaction = (f'START TRANSACTION; SELECT last_change_seq FROM user_sync_state WHERE user_id={U} FOR UPDATE; '
                   f'UPDATE user_sync_state SET last_change_seq=last_change_seq+1 WHERE user_id={U}; '
                   "INSERT INTO change_log(user_id,change_seq,entity_type,entity_id,revision,operation,payload) "
                   f"SELECT user_id,last_change_seq,'SONG',{SONG},last_change_seq,'UPSERT',JSON_OBJECT() "
                   f'FROM user_sync_state WHERE user_id={U}; ')
    with ThreadPoolExecutor(max_workers=2) as pool:
        first = pool.submit(query, transaction + "SELECT GET_LOCK('p0406_seq',0); SELECT SLEEP(3); COMMIT;")
        wait_for_lock('p0406_seq')
        second = pool.submit(query, transaction + 'COMMIT;')
        first.result()
        second.result()
    value('two locked writers commit consecutive sequences', f'SELECT GROUP_CONCAT(change_seq ORDER BY change_seq) FROM change_log WHERE user_id={U}', '1,2')
    value('counter includes both committed changes', f'SELECT last_change_seq FROM user_sync_state WHERE user_id={U}', '2')
    reject('duplicate sequence within user', change(1), 1062)
    query(change(1, user=OTHER, entity_id=OTHER_SONG))
    value('different users may share sequence number', 'SELECT COUNT(*) FROM change_log WHERE change_seq=1', '2')
    reject('change owner requires sync state', change(3, user=uid(8999)), 1452)
    reject('sequence positive', change(0))
    reject('revision positive', change(3, revision='0'))
    reject('unsupported change operation', change(3, operation="'EXECUTE_SQL'"))
    reject('change payload must be object', change(3, payload='JSON_ARRAY()'))
    reject('change namespace is explicit', change(3, entity_type="'song'"))
    reject('change expiry exactly 90 days', change(3, expires_at='UTC_TIMESTAMP(3)+INTERVAL 91 DAY'))
    reject('change history cannot be rewritten', f"UPDATE change_log SET payload=JSON_OBJECT('tampered',true) WHERE user_id={U} AND change_seq=1", 1644)
    value('default change lifetime', f'SELECT TIMESTAMPDIFF(DAY,created_at,expires_at) FROM change_log WHERE user_id={U} AND change_seq=1', '90')
    reject('counter cannot move backwards', f'UPDATE user_sync_state SET last_change_seq=1 WHERE user_id={U}', 1644)

    query(receipt(8050))
    reject('duplicate mutation op ID same account', receipt(8050), 1062)
    reject('changed request cannot replace existing receipt', receipt(8050, request_hash="REPEAT('b',64)"), 1062)
    query(receipt(8050, user=OTHER))
    value('operation ID is account scoped', f'SELECT COUNT(*) FROM mutation_receipt WHERE op_id={uid(8050)}', '2')
    reject('receipt hash format', receipt(8051, request_hash="'bad'"))
    reject('receipt status is final HTTP status', receipt(8051, response_status='199'))
    reject('204 response has no body', receipt(8051, response_status='204'))
    query(receipt(8051, response_status='204', response_body='NULL'))
    reject('receipt owner exists', receipt(8052, user=uid(8999)), 1452)
    reject('receipt expiry exactly 90 days', receipt(8052, expires_at='UTC_TIMESTAMP(3)+INTERVAL 89 DAY'))
    reject('receipt retry cannot extend lifetime', f'UPDATE mutation_receipt SET expires_at=expires_at+INTERVAL 1 DAY WHERE user_id={U} AND op_id={uid(8050)}', 1644)
    value('receipt preserves original status and response', f"SELECT response_status,JSON_EXTRACT(response_body,'$.ok') FROM mutation_receipt WHERE user_id={U} AND op_id={uid(8050)}", '201\ttrue')

    query(batch(8040))
    query(batch(8041, user=OTHER))
    reject('duplicate batch for same operation', batch(8042, op_id=uid(8140)), 1062)
    reject('playlist permanent delete is not seven day trash', batch(8042, mode="'PLAYLIST'"))
    reject('batch expiry exactly seven days', batch(8042, purge_after='UTC_TIMESTAMP(3)+INTERVAL 8 DAY'))
    reject('preview required', batch(8042, preview_version="''"))
    reject('batch owner exists', batch(8042, user=uid(8999)), 1452)
    reject('retry cannot postpone purge', f'UPDATE deletion_batch SET purge_after=purge_after+INTERVAL 1 DAY WHERE id={BATCH}', 1644)
    value('batch lifetime', f'SELECT TIMESTAMPDIFF(DAY,deleted_at,purge_after) FROM deletion_batch WHERE id={BATCH}', '7')
    reject('recording cannot use another owner batch', f'UPDATE recording SET delete_batch_id={OTHER_BATCH} WHERE id={REC}', 1452)
    reject('playlist hidden batch owner isolation', f'UPDATE playlist_item SET hidden_by_batch_id={OTHER_BATCH} WHERE id={ITEM}', 1452)
    reject('nonexistent batch rejected', f'UPDATE recording SET delete_batch_id={uid(8999)} WHERE id={REC}', 1452)
    query(f'UPDATE recording SET delete_batch_id={BATCH} WHERE id={REC}')
    query(f'UPDATE playlist_item SET hidden_by_batch_id={BATCH} WHERE id={ITEM}')
    item = f"INSERT INTO deletion_item(batch_id,user_id,entity_type,entity_id,previous_song_id,detached_link_revision) VALUES({BATCH},{U},'RECORDING',{REC},{SONG},2)"
    query(item)
    reject('deletion item cannot duplicate', item, 1062)
    reject('deletion snapshot owner isolation', f"INSERT INTO deletion_item(batch_id,user_id,entity_type,entity_id) VALUES({BATCH},{U},'SONG',{OTHER_SONG})", 1644)
    reject('item batch owner isolation', f"INSERT INTO deletion_item(batch_id,user_id,entity_type,entity_id) VALUES({OTHER_BATCH},{U},'SONG',{SONG})", 1452)
    query(recording(8021))
    reject('cannot fabricate previous song link', f"INSERT INTO deletion_item(batch_id,user_id,entity_type,entity_id,previous_song_id) VALUES({BATCH},{U},'RECORDING',{uid(8021)},{OTHER_SONG})", 1644)
    reject('detachment revision positive', f"INSERT INTO deletion_item(batch_id,user_id,entity_type,entity_id,previous_song_id,detached_link_revision) VALUES({BATCH},{U},'RECORDING',{uid(8021)},{SONG},0)")
    reject('cannot fabricate previous playlist', f"INSERT INTO deletion_item(batch_id,user_id,entity_type,entity_id,previous_song_id,previous_list_id) VALUES({BATCH},{U},'PLAYLIST_ITEM',{ITEM},{SONG},{uid(8999)})", 1644)
    query(f"INSERT INTO deletion_item(batch_id,user_id,entity_type,entity_id,previous_song_id,previous_list_id) VALUES({BATCH},{U},'PLAYLIST_ITEM',{ITEM},{SONG},{LIST})")
    query(f"UPDATE song SET lifecycle_state='TRASHED',deleted_at='2026-01-01 00:00:00' WHERE id={SONG}")
    query(f"INSERT INTO deletion_item(batch_id,user_id,entity_type,entity_id,original_deleted_at) VALUES({BATCH},{U},'SONG',{SONG},UTC_TIMESTAMP(3))")
    value('original deletion time comes from actual entity', f"SELECT original_deleted_at FROM deletion_item WHERE batch_id={BATCH} AND entity_type='SONG'", '2026-01-01 00:00:00.000')
    reject('restore history cannot be rewritten', f'UPDATE deletion_item SET previous_song_id=NULL WHERE batch_id={BATCH}', 1644)
    query(f'DELETE FROM recording WHERE id={REC}')
    value('deletion snapshot survives target removal', f"SELECT COUNT(*) FROM deletion_item WHERE batch_id={BATCH} AND entity_type='RECORDING'", '1')
    query(f'DELETE FROM playlist_item WHERE id={ITEM}')
    query(f'DELETE FROM playlist WHERE id={LIST}')
    value('previous playlist ID survives removal', f"SELECT previous_list_id={LIST} FROM deletion_item WHERE batch_id={BATCH} AND entity_type='PLAYLIST_ITEM'", '1')

    query(ledger(8060))
    reject('NULL generation cannot duplicate entity tombstone', ledger(8061), 1062)
    query(ledger(8062, entity_type="'RECORDING_ASSET'", object_generation=uid(90001)))
    query(ledger(8063, entity_type="'RECORDING_ASSET'", object_generation=uid(90002)))
    reject('same asset generation cannot be logged twice', ledger(8064, entity_type="'RECORDING_ASSET'", object_generation=uid(90001)), 1062)
    reject('asset ledger requires generation', ledger(8065, entity_type="'RECORDING_ASSET'"))
    reject('entity ledger must not include generation', ledger(8066, object_generation=uid(90003)))
    reject('zero generation reserved for entity marker', ledger(8067, entity_type="'RECORDING_ASSET'", object_generation=uid(0)))
    reject('unknown deletion kind', ledger(8068, entity_type="'UNKNOWN'"))
    reject('user tombstone must identify same account', ledger(8069, entity_type="'USER'"))
    reject('ledger revision positive', ledger(8070, entity_id=uid(99999), revision='0'))
    reject('deletion time cannot be rewritten', f'UPDATE deletion_ledger SET purged_at=UTC_TIMESTAMP(3) WHERE id={uid(8060)}', 1644)
    value('entity tombstone and two file generations stay distinct', f'SELECT COUNT(*) FROM deletion_ledger WHERE user_id={U} AND entity_id={REC}', '3')
    query(f'INSERT INTO app_user(id) VALUES({uid(8071)})')
    query(ledger(8072, user_id=uid(8071), entity_type="'USER'", entity_id=uid(8071)))
    query(job(8073, user_id=uid(8071), type="'DELETE_ACCOUNT'", aggregate_id=uid(8071)))
    query(f'DELETE FROM app_user WHERE id={uid(8071)}')
    value('ledger survives physical account removal', f'SELECT COUNT(*) FROM deletion_ledger WHERE user_id={uid(8071)}', '1')
    value('account cleanup job can continue after account removal', f'SELECT COUNT(*) FROM job WHERE user_id={uid(8071)}', '1')
    query(f'DELETE FROM change_log WHERE user_id={U}; DELETE FROM mutation_receipt WHERE user_id={U}')
    query(f'UPDATE user_sync_state SET retained_from_seq=3 WHERE user_id={U}')
    value('pruned log does not remove tombstones', f'SELECT COUNT(*) FROM deletion_ledger WHERE user_id={U}', '3')
    reject('retention floor cannot rewind', f'UPDATE user_sync_state SET retained_from_seq=1 WHERE user_id={U}', 1644)

    query(job(8080))
    reject('job dedupe is unique', job(8081, dedupe_key="'p0406/user/8001/purge/8080'"), 1062)
    reject('empty dedupe key', job(8081, dedupe_key="''"))
    reject('job payload object', job(8081, payload='JSON_ARRAY()'))
    reject('job type namespace', job(8081, type="'bad type'"))
    reject('job state enumeration', job(8081, state="'DISAPPEARED'"))
    reject('negative attempts', job(8081, attempt_count='-1'))
    reject('job revision positive', job(8081, revision='0'))
    reject('RUNNING requires lease', f"UPDATE job SET state='RUNNING' WHERE id={uid(8080)}")
    reject('partial lease rejected', f"UPDATE job SET lease_token={uid(9090)} WHERE id={uid(8080)}")
    reject('completion requires timestamp', f"UPDATE job SET state='SUCCEEDED' WHERE id={uid(8080)}")
    reject('job payload cannot be repurposed', f"UPDATE job SET payload=JSON_OBJECT('different',true) WHERE id={uid(8080)}", 1644)
    query(job(8081, user_id='NULL', type="'BACKUP_RECONCILE'"))
    value('global maintenance supports no account', f'SELECT user_id IS NULL FROM job WHERE id={uid(8081)}', '1')

    for i in (8090, 8091):
        query(job(i, type="'TEST_CLAIM'"))
    def claim(token):
        return ("START TRANSACTION; SET @claimed=NULL; SELECT id INTO @claimed FROM job "
                "WHERE state='QUEUED' AND type='TEST_CLAIM' ORDER BY run_after,id LIMIT 1 FOR UPDATE SKIP LOCKED; "
                f"UPDATE job SET state='RUNNING',attempt_count=attempt_count+1,lease_token={uid(token)},claimed_at=UTC_TIMESTAMP(3),"
                "lease_until=UTC_TIMESTAMP(3)+INTERVAL 1 MINUTE,revision=revision+1 WHERE id=@claimed; ")
    with ThreadPoolExecutor(max_workers=2) as pool:
        first = pool.submit(query, claim(9090) + "SELECT GET_LOCK('p0406_job_claim',0); SELECT SLEEP(3); COMMIT;")
        wait_for_lock('p0406_job_claim')
        second = pool.submit(query, claim(9091) + 'COMMIT;')
        first.result()
        second.result()
    value('two workers claim different jobs', "SELECT COUNT(*),COUNT(DISTINCT lease_token) FROM job WHERE type='TEST_CLAIM' AND state='RUNNING'", '2\t2')
    query(f"UPDATE job SET claimed_at=UTC_TIMESTAMP(3)-INTERVAL 2 MINUTE,lease_until=UTC_TIMESTAMP(3)-INTERVAL 1 MINUTE WHERE id={uid(8090)}")
    query(f"UPDATE job SET attempt_count=attempt_count+1,lease_token={uid(9092)},claimed_at=UTC_TIMESTAMP(3),"
          f"lease_until=UTC_TIMESTAMP(3)+INTERVAL 1 MINUTE,revision=revision+1 WHERE id={uid(8090)} AND state='RUNNING' AND lease_until<UTC_TIMESTAMP(3)")
    value('stale worker cannot finish reclaimed job with token predicate',
          f"UPDATE job SET state='SUCCEEDED',lease_token=NULL,claimed_at=NULL,lease_until=NULL,finished_at=UTC_TIMESTAMP(3) "
          f"WHERE id={uid(8090)} AND state='RUNNING' AND lease_token={uid(9090)}; SELECT ROW_COUNT()", '0')
    value('current lease holder can finish job',
          f"UPDATE job SET state='SUCCEEDED',lease_token=NULL,claimed_at=NULL,lease_until=NULL,finished_at=UTC_TIMESTAMP(3),revision=revision+1 "
          f"WHERE id={uid(8090)} AND state='RUNNING' AND lease_token={uid(9092)}; SELECT ROW_COUNT()", '1')
    reject('attempt count cannot rewind', f'UPDATE job SET attempt_count=0 WHERE id={uid(8090)}', 1644)
    reject('completed job still reserves dedupe identity', job(8092, dedupe_key="'p0406/user/8001/purge/8090'"), 1062)
    query(f"UPDATE job SET state='RETRY_WAIT',lease_token=NULL,claimed_at=NULL,lease_until=NULL,last_error='OBJECT_STORE_UNAVAILABLE',run_after=UTC_TIMESTAMP(3)+INTERVAL 1 MINUTE WHERE id={uid(8091)}")
    value('retry keeps operation and attempt count', f'SELECT state,attempt_count FROM job WHERE id={uid(8091)}', 'RETRY_WAIT\t1')

    # Proof of transaction support: no partial domain write/sequence/receipt/job.
    query(f"START TRANSACTION; UPDATE user_sync_state SET last_change_seq=3 WHERE user_id={U}; "
          f"UPDATE song SET note='must rollback' WHERE id={SONG}; " + change(3) + '; ' + receipt(8100) + '; ' + job(8100) + '; ROLLBACK;')
    value('rollback restores domain and sequence', f"SELECT CONCAT('[',note,']'),(SELECT last_change_seq FROM user_sync_state WHERE user_id={U}) FROM song WHERE id={SONG}", '[]\t2')
    value('rollback removes change receipt and job together',
          f'SELECT (SELECT COUNT(*) FROM change_log WHERE user_id={U})+(SELECT COUNT(*) FROM mutation_receipt WHERE user_id={U})+(SELECT COUNT(*) FROM job WHERE id={uid(8100)})', '0')
    print(f'P04-06 sync and deletion: {checks} checks passed.', flush=True)


if __name__ == '__main__':
    if os.environ.get('P04_DISPOSABLE_DB') != '1':
        raise SystemExit('Use a disposable DB and set P04_DISPOSABLE_DB=1; never run on user data.')
    if '--seed-upgrade' in sys.argv:
        seed_upgrade()
    else:
        main()
