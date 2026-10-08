"""One-time masked entry. No credential persistence or vault reads; status-only reports."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import threading

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = ROOT / '.local/workflow/cloudflare'
LABELS = ('dev.api', 'dev.worker', 'prod.api', 'prod.worker')
ACCOUNT = 'c061b2724b72861b43bfe2817be31f35'

class SecretError(Exception):
    pass

def validate(access, secret):
    if not re.fullmatch(r'[a-fA-F0-9]{32}', access) or not re.fullmatch(r'[a-fA-F0-9]{64}', secret):
        raise SecretError('Check Access Key ID and Secret Access Key fields')

def parse_report(output, label, full=False, signed=False, audio=False):
    if audio:
        key, separator, value=output.strip().partition("=")
        if label!='dev.worker' or key!="audio.temporary" or not separator or value not in ("VERIFIED","ERROR","BYTES_MISMATCH","VALIDATION_FAILED","CLEANUP_FAILED"): raise SecretError("Invalid audio checker result")
        return {"status":"PASS" if value=="VERIFIED" else "FAIL", "checks":{key:value}}
    if signed:
        key, separator, value=output.strip().partition("=")
        if key!="signed.temporary" or not separator or value not in ("VERIFIED","ERROR","PUT_FAILED","BYTES_MISMATCH","EXPIRY_FAILED","CLEANUP_FAILED"): raise SecretError("Invalid signed checker result")
        return {"status":"PASS" if value=="VERIFIED" else "FAIL", "checks":{key:value}}
    expected = {e+'.'+k for e in ('dev','prod') for k in ('temporary','final')}
    if full: expected |= {'write.temporary','write.final'}
    result = {}
    for line in output.splitlines():
        key, separator, value = line.partition('=')
        safe_value=value in ('ALLOWED','DENIED','MISSING','ERROR','VERIFIED','CLEANUP_FAILED','BYTES_MISMATCH') or (key.startswith('write.') and re.fullmatch(r'(PUT|GET|ANONYMOUS)_(HTTP_[1-5][0-9]{2}|TRANSPORT_ERROR)',value))
        if not separator or key not in expected or key in result or not safe_value:
            raise SecretError('Invalid checker result')
        result[key] = value
    if result.keys() != expected: raise SecretError('Incomplete checker result')
    environment, role = label.split('.')
    wanted = {key: 'ALLOWED' if key.startswith(environment+'.') and (key.endswith('temporary') or role=='worker') else 'DENIED' for key in expected}
    if full:
        wanted.update({'write.temporary':'VERIFIED','write.final':'VERIFIED' if role=='worker' else 'DENIED'})
    return {'status': 'PASS' if result==wanted else 'FAIL', 'checks': result} if full else {'status': 'PASS' if result==wanted else 'FAIL', 'bucket_read_scope': result}

def check(label, java, access, secret, directory=DIRECTORY, full=False, signed=False, audio=False):
    if label not in LABELS or (full and not label.startswith('dev.')): raise SecretError('Invalid role')
    if sum((bool(full),bool(signed),bool(audio)))>1: raise SecretError('Select one diagnostic')
    if audio and label!='dev.worker': raise SecretError('Development worker only')
    if signed and label!='dev.api': raise SecretError('Development API only')
    report_name='audio-reports' if audio else 'signed-put-reports' if signed else 'development-reports' if full else 'reports'
    try:
        # Invalidate prior PASS before trying new input, including failed validation.
        (directory/report_name/(label+'.json')).unlink(missing_ok=True)
        validate(access, secret)
        environment, role = label.split('.')
        prefix = 'songrecord.storage.'+environment+'.'
        lines = ['songrecord.storage.environment='+environment, 'songrecord.storage.role='+role,
                 prefix+'account-id='+ACCOUNT, prefix+'temporary-bucket=song-record-'+environment+'-temporary',
                 prefix+'final-bucket=song-record-'+environment+'-final',
                 prefix+role+'.access-key='+access, prefix+role+'.secret-key='+secret]
        if audio:
            ffmpeg=shutil.which('ffmpeg');ffprobe=shutil.which('ffprobe')
            if not ffmpeg or not ffprobe: raise SecretError('Audio tools unavailable')
            lines.extend(['diagnostic.mode=audio-validation','diagnostic.audio-file='+(ROOT/'.local/workflow/p12-07/probe.m4a').as_posix(), 'diagnostic.ffmpeg='+Path(ffmpeg).as_posix(),'diagnostic.ffprobe='+Path(ffprobe).as_posix()])
        elif signed: lines.append('diagnostic.mode=signed-put')
        elif full: lines.append('diagnostic.mode=development-write')
        classpath = (directory/'checker-classpath.txt').read_text(encoding='utf-8')
        child = subprocess.run([str(java), '-cp', classpath, 'com.ksh321.songrecord.api.storage.R2CredentialCheck'],
            input='\n'.join(lines), encoding='utf-8', capture_output=True, timeout=240 if full or audio else 100,
            creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        if child.returncode != 0: raise SecretError('Connection check failed')
        result = parse_report(child.stdout, label, full, signed, audio)
        # Persist only a closed set of labels/statuses. Never copy stderr or provider responses.
        report = directory/report_name;report.mkdir(exist_ok=True)
        from datetime import datetime, timezone
        result['checked_utc']=datetime.now(timezone.utc).isoformat()
        target=report/(label+'.json');temporary=target.with_suffix('.tmp')
        temporary.write_text(json.dumps(result),encoding='utf-8');temporary.replace(target)
        return result['status']
    except Exception:
        raise SecretError('Connection check failed; verify credentials, scope and network') from None

def gui(java, full=False, signed=False, audio=False):
    import tkinter as tk
    from tkinter import ttk, messagebox
    import queue
    window=tk.Tk();window.title('Song_Record — P12-07 실제 오디오 검사' if audio else 'Song_Record — P12-04 서명 URL 검사' if signed else 'Song_Record — R2 개발 쓰기 검사' if full else 'Song_Record — R2 일회용 검사');window.geometry('690x430')
    window.report_callback_exception=lambda *args: messagebox.showerror('오류','처리하지 못했습니다. 키 내용은 기록하지 않았습니다.')
    ttk.Label(window,text='P12-07 실제 오디오 검증 — 키 저장 없음' if audio else 'P12-04 개발 PUT URL·재발급 검사 — 키 저장 없음' if signed else 'R2 개발 쓰기·읽기·삭제 검사 — 키 저장 없음' if full else 'R2 일회용 연결 검사 — 키 저장 없음',font=('',16)).pack(pady=12)
    ttk.Label(window,text='개발 버킷에 작은 시험 파일을 쓰고 읽은 뒤 삭제합니다. 운영 버킷 쓰기 없음.' if full or audio else '키는 이번 검사에만 사용합니다. 저장 파일을 만들거나 기존 키 파일을 읽지 않습니다.').pack(pady=6)
    role=tk.StringVar(value='dev.worker' if audio else LABELS[0]);selector=ttk.Combobox(window,textvariable=role,values=('dev.worker',) if audio else LABELS[:1] if signed else LABELS[:2] if full else LABELS,state='readonly',width=24);selector.pack(pady=8)
    form=ttk.Frame(window);form.pack(fill='x',padx=30)
    ttk.Label(form,text='Access Key ID').pack(anchor='w');access=ttk.Entry(form,show='*',width=76);access.pack(fill='x',pady=4)
    ttk.Label(form,text='Secret Access Key').pack(anchor='w');secret=ttk.Entry(form,show='*',width=76);secret.pack(fill='x',pady=4)
    status=tk.StringVar(value='롤 완료한 최신 키를 넣으세요. Token value가 아닙니다.');ttk.Label(window,textvariable=status,wraplength=640).pack(pady=12)
    messages=queue.Queue();busy=False
    def run_check():
        nonlocal busy
        chosen=role.get();values=(access.get().strip(),secret.get().strip())
        access.delete(0,'end');secret.delete(0,'end')
        busy=True;verify.config(state='disabled');selector.config(state='disabled');status.set(chosen+' 검사 중… 입력란을 비웠습니다.')
        def run(pair):
            try:
                result=check(chosen,java,pair[0],pair[1],full=full,signed=signed,audio=audio);message=chosen+((' 실제 오디오 검증·시험 파일 정리 확인 완료' if audio else ' PUT URL·재발급·시험 파일 정리 확인 완료' if signed else ' 개발 쓰기·비서명 접근 차단·정리 확인 완료' if full else ' 연결·읽기 권한 확인 완료') if result=='PASS' else ' 검사 단계에 실패가 있습니다. AI가 결과 파일로 원인을 확인합니다.')
            except Exception:message=chosen+' 검사 실행 실패. 키를 바꾸지 말고 AI에게 알려 주세요.'
            finally:pair=None
            messages.put(message)
        threading.Thread(target=run,args=(values,),daemon=True).start()
    def poll():
        nonlocal busy
        try:
            status.set(messages.get_nowait());busy=False;verify.config(state='normal');selector.config(state='readonly')
        except queue.Empty:pass
        window.after(200,poll)
    def close():
        if busy:
            status.set('진행 중인 검사가 끝나면 닫아 주세요. 키는 저장하지 않습니다.');return
        access.delete(0,'end');secret.delete(0,'end');window.destroy()
    verify=ttk.Button(window,text='이번 입력으로 검사 — 저장 안 함',command=run_check);verify.pack(pady=8)
    ttk.Label(window,text='검사 결과만 저장합니다. 실행 중 메모리·클립보드까지 완전 삭제하거나 접근을 차단하는 보장은 아닙니다.',wraplength=640).pack(pady=14)
    window.protocol('WM_DELETE_WINDOW',close)
    DIRECTORY.mkdir(parents=True,exist_ok=True)
    (DIRECTORY/'ui-status.json').write_text(json.dumps({'pid':os.getpid(),'status':'READY','mode':'ONE_TIME'}),encoding='utf-8')
    window.after(200,poll);window.mainloop()

if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser();parser.add_argument('--java',type=Path,required=True);parser.add_argument('--development-write',action='store_true');parser.add_argument('--signed-put',action='store_true');parser.add_argument('--audio-check',action='store_true');args=parser.parse_args()
    try:gui(args.java,args.development_write,args.signed_put,args.audio_check)
    except Exception:raise SystemExit(1)
