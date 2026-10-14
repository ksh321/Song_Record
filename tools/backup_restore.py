"""Actual authenticated backup restore into a new isolated, least-privilege validation DB."""
import datetime as dt
import hashlib
import json
import os
import re
import secrets
import shutil
import subprocess
import time
import uuid
from pathlib import Path
import validation_runtime as runtime
from backup_credentials import encryption_key
from backup_store import R2, EncryptedStore, BACKUP_BUCKET, BackupError
from backup_ledger import Ledger
from backup_overlay import statements, require_database
from operational_backup import Backup, PREFIX, check_file
from backup_runtime import bounded
from r2_vault import load, _secure, _crypt
from manual_usage import atomic_json

ROOT=Path(__file__).resolve().parents[1]
DIRECTORY=ROOT/'.local/workflow/restore'


def scoped_dump(raw):
    # Only conditional DDL comments are changed. User notes in INSERT values are preserved byte-for-byte.
    lines=[]
    for line in raw.splitlines(keepends=True):
        if line.lstrip().startswith(b'/*!') or re.match(rb'^\s*CREATE\b',line,re.I):
            line=re.sub(rb'DEFINER=`[^`]*`@`[^`]*`',b'',line)
        lines.append(line)
    return b''.join(lines)


def invoke(action, credentials):
    require_database(credentials['database'])
    payload='\n'.join(f'{k}={credentials[k]}' for k in ('database','user','password')).encode()
    target=runtime.containers()['api']
    output=runtime.run(['docker','exec','-i',target,'java','-Dloader.main=com.ksh321.songrecord.api.operations.RestoreValidationOperator','-cp','/app/api.jar','org.springframework.boot.loader.launch.PropertiesLauncher',action],input=payload)
    if len(output)>32*1024*1024:raise BackupError('RESTORE_OUTPUT_LIMIT')
    return output


class Database:
    def __init__(self, directory):
        self.credentials={'database':'song_record_restore_'+uuid.uuid4().hex,'user':'sr_restore_'+uuid.uuid4().hex[:16],'password':secrets.token_urlsafe(32)}
        require_database(self.credentials['database']);self.directory=directory
        self.target=runtime.containers()['mysql'];self.root_config='/run/runtime/restore-root-'+uuid.uuid4().hex+'.cnf'
        self.config='/run/runtime/restore-user-'+uuid.uuid4().hex+'.cnf'

    def create(self):
        # Only CREATE; a collision fails instead of reusing or initializing an existing database.
        runtime.run(['docker','exec','-u','0',self.target,'sh','-c','umask 077; printf "[client]\\nuser=root\\npassword=%s\\n" "$(cat /run/runtime/root-password)" > '+self.root_config])
        c=self.credentials
        sql=f"CREATE DATABASE `{c['database']}`; CREATE USER '{c['user']}'@'%' IDENTIFIED BY '{c['password']}'; GRANT ALL PRIVILEGES ON `{c['database']}`.* TO '{c['user']}'@'%';"
        bounded(['docker','exec','-i','-u','0',self.target,'mysql','--defaults-extra-file='+self.root_config],input_data=sql.encode(),timeout=20)
        config=f"[client]\nuser={c['user']}\npassword={c['password']}\n".encode()
        runtime.run(['docker','exec','-i','-u','0',self.target,'sh','-c','umask 077; cat > '+self.config],input=config)
        (self.directory/'credentials.dpapi').write_bytes(_crypt(json.dumps(c).encode(),'staging.backup'))
        atomic_json(self.directory/'scope.json',{'database':c['database'],'disposable':True,'source_database':'song_record_validation','created_utc':dt.datetime.now(dt.timezone.utc).isoformat()})

    def execute(self, sql):
        require_database(self.credentials['database'])
        result=subprocess.run(['docker','exec','-i','-u','0',self.target,'mysql','--defaults-extra-file='+self.config,'--batch','--skip-column-names',self.credentials['database']],input=sql,capture_output=True,timeout=120)
        if result.returncode:
            match=re.search(rb'ERROR ([0-9]{3,5})',result.stderr)
            code=match.group(1).decode() if match else 'UNCONFIRMED'
            raise BackupError('RESTORE_MYSQL_'+code)
        if len(result.stdout)>32*1024*1024:raise BackupError('RESTORE_OUTPUT_LIMIT')
        return result.stdout

    def close_configs(self):
        runtime.run(['docker','exec','-u','0',self.target,'rm','-f',self.root_config,self.config])


def restore():
    started=time.monotonic();observed=dt.datetime.now(dt.timezone.utc)
    run_id=uuid.uuid4().hex;directory=DIRECTORY/run_id;_secure(directory)
    store=EncryptedStore(R2(*load('staging.backup'),BACKUP_BUCKET),encryption_key())
    instance=runtime.state()['instance_id'];backup=Backup(store,None,None,instance,require_ledger=True)
    catalog=backup.catalog()
    if not catalog['points']:raise BackupError('RESTORE_POINT_UNAVAILABLE')
    point=max(catalog['points'],key=lambda p:p['day']);manifest=backup.verify(point)
    point_time=dt.datetime.fromisoformat(manifest['created_utc']);rpo=(observed-point_time).total_seconds()
    if rpo<0:raise BackupError('RESTORE_POINT_TIME_INVALID')
    ledger=Ledger(store,instance);entries=ledger.read();files=ledger.require_restore(manifest['files'])
    sql=store.get(PREFIX+'points/'+point['id']+'/database.enc')
    if sql is None or hashlib.sha256(sql).hexdigest()!=manifest['database_sha256']:raise BackupError('RESTORE_DATABASE_HASH')
    database=Database(directory)
    stage='DATABASE_CREATE'
    try:
        database.create();stage='DATABASE_IMPORT';database.execute(scoped_dump(sql))
        stage='SCHEMA_MIGRATE'
        migration=invoke('migrate',database.credentials)
        # Migration stdout stays protected, with no credentials. Do not include it in the chat.
        (directory/'migrations.log').write_bytes(migration)
        stage='METADATA_AND_OVERLAY'
        metadata=json.loads(invoke('metadata',database.credentials))
        database.execute(statements(database.credentials['database'],metadata,entries))
        restored=json.loads(invoke('check',database.credentials))
        stage='FILE_LIST_AND_AUDIO'
        identity=lambda rows:{(r['owner'],r['recording'],r['generation'],r['sha256'],r['size']) for r in rows}
        if identity(restored['files'])!=identity(files):raise BackupError('RESTORE_DATABASE_FILE_LIST')
        ffmpeg=shutil.which('ffmpeg');ffprobe=shutil.which('ffprobe')
        if not ffmpeg or not ffprobe:raise BackupError('RESTORE_AUDIO_TOOLS_UNAVAILABLE')
        played=0;verified=0;speaker='NOT_EXERCISED'
        fixture_path=ROOT/'.local/workflow/p24-05/fixture.json'
        fixture=json.loads(fixture_path.read_text(encoding='utf-8')) if fixture_path.exists() else {}
        for file in files:
            data=store.get(check_file(file))
            if data is None or len(data)!=file['size'] or hashlib.sha256(data).hexdigest()!=file['sha256']:raise BackupError('RESTORE_FILE_HASH')
            path=directory/(hashlib.sha256(file['key'].encode()).hexdigest()+'.m4a')
            path.write_bytes(data)
            try:
                probe=subprocess.run([ffprobe,'-v','error','-show_entries','format=duration','-of','json',str(path)],capture_output=True,timeout=20)
                if probe.returncode or float(json.loads(probe.stdout)['format']['duration'])<=0:raise BackupError('RESTORE_AUDIO_INVALID')
                decode=subprocess.run([ffmpeg,'-v','error','-i',str(path),'-f','null','-'],capture_output=True,timeout=20)
                if decode.returncode:raise BackupError('RESTORE_AUDIO_DECODE_FAILED')
                verified+=1;played+=1
                if fixture.get('synthetic') is True and fixture.get('key')==file['key'] and fixture.get('sha256')==file['sha256']:
                    wav=path.with_suffix('.wav')
                    try:
                        converted=subprocess.run([ffmpeg,'-v','error','-i',str(path),'-c:a','pcm_s16le',str(wav)],capture_output=True,timeout=20)
                        if converted.returncode:raise BackupError('RESTORE_AUDIO_DECODE_FAILED')
                        output=subprocess.run(['pwsh','-NoProfile','-File',str(ROOT/'tools/play-restore-probe.ps1'),'-Path',str(wav)],capture_output=True,timeout=20)
                        speaker='PASS_OS_PLAYBACK_COMPLETED' if output.returncode==0 and b'RESTORED_SYNTHETIC_SOUND_PLAYBACK=PASS' in output.stdout else 'UNCONFIRMED'
                    finally:wav.unlink(missing_ok=True)
            finally:path.unlink(missing_ok=True)
        # Re-read the independent ledger after the long restore; newer deletions cannot slip through.
        current=ledger.read()
        if current!=entries:raise BackupError('RESTORE_LEDGER_CHANGED_RETRY_REQUIRED')
        result={'status':'PASS','run_id':run_id,'observed_utc':observed.isoformat(),'backup_created_utc':point_time.isoformat(),
                'rpo_seconds':round(rpo,3),'data_restore_rto_seconds':round(time.monotonic()-started,3),
                'goal_seconds':86400,'rpo_goal_met':rpo<=86400,'data_restore_rto_goal_met':time.monotonic()-started<=86400,
                'restored_users':restored['users'],'restored_recordings':restored['recordings'],'verified_files':verified,
                'audio_decode_replay':played,'deleted_files_excluded':len(manifest['files'])-len(files),
                'synthetic_notebook_sound_playback':speaker,'human_heard_audio':'UNCONFIRMED',
                'database_scope':'new isolated DB with scoped temporary user','source_database_modified':False,
                'public_service_rto':'UNCONFIRMED: no public deployment or real OAuth recovery exercised',
                'plaintext_audio_retained':False,'source_file_overwrite':False,'full_user_session_recovery':'P25_RELEASE_VALIDATION_PENDING'}
        atomic_json(directory/'report.json',result);atomic_json(DIRECTORY/'latest.json',result)
        return result
    except Exception as error:
        code=str(error) if isinstance(error,BackupError) and re.fullmatch(r'RESTORE_[A-Z_0-9]+',str(error)) else 'RESTORE_UNCONFIRMED'
        atomic_json(directory/'report.json',{'status':'FAIL','stage':stage,'code':code,'source_database_modified':False,'new_disposable_database_retained':True})
        raise
    finally:database.close_configs()


if __name__=='__main__':
    import sys
    try:
        if sys.argv[1:]!=['run']:raise BackupError('RESTORE_ACTION_INVALID')
        print(json.dumps(restore()))
    except Exception:print('Restore unconfirmed; source preserved, values suppressed.',file=sys.stderr);sys.exit(2)
