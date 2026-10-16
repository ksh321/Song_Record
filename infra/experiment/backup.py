"""Independent experiment backup. Reuses authenticated backup/ledger format, not laptop state."""
import base64
import datetime as dt
import json
import os
from pathlib import Path
import subprocess
import sys
import threading

ROOT = Path('/opt/song-record-experiment/operations')
DIRECTORY = ROOT/'backup'
sys.path.insert(0, str(ROOT/'modules'))
from backup_store import BackupError, EncryptedStore, R2, MAX_BYTES
from operational_backup import Backup
from backup_ledger import Ledger, subject
from observe import atomic, operator
from execution_lock import execution_lock

BUCKET = 'song-record-experiment-backup'
TARGET = 'song-record-experiment-mysql-1'
DATABASE = 'song_record_experiment'
STAGE = 'START'


def source_transport(vault=Path('/etc/song-record-experiment')):
    marker=vault/'application-storage.json'
    if marker.exists():
        if json.loads(marker.read_text())!={'scope':'experiment','final_bucket':'song-record-experiment-final'}:
            raise BackupError('EXPERIMENT_SOURCE_SCOPE_REJECTED')
        row=json.loads((vault/'r2-experiment.json').read_text())
        if row.get('scope')!='song_record_experiment_application:v1' or set(row.get('roles',{}))!={'experiment.api','experiment.worker','experiment.playback'}:
            raise BackupError('EXPERIMENT_SOURCE_SCOPE_REJECTED')
        reader=row['roles']['experiment.playback']
        return R2(reader['access'],reader['secret'],'song-record-experiment-final')
    roles=json.loads((vault/'r2-staging.json').read_text())
    reader=roles['staging.playback']
    return R2(reader['access'],reader['secret'],'song-record-staging-dev-final')


def credentials():
    row = json.loads(Path('/etc/song-record-experiment/backup-experiment.json').read_text())
    if row.get('scope') != 'song_record_experiment_backup:v1' or row.get('bucket') != BUCKET:
        raise BackupError('EXPERIMENT_BACKUP_SCOPE_REJECTED')
    key = base64.b64decode(row['master'], validate=True)
    envelope = base64.b64decode(row['recovery'], validate=True)
    if len(key) != 32 or len(envelope) != 84 or not envelope.startswith(b'SRR1'):
        raise BackupError('EXPERIMENT_BACKUP_KEY_INVALID')
    return row, key, envelope


def bounded(args, limit=MAX_BYTES, data=None, timeout=30):
    process = subprocess.Popen(args, stdin=subprocess.PIPE if data is not None else subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    timer = threading.Timer(timeout, process.kill); timer.start()
    try:
        if data is not None:
            process.stdin.write(data); process.stdin.close()
        result = process.stdout.read(limit+1)
        if len(result) > limit or process.wait(timeout=3) != 0:
            raise BackupError('EXPERIMENT_BACKUP_COMMAND_FAILED')
        return result
    finally:
        timer.cancel()
        if process.poll() is None: process.kill()
        process.wait(); process.stdout.close()


def snapshot():
    global STAGE
    STAGE = 'DATABASE_SNAPSHOT'
    scope = bounded(['docker','inspect','--format','{{ index .Config.Labels "com.docker.compose.project" }}',TARGET],256).strip()
    if scope != b'song-record-experiment': raise BackupError('EXPERIMENT_DATABASE_SCOPE_REJECTED')
    config = '/run/runtime/experiment-backup-client.cnf'
    bounded(['docker','exec','-u','0',TARGET,'sh','-c',
             'umask 077; printf "[client]\\nuser=root\\npassword=%s\\n" "$(cat /run/runtime/root-password)" > /run/runtime/experiment-backup-client.cnf'],256)
    mysql = ['docker','exec','-i','-u','0',TARGET,'mysql','--defaults-extra-file='+config,
             '--batch','--raw','--skip-column-names','--unbuffered',DATABASE]
    lock = None; watchdog = None
    try:
        lock = subprocess.Popen(mysql,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
        watchdog = threading.Timer(30,lock.kill);watchdog.start()
        lock.stdin.write(b"SET SESSION lock_wait_timeout=5; SET SESSION wait_timeout=30; FLUSH TABLES WITH READ LOCK; SELECT 'LOCKED';\n");lock.stdin.flush()
        if lock.stdout.readline(32).strip() != b'LOCKED':raise BackupError('SNAPSHOT_LOCK_UNAVAILABLE')
        sql = b"SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='song_record_experiment' AND table_type='BASE TABLE' AND engine<>'InnoDB';\n"
        if bounded(mysql,256,sql,8).strip() != b'0':raise BackupError('NONTRANSACTIONAL_DB_TABLE')
        if bounded(mysql,256,b"SELECT COUNT(*) FROM app_user WHERE status='DELETING';\n",8).strip() != b'0':raise BackupError('BACKUP_ACCOUNT_PURGE_PENDING')
        subjects = bounded(mysql,4*1024*1024,b'SELECT BIN_TO_UUID(id) FROM app_user ORDER BY id;\n',8).decode('ascii').splitlines()
        raw = bounded(mysql,32*1024*1024,b"SELECT BIN_TO_UUID(a.user_id),BIN_TO_UUID(a.recording_id),BIN_TO_UUID(a.generation),a.object_key,a.sha256,a.verified_size FROM recording_asset a WHERE a.cloud_state IN ('STORED','DELETING') ORDER BY a.recording_id;\n",8)
        files=[]
        for line in raw.decode().splitlines():
            owner,recording,generation,key,sha,size=line.split('\t')
            files.append(dict(owner=owner,recording=recording,generation=generation,key=key,sha256=sha,size=int(size)))
        dump = bounded(['docker','exec','-u','0',TARGET,'mysqldump','--defaults-extra-file='+config,
                        '--single-transaction','--skip-lock-tables','--hex-blob','--no-tablespaces',
                        '--set-gtid-purged=OFF','--routines','--triggers','--events',DATABASE],timeout=20)
        if lock.poll() is not None:raise BackupError('SNAPSHOT_LOCK_EXPIRED')
        lock.stdin.write(b'UNLOCK TABLES;\n');lock.stdin.close()
        if lock.wait(timeout=3) != 0:raise BackupError('SNAPSHOT_LOCK_RELEASE_FAILED')
        return dump,files,subjects
    finally:
        if watchdog:watchdog.cancel()
        if lock:
            if lock.poll() is None:lock.kill()
            lock.wait();lock.stdout.close()
        bounded(['docker','exec','-u','0',TARGET,'rm','-f',config],256,timeout=8)


def mirror_ledger(store, instance, source=None):
    source = json.loads(operator('BackupLedgerOperator', action='snapshot')) if source is None else source
    ledger = Ledger(store, instance)
    rows = ledger.merge(source['entries'])
    listed = store.transport.list_objects('operational/v1/')
    if store.get('operational/v1/catalog.enc') is None:
        allowed={'operational/v1/deletion-ledger.enc','operational/v1/recovery-key.enc'}
        if any(row['key'] not in allowed for row in listed):raise BackupError('BACKUP_UNKNOWN_ARTIFACTS')
    cleanup = ledger.prune(dt.datetime.now(dt.timezone.utc), listed)
    remote = {subject(row):row for row in rows}; ack=[]
    for pending in source['pending']:
        key=(pending['owner'],pending['type'],pending['entity'],pending.get('generation') or None)
        value=remote.get(key)
        if value is None or value['revision'] < pending['revision']:raise BackupError('BACKUP_LEDGER_ACK_CONFLICT')
        ack.append({'id':pending['id'],'revision':pending['revision'],'absent':pending['owner'] in cleanup['absent_owners']})
    if ack:
        result=operator('BackupLedgerOperator',json.dumps(ack).encode(),action='ack').strip()
        if result != ('BACKUP_LEDGER_ACK='+str(len(ack))).encode():raise BackupError('BACKUP_LEDGER_ACK_INVALID')
    if cleanup.get('unknown_artifacts',False):raise BackupError('BACKUP_UNKNOWN_ARTIFACTS')
    return {'status':'PASS','observed_utc':dt.datetime.now(dt.timezone.utc).isoformat(),
            'entries':len(rows),'acknowledged':len(ack)}


def once():
    global STAGE
    if os.getuid() != 0:raise BackupError('ROOT_REQUIRED')
    os.umask(0o077);DIRECTORY.mkdir(mode=0o700,exist_ok=True)
    with execution_lock(DIRECTORY/'execution.lock'):
        STAGE='CREDENTIAL_SCOPE';row,key,envelope=credentials()
        transport=R2(row['access'],row['secret'],BUCKET)
        STAGE='RECOVERY_ENVELOPE'
        if transport.get('operational/v1/recovery-key.enc') != envelope:
            transport.put_verified('operational/v1/recovery-key.enc',envelope)
        store=EncryptedStore(transport,key)
        STAGE='LEDGER_MIRROR';atomic(DIRECTORY/'ledger-latest.json',mirror_ledger(store,row['instance']))
        source=source_transport()
        STAGE='BACKUP_POINT';backup=Backup(store,source,snapshot,row['instance'],require_ledger=True);result=backup.once()
        point=max(backup.catalog()['points'],key=lambda item:item['day'])
        created=backup.verify(point)['created_utc']
        result.update(observed_utc=dt.datetime.now(dt.timezone.utc).isoformat(),source_database=DATABASE,
                      data_created_utc=created,encrypted=True,source_deletion=False,restore_verified=False)
        atomic(DIRECTORY/'latest.json',result)
        return result


if __name__=='__main__':
    try:print(json.dumps(once()))
    except Exception as error:
        try:atomic(DIRECTORY/'failure.json',{'status':'FAIL','observed_utc':dt.datetime.now(dt.timezone.utc).isoformat(),'diagnostic':'EXPERIMENT_BACKUP_UNCONFIRMED','stage':STAGE,'category':type(error).__name__})
        except Exception:pass
        print('EXPERIMENT_BACKUP_UNCONFIRMED: values suppressed');raise SystemExit(2)
