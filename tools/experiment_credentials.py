"""Approved experiment app roles; atomic CurrentUser DPAPI bundle, no secrets in reports."""
import json
import os
from pathlib import Path
import queue
import threading
import uuid
from backup_store import R2,BackupError
from r2_credentials import validate
from r2_vault import _crypt,_secure

ROOT=Path(__file__).resolve().parents[1]
DIRECTORY=ROOT/'.local/workflow/experiment-app'
ENTROPY='experiment.application'
SCOPE='song_record_experiment_application:v1'
ROLES=('experiment.api','experiment.worker','experiment.playback')
BUCKETS=('song-record-experiment-temporary','song-record-experiment-final')
FORBIDDEN=tuple(f'song-record-{env}-{kind}' for env in ('dev','prod','staging-dev') for kind in ('temporary','final'))+('song-record-staging-backup','song-record-experiment-backup')


def validate_bundle(row):
    if set(row)!= {'scope','roles'} or row['scope']!=SCOPE or set(row['roles'])!=set(ROLES):
        raise BackupError('EXPERIMENT_APPLICATION_SCOPE_REJECTED')
    for role in ROLES:
        pair=row['roles'][role]
        if set(pair)!= {'access','secret'}:raise BackupError('EXPERIMENT_APPLICATION_SCOPE_REJECTED')
        validate(pair['access'],pair['secret'])
    if len({row['roles'][role]['access'] for role in ROLES})!=3:
        raise BackupError('EXPERIMENT_ROLES_MUST_BE_SEPARATE')


def load():
    with (DIRECTORY/'credentials.dpapi').open('rb') as stream:raw=stream.read(16385)
    if len(raw)>16384:raise BackupError('EXPERIMENT_APPLICATION_RECORD_LIMIT')
    row=json.loads(_crypt(raw,ENTROPY,True));validate_bundle(row)
    return row


def probe_write(transport,allowed):
    path='operational/v1/credential-probes/'+str(uuid.uuid4())
    data=b'Song_Record experiment synthetic credential probe'
    status,_=transport.request('PUT',path,data)
    if status==200:
        try:
            if transport.get(path)!=data:raise BackupError('EXPERIMENT_WRITE_READBACK_FAILED')
        finally:
            transport.delete(path)
    if status!=(200 if allowed else 403):raise BackupError('EXPERIMENT_WRITE_SCOPE_REJECTED')
    if not allowed and transport.request('DELETE',path)[0]!=403:
        raise BackupError('EXPERIMENT_DELETE_SCOPE_REJECTED')


def check(row):
    validate_bundle(row)
    for role in ROLES:
        pair=row['roles'][role];access,secret=pair['access'],pair['secret']
        for bucket in FORBIDDEN:
            transport=R2(access,secret,bucket)
            if transport.request('GET',query={'list-type':'2','max-keys':'1'})[0]!=403:
                raise BackupError('EXPERIMENT_KEY_REACHES_EXISTING_BUCKET')
            path='operational/v1/credential-probes/'+str(uuid.uuid4())
            if transport.request('DELETE',path)[0]!=403:raise BackupError('EXPERIMENT_KEY_CAN_DELETE_EXISTING_BUCKET')
        for index,bucket in enumerate(BUCKETS):
            read=role=='experiment.worker' or role=='experiment.api' and index==0 or role=='experiment.playback' and index==1
            write=role=='experiment.worker' or role=='experiment.api' and index==0
            transport=R2(access,secret,bucket)
            if transport.request('GET',query={'list-type':'2','max-keys':'1'})[0]!=(200 if read else 403):
                raise BackupError('EXPERIMENT_ROLE_READ_SCOPE_REJECTED')
            probe_write(transport,write)
    return True


def register(pairs):
    row={'scope':SCOPE,'roles':{role:dict(access=pairs[role][0],secret=pairs[role][1]) for role in ROLES}}
    check(row);_secure(DIRECTORY)
    cipher=_crypt(json.dumps(row).encode(),ENTROPY)
    if json.loads(_crypt(cipher,ENTROPY,True))!=row:raise BackupError('EXPERIMENT_VAULT_ROUNDTRIP_FAILED')
    target=DIRECTORY/'credentials.dpapi'
    previous=target.read_bytes() if target.exists() else None
    pending=DIRECTORY/(uuid.uuid4().hex+'.pending')
    try:
        with pending.open('xb') as stream:stream.write(cipher);stream.flush();os.fsync(stream.fileno())
        pending.replace(target)
    finally:pending.unlink(missing_ok=True)
    try:
        saved=load()
        if saved!=row:raise BackupError('EXPERIMENT_VAULT_ROUNDTRIP_FAILED')
        check(saved)
    except Exception:
        if previous is None:target.unlink(missing_ok=True)
        else:
            with pending.open('xb') as stream:stream.write(previous);stream.flush();os.fsync(stream.fileno())
            pending.replace(target)
        raise
    report={'status':'PASS','scope':SCOPE,'roles':list(ROLES),'buckets':list(BUCKETS),'automatic_load_checked':True,'existing_buckets_denied':True,'aws_transferred':False}
    (DIRECTORY/'registration.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    row['roles'].clear();saved['roles'].clear()
    return report


def gui():
    import tkinter as tk
    from tkinter import ttk
    window=tk.Tk();window.title('Song_Record — AWS 앱 키 3개 암호화 등록');window.geometry('850x800')
    ttk.Label(window,text='AWS 전용 앱 키 3개 · 최초 한 번 등록',font=('',17)).pack(pady=10)
    ttk.Label(window,text='새 experiment temporary/final 버킷만 선택한 키를 넣으세요.\n기존 staging·개발·운영·백업 키를 넣지 마세요. 키·발급 화면은 채팅에 보내지 마세요.').pack(pady=5)
    forms={}
    for role in ROLES:
        frame=ttk.LabelFrame(window,text=role);frame.pack(fill='x',padx=24,pady=7)
        fields=[]
        for label in ('Access Key ID','Secret Access Key'):
            ttk.Label(frame,text=label).pack(anchor='w',padx=10)
            field=ttk.Entry(frame,show='*');field.pack(fill='x',padx=10,pady=5);fields.append(field)
        forms[role]=fields
    status=tk.StringVar(value='Windows 계정으로 암호화하며 기존 등록은 보존합니다. 최초 1회 뒤 자동 사용합니다.')
    ttk.Label(window,textvariable=status,wraplength=790).pack(pady=10)
    messages=queue.Queue();busy=False
    def submit():
        nonlocal busy
        pairs={role:tuple(field.get().strip() for field in fields) for role,fields in forms.items()}
        for fields in forms.values():
            for field in fields:field.delete(0,'end')
        busy=True;button.config(state='disabled');status.set('새 버킷 허용·기존 버킷 차단·쓰기·암호화 자동 사용 검사 중…')
        def work():
            try:register(pairs);message='AWS 앱 키 3개 암호화 등록·분리 권한·자동 사용 확인 완료'
            except Exception:message='AWS 앱 키 등록 검사 실패. 새 버킷·세 역할 권한을 확인해 주세요. 키는 채팅에 보내지 마세요.'
            finally:pairs.clear()
            messages.put(message)
        threading.Thread(target=work,daemon=True).start()
    def poll():
        nonlocal busy
        try:status.set(messages.get_nowait());busy=False;button.config(state='normal')
        except queue.Empty:pass
        window.after(200,poll)
    def close():
        if busy:status.set('검사 완료 뒤 닫아 주세요.');return
        for fields in forms.values():
            for field in fields:field.delete(0,'end')
        window.destroy()
    button=ttk.Button(window,text='3개 역할 분리 확인 후 Windows 암호화 등록',command=submit);button.pack(pady=7)
    window.report_callback_exception=lambda *args:status.set('처리 실패. 비밀값은 기록하지 않았습니다.')
    window.protocol('WM_DELETE_WINDOW',close);window.after(200,poll);window.mainloop()


if __name__=='__main__':gui()
