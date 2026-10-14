"""Non-AI freshness/deadline checks over existing private operator evidence."""
import calendar, datetime as dt, hashlib, json, os, re, subprocess, sys, time
from pathlib import Path
from cost_monitor import atomic
from workflow_runtime import RunLock
ROOT=Path(__file__).resolve().parents[1]
DIRECTORY=ROOT/'.local/workflow/operational-checks'
UTC=dt.timezone.utc

def read(path):
    try: return json.loads(path.read_text(encoding='utf-8-sig'))
    except (OSError, ValueError): return {}

def stamp(value):
    try:
        # Java Instant may contain nanoseconds; laptop Python 3.10 accepts microseconds.
        value=re.sub(r'(\.\d{6})\d+(?=Z|[+-]\d\d:\d\d$)',r'\1',value)
        value=dt.datetime.fromisoformat(value.replace('Z','+00:00'))
        return value if value.tzinfo else None
    except (ValueError, TypeError, AttributeError): return None

def fresh(row, field, now, hours):
    point=stamp(row.get(field))
    return row.get('status')=='PASS' and point is not None and dt.timedelta(0)<=now-point<=dt.timedelta(hours=hours)

def next_month(point):
    year=point.year+(point.month==12);month=point.month%12+1
    return point.replace(year=year,month=month,day=min(point.day,calendar.monthrange(year,month)[1]))

def evaluate(rows, now):
    checks={name:('PASS' if fresh(rows.get(name,{}),field,now,hours) else 'WARNING')
            for name,field,hours in [('backup','observed_utc',26),('ledger','observed_utc',1),('observation','observed_utc',1)]}
    restore=rows.get('restore',{});point=stamp(restore.get('observed_utc'))
    checks['monthly_restore']='PASS' if restore.get('status')=='PASS' and point and point<=now<next_month(point) else 'DUE_OR_UNCONFIRMED'
    checks['cost']='PASS' if fresh(rows.get('cost',{}),'queried_utc',now,26) and rows['cost'].get('level')!='UNCONFIRMED' else 'WARNING'
    # This environment intentionally has destructive maintenance disabled.
    # Register the launch gate; do not pretend the daily R2/DB comparison ran.
    checks['daily_object_comparison']='RELEASE_GATE_NOT_CONNECTED'
    return {'observed_utc':now.isoformat(),'status':'PASS' if all(checks[k]=='PASS' for k in checks if k!='daily_object_comparison') else 'WARNING',
            'checks':checks,'monthly_restore_due_utc':next_month(point).isoformat() if point else None,
            'daily_object_comparison_required_before_launch':True,'scope':'connected private monitor evidence only',
            'release_ready':False,'ai_calls':False,'host_must_be_awake':True}

def notify(report):
    # Cost already has its own fixed, deduplicated phone notification.
    issues=sorted(k for k,v in report['checks'].items() if k!='cost' and v in ('WARNING','DUE_OR_UNCONFIRMED'))
    path=DIRECTORY/'alert.json';old=read(path)
    if not issues:
        atomic(path,{'active':None});return
    key=hashlib.sha256('|'.join(issues).encode()).hexdigest()
    if old.get('active')==key:return
    attempted=stamp(read(ROOT/'.local/workflow/phone/attempt.json').get('utc'))
    if attempted and dt.datetime.now(UTC)-attempted<dt.timedelta(seconds=60):return
    atomic(path,{'active':key,'status':'ATTEMPTED','phone_receipt':'UNCONFIRMED'})
    result=subprocess.run(['pwsh','-NoProfile','-File',str(ROOT/'tools/phone-notify.ps1'),'-TaskId','P24-10','-Kind','OperationsWarning'],capture_output=True,timeout=30,creationflags=getattr(subprocess,"CREATE_NO_WINDOW",0))
    atomic(path,{'active':key,'status':'SERVER_ACCEPTED' if result.returncode==0 else 'UNCONFIRMED','phone_receipt':'UNCONFIRMED'})

def once(send=True):
    base=ROOT/'.local/workflow'
    paths={'backup':'backup/status.json','ledger':'backup-ledger/latest.json','observation':'operations/latest.json','restore':'restore/latest.json','cost':'cost/latest.json'}
    rows={k:read(base/v) for k,v in paths.items()}
    failure=read(base/'operations/failure.json')
    failed_at=stamp(failure.get('observed_utc'));passed_at=stamp(rows['observation'].get('observed_utc'))
    if failed_at and (passed_at is None or failed_at>passed_at):rows['observation']['status']='FAIL'
    report=evaluate(rows,dt.datetime.now(UTC))
    atomic(DIRECTORY/'latest.json',report)
    if send:notify(report)
    return report

def watch():
    DIRECTORY.mkdir(parents=True,exist_ok=True)
    with RunLock(DIRECTORY/'watch.lock'):
        atomic(DIRECTORY/'process.json',{'pid':os.getpid(),'ai_calls':False,'interval_seconds':60})
        while True:
            try:once()
            except Exception:atomic(DIRECTORY/'failure.json',{'status':'UNCONFIRMED','values_suppressed':True})
            time.sleep(60)

if __name__=='__main__':
    try:
        if sys.argv[1:]==['watch']:watch()
        elif sys.argv[1:] in (['once'],['check']):print(json.dumps(once(sys.argv[1]=='once')))
        else:raise ValueError()
    except Exception:print('OPERATIONAL_CHECK_UNCONFIRMED: values suppressed',file=sys.stderr);sys.exit(2)
