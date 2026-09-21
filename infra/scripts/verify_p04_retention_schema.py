"""P04-05 checks. Run only on a disposable MySQL database immediately after V5.

Shared client supports CI Docker and an isolated local MySQL. No third-party deps.
Rejected mutations must report a constraint error, not connection/syntax failure.
"""
import os
import sys
from concurrent.futures import ThreadPoolExecutor
import time

from verify_p04_extended_schema import query, uid


checks = 0
U, OTHER, DEVICE, OTHER_DEVICE = map(uid, (5001, 5002, 5003, 5004))
SONG, SECOND_SONG, OTHER_SONG = map(uid, (5010, 5011, 5012))


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


def pin(slot, current='NULL', pending='NULL', user=U):
    return ("INSERT INTO pin_slot(user_id,slot_no,current_recording_id,pending_recording_id,operation_id,requested_at) "
            f"VALUES ({user},{slot},{current},{pending},{uid(5500 + slot)},UTC_TIMESTAMP(3))")


def cleanup(identifier, recording=5201, **fields):
    row = dict(id=uid(identifier), user_id=U, recording_id=uid(recording), generation=uid(10000 + recording),
               expected_sha256="REPEAT('a',64)", expected_cloud_revision='1')
    row.update(fields)
    return f"INSERT INTO cloud_cleanup({','.join(row)}) VALUES ({','.join(row.values())})"


def hold(identifier, reason="'ORPHAN_KEEP'", op='NULL', revision='NULL', recording=5201, user=U):
    return ("INSERT INTO cloud_hold(id,user_id,recording_id,reason,related_operation_id,required_selection_revision) "
            f"VALUES ({uid(identifier)},{user},{uid(recording)},{reason},{op},{revision})")


def wait_for_lock(name):
    for _ in range(100):
        if query(f"SELECT IS_USED_LOCK('{name}') IS NOT NULL") == '1':
            return
        time.sleep(0.05)
    raise AssertionError('Concurrent transaction never reached barrier: ' + name)


def seed_upgrade():
    """Nonzero old data proves V5 handles trash/deleting and terminal uploads."""
    value('upgrade seed starts at V4', "SELECT schema_value FROM app_schema_metadata WHERE schema_key='schema_contract'", '4')
    user, device = uid(6001), uid(6002)
    query(f'INSERT INTO app_user(id) VALUES({user})')
    query(f"INSERT INTO device(id,user_id,display_name,last_seen_at) VALUES({device},{user},'upgrade',UTC_TIMESTAMP(3))")
    for r, size, state, lifecycle in [(6010,100,'STORED','TRASHED'), (6011,500,'DELETING','ACTIVE')]:
        deleted = 'UTC_TIMESTAMP(3)' if lifecycle == 'TRASHED' else 'NULL'
        query(f"INSERT INTO recording(id,user_id,origin_device_id,note,recorded_at,timezone_id,timezone_offset_minutes,"
              f"title_snapshot,artist_snapshot,key_mode,key_shift,lifecycle_state,deleted_at) VALUES "
              f"({uid(r)},{user},{device},'',UTC_TIMESTAMP(3),'UTC',0,'legacy','artist','ORIGINAL',0,'{lifecycle}',{deleted})")
        query(f"INSERT INTO recording_file_spec(recording_id,user_id,sha256,size_bytes,duration_ms,codec,sample_rate,channels,capture_integrity) "
              f"VALUES ({uid(r)},{user},REPEAT('a',64),{size},1000,'AAC_LC',48000,1,'VALIDATED')")
        query(f"UPDATE recording SET metadata_state='SAVED' WHERE id={uid(r)}")
        query(f"INSERT INTO recording_asset(recording_id,user_id,cloud_state,object_key,generation,verified_size,sha256,stored_at) "
              f"VALUES({uid(r)},{user},'{state}','p0405/upgrade/{r}',{uid(16000+r)},{size},REPEAT('a',64),UTC_TIMESTAMP(3))")
    # A separate DRAFT represents a still-running upload; eligibility is a later API check.
    query(f"INSERT INTO recording(id,user_id,origin_device_id,note,recorded_at,timezone_id,timezone_offset_minutes) "
          f"VALUES ({uid(6012)},{user},{device},'',UTC_TIMESTAMP(3),'UTC',0)")
    for i, state, size, slot in [(6020,'VERIFYING',77,'0'), (6021,'FAILED',99,'NULL'), (6022,'COMMITTED',100,'NULL')]:
        query(f"INSERT INTO recording_upload(id,user_id,recording_id,state,active_slot,expected_size,expected_sha256,"
              f"temp_key,final_key,policy_revision,expires_at) VALUES ({uid(i)},{user},{uid(6012)},'{state}',{slot},{size},"
              f"REPEAT('a',64),'p0405/temp/{i}','p0405/final/{i}',1,UTC_TIMESTAMP(3)+INTERVAL 1 DAY)")
    query("INSERT INTO app_schema_metadata(schema_key,schema_value) VALUES('p04_05_upgrade_seed','1')")
    print('P04-05 V4 upgrade fixtures inserted.', flush=True)


def main():
    value('schema contract', "SELECT schema_value FROM app_schema_metadata WHERE schema_key='schema_contract'", '5')
    value('all existing users receive one usage row',
          'SELECT (SELECT COUNT(*) FROM app_user)=(SELECT COUNT(*) FROM storage_usage)', '1')
    value('upgrade backfills physical bytes including DELETING', """
        SELECT COUNT(*) FROM storage_usage s WHERE s.used_bytes <>
        (SELECT COALESCE(SUM(a.verified_size),0) FROM recording_asset a WHERE a.user_id=s.user_id
         AND a.cloud_state IN ('STORED','DELETING'))""", '0')
    value('upgrade backfills active reservations only', """
        SELECT COUNT(*) FROM storage_usage s WHERE s.reserved_bytes <>
        (SELECT COALESCE(SUM(r.expected_size),0) FROM recording_upload r WHERE r.user_id=s.user_id
         AND r.state IN ('RESERVED','UPLOADING','VERIFYING'))""", '0')
    value('global totals match user totals', """
        SELECT g.used_bytes=(SELECT COALESCE(SUM(used_bytes),0) FROM storage_usage),
          g.reserved_bytes=(SELECT COALESCE(SUM(reserved_bytes),0) FROM storage_usage)
        FROM global_storage_usage g WHERE id=1""", '1\t1')
    value('global default uses decimal 20 GB',
          'SELECT primary_quota_bytes,temp_observed_bytes,upload_locked FROM global_storage_usage WHERE id=1',
          '20000000000\t0\t0')
    if query("SELECT COUNT(*) FROM app_schema_metadata WHERE schema_key='p04_05_upgrade_seed'") == '1':
        value('upgrade keeps trash and DELETING bytes, excludes terminal reservations',
              f'SELECT used_bytes,reserved_bytes FROM storage_usage WHERE user_id={uid(6001)}', '600\t77')
        value('upgrade preserves physical object metadata',
              f'SELECT cloud_state,verified_size FROM recording_asset WHERE recording_id={uid(6011)}', 'DELETING\t500')
    value('all byte fields use BIGINT', """
        SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE()
        AND table_name IN ('storage_usage','global_storage_usage') AND column_name LIKE '%bytes'
        AND data_type='bigint'""", '6')

    query(f"INSERT INTO app_user(id) VALUES ({U}),({OTHER})")
    query(f"INSERT INTO user_entitlement(user_id) VALUES ({U}),({OTHER})")
    query(f"INSERT INTO storage_usage(user_id) VALUES ({U}),({OTHER})")
    query(f"INSERT INTO device(id,user_id,display_name,last_seen_at) VALUES "
          f"({DEVICE},{U},'retention',UTC_TIMESTAMP(3)),({OTHER_DEVICE},{OTHER},'other',UTC_TIMESTAMP(3))")
    for s, u in [(SONG, U), (SECOND_SONG, U), (OTHER_SONG, OTHER)]:
        query(f"INSERT INTO song(id,user_id,source_type,title,artist,note) VALUES ({s},{u},'MANUAL','song','artist','')")
    for r in range(5201, 5220):
        # 5217: DRAFT, 5218: SAVED with no asset, 5219: DELETING asset.
        s = 'NULL' if r == 5218 else SONG
        query(f"INSERT INTO recording(id,user_id,origin_device_id,song_id,title_snapshot,artist_snapshot,note,"
              f"recorded_at,timezone_id,timezone_offset_minutes,key_mode,key_shift) VALUES "
              f"({uid(r)},{U},{DEVICE},{s},'title','artist','',UTC_TIMESTAMP(3),'Asia/Seoul',540,'ORIGINAL',0)")
        if r == 5217:
            continue
        query(f"INSERT INTO recording_file_spec(recording_id,user_id,sha256,size_bytes,duration_ms,codec,sample_rate,channels,capture_integrity) "
              f"VALUES ({uid(r)},{U},REPEAT('a',64),100,1000,'AAC_LC',48000,1,'VALIDATED')")
        query(f"UPDATE recording SET metadata_state='SAVED' WHERE id={uid(r)}")
        if r != 5218:
            state = 'DELETING' if r == 5219 else 'STORED'
            query(f"INSERT INTO recording_asset(recording_id,user_id,cloud_state,object_key,generation,verified_size,sha256,stored_at) "
                  f"VALUES ({uid(r)},{U},'{state}','retention/{r}',{uid(10000+r)},100,REPEAT('a',64),UTC_TIMESTAMP(3))")

    R = uid(5201)
    query(f"INSERT INTO song_cloud_selection(song_id,user_id,representative_id,latest_id,lowest_tier_id) "
          f"VALUES ({SONG},{U},{R},{R},{R})")
    value('one file can satisfy all three roles',
          f'SELECT representative_id=latest_id AND latest_id=lowest_tier_id FROM song_cloud_selection WHERE song_id={SONG}', '1')
    value('roles do not duplicate physical files', f'SELECT COUNT(*) FROM recording_asset WHERE recording_id={R}', '1')
    reject('selection owner isolation', f"INSERT INTO song_cloud_selection(song_id,user_id) VALUES ({OTHER_SONG},{U})", 1452)
    reject('selection cannot reference another song recording',
           f"INSERT INTO song_cloud_selection(song_id,user_id,latest_id) VALUES ({SECOND_SONG},{U},{R})", 1452)
    reject('one selection per song', f"INSERT INTO song_cloud_selection(song_id,user_id) VALUES ({SONG},{U})", 1062)
    reject('selection revision positive', f'UPDATE song_cloud_selection SET selection_revision=0 WHERE song_id={SONG}')
    query(f"INSERT INTO song_cloud_selection(song_id,user_id) VALUES ({SECOND_SONG},{U})")
    value('unselected roles are NULL', f'SELECT latest_id IS NULL FROM song_cloud_selection WHERE song_id={SECOND_SONG}', '1')

    reject('pin cannot reference other owner', pin(1, pending=R, user=OTHER), 1644)
    reject('pin rejects DRAFT', pin(1, pending=uid(5217)), 1644)
    reject('current pin requires STORED', pin(1, current=uid(5218)), 1644)
    reject('pin rejects cleanup in progress', pin(1, pending=uid(5219)), 1644)
    reject('slot is one based', pin(0, current=R))
    reject('same current and pending rejected', pin(1, current=R, pending=R))
    reject('occupied pin requires operation', f'INSERT INTO pin_slot(user_id,slot_no,pending_recording_id) VALUES({U},1,{R})')
    query(pin(1, current=R))
    query(pin(2, pending=uid(5218)))
    value('unlinked waiting file consumes a slot', f'SELECT COUNT(*) FROM pin_slot WHERE user_id={U}', '2')
    # Use a STORED target here so missing-file validation cannot mask a broken duplicate guard.
    query(f'UPDATE pin_slot SET pending_recording_id={uid(5216)} WHERE user_id={U} AND slot_no=2')
    reject('current cannot duplicate another pending', pin(3, current=uid(5216)), 1644)
    query(f'UPDATE pin_slot SET pending_recording_id={uid(5218)} WHERE user_id={U} AND slot_no=2')
    reject('pending cannot duplicate another current', pin(3, pending=R), 1644)
    query(f'UPDATE pin_slot SET pending_recording_id={uid(5202)} WHERE user_id={U} AND slot_no=1')
    value('replacement protects current and pending in one slot',
          f'SELECT current_recording_id={R},pending_recording_id={uid(5202)} FROM pin_slot WHERE user_id={U} AND slot_no=1', '1\t1')
    query(f'UPDATE pin_slot SET pending_recording_id=NULL WHERE user_id={U} AND slot_no=1')
    value('cancel replacement retains current', f'SELECT current_recording_id={R} FROM pin_slot WHERE user_id={U} AND slot_no=1', '1')
    query(f'UPDATE pin_slot SET pending_recording_id={uid(5202)} WHERE user_id={U} AND slot_no=1')
    query(f'UPDATE pin_slot SET current_recording_id=pending_recording_id,pending_recording_id=NULL WHERE user_id={U} AND slot_no=1')
    value('stored replacement promotion is atomic',
          f'SELECT current_recording_id={uid(5202)},pending_recording_id IS NULL FROM pin_slot WHERE user_id={U} AND slot_no=1', '1\t1')
    for slot in range(3, 10):
        query(pin(slot, current=uid(5200 + slot)))
    # Two independent client transactions contend for the tenth slot.
    with ThreadPoolExecutor(max_workers=2) as pool:
        first = pool.submit(query, f'START TRANSACTION; SELECT pinned_limit FROM user_entitlement WHERE user_id={U} FOR UPDATE; '
                            + pin(10, current=uid(5210)) + "; SELECT GET_LOCK('p0405_tenth_slot',0); SELECT SLEEP(3); COMMIT;")
        wait_for_lock('p0405_tenth_slot')
        second = pool.submit(query, pin(10, current=uid(5211)), 1062)
        first.result()
        second.result()
    value('two devices never create eleven pins', f'SELECT COUNT(*) FROM pin_slot WHERE user_id={U}', '10')
    reject('eleventh slot rejected', pin(11, current=uid(5211)), 1644)
    query(f'UPDATE user_entitlement SET pinned_limit=5 WHERE user_id={U}')
    value('lowering limit never deletes existing pins', f'SELECT COUNT(*) FROM pin_slot WHERE user_id={U}', '10')
    query(f'UPDATE pin_slot SET pending_recording_id={uid(5211)} WHERE user_id={U} AND slot_no=10')
    value('existing high slot retains replacement capability', f'SELECT pending_recording_id={uid(5211)} FROM pin_slot WHERE user_id={U} AND slot_no=10', '1')
    query(f'UPDATE pin_slot SET pending_recording_id=NULL,current_recording_id=NULL WHERE user_id={U} AND slot_no=3')
    reject('lowered limit prevents refilling while over limit',
           f'UPDATE pin_slot SET pending_recording_id={uid(5212)} WHERE user_id={U} AND slot_no=3', 1644)
    reject('slot cannot be moved to another owner', f'UPDATE pin_slot SET user_id={OTHER} WHERE user_id={U} AND slot_no=3', 1644)
    reject('pin revision positive', f'UPDATE pin_slot SET revision=0 WHERE user_id={U} AND slot_no=3')
    query(f'UPDATE user_entitlement SET pinned_limit=10 WHERE user_id={U}')

    # Establish an old RR snapshot before another client pins the target.
    query(f'UPDATE pin_slot SET current_recording_id=NULL WHERE user_id={U} AND slot_no=4')
    with ThreadPoolExecutor(max_workers=1) as pool:
        stale = pool.submit(query, f'START TRANSACTION; SELECT COUNT(*) FROM pin_slot WHERE user_id={U}; '
                            "SELECT GET_LOCK('p0405_stale_snapshot',0); SELECT SLEEP(3); "
                            + f'UPDATE pin_slot SET pending_recording_id={uid(5214)} WHERE user_id={U} AND slot_no=4; COMMIT;', 1644)
        wait_for_lock('p0405_stale_snapshot')
        query(f'UPDATE pin_slot SET pending_recording_id={uid(5214)} WHERE user_id={U} AND slot_no=3')
        stale.result()
    value('old RR snapshot cannot bypass cross-column duplicate guard',
          f'SELECT COUNT(*) FROM pin_slot WHERE user_id={U} AND pending_recording_id={uid(5214)}', '1')

    query(hold(5601))
    reject('NULL operation cannot bypass hold deduplication', hold(5602), 1062)
    query(hold(5603, reason="'WAITING_LOCAL_CONFIRM'"))
    query(hold(5604, reason="'PENDING_REPLACEMENT'", op=uid(5650), revision='2'))
    reject('same related operation is idempotent', hold(5605, reason="'PENDING_REPLACEMENT'", op=uid(5650), revision='2'), 1062)
    query(hold(5606, reason="'PENDING_REPLACEMENT'", op=uid(5651), revision='3'))
    reject('replacement needs operation and selection', hold(5607, reason="'PENDING_REPLACEMENT'"))
    reject('unknown hold reason', hold(5608, reason="'PINNED'"))
    reject('hold owner isolation', hold(5609, user=OTHER), 1452)
    reject('zero UUID reserved for standing hold', hold(5610, op=uid(0)))
    reject('hold revision positive', hold(5611, op=uid(5660), revision='0'))
    value('multiple reasons do not duplicate bytes', f'SELECT COUNT(*) FROM recording_asset WHERE recording_id={R}', '1')

    query(cleanup(5701))
    reject('one active cleanup per generation', cleanup(5702), 1062)
    reject('cleanup must bind to current generation', cleanup(5703, generation=uid(99999)), 1644)
    reject('cleanup must bind to checksum', cleanup(5704, expected_sha256="REPEAT('b',64)"), 1644)
    reject('cleanup must bind to cloud revision', cleanup(5705, expected_cloud_revision='2'), 1644)
    reject('cleanup owner isolation', cleanup(5706, user_id=OTHER), 1644)
    reject('cleanup captured identity immutable', f'UPDATE cloud_cleanup SET generation={uid(99999)} WHERE id={uid(5701)}', 1644)
    reject('cleanup cannot delete without confirmation', f"UPDATE cloud_cleanup SET state='DELETING' WHERE id={uid(5701)}")
    reject('partial confirmation rejected', f"UPDATE cloud_cleanup SET confirmation_mode='LOCAL_VERIFIED' WHERE id={uid(5701)}")
    reject('confirmation max fifteen minutes', f"UPDATE cloud_cleanup SET confirmation_mode='LOCAL_VERIFIED',confirmed_at=UTC_TIMESTAMP(3),"
           f"confirmation_expires_at=UTC_TIMESTAMP(3)+INTERVAL 16 MINUTE WHERE id={uid(5701)}")
    query(f"UPDATE cloud_cleanup SET confirmation_mode='LOCAL_VERIFIED',confirmed_at=UTC_TIMESTAMP(3),"
          f"confirmation_expires_at=UTC_TIMESTAMP(3)+INTERVAL 15 MINUTE,state='CONFIRMED' WHERE id={uid(5701)}")
    query(f"UPDATE cloud_cleanup SET state='DELETING',lease_until=UTC_TIMESTAMP(3)+INTERVAL 1 MINUTE WHERE id={uid(5701)}")
    query(f"UPDATE cloud_cleanup SET state='RETRY_WAIT',error_code='OBJECT_STORE_UNAVAILABLE' WHERE id={uid(5701)}")
    reject('retry continues holding generation reservation', cleanup(5707), 1062)
    reject('terminal cleanup requires completion time', f"UPDATE cloud_cleanup SET state='CANCELLED' WHERE id={uid(5701)}")
    query(f"UPDATE cloud_cleanup SET state='CANCELLED',completed_at=UTC_TIMESTAMP(3) WHERE id={uid(5701)}")
    query(cleanup(5708, state="'CONFIRMED'", confirmation_mode="'USER_CONFIRMED_LOSS'",
                  confirmed_at='UTC_TIMESTAMP(3)', confirmation_expires_at='UTC_TIMESTAMP(3)+INTERVAL 15 MINUTE'))
    value('terminal history coexists with new attempt', f'SELECT COUNT(*) FROM cloud_cleanup WHERE recording_id={R}', '2')
    query(f'UPDATE recording_asset SET generation={uid(88888)},cloud_revision=cloud_revision+1 WHERE recording_id={R}')
    value('cleanup history retains original generation after asset replacement',
          f'SELECT generation={uid(15201)} FROM cloud_cleanup WHERE id={uid(5701)}', '1')

    for table, where, fields in [('storage_usage', f'user_id={U}', ['used_bytes','reserved_bytes']),
                                  ('global_storage_usage', 'id=1', ['used_bytes','reserved_bytes','primary_quota_bytes','temp_observed_bytes'])]:
        for field in fields:
            reject('nonnegative ' + table + '.' + field, f'UPDATE {table} SET {field}=-1 WHERE {where}')
        reject('positive revision ' + table, f'UPDATE {table} SET revision=0 WHERE {where}')
    reject('global row must be id 1', 'INSERT INTO global_storage_usage(id) VALUES(2)')
    reject('global singleton duplicate', 'INSERT INTO global_storage_usage(id) VALUES(1)', 1062)
    reject('lock flag boolean', 'UPDATE global_storage_usage SET upload_locked=2 WHERE id=1')
    reject('usage owner must exist', f'INSERT INTO storage_usage(user_id) VALUES({uid(99999)})', 1452)
    query(f'UPDATE storage_usage SET used_bytes=3000000000,reserved_bytes=123 WHERE user_id={U}')
    value('BIGINT supports values above signed INT and retains over-quota data',
          f'SELECT used_bytes,reserved_bytes FROM storage_usage WHERE user_id={U}', '3000000000\t123')
    query('UPDATE global_storage_usage SET used_bytes=21000000000,upload_locked=1 WHERE id=1')
    value('budget lock does not delete stored usage', 'SELECT used_bytes,upload_locked FROM global_storage_usage WHERE id=1', '21000000000\t1')
    print(f'P04-05 retention and storage: {checks} checks passed.', flush=True)


if __name__ == '__main__':
    if os.environ.get('P04_DISPOSABLE_DB') != '1':
        raise SystemExit('Use a disposable DB and set P04_DISPOSABLE_DB=1; never run on user data.')
    if '--seed-upgrade' in sys.argv:
        seed_upgrade()
    else:
        main()
