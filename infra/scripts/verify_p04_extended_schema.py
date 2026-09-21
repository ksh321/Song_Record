"""P04-01~04 regression checks against a disposable, already migrated MySQL 8.4 DB.

Default: docker compose exec from infra/. Local: MYSQL_TEST_CLIENT, MYSQL_PORT,
MYSQL_USER, MYSQL_DATABASE and (optionally) MYSQL_PWD. No production databases.
Every rejection checks the actual MySQL error; connection/syntax errors fail tests.
"""
import os
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor


def query(statement, error=None):
    client = os.environ.get('MYSQL_TEST_CLIENT')
    if client:
        command = [client, '--no-defaults', '--protocol=tcp', '-h127.0.0.1',
                   '-P' + os.environ.get('MYSQL_PORT', '33316'),
                   '-u' + os.environ.get('MYSQL_USER', 'root'),
                   os.environ['MYSQL_DATABASE'], '--default-character-set=utf8mb4',
                   '--batch', '--skip-column-names']
    else:
        command = ['docker', 'compose', 'exec', '-T', 'mysql', 'sh', '-lc',
                   'MYSQL_PWD="$MYSQL_PASSWORD" mysql --protocol=tcp -h127.0.0.1 '
                   '-u"$MYSQL_USER" "$MYSQL_DATABASE" --default-character-set=utf8mb4 '
                   '--batch --skip-column-names']
    # Match the project's UTC database; host Windows time zone must not affect DATETIME defaults.
    result = subprocess.run(command, input="SET time_zone='+00:00';\n" + statement, text=True, encoding='utf-8',
                            capture_output=True, timeout=30)
    if error:
        assert result.returncode and f'ERROR {error} ' in result.stderr, (statement, result.stderr)
    else:
        assert result.returncode == 0, (statement, result.stderr)
    return result.stdout.strip()


checks = 0


def reject(label, statement, error):
    global checks
    query(statement, error)
    checks += 1
    print('PASS reject:', label)


def value(label, statement, expected):
    global checks
    actual = query(statement)
    assert actual == expected, (label, expected, actual)
    checks += 1
    print('PASS value:', label)


def uid(number):
    return f"UNHEX('{number:032x}')"


U, OTHER, DEVICE = map(uid, (901, 902, 903))
S, MANUAL, OTHER_S = map(uid, (910, 911, 912))
R, R2, R3 = map(uid, (920, 921, 922))
P, P2, OTHER_P = map(uid, (930, 931, 932))
T, T2, OTHER_T = map(uid, (940, 941, 942))


def item(identifier, playlist=P, song='NULL', brand='NULL', number='NULL', snapshot='NULL', key='forged'):
    return ("INSERT INTO playlist_item(id,user_id,playlist_id,song_id,candidate_brand,"
            "candidate_number,candidate_snapshot,entry_key,position) VALUES "
            f"({uid(identifier)},{U},{playlist},{song},{brand},{number},{snapshot},'{key}',7)")


def upload(identifier, recording, slot):
    return ("INSERT INTO recording_upload(id,user_id,recording_id,state,active_slot,expected_size,"
            "expected_sha256,temp_key,final_key,policy_revision,expires_at) VALUES "
            f"({uid(identifier)},{U},{recording},'RESERVED',{slot},123,REPEAT('a',64),"
            f"'audit/tmp/{identifier}','audit/final/{identifier}',1,UTC_TIMESTAMP(3)+INTERVAL 1 DAY)")


def main():
    value('schema contract', "SELECT schema_value FROM app_schema_metadata WHERE schema_key='schema_contract'", '4')
    query(f"INSERT INTO app_user(id) VALUES ({U}),({OTHER})")
    query(f"INSERT INTO device(id,user_id,display_name,last_seen_at) VALUES ({DEVICE},{U},'audit',UTC_TIMESTAMP(3))")
    query(f"INSERT INTO song(id,user_id,source_type,tj_number,title,artist,note) VALUES "
          f"({S},{U},'TJ','00901','audit','artist',''),({MANUAL},{U},'MANUAL',NULL,'manual','artist',''),"
          f"({OTHER_S},{OTHER},'TJ','00901','other','artist','')")
    for recording in (R, R2, R3):
        query(f"INSERT INTO recording(id,user_id,origin_device_id,song_id,note,recorded_at,timezone_id,timezone_offset_minutes) "
              f"VALUES ({recording},{U},{DEVICE},{S},'',UTC_TIMESTAMP(3),'Asia/Seoul',540)")
    for state in ('ACTIVE', 'TRASHED', 'PURGE_PENDING'):
        deleted = 'NULL' if state == 'ACTIVE' else 'UTC_TIMESTAMP(3)'
        query(f"UPDATE song SET lifecycle_state='{state}',deleted_at={deleted} WHERE id={S}")
        reject('TJ reservation ' + state, f"INSERT INTO song(id,user_id,source_type,tj_number,title,artist,note) "
               f"VALUES ({uid(913)},{U},'TJ','00901','duplicate','artist','')", 1062)
    query(f"UPDATE song SET lifecycle_state='ACTIVE',deleted_at=NULL WHERE id={S}")
    for mode, shift in [("'MALE'", 'NULL'), ('NULL', '2'), ("'FEMALE'", '13')]:
        reject('song partial/invalid key', f"UPDATE song SET representative_key_mode={mode},representative_key_shift={shift} WHERE id={S}", 3819)
        reject('recording partial/invalid key', f"UPDATE recording SET key_mode={mode},key_shift={shift} WHERE id={R}", 3819)
    query(upload(960, R, '0'))
    query(upload(961, R2, '1'))
    reject('NULL cannot bypass two upload slots', upload(962, R3, 'NULL'), 3819)
    reject('third active upload', upload(963, R3, '0'), 1062)
    query(f"UPDATE recording_upload SET state='FAILED',active_slot=NULL WHERE id={uid(961)}")
    reject('same recording in another slot', upload(964, R, '1'), 1062)
    query(f"INSERT INTO recording_asset(recording_id,user_id,cloud_state,generation,object_key,verified_size,sha256,stored_at) "
          f"VALUES ({R},{U},'STORED',{uid(970)},'audit/object',123,REPEAT('a',64),UTC_TIMESTAMP(3))")
    value('generation is a UUID', f"SELECT OCTET_LENGTH(generation) FROM recording_asset WHERE recording_id={R}", '16')
    reject('STORED must have generation', f"UPDATE recording_asset SET generation=NULL WHERE recording_id={R}", 3819)
    reject('empty final object key', f"UPDATE recording_asset SET object_key='' WHERE recording_id={R}", 3819)

    query(f"INSERT INTO playlist(id,user_id,name) VALUES ({P},{U},'same'),({P2},{U},'same'),({OTHER_P},{OTHER},'same')")
    query(item(980, song=S))
    value('DB derives TJ key', f"SELECT entry_key FROM playlist_item WHERE id={uid(980)}", 'tj:00901')
    reject('candidate duplicates registered song', item(981, brand="'TJ'", number="'00901'", snapshot="JSON_OBJECT('title','candidate')"), 1062)
    query(item(982, playlist=P2, song=S))
    query(item(983, song=MANUAL))
    value('MANUAL derived identity', f"SELECT entry_key FROM playlist_item WHERE id={uid(983)}", 'manual:00000000-0000-0000-0000-00000000038f')
    reject('duplicate MANUAL song with forged key', item(984, song=MANUAL, key='bypass'), 1062)
    reject('foreign playlist', item(985, playlist=OTHER_P, song=S), 1644)
    reject('foreign song', item(986, song=OTHER_S), 1644)
    reject('KY candidate', item(987, brand="'KY'", number="'12'", snapshot='JSON_OBJECT()'), 1644)
    reject('missing candidate snapshot', item(988, brand="'TJ'", number="'12'"), 1644)
    reject('partial linked candidate', item(989, song=S, number="'12'"), 3819)
    reject('mismatched linked number', item(990, song=S, brand="'TJ'", number="'12'", snapshot='JSON_OBJECT()'), 1644)
    reject('MANUAL with candidate', item(991, song=MANUAL, brand="'TJ'", number="'12'", snapshot='JSON_OBJECT()'), 1644)
    reject('non-numeric TJ candidate', item(995, brand="'TJ'", number="'abc'", snapshot='JSON_OBJECT()'), 3819)
    reject('non-object candidate snapshot', item(996, brand="'TJ'", number="'99'", snapshot='JSON_ARRAY()'), 3819)
    reject('negative playlist position', f"UPDATE playlist_item SET position=-1 WHERE id={uid(980)}", 3819)
    query(item(992, brand="'TJ'", number="'00199'", snapshot="JSON_OBJECT('title','original')"))
    S_NEW = uid(914)
    query(f"INSERT INTO song(id,user_id,source_type,tj_number,title,artist,note) VALUES ({S_NEW},{U},'TJ','00199','new','artist','')")
    query(f"UPDATE playlist_item SET song_id={S_NEW},entry_key='forged' WHERE id={uid(992)}")
    value('link preserves ID position and source', f"SELECT entry_key,position,JSON_UNQUOTE(JSON_EXTRACT(candidate_snapshot,'$.title')) FROM playlist_item WHERE id={uid(992)}", 'tj:00199\t7\toriginal')
    reject('link cannot change candidate identity', f"UPDATE playlist_item SET song_id={MANUAL},candidate_brand=NULL,candidate_number=NULL,candidate_snapshot=NULL WHERE id={uid(992)}", 1644)
    reject('song number immutable', f"UPDATE song SET tj_number='changed' WHERE id={S}", 1644)
    query(f"UPDATE song SET lifecycle_state='TRASHED',deleted_at=UTC_TIMESTAMP(3) WHERE id={S_NEW}")
    reject('new link to trashed song', item(993, playlist=P2, song=S_NEW), 1644)
    query(f"UPDATE playlist_item SET hidden_by_batch_id={uid(999)} WHERE id={uid(992)}")
    query(f"UPDATE song SET lifecycle_state='ACTIVE',deleted_at=NULL WHERE id={S_NEW}")
    query(f"UPDATE playlist_item SET hidden_by_batch_id=NULL,position=10 WHERE id={uid(992)}")
    value('hidden relation retained for restore', f"SELECT position FROM playlist_item WHERE id={uid(992)}", '10')
    query(f"UPDATE playlist SET deleted_at=UTC_TIMESTAMP(3) WHERE id={P2}")
    reject('deleted playlist new item', item(994, playlist=P2, song=MANUAL), 1644)
    reject('deleted playlist edit', f"UPDATE playlist_item SET position=20 WHERE id={uid(982)}", 1644)

    query(f"INSERT INTO tag(id,user_id,name,normalized_name_key) VALUES ({T},{U},'Practice',_binary'practice'),({T2},{U},'Other',_binary'other'),({OTHER_T},{OTHER},'Practice',_binary'practice')")
    reject('normalized active name duplicate', f"INSERT INTO tag(id,user_id,name,normalized_name_key) VALUES ({uid(943)},{U},'PRACTICE',_binary'practice')", 1062)
    query(f"INSERT INTO recording_tag(user_id,recording_id,tag_id,name_snapshot) VALUES ({U},{R},{T},'forged'),({U},{R},{T2},'forged')")
    value('multiple tags allowed', f"SELECT COUNT(*) FROM recording_tag WHERE recording_id={R}", '2')
    value('tag snapshot derived', f"SELECT name_snapshot FROM recording_tag WHERE recording_id={R} AND tag_id={T}", 'Practice')
    reject('duplicate relation', f"INSERT INTO recording_tag(user_id,recording_id,tag_id) VALUES ({U},{R},{T})", 1062)
    reject('foreign tag', f"INSERT INTO recording_tag(user_id,recording_id,tag_id) VALUES ({U},{R},{OTHER_T})", 1644)
    reject('foreign recording', f"INSERT INTO recording_tag(user_id,recording_id,tag_id) VALUES ({OTHER},{R},{OTHER_T})", 1452)
    query(f"UPDATE tag SET name='Renamed',normalized_name_key=_binary'renamed',archived_at=UTC_TIMESTAMP(3) WHERE id={T}")
    value('historical tag name preserved', f"SELECT name_snapshot FROM recording_tag WHERE recording_id={R} AND tag_id={T}", 'Practice')
    query(f"UPDATE recording_tag SET name_snapshot=name_snapshot WHERE recording_id={R} AND tag_id={T}")
    reject('new archived tag relation', f"INSERT INTO recording_tag(user_id,recording_id,tag_id) VALUES ({U},{R2},{T})", 1644)
    reject('rewriting historical tag name', f"UPDATE recording_tag SET name_snapshot='overwritten' WHERE recording_id={R} AND tag_id={T}", 1644)
    query(f"INSERT INTO tag(id,user_id,name,normalized_name_key) VALUES ({uid(944)},{U},'Renamed',_binary'renamed')")
    reject('unarchive conflicts with active name', f"UPDATE tag SET archived_at=NULL WHERE id={T}", 1062)

    value('condition starts unselected', f"SELECT condition_code IS NULL AND condition_name_snapshot IS NULL FROM recording WHERE id={R}", '1')
    for code, name in [('VERY_GOOD','매우 좋음'),('GOOD','좋음'),('NORMAL','보통'),('BAD','안 좋음')]:
        query(f"UPDATE recording SET condition_code='{code}',condition_name_snapshot='forged' WHERE id={R}")
        value('condition snapshot ' + code, f"SELECT condition_name_snapshot FROM recording WHERE id={R}", name)
    reject('unknown condition', f"UPDATE recording SET condition_code='CUSTOM' WHERE id={R}", 3819)
    query(f"UPDATE recording SET condition_code=NULL WHERE id={R}")
    value('condition clearing leaves tags', f"SELECT COUNT(*) FROM recording_tag WHERE recording_id={R}", '2')
    reject('catalog update', "UPDATE condition_catalog SET name='Changed' WHERE code='GOOD'", 1644)
    reject('catalog delete', "DELETE FROM condition_catalog WHERE code='GOOD'", 1644)
    reject('catalog insert', "INSERT INTO condition_catalog VALUES ('EXTRA','Extra',5,1)", 1644)

    concurrent_playlist = uid(933)
    query(f"INSERT INTO playlist(id,user_id,name) VALUES ({concurrent_playlist},{U},'concurrent')")
    with ThreadPoolExecutor(max_workers=1) as executor:
        future = executor.submit(query, 'START TRANSACTION; ' + item(997, playlist=concurrent_playlist, song=S)
                                 + "; SELECT GET_LOCK('p04_playlist_race',0); DO SLEEP(2); COMMIT; DO RELEASE_LOCK('p04_playlist_race');")
        await_lock('p04_playlist_race', future)
        reject('concurrent duplicate playlist entry', item(998, playlist=concurrent_playlist, brand="'TJ'", number="'00901'", snapshot='JSON_OBJECT()'), 1062)
        future.result()
    value('concurrent duplicate leaves exactly one item', f"SELECT COUNT(*) FROM playlist_item WHERE playlist_id={concurrent_playlist}", '1')

    # Serialize SAVED transition with concurrent deletion, checking the real lock.
    query(f"INSERT INTO recording_file_spec(recording_id,user_id,sha256,size_bytes,duration_ms,codec,sample_rate,channels,capture_integrity) VALUES ({R3},{U},REPEAT('a',64),123,1000,'AAC_LC',48000,1,'VALIDATED')")
    with ThreadPoolExecutor(max_workers=1) as executor:
        future = executor.submit(query, f"START TRANSACTION; UPDATE recording SET title_snapshot='saved',artist_snapshot='artist',key_mode='ORIGINAL',key_shift=0,metadata_state='SAVED' WHERE id={R3}; SELECT GET_LOCK('p04_saved_race',0); DO SLEEP(2); COMMIT; DO RELEASE_LOCK('p04_saved_race');")
        await_lock('p04_saved_race', future)
        reject('concurrent save protects file specification', f"DELETE FROM recording_file_spec WHERE recording_id={R3}", 1644)
        future.result()
    value('saved file specification survived race', f"SELECT COUNT(*) FROM recording_file_spec WHERE recording_id={R3}", '1')
    query(f"INSERT INTO recording_file_spec(recording_id,user_id,sha256,size_bytes,duration_ms,codec,sample_rate,channels,capture_integrity) VALUES ({R2},{U},REPEAT('a',64),123,1000,'AAC_LC',48000,1,'VALIDATED')")
    with ThreadPoolExecutor(max_workers=1) as executor:
        future = executor.submit(query, f"START TRANSACTION; DELETE FROM recording_file_spec WHERE recording_id={R2}; SELECT GET_LOCK('p04_delete_race',0); DO SLEEP(2); COMMIT; DO RELEASE_LOCK('p04_delete_race');")
        await_lock('p04_delete_race', future)
        reject('concurrent deleted specification blocks SAVED', f"UPDATE recording SET title_snapshot='saved',artist_snapshot='artist',key_mode='ORIGINAL',key_shift=0,metadata_state='SAVED' WHERE id={R2}", 1644)
        future.result()
    value('failed save stays DRAFT', f"SELECT metadata_state FROM recording WHERE id={R2}", 'DRAFT')
    print(f'P04 audit and P04-04: {checks} checks passed.')


def await_lock(name, future):
    deadline = time.monotonic() + 10
    while query(f"SELECT IS_USED_LOCK('{name}') IS NOT NULL") != '1':
        if future.done():
            future.result()
            raise AssertionError('Race transaction finished before lock was observed')
        assert time.monotonic() < deadline, 'Race lock was not observed'
        time.sleep(0.05)


if __name__ == '__main__':
    main()
