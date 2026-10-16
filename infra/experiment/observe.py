"""Private experiment operator bridge; no credential output, customer content or public endpoint."""
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path('/opt/song-record-experiment/operations')
TARGET = 'song-record-experiment-api-1'


def run(args, input_data=None):
    result = subprocess.run(args, input=input_data, capture_output=True, timeout=45)
    if result.returncode or len(result.stdout) > 1_000_000:
        raise RuntimeError('EXPERIMENT_OBSERVATION_UNCONFIRMED')
    return result.stdout


def verify_scope(container):
    if container['Config']['Labels'].get('com.docker.compose.project') != 'song-record-experiment':
        raise ValueError('EXPERIMENT_SCOPE_REJECTED')
    environment = dict(value.split('=', 1) for value in container['Config']['Env'] if '=' in value)
    if environment.get('DB_NAME') != 'song_record_experiment' or environment.get('DB_USER') != 'song_record_experiment':
        raise ValueError('EXPERIMENT_SCOPE_REJECTED')
    if not container['State']['Running']:
        raise ValueError('EXPERIMENT_API_UNAVAILABLE')


def atomic(path, report):
    pending = path.with_suffix('.pending')
    with pending.open('w', encoding='utf-8') as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
        stream.flush()
        os.fsync(stream.fileno())
    pending.replace(path)


def operator(main, payload=None, action=None):
    allowed = {'OperationsOperator': (None,), 'CostOperator': (None,),
               'BackupLedgerOperator': ('snapshot', 'ack'),
               'RestoreValidationOperator': ('migrate', 'metadata', 'check')}
    if main not in allowed or action not in allowed[main]:
        raise ValueError('EXPERIMENT_OPERATOR_SCOPE_REJECTED')
    if os.getuid() != 0:
        raise ValueError('ROOT_REQUIRED')
    os.umask(0o077)
    container = json.loads(run(['docker', 'inspect', TARGET]))[0]
    verify_scope(container)
    artifact = ROOT / 'api-operator.jar'
    manifest = json.loads((ROOT / 'artifact.json').read_text())
    if hashlib.sha256(artifact.read_bytes()).hexdigest() != manifest['sha256']:
        raise ValueError('EXPERIMENT_OPERATOR_ARTIFACT_MISMATCH')
    # A separate bounded container leaves the live API process and its small secret tmpfs intact.
    network = 'song-record-experiment_database'
    if network not in container['NetworkSettings']['Networks']:
        raise ValueError('EXPERIMENT_NETWORK_SCOPE_REJECTED')
    network_row = json.loads(run(['docker', 'network', 'inspect', network]))[0]
    if network_row['Labels'].get('com.docker.compose.project') != 'song-record-experiment':
        raise ValueError('EXPERIMENT_NETWORK_SCOPE_REJECTED')
    credential_mount = []
    if main != 'RestoreValidationOperator':
        private = json.loads(Path('/etc/song-record-experiment/runtime.json').read_text())
        credential = ROOT / 'DB_PASSWORD'
        if credential.exists():
            if credential.is_symlink() or credential.read_text() != private['db_password']:
                raise ValueError('EXPERIMENT_OPERATOR_CREDENTIAL_MISMATCH')
        else:
            with credential.open('x') as stream:
                stream.write(private['db_password'])
        credential.chmod(0o600)
        credential_mount = ['--mount', 'type=bind,src=' + str(credential) + ',dst=/run/runtime/DB_PASSWORD,readonly']
        del private
    name = 'song-record-experiment-' + main.lower()
    try:
        return run(['docker', 'run', '--rm', '-i', '--name', name,
            '--network', network, '--user', '0:0', '--read-only', '--cap-drop', 'ALL',
            '--security-opt', 'no-new-privileges:true', '--memory', '256m', '--cpus', '0.25',
            '--tmpfs', '/tmp:rw,noexec,nosuid,nodev,size=32m',
            '--mount', 'type=bind,src=' + str(artifact) + ',dst=/app/operator.jar,readonly',
            *credential_mount,
            '-e', 'DB_NAME=song_record_experiment', '-e', 'DB_USER=song_record_experiment',
            '--entrypoint', 'java', container['Config']['Image'], '-Xmx128m',
            '-Dloader.main=com.ksh321.songrecord.api.operations.' + main,
            '-cp', '/app/operator.jar', 'org.springframework.boot.loader.launch.PropertiesLauncher']
            + ([action] if action is not None else []), payload)
    finally:
        # Only this tool's disposable process; no application container or DB volume is touched.
        subprocess.run(['docker', 'stop', '--time', '3', name], capture_output=True, timeout=10)


def once():
    report = json.loads(operator('OperationsOperator'))
    if not isinstance(report, dict) or 'observed_utc' not in report or 'capacity' not in report:
        raise ValueError('EXPERIMENT_OBSERVATION_SCHEMA_REJECTED')
    failures=0;retention_failures=0
    for role in ('api','worker'):
        logs=subprocess.run(['docker','logs','--since','1h','--tail','20000','song-record-experiment-'+role+'-1'],capture_output=True,timeout=45)
        data=logs.stdout+logs.stderr
        if logs.returncode or len(data)>4_000_000 or data.count(b'\n')>=20000:
            raise ValueError('EXPERIMENT_OBSERVATION_LOG_COVERAGE_UNCONFIRMED')
        failures+=sum(data.count(marker) for marker in (b'operations_observation_failed',b'operations_job_observation_failed',b'operations_job_observer_failed'))
        retention_failures+=data.count(b'operations_retention_failed')
    report.update(status='PASS' if failures==retention_failures==0 else 'FAIL', scope='private AWS experiment aggregates only',
                  release_ready=False, ai_calls=False, notification_connected=False)
    report.update(observation_write_failures_last_hour=failures,observation_retention_failures_last_hour=retention_failures)
    atomic(ROOT / 'latest.json', report)
    return {'status': report['status'], 'observed_utc': report['observed_utc'], 'release_ready': False}


if __name__ == '__main__':
    try:
        print(json.dumps(once()))
    except Exception:
        try:
            atomic(ROOT / 'failure.json', {'status': 'FAIL',
                   'observed_utc': dt.datetime.now(dt.timezone.utc).isoformat(),
                   'diagnostic': 'EXPERIMENT_OBSERVATION_UNCONFIRMED'})
        except Exception:
            pass
        print('EXPERIMENT_OBSERVATION_UNCONFIRMED: values suppressed')
        raise SystemExit(2)
