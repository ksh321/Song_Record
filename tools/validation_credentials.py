"""Isolated validation credentials: existing DPAPI vault and sealed Java scope checker."""
import json,subprocess,sys,threading,queue
from pathlib import Path
from r2_vault import save,load
from r2_credentials import validate,ACCOUNT
ROOT=Path(__file__).resolve().parents[1]
DIRECTORY=ROOT/'.local/workflow/p24-01'
ROLES=('staging.api','staging.worker','staging.playback')
JAVA='C:/Program Files/Eclipse Adoptium/jdk-21.0.12.101-hotspot/bin/java.exe'
def parse(output,role,full=False):
 if role not in ROLES:raise ValueError('Invalid role')
 wanted={'staging.temporary':'ALLOWED' if role!='staging.playback' else 'DENIED','staging.final':'ALLOWED' if role!='staging.api' else 'DENIED',**{f'{e}.{k}':'DENIED' for e in ('dev','prod') for k in ('temporary','final')}}
 if full:wanted.update({'write.temporary':'DENIED' if role=='staging.playback' else 'VERIFIED','write.final':'VERIFIED' if role=='staging.worker' else 'DENIED'})
 rows={}
 for line in output.splitlines():
  if line.count('=')!=1:raise ValueError('Closed scope report required')
  key,value=line.split('=')
  if key not in wanted or key in rows or value not in ('ALLOWED','DENIED','VERIFIED'):raise ValueError('Closed scope report required')
  rows[key]=value
 return rows==wanted
def check(role,access=None,secret=None,full=False):
 if role not in ROLES:raise ValueError('Invalid role')
 try:
  if access is None:access,secret=load(role)
  validate(access,secret);name=role.split('.')[1];prefix='songrecord.storage.dev.'
  payload='\n'.join(['songrecord.storage.environment=dev','songrecord.storage.role='+name,'diagnostic.namespace=staging',prefix+'account-id='+ACCOUNT,prefix+'temporary-bucket=song-record-staging-dev-temporary',prefix+'final-bucket=song-record-staging-dev-final',prefix+name+'.access-key='+access,prefix+name+'.secret-key='+secret])
  if full:payload+='\ndiagnostic.mode=development-write'
  cp=(ROOT/'.local/workflow/cloudflare/checker-classpath.txt').read_text(encoding='utf-8')
  child=subprocess.run([JAVA,'-cp',cp,'com.ksh321.songrecord.api.storage.R2CredentialCheck'],input=payload,text=True,capture_output=True,timeout=120,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
  return child.returncode==0 and parse(child.stdout,role,full)
 finally:access=secret=None
def gui():
 import tkinter as tk
 from tkinter import ttk
 DIRECTORY.mkdir(parents=True,exist_ok=True)
 window=tk.Tk();window.title('Song_Record — 검증 환경 키 3개 암호화 등록');window.geometry('820x760')
 ttk.Label(window,text='검증 전용 3개 역할 · 최초 한 번 등록',font=('',17)).pack(pady=12)
 ttk.Label(window,text='기존 개발/운영 키는 넣지 마세요. 아래 새 역할의 Access Key ID와 Secret Access Key만 입력합니다.').pack(pady=6)
 forms={}
 for role in ROLES:
  frame=ttk.LabelFrame(window,text=role);frame.pack(fill='x',padx=25,pady=8)
  values=[]
  for label in ('Access Key ID','Secret Access Key'):
   ttk.Label(frame,text=label).pack(anchor='w',padx=10);field=ttk.Entry(frame,show='*');field.pack(fill='x',padx=10,pady=5);values.append(field)
  forms[role]=values
 status=tk.StringVar(value='새 검증 버킷만 선택한 키를 입력하세요. 키·성공 화면을 채팅에 보내지 마세요.')
 ttk.Label(window,textvariable=status,wraplength=770).pack(pady=12)
 messages=queue.Queue();busy=False
 def submit():
  nonlocal busy
  pairs={role:tuple(field.get().strip() for field in fields) for role,fields in forms.items()}
  for fields in forms.values():
   for field in fields:field.delete(0,'end')
  busy=True;button.config(state='disabled');status.set('연결·분리 권한 검사 중… 입력란은 비웠습니다.')
  def work():
   try:
    for role,pair in pairs.items():
     if not check(role,*pair):raise ValueError('Scope unconfirmed')
    for role,pair in pairs.items():save(role,*pair)
    if not all(check(role) for role in ROLES):raise ValueError('Saved scope unconfirmed')
    result='검증용 3개 역할 암호화 등록·자동 사용 확인 완료';success=True
   except Exception:result='검증 키 연결/권한 확인 실패. 새 역할·선택 버킷을 확인해 다시 입력해 주세요. 키는 채팅에 보내지 마세요.';success=False
   finally:pairs.clear()
   (DIRECTORY/'credential-registration.json').write_text(json.dumps({'status':'PASS' if success else 'FAIL','roles':list(ROLES),'secret_values_logged':False}),encoding='utf-8');messages.put(result)
  threading.Thread(target=work,daemon=True).start()
 def poll():
  nonlocal busy
  try:status.set(messages.get_nowait());busy=False;button.config(state='normal')
  except queue.Empty:pass
  window.after(200,poll)
 def close():
  if busy:status.set('검사가 끝나면 닫아 주세요.');return
  for fields in forms.values():
   for field in fields:field.delete(0,'end')
  window.destroy()
 window.report_callback_exception=lambda *args:status.set('처리 실패. 비밀값은 기록하지 않았습니다.')
 button=ttk.Button(window,text='3개 역할 연결 확인 후 Windows 암호화 등록',command=submit);button.pack(pady=8)
 window.protocol('WM_DELETE_WINDOW',close);window.after(200,poll);window.mainloop()
if __name__=='__main__':gui()
