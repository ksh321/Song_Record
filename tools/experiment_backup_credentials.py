"""One-time masked registration for the approved experiment-only backup; no secret stdout."""
import base64
import json
import os
from pathlib import Path
import queue
import threading
import uuid
from backup_store import BackupError, R2, EncryptedStore
from backup_credentials import recovery_wrap, recovery_unwrap
from r2_credentials import validate
from r2_vault import _crypt, _secure, load as load_role

ROLE = 'experiment.backup'
BUCKET = 'song-record-experiment-backup'
ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = ROOT/'.local/workflow/experiment-backup'
SCOPE = 'song_record_experiment_backup:v1'
OTHER_BUCKETS = tuple(f'song-record-{env}-{kind}' for env in ('dev','prod','staging-dev')
                      for kind in ('temporary','final')) + ('song-record-staging-backup',)


def load():
    with (DIRECTORY/'credentials.dpapi').open('rb') as stream:
        encrypted = stream.read(16385)
    if len(encrypted) > 16384:
        raise BackupError('EXPERIMENT_BACKUP_KEY_INVALID')
    record = json.loads(_crypt(encrypted, ROLE, True))
    if record.get('scope') != SCOPE or record.get('bucket') != BUCKET:
        raise BackupError('EXPERIMENT_BACKUP_SCOPE_REJECTED')
    validate(record['access'], record['secret'])
    recovery = base64.b64decode(record['recovery'], validate=True)
    if len(base64.b64decode(record['master'], validate=True)) != 32 or len(recovery) != 84 or not recovery.startswith(b'SRR1'):
        raise BackupError('EXPERIMENT_BACKUP_KEY_INVALID')
    uuid.UUID(record['instance'])
    return record


def check_scope(access, secret):
    validate(access, secret)
    own = R2(access, secret, BUCKET)
    if own.request('GET', query={'list-type':'2','max-keys':'1'})[0] != 200:
        raise BackupError('EXPERIMENT_BACKUP_BUCKET_UNAVAILABLE')
    for bucket in OTHER_BUCKETS:
        if R2(access, secret, bucket).request('GET', query={'list-type':'2','max-keys':'1'})[0] != 403:
            raise BackupError('EXPERIMENT_BACKUP_KEY_TOO_BROAD')
    for role in ('staging.api','staging.worker','staging.playback'):
        app = R2(*load_role(role), BUCKET)
        if app.request('GET', query={'list-type':'2','max-keys':'1'})[0] != 403:
            raise BackupError('APPLICATION_CAN_READ_EXPERIMENT_BACKUP')
    path = 'operational/v1/probes/' + str(uuid.uuid4())
    probe = EncryptedStore(own, os.urandom(32))
    probe.put(path, b'Song_Record experiment backup scope probe')
    if probe.get(path) != b'Song_Record experiment backup scope probe':
        raise BackupError('EXPERIMENT_BACKUP_PROBE_FAILED')
    probe.delete(path)
    return own


def register(access, secret, phrase, again):
    if len(phrase) < 16 or phrase != again:
        raise BackupError('RECOVERY_PHRASE_MISMATCH')
    own = check_scope(access, secret)
    _secure(DIRECTORY)
    target = DIRECTORY/'credentials.dpapi'
    old = load() if target.exists() else None
    if old is None and own.get('operational/v1/catalog.enc') is not None:
        raise BackupError('EXISTING_BACKUP_RECOVERY_REQUIRED')
    master = base64.b64decode(old['master']) if old else os.urandom(32)
    envelope = recovery_wrap(master, phrase)
    if recovery_unwrap(envelope, phrase) != master:
        raise BackupError('RECOVERY_KEY_CHECK_FAILED')
    record = {'scope':SCOPE, 'bucket':BUCKET, 'instance':old['instance'] if old else str(uuid.uuid4()),
              'access':access, 'secret':secret, 'master':base64.b64encode(master).decode(),
              'recovery':base64.b64encode(envelope).decode()}
    encrypted = _crypt(json.dumps(record).encode(), ROLE)
    if json.loads(_crypt(encrypted, ROLE, True)) != record:
        raise BackupError('EXPERIMENT_BACKUP_VAULT_CHECK_FAILED')
    pending = DIRECTORY/(str(uuid.uuid4())+'.pending')
    try:
        with pending.open('xb') as stream:
            stream.write(encrypted);stream.flush();os.fsync(stream.fileno())
        pending.replace(target)
    finally:
        pending.unlink(missing_ok=True)
    verified = load()
    if verified != record:
        raise BackupError('EXPERIMENT_BACKUP_VAULT_CHECK_FAILED')
    result = {'status':'PASS','bucket':BUCKET,'scope':SCOPE,'windows_encrypted':True,
              'automatic_load_checked':True,'recovery_phrase_stored':False,'aws_transferred':False}
    (DIRECTORY/'registration.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    record.clear();verified.clear()
    return result


def gui():
    import tkinter as tk
    from tkinter import ttk
    window=tk.Tk();window.title('Song_Record — AWS 전용 백업 키 암호화 등록');window.geometry('850x590')
    ttk.Label(window,text='AWS 전용 독립 백업 · 최초 한 번 등록',font=('',17)).pack(pady=15)
    ttk.Label(window,text=BUCKET+' / 이 버킷 하나의 Object Read & Write\n기존 노트북 백업 키와 다른 새 키를 입력하세요. 키·화면은 채팅에 보내지 마세요.').pack(pady=8)
    fields=[]
    for label in ('Access Key ID','Secret Access Key','새 백업 복구 암호 (16자 이상 · 프로그램 밖에 안전하게 보관)','복구 암호 다시 입력'):
        ttk.Label(window,text=label).pack(anchor='w',padx=25)
        field=ttk.Entry(window,show='*');field.pack(fill='x',padx=25,pady=6);fields.append(field)
    status=tk.StringVar(value='Windows 계정으로 암호화 보관합니다. 복구 암호 평문은 저장·AWS 전송하지 않습니다.')
    ttk.Label(window,textvariable=status,wraplength=790).pack(pady=12)
    messages=queue.Queue();busy=False
    def submit():
        nonlocal busy
        if busy:return
        values=[field.get() for field in fields]
        for field in fields:field.delete(0,'end')
        busy=True;button.config(state='disabled');status.set('버킷 권한·암호화·자동 사용 확인 중…')
        def work():
            try:register(*values);messages.put('AWS 전용 백업 키 암호화 등록·자동 사용·복구 키 확인 완료')
            except Exception as error:messages.put('등록 실패 — '+(str(error) if isinstance(error,BackupError) else '상태 미확인')+' (키는 채팅에 보내지 마세요.)')
            finally:values.clear()
        threading.Thread(target=work,daemon=True).start()
    def poll():
        nonlocal busy
        try:status.set(messages.get_nowait());busy=False;button.config(state='normal')
        except queue.Empty:pass
        window.after(200,poll)
    button=ttk.Button(window,text='권한 확인 후 Windows 암호화 등록',command=submit);button.pack(pady=7)
    poll();window.mainloop()


if __name__=='__main__':gui()
