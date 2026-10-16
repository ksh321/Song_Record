"""Existing experiment only: preserved DB state and isolated app keys into role-private tmpfs."""
import base64
import json
import os
from pathlib import Path
import re
import stat
import subprocess

ROOT=Path('/opt/song-record-experiment')
VAULT=Path('/etc/song-record-experiment')
ROLES={'experiment.api','experiment.worker','experiment.playback'}
BUCKETS=('song-record-experiment-temporary','song-record-experiment-final')
COMPOSE=['docker','compose','--project-name','song-record-experiment','-f',str(ROOT/'compose.yaml')]
STEP='PRECONDITIONS'


def run(args,data=None,timeout=180):
    result=subprocess.run(args,input=data,capture_output=True,timeout=timeout)
    if result.returncode:raise RuntimeError('EXPERIMENT_RUNTIME_COMMAND_FAILED')
    return result.stdout


def private_json(path):
    if path.is_symlink() or path.stat().st_uid!=0 or stat.S_IMODE(path.stat().st_mode)!=0o600:
        raise ValueError('EXPERIMENT_CONFIGURATION_PROTECTION_REQUIRED')
    return json.loads(path.read_text())


def validate_roles(row):
    if set(row)!= {'scope','roles'} or row['scope']!='song_record_experiment_application:v1' or set(row['roles'])!=ROLES:
        raise ValueError('EXPERIMENT_APPLICATION_SCOPE_REJECTED')
    for pair in row['roles'].values():
        if set(pair)!= {'access','secret'} or not re.fullmatch('[0-9a-fA-F]{32}',pair['access']) or not re.fullmatch('[0-9a-fA-F]{64}',pair['secret']):
            raise ValueError('EXPERIMENT_APPLICATION_SCOPE_REJECTED')
    if len({pair['access'] for pair in row['roles'].values()})!=3:raise ValueError('EXPERIMENT_ROLES_MUST_BE_SEPARATE')


def verify_database(info):
    environment=dict(item.split('=',1) for item in info['Config']['Env'] if '=' in item)
    if info['Config']['Labels'].get('com.docker.compose.project')!='song-record-experiment' or environment.get('MYSQL_DATABASE')!='song_record_experiment' or environment.get('MYSQL_USER')!='song_record_experiment':
        raise ValueError('EXPERIMENT_DB_CONTAINER_REJECTED')
    if not any(m.get('Type')=='volume' and m.get('Name')=='song-record-experiment_validation_db' and m.get('Destination')=='/var/lib/mysql' for m in info['Mounts']):
        raise ValueError('EXPERIMENT_DB_VOLUME_REJECTED')


def validate_policy(policy):
    if set(policy)!={'upload','account_deletion'} or any(type(value) is not bool for value in policy.values()):
        raise ValueError('EXPERIMENT_WORKER_POLICY_REJECTED')


def web_settings(web,provider):
    if web is None:return {}
    fields={'scope','enabled','origin','google_client_id','kakao_rest_key','kakao_client_secret','rate_secret'}
    if set(web)!=fields or web['scope']!='song_record_experiment_web:v1' or type(web['enabled']) is not bool:
        raise ValueError('EXPERIMENT_WEB_SCOPE_REJECTED')
    if web['origin']!='https://song-record-beta-ksh321.duckdns.org':
        raise ValueError('EXPERIMENT_WEB_ORIGIN_REJECTED')
    if not isinstance(web['google_client_id'],str) or not re.fullmatch(r'660802266773-[a-z0-9]+\.apps\.googleusercontent\.com',web['google_client_id']) or web['google_client_id']==provider['auth.google.server-client-id']:
        raise ValueError('EXPERIMENT_WEB_AUDIENCE_REJECTED')
    if not isinstance(web['kakao_rest_key'],str) or not re.fullmatch('[a-fA-F0-9]{32}',web['kakao_rest_key']) or web['kakao_rest_key']==provider['auth.kakao.native-app-key']:
        raise ValueError('EXPERIMENT_WEB_KAKAO_REST_KEY_REQUIRED')
    if not isinstance(web['kakao_client_secret'],str) or not re.fullmatch('[A-Za-z0-9_-]{16,256}',web['kakao_client_secret']) or web['kakao_client_secret']==web['kakao_rest_key']:
        raise ValueError('EXPERIMENT_WEB_KAKAO_SECRET_REQUIRED')
    if not isinstance(web['rate_secret'],str) or not re.fullmatch('[a-f0-9]{64}',web['rate_secret']):
        raise ValueError('EXPERIMENT_WEB_RATE_SECRET_REQUIRED')
    if not web['enabled']:return {'account.deletion.web.enabled':'false'}
    return {'account.deletion.web.enabled':'true','account.deletion.web.origin':web['origin'],
            'account.deletion.web.google-client-id':web['google_client_id'],
            'account.deletion.web.kakao-rest-key':web['kakao_rest_key'],
            'account.deletion.web.kakao-client-secret':web['kakao_client_secret'],
            'account.deletion.web.rate-secret':web['rate_secret']}


def observation_settings(role,policy):
    if policy is None:return {'songrecord.operations.retention.enabled':'false'}
    if set(policy)!={'scope','enabled','retention_days'} or policy['scope']!='song_record_experiment_observation:v1' or type(policy['enabled']) is not bool or type(policy['retention_days']) is not int or policy['retention_days']!=30:
        raise ValueError('EXPERIMENT_OBSERVATION_POLICY_REJECTED')
    return {'songrecord.operations.retention.enabled':str(role=='worker' and policy['enabled']).lower()}


def settings(role,state,roles,provider,certificate,pkcs,policy=None,web=None,observation=None):
    if role not in ('api','worker'):raise ValueError('EXPERIMENT_ROLE_REJECTED')
    policy={'upload':False,'account_deletion':False} if policy is None else policy;validate_policy(policy)
    own=roles['roles']['experiment.'+role];reader=roles['roles']['experiment.playback'];prefix='songrecord.storage.dev.'
    allowed={'auth.google.enabled','auth.google.server-client-id','auth.kakao.enabled','auth.kakao.app-id','auth.kakao.native-app-key'}
    extra_provider=set(provider)-allowed
    if not allowed.issubset(provider) or extra_provider-{'auth.kakao.beta-native-app-key'}:
        raise ValueError('EXPERIMENT_PROVIDER_CONFIGURATION_REJECTED')
    beta_native=provider.get('auth.kakao.beta-native-app-key')
    if beta_native is not None and (not isinstance(beta_native,str) or not re.fullmatch('[a-fA-F0-9]{32}',beta_native) or beta_native==provider['auth.kakao.native-app-key']):
        raise ValueError('EXPLICIT_SEPARATE_BETA_NATIVE_KEY_REQUIRED')
    result={'DB_PASSWORD':state['db_password'],'TLS_KEYSTORE_PASSWORD':state['tls_password'],
            'server.p12':base64.b64encode(pkcs).decode(),'server.crt':certificate,
            'songrecord.pagination.key-base64':state['pagination'],'songrecord.karaoke.key-base64':state['karaoke'],
            'songrecord.deployment.storage-scope':'experiment',prefix+'account-id':'c061b2724b72861b43bfe2817be31f35',
            prefix+'temporary-bucket':BUCKETS[0],prefix+'final-bucket':BUCKETS[1],
            prefix+role+'.access-key':own['access'],prefix+role+'.secret-key':own['secret'],
            prefix+'playback.access-key':reader['access'],prefix+'playback.secret-key':reader['secret'],
            'songrecord.upload.scheduling-enabled':str(role=='worker' and policy['upload']).lower(),
            'songrecord.account-deletion.worker.enabled':str(role=='worker' and policy['account_deletion']).lower()}
    result.update(provider)
    result.update(observation_settings(role,observation))
    extra=web_settings(web,provider)
    if role=='api':result.update(extra)
    return result


def start():
    global STEP
    if os.getuid()!=0 or (VAULT/'user-requested-pause').exists():raise ValueError('EXPERIMENT_RUNTIME_PAUSED_OR_NOT_ROOT')
    os.umask(0o077);os.environ['VALIDATION_IMAGE_TAG']='p25-06-experiment'
    STEP='READ_PRIVATE_CONFIGURATION'
    state=private_json(VAULT/'runtime.json');roles=private_json(VAULT/'r2-experiment.json');validate_roles(roles)
    provider=private_json(VAULT/'provider-public.json')
    web=private_json(VAULT/'web-ownership.json') if (VAULT/'web-ownership.json').exists() else None
    policy=private_json(VAULT/'worker-policy.json') if (VAULT/'worker-policy.json').exists() else {'upload':False,'account_deletion':False}
    observation=private_json(VAULT/'observation-policy.json') if (VAULT/'observation-policy.json').exists() else None
    validate_policy(policy)
    if any(policy.values()) and private_json(VAULT/'application-storage.json')!={'scope':'experiment','final_bucket':'song-record-experiment-final'}:
        raise ValueError('EXPERIMENT_WORKER_POLICY_REJECTED')
    # Never initialize a new DB or choose another volume when resuming this existing deployment.
    STEP='VERIFY_EXISTING_DATABASE'
    volume=json.loads(run(['docker','volume','inspect','song-record-experiment_validation_db']))[0]
    if volume['Labels'].get('com.docker.compose.project')!='song-record-experiment':raise ValueError('EXPERIMENT_DB_VOLUME_REJECTED')
    run(COMPOSE+['up','-d','mysql']);db=run(COMPOSE+['ps','-q','mysql']).decode().strip()
    info=json.loads(run(['docker','inspect',db]))[0]
    verify_database(info)
    ready=subprocess.run(['docker','exec',db,'test','-f','/run/runtime/ready'],capture_output=True,timeout=15).returncode==0
    if not ready:
        for name,field in [('db-password','db_password'),('root-password','root_password')]:
            run(['docker','exec','-i','-u','0',db,'sh','-c','umask 077; cat > /run/runtime/'+name],state[field].encode())
        run(['docker','exec','-u','0',db,'touch','/run/runtime/ready'])
    run(COMPOSE+['up','-d','--wait','--wait-timeout','150','mysql'])
    run(COMPOSE+['up','-d','api','worker'])
    for role in ('api','worker'):
        STEP='CONFIGURE_'+role.upper()
        target=run(COMPOSE+['ps','-q',role]).decode().strip()
        info=json.loads(run(['docker','inspect',target]))[0]
        if info['Config']['Labels'].get('com.docker.compose.project')!='song-record-experiment':raise ValueError('EXPERIMENT_APP_CONTAINER_REJECTED')
        ready=subprocess.run(['docker','exec',target,'test','-f','/run/runtime/ready'],capture_output=True,timeout=15).returncode==0
        if ready:
            observed=run(['docker','exec',target,'cat','/run/runtime/songrecord.deployment.storage-scope'],timeout=15).strip()
            if observed!=b'experiment':raise ValueError('EXPERIMENT_APP_RECREATE_REQUIRED')
            continue
        values=settings(role,state,roles,provider,(VAULT/'server.crt').read_text(),(VAULT/'server.p12').read_bytes(),policy,web,observation)
        run(['docker','exec','-i',target,'python3','/app/inject-runtime.py'],json.dumps(values).encode());values.clear()
    STEP='WAIT_FOR_APP_HEALTH'
    run(COMPOSE+['up','-d','--wait','--wait-timeout','150','api','worker'])
    print('EXPERIMENT_PRIVATE_SERVICES_HEALTH_PASS')


if __name__=='__main__':
    try:start()
    except Exception as error:
        try:
            report={'status':'FAIL','step':STEP,'category':type(error).__name__}
            if re.fullmatch('EXPERIMENT_[A-Z_]+',str(error)):report['diagnostic']=str(error)
            path=VAULT/'runtime-failure.json';path.write_text(json.dumps(report));path.chmod(0o600)
        except Exception:pass
        print('EXPERIMENT_ISOLATED_RUNTIME_UNCONFIRMED: values suppressed');raise SystemExit(2)
