"""V7 -> V8 session preservation checks on the disposable CI database only."""
import os
import sys

from verify_p04_extended_schema import query, uid, value, reject

USER, DEVICE, SESSION = map(uid, (606001, 606002, 606003))
HASH = "UNHEX(SHA2('p06-ci-synthetic-refresh',256))"
CREATED = "'2026-01-01 00:00:00.000'"
EXPIRES = "'2099-01-01 00:00:00.000'"


def seed():
    value('seed starts at V7',
          'SELECT MAX(CAST(version AS UNSIGNED)) FROM flyway_schema_history WHERE success=1', '7')
    query(f"INSERT INTO app_user(id) VALUES({USER});"
          f"INSERT INTO device(id,user_id,display_name,last_seen_at) "
          f"VALUES({DEVICE},{USER},'CI fixture',UTC_TIMESTAMP(3));"
          f"INSERT INTO auth_session(id,user_id,device_id,refresh_hash,expires_at,created_at) "
          f"VALUES({SESSION},{USER},{DEVICE},{HASH},{EXPIRES},{CREATED});")


def verify():
    value('all existing refresh hashes and creation times preserved',
          'SELECT COUNT(*) FROM auth_session s LEFT JOIN auth_refresh_token t '
          'ON t.token_hash=s.refresh_hash AND t.session_id=s.id '
          'AND t.created_at=s.created_at AND t.consumed_at IS NULL '
          'WHERE t.token_hash IS NULL', '0')
    value('seed session and ownership preserved',
          f'SELECT COUNT(*) FROM auth_session WHERE id={SESSION} AND user_id={USER} '
          f'AND device_id={DEVICE} AND refresh_hash={HASH} AND expires_at={EXPIRES} '
          f'AND created_at={CREATED} AND revoked_at IS NULL', '1')
    value('existing session refresh backfilled',
          f'SELECT COUNT(*) FROM auth_refresh_token WHERE session_id={SESSION} AND token_hash={HASH}', '1')
    reject('duplicate refresh hash',
           f'INSERT INTO auth_refresh_token VALUES({HASH},{SESSION},NULL,{CREATED})', 1062)
    reject('refresh requires a session',
           f"INSERT INTO auth_refresh_token VALUES(UNHEX(SHA2('orphan',256)),{uid(606099)},NULL,{CREATED})", 1452)
    reject('access requires a session',
           f'INSERT INTO auth_access_token VALUES({HASH},{uid(606099)},{EXPIRES},{CREATED})', 1452)
    reject('access expiry must follow creation',
           f'INSERT INTO auth_access_token VALUES({HASH},{SESSION},{CREATED},{CREATED})', 3819)
    query(f'INSERT INTO auth_access_token VALUES({HASH},{SESSION},{EXPIRES},{CREATED})')
    reject('duplicate access hash',
           f'INSERT INTO auth_access_token VALUES({HASH},{SESSION},{EXPIRES},{CREATED})', 1062)
    query(f'DELETE FROM auth_session WHERE id={SESSION}')
    for table in ('auth_refresh_token', 'auth_access_token'):
        value(f'{table} cascades with session',
              f'SELECT COUNT(*) FROM {table} WHERE session_id={SESSION}', '0')
    query(f'DELETE FROM device WHERE id={DEVICE}; DELETE FROM app_user WHERE id={USER}')
    print('P06-06 V8 session migration: 10 checks passed.', flush=True)


if __name__ == '__main__':
    if os.environ.get('P04_DISPOSABLE_DB') != '1':
        raise SystemExit('Requires P04_DISPOSABLE_DB=1 and a disposable database.')
    if '--seed-upgrade' in sys.argv:
        seed()
    else:
        verify()
