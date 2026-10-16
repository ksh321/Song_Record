"""Read-only experiment inventory. Never starts workers, deletes objects, or opens upload gates."""
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import uuid
from backup import bounded,TARGET
from backup_store import R2
from observe import ROOT,atomic


def compare(rows,finals,temporary,reader):
    expected={key:(size,sha) for key,size,sha in rows}
    if len(expected)!=len(rows):raise ValueError('EXPERIMENT_DUPLICATE_DATABASE_OBJECT')
    actual={row['key']:row['size'] for row in finals}
    missing=set(expected)-set(actual);unreferenced=set(actual)-set(expected)
    invalid=0;verified=0
    for key,(size,sha) in expected.items():
        if key not in actual:continue
        if actual[key]!=size:invalid+=1;continue
        data=reader.get(key)
        if data is None or len(data)!=size or hashlib.sha256(data).hexdigest()!=sha:invalid+=1
        else:verified+=1
    issues=len(missing)+len(unreferenced)+invalid
    return {'status':'PASS' if issues==0 else 'WARNING','observed_utc':dt.datetime.now(dt.timezone.utc).isoformat(),
            'database_files':len(rows),'final_objects':len(finals),'temporary_objects':len(temporary),
            'missing_files':len(missing),'unreferenced_objects':len(unreferenced),'invalid_files':invalid,'verified_files':verified,
            'read_only':True,'objects_deleted':0,'database_modified':False,'worker_started':False,'upload_gate_changed':False,
            'release_ready':False}


def once():
    if os.getuid()!=0:raise ValueError('ROOT_REQUIRED')
    os.umask(0o077);vault=Path('/etc/song-record-experiment')
    if json.loads((vault/'application-storage.json').read_text())!={'scope':'experiment','final_bucket':'song-record-experiment-final'}:raise ValueError('EXPERIMENT_SCOPE_REJECTED')
    row=json.loads((vault/'r2-experiment.json').read_text())
    if row.get('scope')!='song_record_experiment_application:v1' or set(row.get('roles',{}))!={'experiment.api','experiment.worker','experiment.playback'}:raise ValueError('EXPERIMENT_SCOPE_REJECTED')
    scope=bounded(['docker','inspect','--format','{{ index .Config.Labels "com.docker.compose.project" }}',TARGET],256).strip()
    if scope!=b'song-record-experiment':raise ValueError('EXPERIMENT_DATABASE_SCOPE_REJECTED')
    config='/run/runtime/inventory-audit-'+uuid.uuid4().hex+'.cnf'
    bounded(['docker','exec','-u','0',TARGET,'sh','-c','umask 077; printf "[client]\\nuser=root\\npassword=%s\\n" "$(cat /run/runtime/root-password)" > '+config],256)
    try:
        sql=b"SET TRANSACTION READ ONLY; START TRANSACTION; SELECT object_key,verified_size,sha256 FROM recording_asset WHERE cloud_state IN ('STORED','DELETING') ORDER BY recording_id; COMMIT;"
        raw=bounded(['docker','exec','-i','-u','0',TARGET,'mysql','--defaults-extra-file='+config,'--batch','--skip-column-names','song_record_experiment'],32*1024*1024,sql,30)
        rows=[]
        for line in raw.decode().splitlines():
            key,size,sha=line.split('\t');rows.append((key,int(size),sha))
    finally:bounded(['docker','exec','-u','0',TARGET,'rm','-f',config],256)
    reader=row['roles']['experiment.playback'];api=row['roles']['experiment.api']
    final=R2(reader['access'],reader['secret'],'song-record-experiment-final')
    temp=R2(api['access'],api['secret'],'song-record-experiment-temporary')
    result=compare(rows,final.list_objects(''),temp.list_objects(''),final)
    atomic(ROOT/'inventory-audit.json',result)
    return result


if __name__=='__main__':
    try:print(json.dumps(once()))
    except Exception:print('EXPERIMENT_READ_ONLY_AUDIT_UNCONFIRMED: values suppressed');raise SystemExit(2)
