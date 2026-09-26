"""V8 -> V9 constraints on the disposable CI database only."""
import os
import sys
from verify_p04_extended_schema import query, uid, value, reject

U, D, S, C = map(uid, (607001, 607002, 607003, 607004))
H = "UNHEX(SHA2('p06-07-synthetic',256))"
NOW = "'2026-01-01 00:00:00.000'"
END = "'2099-01-01 00:00:00.000'"


def seed():
    value('link upgrade starts at V8', 'SELECT MAX(CAST(version AS UNSIGNED)) FROM flyway_schema_history WHERE success=1', '8')
    query(f"INSERT INTO app_user(id) VALUES({U});"
          f"INSERT INTO device(id,user_id,display_name,last_seen_at) VALUES({D},{U},'fixture',{NOW});"
          f"INSERT INTO auth_session(id,user_id,device_id,refresh_hash,expires_at,created_at) VALUES({S},{U},{D},{H},{END},{NOW});"
          f"INSERT INTO auth_refresh_token(token_hash,session_id,created_at) VALUES({H},{S},{NOW});")


def main():
    value('refresh token survives V9', f'SELECT COUNT(*) FROM auth_refresh_token WHERE token_hash={H} AND session_id={S}', '1')
    insert = (f"INSERT INTO auth_link_challenge(id,session_id,stage,provider,target_provider,nonce_hash,created_at,expires_at) "
              f"VALUES({C},{S},'REAUTH','GOOGLE','KAKAO',{H},{NOW},'2026-01-01 00:05:00.000')")
    reject('unknown provider', insert.replace("'GOOGLE'", "'UNKNOWN'"), 3819)
    reject('unknown stage', insert.replace("'REAUTH'", "'UNKNOWN'"), 3819)
    reject('expiry before creation', insert.replace("'2026-01-01 00:05:00.000'", NOW), 3819)
    reject('missing session', insert.replace(S, uid(607099)), 1452)
    query(insert)
    value('nonce stored as hash', f'SELECT OCTET_LENGTH(nonce_hash) FROM auth_link_challenge WHERE id={C}', '32')
    query(f'DELETE FROM auth_session WHERE id={S}')
    value('challenge cascades with session', f'SELECT COUNT(*) FROM auth_link_challenge WHERE id={C}', '0')
    query(f'DELETE FROM device WHERE id={D}; DELETE FROM app_user WHERE id={U}')
    print('P06-07 V9 link migration: 7 checks passed.', flush=True)


if __name__ == '__main__':
    if os.environ.get('P04_DISPOSABLE_DB') != '1':
        raise SystemExit('Requires P04_DISPOSABLE_DB=1 and a disposable database.')
    if '--seed-upgrade' in sys.argv:
        seed()
    else:
        main()
