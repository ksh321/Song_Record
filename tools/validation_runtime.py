"""Local validation only: account-encrypted state, private TLS, sealed stdin into tmpfs."""
import base64,json,secrets,subprocess,sys,os,ssl,urllib.request,urllib.error,re
from pathlib import Path
from r2_vault import _crypt,_secure,load
from r2_credentials import ACCOUNT
ROOT=Path(__file__).resolve().parents[1]
DIRECTORY=ROOT/'.local/workflow/validation'
COMPOSE=['docker','compose','-f',str(ROOT/'infra/validation/compose.yaml')]

def select_image():
 path=DIRECTORY/'image.json'
 tag=os.environ.get('VALIDATION_IMAGE_TAG') or (json.loads(path.read_text())['tag'] if path.exists() else 'p24-01-local')
 if not re.fullmatch(r'p24-\d{2}-local',tag):raise ValueError('Validation image tag invalid')
 os.environ['VALIDATION_IMAGE_TAG']=tag
 return tag
def run(args,**kwargs):
 result=subprocess.run(args,capture_output=True,**kwargs)
 if result.returncode:raise RuntimeError('VALIDATION_COMMAND_FAILED: values suppressed')
 return result.stdout
def state():
 path=DIRECTORY/'runtime.dpapi'
 if path.exists():
  row=json.loads(_crypt(path.read_bytes(),'staging.api',True));assert row['scope']=='song_record_validation:v1';return row
 found=subprocess.run(['docker','volume','inspect','song-record-validation_validation_db'],capture_output=True)
 if found.returncode==0:raise RuntimeError('VALIDATION_STATE_MISSING: preserve existing volume; operator recovery required')
 _secure(DIRECTORY)
 row={'scope':'song_record_validation:v1','instance_id':secrets.token_hex(16),**{key:secrets.token_urlsafe(32) for key in ('db_password','root_password','tls_password')},**{key:base64.b64encode(secrets.token_bytes(32)).decode() for key in ('pagination','karaoke')}}
 encrypted=_crypt(json.dumps(row).encode(),'staging.api');pending=path.with_suffix('.pending')
 with pending.open('xb') as file:file.write(encrypted);file.flush();os.fsync(file.fileno())
 pending.replace(path);return row
def containers():
 select_image()
 return {role:run(COMPOSE+['ps','-q',role]).decode().strip() for role in ('mysql','api','worker')}

def start_cost_monitor():
 # Account-encrypted key must exist; no interactive prompt or synthetic zero estimate.
 if not (ROOT/'.local/workflow/cloudflare/analytics/analytics.dpapi').exists():return 'Cost key absent: new deployment uploads remain closed'
 directory=ROOT/'.local/workflow/cost';directory.mkdir(parents=True,exist_ok=True)
 with (directory/'monitor.log').open('ab') as log:
  subprocess.Popen([sys.executable,str(ROOT/'tools/cost_monitor.py'),'watch'],cwd=ROOT,stdout=log,stderr=log,creationflags=subprocess.CREATE_NO_WINDOW|subprocess.DETACHED_PROCESS)
 return 'Cost monitor requested; freshness is enforced by the server, not process presence'
def start_operations_monitor():
 if int(select_image()[4:6])<4:return 'Operations image not yet deployed'
 directory=ROOT/'.local/workflow/operations';directory.mkdir(parents=True,exist_ok=True)
 with (directory/'monitor.log').open('ab') as log:
  subprocess.Popen([sys.executable,str(ROOT/'tools/operations_monitor.py'),'watch'],cwd=ROOT,stdout=log,stderr=log,creationflags=subprocess.CREATE_NO_WINDOW|subprocess.DETACHED_PROCESS)
 return 'Private operations monitor requested'

def start_backup_monitor():
 directory=ROOT/'.local/workflow/backup'
 if not (directory/'master.dpapi').exists() or not (ROOT/'.local/workflow/cloudflare/credentials/staging.backup.dpapi').exists():return 'Backup registration pending'
 # Reuse the installed desktop dependency runtime with cryptography; no package/API purchase.
 python=Path.home()/'.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
 if not python.is_file():raise RuntimeError('BACKUP_CRYPTO_RUNTIME_UNAVAILABLE')
 with (directory/'monitor.log').open('ab') as log:
  subprocess.Popen([str(python),str(ROOT/'tools/backup_runtime.py'),'watch'],cwd=ROOT,stdout=log,stderr=log,creationflags=subprocess.CREATE_NO_WINDOW|subprocess.DETACHED_PROCESS)
 return 'Private daily backup monitor requested'
def prepare():
 row=state();directory=DIRECTORY/'https';directory.mkdir(exist_ok=True)
 if not (directory/'server.p12').exists():run(['pwsh','-NoProfile','-File',str(ROOT/'infra/validation/create-certificate.ps1')],input=json.dumps({'password':row['tls_password'],'directory':str(directory)}).encode())
 select_image()
 run(COMPOSE+['up','-d','mysql']);target=containers()['mysql'];assert target
 for name,key in (('db-password','db_password'),('root-password','root_password')):
  # Values are stdin only. Root-only tmpfs; no file on host or Docker Config.Env.
  run(['docker','exec','-i','-u','0',target,'sh','-c','umask 077; cat > /run/runtime/'+name],input=row[key].encode())
 run(['docker','exec','-u','0',target,'touch','/run/runtime/ready'])
 return 'Validation MySQL initialized/requested in its own volume; original developer volume unchanged'
def connect():
 row=state();select_image()
 db=containers()['mysql'];assert db
 info=json.loads(run(['docker','inspect',db]))[0];assert info['State'].get('Health',{}).get('Status')=='healthy'
 # Stateless owned services only: fresh tmpfs on resume; the separate DB volume is untouched.
 run(COMPOSE+['up','-d','--force-recreate','api','worker']);targets=containers()
 for role in ('api','worker'):
  access,secret=load('staging.'+role);reader,readsecret=load('staging.playback');prefix='songrecord.storage.dev.'
  values={'DB_PASSWORD':row['db_password'],'TLS_KEYSTORE_PASSWORD':row['tls_password'],'server.p12':base64.b64encode((DIRECTORY/'https/server.p12').read_bytes()).decode(),'server.crt':(DIRECTORY/'https/server.crt').read_text(),'songrecord.pagination.key-base64':row['pagination'],'songrecord.karaoke.key-base64':row['karaoke'],prefix+'account-id':ACCOUNT,prefix+'temporary-bucket':'song-record-staging-dev-temporary',prefix+'final-bucket':'song-record-staging-dev-final',prefix+role+'.access-key':access,prefix+role+'.secret-key':secret,prefix+'playback.access-key':reader,prefix+'playback.secret-key':readsecret}
  run(['docker','exec','-i',targets[role],'python3','/app/inject-runtime.py'],input=json.dumps(values).encode())
  values.clear();access=secret=reader=readsecret=None
 run(COMPOSE+['up','-d','--wait','--wait-timeout','90','api','worker'])
 path=DIRECTORY/'image.json';pending=path.with_suffix('.pending')
 pending.write_text(json.dumps({'tag':os.environ['VALIDATION_IMAGE_TAG']}),encoding='utf-8');pending.replace(path)
 start_cost_monitor()
 start_operations_monitor()
 start_backup_monitor()
 return 'Validation API/worker configured from sealed stdin; no public deployment'
def smoke():
 context=ssl.create_default_context(cafile=str(DIRECTORY/'https/server.crt'))
 client=urllib.request.build_opener(urllib.request.ProxyHandler({}),urllib.request.HTTPSHandler(context=context))
 results={}
 for path in ('/actuator/health','/api/dev/errors/sample','/v1/auth/me'):
  request=urllib.request.Request('https://localhost:18443'+path)
  try:
   with client.open(request,timeout=10) as reply:code=reply.status;body=reply.read(4096)
  except urllib.error.HTTPError as error:code=error.code;body=error.read(4096)
  if path=='/actuator/health':assert code==200 and json.loads(body)['status']=='UP'
  elif path.startswith('/api/dev/'):assert code==404
  else:assert code==401
  results[path]=code
 for provider in ('GOOGLE','KAKAO'):
  request=urllib.request.Request('https://localhost:18443/v1/auth/social',data=json.dumps({'provider':provider,'proof':'development-fake-proof','deviceName':'P24 boundary verification'}).encode(),headers={'Content-Type':'application/json'},method='POST')
  try:
   with client.open(request,timeout=10) as reply:code=reply.status
  except urllib.error.HTTPError as error:code=error.code
  assert code==503 # No real provider configuration: fail closed, never synthetic identity acceptance.
  results['fake-'+provider]=code
 print(json.dumps(results));return 'HTTPS validation boundary smoke PASS'
if __name__=='__main__':
 try:
  action=sys.argv[1];assert action in ('prepare','connect','smoke');print({'prepare':prepare,'connect':connect,'smoke':smoke}[action]())
 except Exception:print('Validation step unconfirmed; inspect protected local state/configuration. Values suppressed.',file=sys.stderr);sys.exit(2)
