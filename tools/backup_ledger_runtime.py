"""Non-AI five-second DB outbox -> encrypted remote fence -> exact revision acknowledgement."""
import datetime as dt
import json
import os
import time
from pathlib import Path
import validation_runtime as runtime
from backup_store import R2, BACKUP_BUCKET, EncryptedStore, BackupError
from backup_credentials import encryption_key
from backup_ledger import Ledger, subject
from r2_vault import load, _secure
from manual_usage import RunLock, atomic_json

DIRECTORY=Path(__file__).resolve().parents[1]/'.local/workflow/backup-ledger'


def operator(action, data=None):
    target=runtime.containers()['api']
    if not target:raise BackupError('BACKUP_LEDGER_DB_UNAVAILABLE')
    args=['docker','exec']+(['-i'] if data is not None else [])+[target,'java','-Dloader.main=com.ksh321.songrecord.api.operations.BackupLedgerOperator','-cp','/app/api.jar','org.springframework.boot.loader.launch.PropertiesLauncher',action]
    raw=runtime.run(args,**({'input':data} if data is not None else {}))
    if len(raw)>32*1024*1024:raise BackupError('BACKUP_LEDGER_SIZE_LIMIT')
    return raw


def once(source=None):
    _secure(DIRECTORY)
    with RunLock(DIRECTORY.parent/'backup/execution.lock'):
        try:
            source=source or json.loads(operator('snapshot'))
            ledger=Ledger(EncryptedStore(R2(*load('staging.backup'),BACKUP_BUCKET),encryption_key()),runtime.state()['instance_id'])
            rows=ledger.merge(source['entries'])
            now=dt.datetime.now(dt.timezone.utc)
            listed=ledger.store.transport.list_objects('operational/v1/')
            cleanup=ledger.prune(now,listed)
            remote={subject(row):row for row in rows};ack=[]
            for pending in source['pending']:
                key=(pending['owner'],pending['type'],pending['entity'],pending.get('generation') or None)
                value=remote.get(key)
                if value is None or value['revision']<pending['revision']:raise BackupError('BACKUP_LEDGER_ACK_CONFLICT')
                ack.append({'id':pending['id'],'revision':pending['revision'],'absent':pending['owner'] in cleanup['absent_owners']})
            acknowledged=0
            if ack:
                response=operator('ack',json.dumps(ack).encode()).strip()
                if not response.startswith(b'BACKUP_LEDGER_ACK='):raise BackupError('BACKUP_LEDGER_ACK_INVALID')
                acknowledged=int(response.split(b'=')[1])
                if not 0<=acknowledged<=len(ack):raise BackupError('BACKUP_LEDGER_ACK_INVALID')
            canonical_owners={row['owner'] for row in source['entries'] if row.get('origin')=='ledger'}
            retired=[row['owner'] for row in rows if row['type']=='USER' and row['state']=='COMMITTED' and row['owner'] in cleanup['absent_owners'] and row['owner'] not in canonical_owners and now-dt.datetime.fromisoformat(row['at'])>=dt.timedelta(days=30)]
            if retired:
                operator('retire',json.dumps(retired).encode())
                ledger.retire_owners(retired,now,cleanup['absent_owners'])
            result={'status':'UNCONFIRMED' if cleanup['unknown_artifacts'] else 'PASS','entries':len(rows),'acknowledged':acknowledged,
                    'removed_points':cleanup['removed_points'],'removed_files':cleanup['removed_files'],
                    'unknown_artifacts':cleanup['unknown_artifacts'],'observed_utc':dt.datetime.now(dt.timezone.utc).isoformat(),'values_logged':False}
            atomic_json(DIRECTORY/'latest.json',result);atomic_json(DIRECTORY/'status.json',result)
            return result
        except Exception:
            atomic_json(DIRECTORY/'status.json',{'status':'FAIL','code':'BACKUP_LEDGER_UNCONFIRMED','observed_utc':dt.datetime.now(dt.timezone.utc).isoformat()})
            raise BackupError('BACKUP_LEDGER_UNCONFIRMED') from None


def watch():
    _secure(DIRECTORY)
    with RunLock(DIRECTORY/'watch.lock'):
        atomic_json(DIRECTORY/'process.json',{'pid':os.getpid(),'interval_seconds':30,'pending_ack_interval_seconds':5,'ai_calls':False})
        last=None;checked=0;failures=0
        while True:
            try:
                source=json.loads(operator('snapshot'))
                raw=json.dumps(source,sort_keys=True)
                if raw!=last or time.monotonic()-checked>=3600:
                    once(source);last=raw;checked=time.monotonic()
                failures=0
            except Exception:failures=min(6,failures+1)
            pending=any(row.get('needs_ack') for row in source.get('pending',[])) if failures==0 else False
            time.sleep((5 if pending else 30) if failures==0 else min(300,5*2**failures))


if __name__=='__main__':
    import sys
    try:
        if sys.argv[1:]==['watch']:watch()
        elif sys.argv[1:]==['once']:print(json.dumps(once()))
        else:raise BackupError('BACKUP_LEDGER_ACTION_INVALID')
    except Exception:print('Backup ledger unconfirmed; values suppressed.',file=sys.stderr);sys.exit(2)
