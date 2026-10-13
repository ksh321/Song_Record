"""Non-AI cost observation -> private staging DB gate -> deduplicated phone event."""
import datetime as dt,json,os,subprocess,sys,time
from pathlib import Path
import cloudflare_metrics as metrics
import r2_cost
import validation_runtime as runtime
ROOT=Path(__file__).resolve().parents[1];DIRECTORY=ROOT/'.local/workflow/cost';REPORT=DIRECTORY/'latest.json'

def atomic(path,row):
 path.parent.mkdir(parents=True,exist_ok=True);pending=path.with_suffix('.pending');pending.write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding='utf-8');pending.replace(path)

def apply(report):
 target=runtime.containers()['api']
 if not target:raise metrics.MetricsError('VALIDATION_API_UNAVAILABLE')
 payload=f"observed={report['queried_utc']}\nkrw={report['r2_projected_month_krw']}\n".encode()
 runtime.run(['docker','exec','-i',target,'java','-Dloader.main=com.ksh321.songrecord.api.operations.CostOperator','-cp','/app/api.jar','org.springframework.boot.loader.launch.PropertiesLauncher'],input=payload)

def notify(report):
 # Reuse the existing validated topic and fixed text. No credentials/cost raw metrics in phone payload.
 level=report['level'];key=report.get('billing_start',report.get('queried_utc','unknown')[:10])+'|'+level
 if level=='NORMAL':return
 event=DIRECTORY/('event-'+level+'.json')
 if event.exists() and json.loads(event.read_text())['key']==key:return
 # Unknown outcomes are not resent automatically; receipt never implies handset delivery.
 atomic(event,{'key':key,'status':'ATTEMPTED','phone_receipt':'UNCONFIRMED'})
 kind={'NOTICE':'CostNotice','WARNING':'CostWarning','LOCK':'CostLock','UNCONFIRMED':'CostUnknown'}[level]
 try:
  p=subprocess.run(['pwsh','-NoProfile','-File',str(ROOT/'tools/phone-notify.ps1'),'-TaskId','P24-03','-Kind',kind],capture_output=True,timeout=30)
  if p.returncode:raise ValueError()
 except Exception:raise metrics.MetricsError('PHONE_DELIVERY_UNCONFIRMED') from None
 atomic(event,{'key':key,'status':'SERVER_ACCEPTED','phone_receipt':'UNCONFIRMED'})

def once(send_notifications=True):
 try:
  now=dt.datetime.now(dt.timezone.utc);start,_=r2_cost.cycle(now)
  pricing=r2_cost.check_pricing(now)
  snapshot=metrics.fetch(metrics.load(),start=start,end=now);report=r2_cost.estimate(snapshot,r2_cost.exchange(now));report['pricing_check']=pricing;apply(report)
  atomic(REPORT,report)
  if send_notifications:notify(report)
  return report
 except Exception as error:
  # No exception bodies, SQL, secrets, URLs or raw HTTP responses in evidence.
  report={'status':'FAIL','level':'UNCONFIRMED','diagnostic':str(error) if isinstance(error,metrics.MetricsError) else 'COST_CHECK_UNCONFIRMED','queried_utc':dt.datetime.now(dt.timezone.utc).isoformat()}
  atomic(DIRECTORY/'failure.json',report)
  try:
   if send_notifications:notify(report)
  except Exception:pass
  raise metrics.MetricsError(report['diagnostic']) from None

def watch():
 import msvcrt
 DIRECTORY.mkdir(parents=True,exist_ok=True)
 with (DIRECTORY/'monitor.lock').open('a+b') as lock:
  lock.seek(0);lock.write(b'0');lock.flush();lock.seek(0)
  try:msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1)
  except OSError:return
  atomic(DIRECTORY/'process.json',{'pid':os.getpid(),'started_utc':dt.datetime.now(dt.timezone.utc).isoformat()})
  while True:
   try:once()
   except metrics.MetricsError:pass
   # Native background monitor, no AI calls. Refresh hourly; server enforces freshness even if host stops.
   time.sleep(3600)

if __name__=='__main__':
 try:
  if sys.argv[1:] == ['watch']:watch()
  elif sys.argv[1:] == ['once']:print(json.dumps({k:v for k,v in once().items() if k in ('status','level','r2_projected_month_krw')}))
  else:raise metrics.MetricsError('COST_COMMAND_INVALID')
 except Exception:print('COST_MONITOR_UNCONFIRMED: protected local evidence saved',file=sys.stderr);sys.exit(2)
