"""Cloudflare analytics-only credential handoff. No token values in argv, logs, reports or Git."""
import json,re,sys,threading,queue,urllib.request,urllib.error,datetime as dt,time
from pathlib import Path
from r2_vault import _crypt,_secure
from r2_credentials import ACCOUNT
ROOT=Path(__file__).resolve().parents[1]
DIRECTORY=ROOT/'.local/workflow/cloudflare/analytics'
REPORT=ROOT/'.local/workflow/p24-03/metrics-registration.json'
QUERY='''query R2Cost($accountTag:string!,$start:Time,$end:Time){viewer{accounts(filter:{accountTag:$accountTag}){r2OperationsAdaptiveGroups(limit:10000,filter:{datetime_geq:$start,datetime_leq:$end}){sum{requests} dimensions{actionType responseStatusCode bucketName}} r2StorageAdaptiveGroups(limit:10000,filter:{datetime_geq:$start,datetime_leq:$end},orderBy:[datetime_DESC]){max{payloadSize metadataSize objectCount uploadCount} dimensions{bucketName datetime}}}}}'''
class MetricsError(Exception):pass

def validate(token):
 if not isinstance(token,str) or not re.fullmatch(r'[A-Za-z0-9_-]{20,2048}',token):raise MetricsError('TOKEN_FORMAT_UNCONFIRMED')
 if re.fullmatch(r'[a-fA-F0-9]{32}',token) or token=='song-record-r2-cost-read':raise MetricsError('TOKEN_ID_OR_NAME_INSTEAD_OF_SECRET')

def verify(token):
 validate(token);client=urllib.request.build_opener(urllib.request.ProxyHandler({}))
 request=urllib.request.Request('https://api.cloudflare.com/client/v4/accounts/'+ACCOUNT+'/tokens/verify',headers={'Authorization':'Bearer '+token})
 for attempt in range(3):
  try:
   with client.open(request,timeout=20) as reply:row=json.loads(reply.read(65537))
  except urllib.error.HTTPError as e:
   if e.code==401 and attempt<2:time.sleep((2,5)[attempt]);continue
   raise MetricsError('TOKEN_VERIFY_HTTP_'+str(e.code)) from None
  except Exception:raise MetricsError('TOKEN_VERIFY_UNCONFIRMED') from None
  if not row.get('success') or row.get('result',{}).get('status')!='active':raise MetricsError('TOKEN_NOT_ACTIVE')
  return

def management_denied(token):
 validate(token);client=urllib.request.build_opener(urllib.request.ProxyHandler({}))
 try:
  with client.open(urllib.request.Request('https://api.cloudflare.com/client/v4/accounts/'+ACCOUNT+'/r2/buckets',headers={'Authorization':'Bearer '+token}),timeout=20):raise MetricsError('R2_MANAGEMENT_SCOPE_TOO_BROAD')
 except urllib.error.HTTPError as e:
  if e.code!=403:raise MetricsError('R2_MANAGEMENT_SCOPE_UNCONFIRMED') from None

def fetch(token,start=None,end=None,scope_check=False):
 validate(token);now=dt.datetime.now(dt.timezone.utc);end=end or now
 start=start or now-dt.timedelta(hours=24)
 if not dt.timedelta(0)<end-start<=dt.timedelta(days=31):raise MetricsError('QUERY_RANGE_INVALID')
 client=urllib.request.build_opener(urllib.request.ProxyHandler({}))
 headers={'Authorization':'Bearer '+token,'Content-Type':'application/json','User-Agent':'SongRecord-cost-check'}
 body=json.dumps({'query':QUERY,'variables':{'accountTag':ACCOUNT,'start':start.isoformat(),'end':end.isoformat()}}).encode()
 try:
  with client.open(urllib.request.Request('https://api.cloudflare.com/client/v4/graphql',data=body,headers=headers,method='POST'),timeout=35) as reply:raw=reply.read(4000001)
 except urllib.error.HTTPError as e:raise MetricsError('HTTP_'+str(e.code)) from None
 except Exception:raise MetricsError('NETWORK_UNCONFIRMED') from None
 if len(raw)>4000000:raise MetricsError('QUERY_TOO_LARGE')
 result=json.loads(raw)
 if result.get('errors'):raise MetricsError('GRAPHQL_QUERY_REJECTED')
 accounts=result.get('data',{}).get('viewer',{}).get('accounts',[])
 if len(accounts)!=1:raise MetricsError('ACCOUNT_SCOPE_UNCONFIRMED')
 row=accounts[0]
 for key in ('r2OperationsAdaptiveGroups','r2StorageAdaptiveGroups'):
  if not isinstance(row.get(key),list) or len(row[key])>=10000:raise MetricsError('QUERY_COVERAGE_UNCONFIRMED')
 if scope_check:
  # Read-only control-plane probe: analytics-only must not list/manage R2 buckets.
  management_denied(token)
 return {'account':ACCOUNT,'queried_utc':now.isoformat(),'period_start':start.isoformat(),'period_end':end.isoformat(),'operations':row['r2OperationsAdaptiveGroups'],'storage':row['r2StorageAdaptiveGroups']}

def save(token):
 validate(token);_secure(DIRECTORY);p=DIRECTORY/'analytics.dpapi';pending=p.with_suffix('.pending')
 payload={'scope':'cloudflare.analytics.read.v1','account':ACCOUNT,'token':token}
 pending.write_bytes(_crypt(json.dumps(payload).encode(),'staging.api'));pending.replace(p);payload.clear()

def load():
 row=json.loads(_crypt((DIRECTORY/'analytics.dpapi').read_bytes(),'staging.api',True))
 if row.get('scope')!='cloudflare.analytics.read.v1' or row.get('account')!=ACCOUNT:raise MetricsError('VAULT_SCOPE_UNCONFIRMED')
 token=row['token'];validate(token);row.clear();return token

def gui():
 import tkinter as tk
 from tkinter import ttk
 window=tk.Tk();window.title('Song_Record — 비용 분석 키 암호화 등록');window.geometry('800x440')
 ttk.Label(window,text='비용 감시용 분석 조회 키 · 최초 한 번 등록',font=('',17)).pack(pady=15)
 ttk.Label(window,text='준비된 Cloudflare 계정 토큰: song-record-r2-cost-read\nAccount Analytics Read 한 개 · 90일 만료\nR2 객체 쓰기·삭제·관리 권한은 추가하지 않습니다.',justify='left').pack(pady=10)
 ttk.Label(window,text='발급된 분석 API 토큰 하나만 입력 — Access Key ID / Secret Access Key 입력란이 아닙니다.').pack(pady=8)
 entry=ttk.Entry(window,show='*',width=90);entry.pack(padx=25,fill='x')
 status=tk.StringVar(value='키·발급 성공 화면은 채팅에 보내지 마세요. Windows 현재 사용자 암호화 보관 후 자동 사용합니다.')
 ttk.Label(window,textvariable=status,wraplength=750).pack(pady=20);messages=queue.Queue();busy=False
 def submit():
  nonlocal busy
  token=entry.get().strip();entry.delete(0,'end');busy=True;button.config(state='disabled');status.set('실제 R2 분석 조회·관리 접근 거부·암호화 자동 사용 확인 중…')
  def work():
   nonlocal token
   saved=False
   try:
    verify(token);management_denied(token);save(token);saved=True;snapshot=fetch(load())
    report={'status':'PASS','role':'account.analytics.read','scope_probe':'R2_MANAGEMENT_DENIED','secret_values_logged':False,'snapshot':snapshot};message='비용 분석 키 암호화 등록·자동 조회 확인 완료'
   except Exception as e:
    report={'status':'FAIL','diagnostic':str(e) if isinstance(e,MetricsError) else 'CHECK_UNCONFIRMED','credential_saved':saved,'secret_values_logged':False}
    message=('키 인증·암호화 보관 성공, 분석 조회만 미확인 — ' if saved else '키 자체 인증 확인 실패 — ')+report['diagnostic']+' (키는 채팅에 보내지 마세요.)'
   finally:token=None
   REPORT.parent.mkdir(parents=True,exist_ok=True);REPORT.write_text(json.dumps(report),encoding='utf-8');messages.put(message)
  threading.Thread(target=work,daemon=True).start()
 def poll():
  nonlocal busy
  try:status.set(messages.get_nowait());busy=False;button.config(state='normal')
  except queue.Empty:pass
  window.after(200,poll)
 def close():
  if busy:status.set('검사가 끝나면 닫아 주세요.');return
  entry.delete(0,'end');window.destroy()
 button=ttk.Button(window,text='조회 확인 후 Windows 암호화 등록',command=submit);button.pack(pady=8)
 window.report_callback_exception=lambda *args:status.set('처리 미확인. 비밀값은 기록하지 않았습니다.')
 window.protocol('WM_DELETE_WINDOW',close);window.after(200,poll);window.mainloop()
if __name__=='__main__':gui()
