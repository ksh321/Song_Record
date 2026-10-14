"""Run server tests on a new loopback-only, labelled disposable MySQL; never reset existing DBs."""
import datetime as dt, json, os, secrets, subprocess, sys, time, uuid
import xml.etree.ElementTree as ET
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
IMAGE='mysql:8.4.11@sha256:85b9bf2e29cf836ecb8c2a15a935d4ba0c606631dff1dd79531a11983c638f2a'

def command(args, input=None):
    r=subprocess.run(args,input=input,capture_output=True,timeout=120)
    if r.returncode:raise RuntimeError('DISPOSABLE_DB_COMMAND_UNCONFIRMED')
    return r.stdout

def run():
    ident=uuid.uuid4().hex;name='sr-p25-ci-'+ident[:12]
    directory=ROOT/'.local/workflow/p25-02'/ident;directory.mkdir(parents=True)
    password=secrets.token_urlsafe(32)
    report={'id':ident,'name':name,'started_utc':dt.datetime.now(dt.timezone.utc).isoformat(),
            'scope':'new disposable tmpfs MySQL only','existing_database_modified':False}
    owned=False
    try:
        command(['docker','run','-d','--name',name,'--label','songrecord.scope=p25-disposable','--label','songrecord.run='+ident,
                 '--tmpfs','/var/lib/mysql:rw,nosuid,nodev,size=2g','--tmpfs','/run/private:rw,noexec,nosuid,nodev,size=1m,mode=0700',
                 '--memory','1g','-p','127.0.0.1::3306','-e','MYSQL_ROOT_PASSWORD_FILE=/run/private/password','-e','MYSQL_ROOT_HOST=%',
                 '--entrypoint','sh',IMAGE,'-c','until test -f /run/private/ready; do sleep 0.2; done; exec docker-entrypoint.sh mysqld'])
        owned=True
        # Secret only in stdin/tmpfs and child test environment, never argv/log/report.
        command(['docker','exec','-i',name,'sh','-c','umask 077; cat > /run/private/password'],password.encode())
        config=('[client]\nuser=root\npassword='+password+'\nhost=127.0.0.1\nport=3306\n').encode()
        command(['docker','exec','-i',name,'sh','-c','umask 077; cat > /run/private/client.cnf'],config)
        command(['docker','exec',name,'touch','/run/private/ready'])
        deadline=time.monotonic()+120
        while True:
            r=subprocess.run(['docker','exec',name,'mysql','--defaults-extra-file=/run/private/client.cnf','-N','-e','SELECT 1'],capture_output=True)
            if r.returncode==0 and r.stdout.strip()==b'1':break
            if time.monotonic()>=deadline:raise RuntimeError('DISPOSABLE_DB_NOT_READY')
            time.sleep(1)
        binding=command(['docker','port',name,'3306/tcp']).decode().strip()
        assert binding.startswith('127.0.0.1:') and binding.count('\n')==0
        port=int(binding.rsplit(':',1)[1]);assert 0<port<65536
        report['loopback_port']=port;report['ready_utc']=dt.datetime.now(dt.timezone.utc).isoformat()
        env=os.environ.copy();env.update(P07_MYSQL_CI='true',P07_MYSQL_PASSWORD=password,P10_MYSQL_PORT=str(port))
        argv=[str(ROOT/'services/api/gradlew.bat'),'test','--rerun-tasks','--offline','--no-daemon']
        print('New disposable MySQL ready; server checks running',flush=True)
        with (directory/'server.log').open('wb') as log:
            result=subprocess.run(argv,cwd=ROOT/'services/api',env=env,stdout=log,stderr=log,timeout=2400)
        env.pop('P07_MYSQL_PASSWORD',None);password=None;config=None
        suites=[ET.parse(p).getroot() for p in (ROOT/'services/api/build/test-results/test').glob('TEST-*.xml')]
        report.update(exit=result.returncode,tests=sum(int(s.get('tests',0)) for s in suites),skipped=sum(int(s.get('skipped',0)) for s in suites),
                      failures=sum(int(s.get('failures',0))+int(s.get('errors',0)) for s in suites))
        required=[s for s in suites if 'MySql' in s.get('name','')]
        report['mysql_tests']=sum(int(s.get('tests',0)) for s in required)
        report['mysql_skipped']=sum(int(s.get('skipped',0)) for s in required)
        report['status']='PASS' if result.returncode==0 and report['mysql_tests']>0 and report['mysql_skipped']==0 and report['failures']==0 else 'FAIL'
        if report['status']=='PASS':
            # Cleanup only this run's newly created synthetic container, not any volume/project.
            labels=json.loads(command(['docker','inspect','--format','{{json .Config.Labels}}',name]))
            assert labels.get('songrecord.scope')=='p25-disposable' and labels.get('songrecord.run')==ident
            command(['docker','rm','-f',name]);owned=False;report['disposable_container_removed']=True
    except Exception:
        report.update(status='UNCONFIRMED',values_suppressed=True)
    finally:
        report.update(ended_utc=dt.datetime.now(dt.timezone.utc).isoformat(),failed_container_preserved=owned)
        (directory/'report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
        (ROOT/'.local/workflow/p25-02/latest.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report),flush=True)
    return 0 if report['status']=='PASS' else 1

if __name__=='__main__':sys.exit(run())
