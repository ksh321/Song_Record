"""Native independent deletion mirror; fixed experiment DB, no source audio access."""
import datetime as dt
import hashlib
import json
import os
from backup import credentials, DIRECTORY, mirror_ledger
from backup_store import R2,EncryptedStore
from observe import operator,atomic


def once():
    import fcntl
    if os.getuid()!=0:raise ValueError('ROOT_REQUIRED')
    os.umask(0o077);DIRECTORY.mkdir(mode=0o700,exist_ok=True)
    with (DIRECTORY/'execution.lock').open('a+b') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        now=dt.datetime.now(dt.timezone.utc)
        source=json.loads(operator('BackupLedgerOperator',action='snapshot'))
        fingerprint=hashlib.sha256(json.dumps(source,sort_keys=True).encode()).hexdigest()
        path=DIRECTORY/'ledger-latest.json'
        try:previous=json.loads(path.read_text())
        except (OSError,ValueError):previous={}
        try:last=dt.datetime.fromisoformat(previous.get('full_verified_utc',''))
        except (ValueError,TypeError):last=None
        if previous.get('status')=='PASS' and previous.get('source_sha256')==fingerprint and last and dt.timedelta(0)<=now-last<dt.timedelta(hours=1) and not source['pending']:
            result=dict(previous,observed_utc=now.isoformat(),unchanged_remote_reused=True)
        else:
            row,key,_=credentials();store=EncryptedStore(R2(row['access'],row['secret'],row['bucket']),key)
            result=mirror_ledger(store,row['instance'],source)
            result.update(source_sha256=fingerprint,full_verified_utc=now.isoformat(),unchanged_remote_reused=False)
        atomic(path,result)
        return {k:result[k] for k in ['status','observed_utc','entries','acknowledged','unchanged_remote_reused']}


if __name__=='__main__':
    try:print(json.dumps(once()))
    except BlockingIOError:print(json.dumps({'status':'BUSY','diagnostic':'EXISTING_BACKUP_OR_RESTORE_OWNS_LOCK'}))
    except Exception:
        try:atomic(DIRECTORY/'ledger-failure.json',{'status':'FAIL','observed_utc':dt.datetime.now(dt.timezone.utc).isoformat(),'diagnostic':'EXPERIMENT_LEDGER_UNCONFIRMED'})
        except Exception:pass
        print('EXPERIMENT_LEDGER_UNCONFIRMED: values suppressed');raise SystemExit(2)
