"""Restore only into a new disposable database, reapply independent ledger, verify referenced audio."""
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import tempfile
import time
import uuid
from backup import credentials, bounded, DIRECTORY, TARGET
from backup_store import BackupError, R2, EncryptedStore
from operational_backup import Backup, PREFIX, check_file
from backup_ledger import Ledger
from backup_overlay import statements
from observe import atomic, operator
STAGE = 'START'


def require_scope(database, user):
    if not re.fullmatch(r'song_record_restore_[0-9a-f]{32}', database) or not re.fullmatch(r'sr_restore_[0-9a-f]{16}', user):
        raise BackupError('RESTORE_DATABASE_SCOPE_REJECTED')


def scoped_dump(raw):
    lines=[]
    for line in raw.splitlines(keepends=True):
        if re.match(rb'^\s*(USE\b|CREATE\s+DATABASE\b)',line,re.I):
            raise BackupError('RESTORE_DATABASE_SCOPE_REJECTED')
        if line.lstrip().startswith(b'/*!') or re.match(rb'^\s*CREATE\b',line,re.I):
            line=re.sub(rb'DEFINER=`[^`]*`@`[^`]*`',b'',line)
        lines.append(line)
    return b''.join(lines)


def cleanup_created(database, user, root_mysql, database_created, user_created):
    """Only names freshly created by this invocation; never discover or reuse databases."""
    require_scope(database,user)
    sql=[]
    if database_created:sql.append(f'DROP DATABASE `{database}`;')
    if user_created:sql.append(f"DROP USER '{user}'@'%';")
    if sql:bounded(root_mysql,data='\n'.join(sql).encode(),timeout=20)


def once():
    from execution_lock import execution_lock
    global STAGE
    if os.getuid()!=0:raise BackupError('ROOT_REQUIRED')
    os.umask(0o077);DIRECTORY.mkdir(mode=0o700,exist_ok=True)
    with execution_lock(DIRECTORY/'execution.lock'):
        started=time.monotonic();now=dt.datetime.now(dt.timezone.utc)
        STAGE='CREDENTIAL_SCOPE';row,key,_=credentials();store=EncryptedStore(R2(row['access'],row['secret'],row['bucket']),key)
        backup=Backup(store,None,None,row['instance'],require_ledger=True)
        catalog=backup.catalog()
        if not catalog['points']:raise BackupError('RESTORE_POINT_UNAVAILABLE')
        STAGE='POINT_VERIFY';point=max(catalog['points'],key=lambda p:p['day']);manifest=backup.verify(point)
        at=dt.datetime.fromisoformat(manifest['created_utc']);rpo=(now-at).total_seconds()
        if rpo<0:raise BackupError('RESTORE_POINT_TIME_INVALID')
        ledger=Ledger(store,row['instance']);entries=ledger.read();files=ledger.require_restore(manifest['files'])
        sql=store.get(PREFIX+'points/'+point['id']+'/database.enc')
        if sql is None or hashlib.sha256(sql).hexdigest()!=manifest['database_sha256']:raise BackupError('RESTORE_DATABASE_HASH')
        scope=bounded(['docker','inspect','--format','{{ index .Config.Labels "com.docker.compose.project" }}',TARGET],256).strip()
        if scope!=b'song-record-experiment':raise BackupError('EXPERIMENT_DATABASE_SCOPE_REJECTED')
        run=uuid.uuid4().hex;database='song_record_restore_'+run;user='sr_restore_'+run[:16]
        require_scope(database,user);password=secrets.token_urlsafe(32)
        directory=DIRECTORY/'restore'/run;directory.mkdir(mode=0o700,parents=True)
        root_config='/run/runtime/restore-root-'+run+'.cnf';user_config='/run/runtime/restore-user-'+run+'.cnf'
        bounded(['docker','exec','-u','0',TARGET,'sh','-c',
                 'umask 077; printf "[client]\\nuser=root\\npassword=%s\\n" "$(cat /run/runtime/root-password)" > '+root_config],256)
        root_mysql=['docker','exec','-i','-u','0',TARGET,'mysql','--defaults-extra-file='+root_config]
        database_created=False;user_created=False
        try:
            STAGE='NEW_RESTORE_DATABASE'
            bounded(root_mysql,data=f'CREATE DATABASE `{database}`;'.encode(),timeout=20);database_created=True
            bounded(root_mysql,data=f"CREATE USER '{user}'@'%' IDENTIFIED BY '{password}';".encode(),timeout=20);user_created=True
            bounded(root_mysql,data=f"GRANT ALL PRIVILEGES ON `{database}`.* TO '{user}'@'%';".encode(),timeout=20)
            scoped={'database':database,'user':user,'password':password}
            atomic(directory/'credentials.json',scoped)
            atomic(directory/'scope.json',{'database':database,'source':'song_record_experiment','disposable':True})
            bounded(['docker','exec','-i','-u','0',TARGET,'sh','-c','umask 077; cat > '+user_config],256,
                    f'[client]\nuser={user}\npassword={password}\n'.encode())
            mysql=['docker','exec','-i','-u','0',TARGET,'mysql','--defaults-extra-file='+user_config,'--binary-mode=1','--batch','--skip-column-names',database]
            STAGE='DATABASE_IMPORT';bounded(mysql,data=scoped_dump(sql),timeout=120)
            payload='\n'.join(f'{k}={scoped[k]}' for k in ('database','user','password')).encode()
            STAGE='SCHEMA_MIGRATE';operator('RestoreValidationOperator',payload,action='migrate')
            STAGE='DELETION_OVERLAY';tables=json.loads(operator('RestoreValidationOperator',payload,action='metadata'))
            bounded(mysql,data=statements(database,tables,entries),timeout=120)
            restored=json.loads(operator('RestoreValidationOperator',payload,action='check'))
            identity=lambda rows:{(r['owner'],r['recording'],r['generation'],r['sha256'],r['size']) for r in rows}
            if identity(restored['files'])!=identity(files):raise BackupError('RESTORE_DATABASE_FILE_LIST')
            STAGE='FILE_HASH_AND_DECODE';verified=0
            with tempfile.TemporaryDirectory(prefix='song-record-restore-',dir='/dev/shm') as audio_dir:
                for file in files:
                    data=store.get(check_file(file))
                    if data is None or len(data)!=file['size'] or hashlib.sha256(data).hexdigest()!=file['sha256']:raise BackupError('RESTORE_FILE_HASH')
                    path=Path(audio_dir)/(str(verified)+'.m4a');path.write_bytes(data)
                    try:
                        name='song-record-experiment-restore-audio-'+run[:12]
                        args=['docker','run','--rm','--name',name,'--user','0:0','--network','none','--read-only','--cap-drop','ALL',
                              '--security-opt','no-new-privileges:true','--memory','128m','--cpus','0.25',
                              '--mount','type=bind,src='+str(path)+',dst=/audio.m4a,readonly',
                              '--entrypoint','ffmpeg','song-record-validation-api:p25-06-experiment',
                              '-v','error','-i','/audio.m4a','-f','null','-']
                        try:bounded(args,256,timeout=30);verified+=1
                        finally:subprocess.run(['docker','stop','--time','3',name],capture_output=True,timeout=10)
                    finally:path.unlink(missing_ok=True)
            if ledger.read()!=entries:raise BackupError('RESTORE_LEDGER_CHANGED_RETRY_REQUIRED')
            result={'status':'PASS','run_id':run,'observed_utc':now.isoformat(),'rpo_seconds':round(rpo,3),
                    'data_restore_rto_seconds':round(time.monotonic()-started,3),'restored_users':restored['users'],
                    'restored_recordings':restored['recordings'],'verified_audio_files':verified,
                    'physical_playback':'NOT_EXERCISED','live_database_replaced':False,'release_ready':False,
                    'goal_seconds':86400,'rpo_goal_met':rpo<=86400,'data_restore_rto_goal_met':time.monotonic()-started<=86400}
        finally:
            try:
                cleanup_created(database,user,root_mysql,database_created,user_created)
                (directory/'credentials.json').unlink(missing_ok=True)
                atomic(directory/'cleanup.json',{'status':'PASS','fresh_restore_copy_removed':True,'live_database_modified':False})
            finally:
                bounded(['docker','exec','-u','0',TARGET,'rm','-f',root_config,user_config],256,timeout=8)
        result['disposable_copy_removed']=True
        atomic(directory/'result.json',result);atomic(DIRECTORY/'restore-latest.json',result)
        return result


if __name__=='__main__':
    try:print(json.dumps(once()))
    except Exception as error:
        try:atomic(DIRECTORY/'restore-failure.json',{'status':'FAIL','observed_utc':dt.datetime.now(dt.timezone.utc).isoformat(),'diagnostic':'EXPERIMENT_RESTORE_UNCONFIRMED','stage':STAGE,'category':type(error).__name__})
        except Exception:pass
        print('EXPERIMENT_RESTORE_UNCONFIRMED: values suppressed');raise SystemExit(2)
