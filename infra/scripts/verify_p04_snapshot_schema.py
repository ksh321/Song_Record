"""P04-07 disposable MySQL tests; synthetic chart data only, no provider I/O.

--seed-upgrade runs at V6; normal execution runs immediately after V7.
SQL concurrency checks are protocols for later API work, not API tests.
"""
import os
import sys
from concurrent.futures import ThreadPoolExecutor

from verify_p04_extended_schema import query, uid
from verify_p04_retention_schema import wait_for_lock

checks = 0
U, OTHER, SONG = map(uid, (10001, 10002, 10003))


def value(label, sql, expected):
    global checks
    actual = query(sql)
    assert actual == expected, (label, expected, actual)
    checks += 1
    print('PASS value:', label, flush=True)


def reject(label, sql, error=3819):
    global checks
    query(sql, error)
    checks += 1
    print('PASS reject:', label, flush=True)


def chart(identifier, revision=1, **extra):
    row = dict(id=uid(identifier), brand="'TJ'", period="'MONTHLY'", revision=str(revision),
               source_url="'https://api.manana.kr/karaoke/popular/tj/monthly.json'", fetched_at='UTC_TIMESTAMP(3)')
    row.update(extra)
    return f"INSERT INTO chart_snapshot({','.join(row)}) VALUES({','.join(row.values())})"


def chart_item(identifier, position, number, **extra):
    row = dict(snapshot_id=uid(identifier), position=str(position), number=f"'{number}'", brand="'TJ'",
               period="'MONTHLY'", title="'fixture title'", artist="'fixture artist'")
    row.update(extra)
    return f"INSERT INTO chart_item({','.join(row)}) VALUES({','.join(row.values())})"


def publish(identifier, count):
    return f"UPDATE chart_snapshot SET state='PUBLISHED',item_count={count},published_at=UTC_TIMESTAMP(3) WHERE id={uid(identifier)}"


def header(identifier, slot=0, user=U, **extra):
    row = dict(id=uid(identifier), user_id=user, op_id=uid(identifier+10000), purpose="'SYNC'", schema_version='1',
               active_slot=str(slot), reserved_bytes='1024', attempt_id=uid(identifier+20000),
               lease_until='UTC_TIMESTAMP(3)+INTERVAL 5 MINUTE')
    row.update(extra)
    return f"INSERT INTO snapshot_header({','.join(row)}) VALUES({','.join(row.values())})"


def entry(identifier, ordinal=1, **extra):
    row = dict(snapshot_id=uid(identifier), attempt_id=uid(identifier+20000), entity="'SONG'",
               ordinal=str(ordinal), resource_id=SONG, payload="JSON_OBJECT('title','fixture')")
    row.update(extra)
    return f"INSERT INTO snapshot_entry({','.join(row)}) VALUES({','.join(row.values())})"


def capture(identifier):
    return f"UPDATE snapshot_header SET snapshot_cursor=7,captured_at=UTC_TIMESTAMP(3) WHERE id={uid(identifier)}"


def ready(identifier):
    # One timestamp for both fields avoids a client clock/round-trip mismatch.
    return (f"SET @ready=UTC_TIMESTAMP(3); SELECT COUNT(*),COALESCE(SUM(payload_bytes),0) INTO @rows,@bytes "
            f"FROM snapshot_entry WHERE snapshot_id={uid(identifier)}; UPDATE snapshot_header SET status='READY',"
            "ready_at=@ready,expires_at=@ready+INTERVAL 30 MINUTE,row_count=@rows,byte_count=@bytes,"
            f"manifest_hash=REPEAT('a',64),lease_until=NULL WHERE id={uid(identifier)}")


def seed_upgrade():
    value('upgrade starts at V6', "SELECT schema_value FROM app_schema_metadata WHERE schema_key='schema_contract'", '6')
    query(f'INSERT INTO app_user(id) VALUES({uid(9901)})')
    query(f'INSERT INTO user_sync_state(user_id,last_change_seq,retained_from_seq) VALUES({uid(9901)},17,5)')
    query(f"INSERT INTO change_log(user_id,change_seq,entity_type,entity_id,revision,operation,payload) "
          f"VALUES({uid(9901)},17,'SONG',{uid(9902)},4,'UPSERT',JSON_OBJECT('title','preserved'))")
    query("INSERT INTO app_schema_metadata(schema_key,schema_value) SELECT 'p04_07_usage_before',"
          "CONCAT(used_bytes,':',reserved_bytes,':',temp_observed_bytes,':',upload_locked) FROM global_storage_usage WHERE id=1")


def main():
    value('schema contract', "SELECT schema_value FROM app_schema_metadata WHERE schema_key='schema_contract'", '7')
    if query("SELECT COUNT(*) FROM app_schema_metadata WHERE schema_key='p04_07_usage_before'") == '1':
        value('existing sync cursor and retention floor preserved', f'SELECT last_change_seq,retained_from_seq FROM user_sync_state WHERE user_id={uid(9901)}', '17\t5')
        value('existing change payload preserved', f"SELECT payload->>'$.title',revision FROM change_log WHERE user_id={uid(9901)} AND change_seq=17", 'preserved\t4')
        value('existing storage counters preserved', "SELECT CONCAT(used_bytes,':',reserved_bytes,':',temp_observed_bytes,':',upload_locked)="
              "(SELECT schema_value FROM app_schema_metadata WHERE schema_key='p04_07_usage_before') FROM global_storage_usage WHERE id=1", '1')
    query(f'INSERT INTO app_user(id) VALUES({U}),({OTHER})')
    query(f'INSERT INTO user_sync_state(user_id,last_change_seq) VALUES({U},7),({OTHER},0)')
    query(f"INSERT INTO song(id,user_id,source_type,title,artist,note) VALUES({SONG},{U},'MANUAL','before','artist','')")
    value('six independent chart scopes initially empty', 'SELECT COUNT(*),SUM(snapshot_id IS NULL) FROM chart_publication', '6\t6')
    value('no historical ChartMonth table', "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name='chart_month'", '0')
    value('public charts have no user columns', "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name IN ('chart_snapshot','chart_item','chart_publication') AND column_name='user_id'", '0')
    reject('unknown brand', chart(10100, brand="'XX'"))
    reject('historical month not a period', chart(10100, period="'2026-09'"))
    reject('wrong source period', chart(10100, period="'DAILY'"))
    reject('new chart cannot bypass staging', chart(10100, state="'PUBLISHED'", published_at='UTC_TIMESTAMP(3)', item_count='1'), 1644)
    query(chart(10100))
    reject('empty charts cannot publish', publish(10100, 1), 1644)
    reject('staged charts not visible through pointer', f"UPDATE chart_publication SET snapshot_id={uid(10100)} WHERE brand='TJ' AND period='MONTHLY'", 1644)
    query(chart_item(10100, 1, '00001'))
    reject('duplicate chart number', chart_item(10100, 2, '00001'), 1062)
    reject('duplicate position', chart_item(10100, 1, '2'), 1062)
    reject('wrong item brand', chart_item(10100, 2, '2', brand="'KY'"), 1452)
    reject('position is positive', chart_item(10100, 0, '2'))
    reject('number not numeric', chart_item(10100, 2, 'abc'))
    reject('title not blank', chart_item(10100, 2, '2', title="'  '"))
    reject('artist not blank', chart_item(10100, 2, '2', artist="''"))
    query(chart_item(10100, 3, '3'))
    reject('position gaps fail publication', publish(10100, 2), 1644)
    query(f'DELETE FROM chart_item WHERE snapshot_id={uid(10100)} AND position=3')
    query(publish(10100, 1))
    query(f"UPDATE chart_publication SET snapshot_id={uid(10100)} WHERE brand='TJ' AND period='MONTHLY'")
    value('leading zeros and non-100 item count preserved', f'SELECT number FROM chart_item WHERE snapshot_id={uid(10100)}', '00001')
    reject('published chart cannot change', f'UPDATE chart_snapshot SET item_count=2 WHERE id={uid(10100)}', 1644)
    reject('published chart cannot accept rows', chart_item(10100, 2, '2'), 1644)
    reject('published item cannot change', f"UPDATE chart_item SET title='changed' WHERE snapshot_id={uid(10100)}", 1644)
    reject('published item cannot be deleted', f'DELETE FROM chart_item WHERE snapshot_id={uid(10100)}', 1644)
    reject('current chart cannot be deleted', f'DELETE FROM chart_snapshot WHERE id={uid(10100)}', 1451)
    reject('published chart cannot cross scopes', f"UPDATE chart_publication SET snapshot_id={uid(10100)} WHERE brand='KY' AND period='MONTHLY'", 1452)
    reject('failure cannot clear last good chart', "UPDATE chart_publication SET snapshot_id=NULL WHERE brand='TJ' AND period='MONTHLY'", 1644)
    query(chart(10101, 2))
    query(chart_item(10101, 1, '2'))
    query(chart_item(10101, 2, '1'))
    current_chart = "SELECT GROUP_CONCAT(i.number ORDER BY i.position) FROM chart_publication p JOIN chart_item i ON i.snapshot_id=p.snapshot_id WHERE p.brand='TJ' AND p.period='MONTHLY'"
    with ThreadPoolExecutor(max_workers=2) as pool:
        writer = pool.submit(query, 'START TRANSACTION; ' + publish(10101, 2) + '; '
                             f"UPDATE chart_publication SET snapshot_id={uid(10101)} WHERE brand='TJ' AND period='MONTHLY'; "
                             "SELECT GET_LOCK('p0407_chart',0); SELECT SLEEP(3); COMMIT;")
        wait_for_lock('p0407_chart')
        value('reader sees old whole chart during publish', current_chart, '00001')
        writer.result()
    value('reader sees new whole ordered chart after commit', current_chart, '2,1')
    reject('revision cannot move backwards', f"UPDATE chart_publication SET snapshot_id={uid(10100)} WHERE brand='TJ' AND period='MONTHLY'", 1644)
    value('other periods untouched', "SELECT COUNT(*) FROM chart_publication WHERE snapshot_id IS NULL", '5')
    query(chart(10105, period="'DAILY'", source_url="'https://api.manana.kr/karaoke/popular/tj/daily.json'"))
    query(chart_item(10105, 1, '1', period="'DAILY'"))
    with ThreadPoolExecutor(max_workers=2) as pool:
        outdated = pool.submit(query, 'SET TRANSACTION ISOLATION LEVEL REPEATABLE READ; START TRANSACTION; '
                               f'SELECT COUNT(*) FROM chart_item WHERE snapshot_id={uid(10105)}; '
                               "SELECT GET_LOCK('p0407_old_chart_view',0); SELECT SLEEP(3); " + publish(10105, 1), 1644)
        wait_for_lock('p0407_old_chart_view')
        query(chart_item(10105, 2, '2', period="'DAILY'"))
        outdated.result()
    value('publication validates current rows not an old read view', f'SELECT state,item_count FROM chart_snapshot WHERE id={uid(10105)}', 'STAGING\t0')

    query(header(10200))
    value('reservation charged', 'SELECT reserved_bytes FROM snapshot_capacity WHERE id=1', '1024')
    reject('unknown snapshot owner', header(10201, user=uid(19999)), 1452)
    reject('duplicate active slot', header(10201), 1062)
    value('failed inserts do not leak reservations', 'SELECT reserved_bytes FROM snapshot_capacity WHERE id=1', '1024')
    query(header(10201, slot=1, purpose="'EXPORT'"))
    reject('third slot disallowed', header(10202, slot=2))
    reject('same op cannot create another snapshot', header(10202, user=OTHER, op_id=uid(20200)) + '; ' + header(10203, slot=1, user=OTHER, op_id=uid(20200)), 1062)
    # The preceding first statement intentionally committed; close its empty attempt.
    query(f"UPDATE snapshot_header SET status='FAILED',active_slot=NULL,reserved_bytes=0,lease_until=NULL WHERE id={uid(10202)}")
    reject('per snapshot limit 100 MiB', header(10204, user=OTHER, reserved_bytes='104857601'))
    reject('lease limited to ten minutes', header(10204, user=OTHER, lease_until='UTC_TIMESTAMP(3)+INTERVAL 11 MINUTE'))
    reject('cannot start ready', header(10204, user=OTHER, status="'READY'"), 1644)
    reject('cannot remove an active snapshot', f'DELETE FROM snapshot_header WHERE id={uid(10200)}', 1644)
    query(entry(10200))
    value('storage payload hash and UTF8 byte length derived', f'SELECT OCTET_LENGTH(payload_hash),payload_bytes=OCTET_LENGTH(CAST(payload AS CHAR CHARACTER SET utf8mb4)) FROM snapshot_entry WHERE snapshot_id={uid(10200)}', '32\t1')
    reject('ordinal unique within entity', entry(10200), 1062)
    reject('ordinal positive', entry(10200, 0))
    reject('payload object required', entry(10200, 2, payload='JSON_ARRAY()'))
    reject('public chart excluded from personal snapshot', entry(10200, 2, entity="'CHART_ITEM'"))
    reject('authentication secret entity excluded', entry(10200, 2, entity="'AUTH_SESSION'"))
    reject('stale attempt rejected', entry(10200, 2, attempt_id=uid(39999)), 1644)
    reject('payload rows not mutable', f"UPDATE snapshot_entry SET payload=JSON_OBJECT() WHERE snapshot_id={uid(10200)}", 1644)
    query(capture(10200))
    reject('read view cursor cannot change within attempt', f'UPDATE snapshot_header SET snapshot_cursor=8 WHERE id={uid(10200)}', 1644)
    reject('restart cannot keep old partial rows', f'UPDATE snapshot_header SET attempt_id={uid(39999)},attempt_count=2,snapshot_cursor=NULL,captured_at=NULL WHERE id={uid(10200)}', 1644)
    query(entry(10200, 3))
    reject('ordinal gaps prevent ready', ready(10200), 1644)
    query(f'DELETE FROM snapshot_entry WHERE snapshot_id={uid(10200)} AND ordinal=3')
    reject('wrong ready counts rejected', f"UPDATE snapshot_header SET status='READY',row_count=9,byte_count=999,ready_at=UTC_TIMESTAMP(3),expires_at=UTC_TIMESTAMP(3)+INTERVAL 30 MINUTE,manifest_hash=REPEAT('a',64),lease_until=NULL WHERE id={uid(10200)}", 1644)
    query(ready(10200))
    value('ready TTL exactly 30 minutes', f'SELECT TIMESTAMPDIFF(SECOND,ready_at,expires_at) FROM snapshot_header WHERE id={uid(10200)}', '1800')
    reject('ready expiry cannot extend', f'UPDATE snapshot_header SET expires_at=expires_at+INTERVAL 1 MINUTE WHERE id={uid(10200)}', 1644)
    reject('ready payload immutable', entry(10200, 2), 1644)
    reject('ready rows cannot disappear', f'DELETE FROM snapshot_entry WHERE snapshot_id={uid(10200)}', 1644)
    reject('ready cannot reopen building', f"UPDATE snapshot_header SET status='BUILDING' WHERE id={uid(10200)}", 1644)
    value('request predicate rejects expiry exactly', f'SELECT COUNT(*) FROM snapshot_header WHERE id={uid(10200)} AND status=\'READY\' AND expires_at>expires_at', '0')
    value('request predicate accepts one millisecond before expiry', f"SELECT COUNT(*) FROM snapshot_header WHERE id={uid(10200)} AND status='READY' AND expires_at>expires_at-INTERVAL 1000 MICROSECOND", '1')
    value('owner predicate hides other account snapshot', f'SELECT COUNT(*) FROM snapshot_header WHERE id={uid(10200)} AND user_id={OTHER}', '0')

    export_insert = f'INSERT INTO export_session(export_id,user_id,snapshot_id,include_trash) VALUES({uid(10300)},{U},{uid(10201)},1)'
    reject('export cannot attach another account', f'INSERT INTO export_session(export_id,user_id,snapshot_id,include_trash) VALUES({uid(10301)},{OTHER},{uid(10201)},1)', 1452)
    reject('export cannot attach sync snapshot', f'INSERT INTO export_session(export_id,user_id,snapshot_id,include_trash) VALUES({uid(10301)},{U},{uid(10200)},1)', 1452)
    query(export_insert)
    reject('export scope immutable', f'UPDATE export_session SET include_trash=0 WHERE export_id={uid(10300)}', 1644)
    query(entry(10201))
    value('building counters follow stored entries', f'SELECT row_count,byte_count>0 FROM snapshot_header WHERE id={uid(10201)}', '1\t1')
    reject('must reserve bytes before storing them', entry(10201, 2, payload="JSON_OBJECT('large',REPEAT('x',1024))"), 1644)
    query(f'DELETE FROM snapshot_entry WHERE snapshot_id={uid(10201)}')
    value('discarding partial rows resets counters', f'SELECT row_count,byte_count FROM snapshot_header WHERE id={uid(10201)}', '0\t0')
    query(f'UPDATE snapshot_header SET attempt_id={uid(39998)},attempt_count=2,snapshot_cursor=NULL,captured_at=NULL,row_count=0,byte_count=0,build_started_at=UTC_TIMESTAMP(3),lease_until=UTC_TIMESTAMP(3)+INTERVAL 5 MINUTE WHERE id={uid(10201)}')
    reject('previous worker cannot append after restart', entry(10201), 1644)
    query(entry(10201, attempt_id=uid(39998)))
    query(capture(10201))
    query(ready(10201))
    value('export uses exact header TTL not another clock', f'SELECT status,TIMESTAMPDIFF(SECOND,ready_at,expires_at) FROM export_session_state WHERE export_id={uid(10300)}', 'READY\t1800')

    # All source SELECTs share a nonlocking read view, even as another writer commits.
    with ThreadPoolExecutor(max_workers=2) as pool:
        reader = pool.submit(query, 'SET TRANSACTION ISOLATION LEVEL REPEATABLE READ; START TRANSACTION WITH CONSISTENT SNAPSHOT; '
                             f'SELECT last_change_seq FROM user_sync_state WHERE user_id={U}; '
                             "SELECT GET_LOCK('p0407_read_view',0); SELECT SLEEP(3); "
                             f'SELECT title FROM song WHERE id={SONG}; SELECT last_change_seq FROM user_sync_state WHERE user_id={U}; COMMIT;')
        wait_for_lock('p0407_read_view')
        query(f"START TRANSACTION; UPDATE user_sync_state SET last_change_seq=8 WHERE user_id={U}; UPDATE song SET title='after' WHERE id={SONG}; COMMIT;")
        output = reader.result()
    assert output.splitlines() == ['7', '1', '0', 'before', '7'], output
    value('same read view keeps source rows and cursor together', 'SELECT 1', '1')
    value('later view observes new source and cursor', f'SELECT title,(SELECT last_change_seq FROM user_sync_state WHERE user_id={U}) FROM song WHERE id={SONG}', 'after\t8')
    query(f"UPDATE app_user SET status='DELETING' WHERE id={U}")
    value('active-account access predicate blocks snapshots after deletion', f"SELECT COUNT(*) FROM snapshot_header h JOIN app_user u ON u.id=h.user_id WHERE h.id={uid(10200)} AND h.status='READY' AND u.status='ACTIVE' AND h.expires_at>UTC_TIMESTAMP(3)", '0')
    reject('cannot release bytes while payload remains', f"UPDATE snapshot_header SET status='EXPIRED',active_slot=NULL,reserved_bytes=0 WHERE id={uid(10200)}")
    query(f"UPDATE snapshot_header SET status='EXPIRED',active_slot=NULL WHERE user_id={U}")
    value('expired payload retains its capacity until cleanup', 'SELECT reserved_bytes FROM snapshot_capacity WHERE id=1', '2048')
    query(f'DELETE FROM snapshot_header WHERE id={uid(10201)}')
    value('expired cleanup cascades only materialized rows and export session', f'SELECT (SELECT COUNT(*) FROM snapshot_entry WHERE snapshot_id={uid(10201)})+(SELECT COUNT(*) FROM export_session WHERE export_id={uid(10300)})', '0')
    value('cleanup preserves actual source', f'SELECT title FROM song WHERE id={SONG}', 'after')
    reject('expired snapshot cannot revive', f"UPDATE snapshot_header SET status='READY' WHERE id={uid(10200)}", 1644)
    value('one cleaned snapshot refunds only its own capacity', 'SELECT reserved_bytes FROM snapshot_capacity WHERE id=1', '1024')
    query(f'DELETE FROM snapshot_header WHERE id={uid(10200)}')
    value('all cleaned payload capacity refunded', 'SELECT reserved_bytes FROM snapshot_capacity WHERE id=1', '0')

    # Reserve 900 MiB, then race two 100 MiB reservations for the remaining slot.
    for offset in range(11):
        query(f'INSERT INTO app_user(id) VALUES({uid(11000+offset)})')
    for offset in range(9):
        query(header(11100+offset, user=uid(11000+offset), reserved_bytes='104857600'))
    with ThreadPoolExecutor(max_workers=2) as pool:
        first = pool.submit(query, 'START TRANSACTION; ' + header(11109, user=uid(11009), reserved_bytes='104857600')
                            + "; SELECT GET_LOCK('p0407_capacity',0); SELECT SLEEP(3); COMMIT;")
        wait_for_lock('p0407_capacity')
        second = pool.submit(query, header(11110, user=uid(11010), reserved_bytes='104857600'), 3819)
        first.result()
        second.result()
    value('racing reservation cannot exceed global 1 GiB', 'SELECT reserved_bytes FROM snapshot_capacity WHERE id=1', '1048576000')
    value('losing reservation left no header', f'SELECT COUNT(*) FROM snapshot_header WHERE id={uid(11110)}', '0')
    query("UPDATE snapshot_header SET status='FAILED',active_slot=NULL,reserved_bytes=0,lease_until=NULL WHERE status='BUILDING'")
    value('failed attempts release capacity', 'SELECT reserved_bytes FROM snapshot_capacity WHERE id=1', '0')
    value('chart publication created no personal change log', f'SELECT COUNT(*) FROM change_log WHERE user_id IN ({U},{OTHER})', '0')
    print(f'P04-07 charts and snapshots: {checks} checks passed.', flush=True)


if __name__ == '__main__':
    if os.environ.get('P04_DISPOSABLE_DB') != '1':
        raise SystemExit('Use a disposable DB and set P04_DISPOSABLE_DB=1; never run on user data.')
    if '--seed-upgrade' in sys.argv:
        seed_upgrade()
    else:
        main()
