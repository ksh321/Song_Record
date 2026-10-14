"""Private validation operations aggregates, no AI and no raw log/credential output."""
import json,sys,datetime as dt,os,time
from pathlib import Path
import validation_runtime as runtime
from cost_monitor import atomic
ROOT=Path(__file__).resolve().parents[1];DIRECTORY=ROOT/'.local/workflow/operations'
def once():
 targets=runtime.containers();target=targets['api']
 if not target:raise RuntimeError('OPERATIONS_API_UNAVAILABLE')
 raw=runtime.run(['docker','exec',target,'java','-Dloader.main=com.ksh321.songrecord.api.operations.OperationsOperator','-cp','/app/api.jar','org.springframework.boot.loader.launch.PropertiesLauncher'])
 if len(raw)>1000000:raise RuntimeError('OPERATIONS_SNAPSHOT_TOO_LARGE')
 report=json.loads(raw);failures=0
 for role in ('api','worker'):
  # Values stay in process memory; only fixed failure markers are counted.
  logs=runtime.run(['docker','logs','--since','1h','--tail','20000',targets[role]])
  if len(logs)>4000000 or logs.count(b'\n')>=20000:raise RuntimeError('OPERATIONS_LOG_COVERAGE_UNCONFIRMED')
  failures+=sum(logs.count(marker) for marker in (b'operations_observation_failed',b'operations_job_observation_failed',b'operations_job_observer_failed'))
 report['observation_write_failures_last_hour']=failures;report['status']='PASS' if failures==0 else 'FAIL'
 atomic(DIRECTORY/'latest.json',report);return report
def watch():
 import msvcrt
 from operational_checks import once as check_operational_evidence
 DIRECTORY.mkdir(parents=True,exist_ok=True)
 with (DIRECTORY/'monitor.lock').open('a+b') as lock:
  lock.seek(0);lock.write(b'0');lock.flush();lock.seek(0)
  try:msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1)
  except OSError:return
  atomic(DIRECTORY/'process.json',{'pid':os.getpid(),'started_utc':dt.datetime.now(dt.timezone.utc).isoformat()})
  while True:
   try:once()
   except Exception:atomic(DIRECTORY/'failure.json',{'status':'FAIL','diagnostic':'OPERATIONS_OBSERVATION_UNCONFIRMED','observed_utc':dt.datetime.now(dt.timezone.utc).isoformat()})
   try:check_operational_evidence()
   except Exception:atomic(ROOT/'.local/workflow/operational-checks/failure.json',{'status':'UNCONFIRMED','values_suppressed':True})
   time.sleep(60)
if __name__=='__main__':
 try:
  if sys.argv[1:]==['watch']:watch()
  elif sys.argv[1:]==['once']:r=once();print(json.dumps({'status':r['status'],'observed_utc':r['observed_utc'],'observation_write_failures_last_hour':r['observation_write_failures_last_hour']}))
  else:raise ValueError()
 except Exception:print('OPERATIONS_MONITOR_UNCONFIRMED: values suppressed',file=sys.stderr);sys.exit(2)
