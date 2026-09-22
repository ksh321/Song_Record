"""Run the existing P04 MySQL checks in a fresh, isolated Docker Compose project.

Windows: py -3.14 infra/scripts/verify_p04_disposable.py
Focused P04-09 check: add --scope tj-race (fresh V7 DB, no repeat of the regression suite).
Requires Docker Desktop (Linux containers), Java 21 and Git for Windows.
Build services/api with gradlew.bat bootJar first. No third-party Python packages.

This wrapper runs the repository's existing V1 -> V7 migration/constraint checks.
It does not declare all of P04-09 complete or verify Android process recreation.
The source checkout, infra/.env and the development database are not written.
Only this run's generated Compose project/volume is removed on exit.

Compose isolation reference:
https://docs.docker.com/compose/how-tos/environment-variables/envvars/
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import queue
import re
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
from datetime import datetime, timezone


SCRIPTS = (
    'verify_p04_migrations.sh', 'verify_p04_core_schema.sh',
    'verify_p04_extended_schema.py', 'verify_p04_retention_schema.py',
    'verify_p04_sync_schema.py', 'verify_p04_snapshot_schema.py',
)
SUCCESS_LINE = 'P04-01~07 upgrade, constraints and restart verification passed.'
TJ_SCRIPTS = ('verify_p04_migrations.sh', 'verify_p04_extended_schema.py',
              'verify_p04_tj_race.py')
TJ_SUCCESS_LINE = 'P04-09 TJ number race verification passed.'


def clean_environment(source):
    # Explicitly prevent inherited application/Compose settings from redirecting SQL.
    prefixes = ('COMPOSE_', 'SPRING_', 'DB_', 'MYSQL_', 'P04_', 'SERVER_')
    removed = {'BASH_ENV', 'ENV', 'JAVA_TOOL_OPTIONS', '_JAVA_OPTIONS',
               'JDK_JAVA_OPTIONS', 'PYTHONHOME', 'PYTHONPATH',
               'MSYS_NO_PATHCONV', 'MSYS2_ARG_CONV_EXCL', 'MSYS2_ENV_CONV_EXCL'}
    return {key: value for key, value in source.items()
            if not key.upper().startswith(prefixes) and key.upper() not in removed}


def find_bash(explicit, env):
    if explicit:
        candidates = [Path(explicit)]
    elif os.name == 'nt':
        candidates = []
        git = shutil.which('git', path=env.get('PATH'))
        if git:
            for parent in Path(git).resolve().parents:
                candidates.extend((parent / 'bin/bash.exe', parent / 'usr/bin/bash.exe'))
        for variable in ('ProgramFiles', 'ProgramFiles(x86)', 'LOCALAPPDATA'):
            base = env.get(variable.upper(), env.get(variable))
            if base:
                candidates.extend((Path(base) / 'Git/bin/bash.exe',
                                   Path(base) / 'Programs/Git/bin/bash.exe'))
    else:
        candidates = [Path(shutil.which('bash') or '/bin/bash')]
    for candidate in candidates:
        if not candidate.is_file():
            continue
        result = subprocess.run([str(candidate), '--noprofile', '--norc', '-c', 'uname -s'],
                                env=env, capture_output=True, text=True, timeout=15)
        if result.returncode == 0 and (os.name != 'nt' or
                                      re.search(r'MINGW|MSYS', result.stdout)):
            return candidate.resolve()
    raise RuntimeError('Git Bash was not found. Pass --bash "C:/Program Files/Git/bin/bash.exe" '
                       'with the actual Git for Windows path. WSL bash is not used.')


def unused_ports():
    # Hold both reservations together so they cannot choose the same port.
    with socket.socket() as database, socket.socket() as api:
        database.bind(('127.0.0.1', 0))
        api.bind(('127.0.0.1', 0))
        return database.getsockname()[1], api.getsockname()[1]


def make_compose(image, port, password, root_password):
    return {
        'services': {'mysql': {
            'image': image,
            'environment': {'TZ': 'UTC', 'MYSQL_DATABASE': 'song_record_p0409',
                            'MYSQL_USER': 'p0409', 'MYSQL_PASSWORD': password,
                            'MYSQL_ROOT_PASSWORD': root_password},
            'ports': [f'127.0.0.1:{port}:3306'],
            'command': ['--character-set-server=utf8mb4',
                        '--collation-server=utf8mb4_0900_ai_ci',
                        '--default-time-zone=+00:00',
                        '--log-bin-trust-function-creators=1'],
            'volumes': ['test_data:/var/lib/mysql'],
            'healthcheck': {
                'test': ['CMD-SHELL', 'MYSQL_PWD="$${MYSQL_ROOT_PASSWORD}" '
                         'mysqladmin ping -h127.0.0.1 -uroot --silent'],
                'interval': '2s', 'timeout': '5s', 'retries': 60,
                'start_period': '30s'},
        }},
        'volumes': {'test_data': {}},
    }


def stop_owned_process(process):
    if process.poll() is not None:
        return
    if os.name == 'nt':
        # The PID belongs to a process started by this wrapper, never all java.exe.
        subprocess.run(['taskkill.exe', '/PID', str(process.pid), '/T', '/F'],
                       capture_output=True, timeout=20)
    else:
        os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        if os.name != 'nt':
            os.killpg(process.pid, signal.SIGKILL)
        else:
            process.kill()
        process.wait(timeout=10)


class Runner:
    def __init__(self, directory, env, secret_values):
        self.directory = directory
        self.env = env
        self.secret_values = secret_values
        self.log_path = directory / 'verification.log'

    def emit(self, text):
        text = str(text)
        for secret in self.secret_values:
            text = text.replace(secret, '[REDACTED]')
        print(text, flush=True)
        with self.log_path.open('a', encoding='utf-8') as output:
            output.write(text + '\n')

    def run(self, command, *, timeout=60, check=True, show=True):
        options = ({'creationflags': subprocess.CREATE_NEW_PROCESS_GROUP}
                   if os.name == 'nt' else {'start_new_session': True})
        process = subprocess.Popen(command, cwd=self.directory, env=self.env,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   stdin=subprocess.DEVNULL, text=True, encoding='utf-8',
                                   errors='replace', **options)
        messages = queue.Queue()

        def read_output():
            try:
                for line in process.stdout:
                    messages.put(line.rstrip('\r\n'))
            finally:
                messages.put(None)

        reader = threading.Thread(target=read_output, daemon=True)
        reader.start()
        lines = []
        deadline = time.monotonic() + timeout
        heartbeat = time.monotonic() + 20
        try:
            while True:
                if time.monotonic() >= deadline:
                    raise RuntimeError(f'Command exceeded {timeout}s: {command[0]}')
                try:
                    line = messages.get(timeout=0.5)
                except queue.Empty:
                    if show and time.monotonic() >= heartbeat:
                        self.emit('[waiting] The current step is still running...')
                        heartbeat = time.monotonic() + 20
                    continue
                if line is None:
                    break
                lines.append(line)
                if show:
                    self.emit(line)
                heartbeat = time.monotonic() + 20
            code = process.wait(timeout=max(1, deadline - time.monotonic()))
        finally:
            stop_owned_process(process)
            reader.join(timeout=2)
            process.stdout.close()
        output = '\n'.join(lines)
        if check and code != 0:
            if not show:
                self.emit(output)
            raise RuntimeError(f'Command failed (exit {code}): {command[0]}')
        return code, output


def prepare(repo, directory, env, bash, scope='regression'):
    scripts_dir = directory / 'infra/scripts'
    scripts_dir.mkdir(parents=True)
    hashes = {}
    names = TJ_SCRIPTS if scope == 'tj-race' else SCRIPTS
    for name in names:
        source = repo / 'infra/scripts' / name
        text = source.read_text(encoding='utf-8-sig')
        hashes[name] = hashlib.sha256(text.encode('utf-8')).hexdigest()
        # Normalize only the copied scripts: Windows CRLF must not break Bash.
        (scripts_dir / name).write_text(text, encoding='utf-8', newline='\n')
    jar = repo / 'services/api/build/libs/api-0.0.1-SNAPSHOT.jar'
    copy = directory / 'services/api/build/libs' / jar.name
    copy.parent.mkdir(parents=True)
    shutil.copy2(jar, copy)
    launcher = directory / 'run_checks.sh'
    launcher.write_text(
        '#!/usr/bin/env bash\nset -euo pipefail\n'
        'python3() { "$P04_VERIFY_PYTHON" "$@"; }\n'
        'export -f python3\n'
        'exec bash "$1"\n', encoding='utf-8', newline='\n')
    env['P04_VERIFY_PYTHON'] = Path(sys.executable).resolve().as_posix()
    driver = scripts_dir / SCRIPTS[0]
    if scope == 'tj-race':
        # Reuse the original guarded startup/cleanup functions, but migrate once
        # directly to current V7. The original repository script is not edited.
        original = driver.read_text(encoding='utf-8')
        boundary = '\nstart_api "1"\n'
        if original.count(boundary) != 1:
            raise RuntimeError('Migration driver layout changed; review focused startup before running.')
        prefix = original.split(boundary, 1)[0]
        driver = scripts_dir / 'verify_p04_tj_only.sh'
        driver.write_text(prefix + '\nstart_api ""\nstop_api\n'
                          'python3 "$infra_dir/scripts/verify_p04_tj_race.py"\n',
                          encoding='utf-8', newline='\n')
        hashes[driver.name] = hashlib.sha256(driver.read_bytes()).hexdigest()
    return [str(bash), '--noprofile', '--norc', launcher.as_posix(),
            driver.as_posix()], hashes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=None, help='Song_Record repository root')
    parser.add_argument('--bash', help='Optional absolute Git Bash executable path')
    parser.add_argument('--scope', choices=('regression', 'tj-race'), default='regression',
                        help='Existing V1-V7 suite or only the extra P04-09 TJ-number races')
    args = parser.parse_args()
    repo = (args.repo or Path(__file__).resolve().parents[2]).resolve()
    env = clean_environment(os.environ)
    for relative in ('infra/compose.yaml', 'services/api/build/libs/api-0.0.1-SNAPSHOT.jar',
                     *(f'infra/scripts/{name}' for name in
                       (TJ_SCRIPTS if args.scope == 'tj-race' else SCRIPTS))):
        if not (repo / relative).is_file():
            raise RuntimeError(f'Missing {repo / relative}. Check --repo and run bootJar first.')
    docker = shutil.which('docker', path=env.get('PATH'))
    java = shutil.which('java', path=env.get('PATH'))
    if not docker or not java:
        raise RuntimeError('docker and java must be available in this terminal.')
    bash = find_bash(args.bash, env)
    compose_source = (repo / 'infra/compose.yaml').read_text(encoding='utf-8-sig')
    match = re.search(r'^\s+image:\s*(mysql:[0-9.]+@sha256:[0-9a-f]{64})\s*$',
                      compose_source, re.MULTILINE)
    if not match:
        raise RuntimeError('Expected a digest-pinned MySQL image in infra/compose.yaml.')
    directory = Path(tempfile.mkdtemp(prefix='song-record-p0409-')).resolve()
    project = 'song-record-p0409-' + secrets.token_hex(8)
    password, root_password = secrets.token_hex(24), secrets.token_hex(24)
    mysql_port, api_port = unused_ports()
    compose_file = directory / 'compose.json'
    config = make_compose(match.group(1), mysql_port, password, root_password)
    compose_file.write_text(json.dumps(config, indent=2), encoding='utf-8')
    (directory / 'empty.env').write_text('', encoding='utf-8')
    env.update({
        'COMPOSE_FILE': compose_file.as_posix(), 'COMPOSE_PROJECT_NAME': project,
        'COMPOSE_ENV_FILES': (directory / 'empty.env').as_posix(),
        'COMPOSE_DISABLE_ENV_FILE': '1', 'COMPOSE_ANSI': 'never', 'COMPOSE_MENU': 'false',
        'PYTHONUTF8': '1', 'PYTHONUNBUFFERED': '1',
        'MYSQL_DATABASE': 'song_record_p0409', 'MYSQL_USER': 'p0409',
        'MYSQL_PORT': str(mysql_port), 'DB_PASSWORD': password,
        'P04_API_PORT': str(api_port), 'P04_DISPOSABLE_DB': '1',
    })
    runner = Runner(directory, env, (password, root_password))
    compose = [docker, 'compose', '-p', project, '-f', compose_file.as_posix(),
               '--env-file', (directory / 'empty.env').as_posix()]
    result = {'started_utc': datetime.now(timezone.utc).isoformat(), 'repo': str(repo),
              'project': project, 'mysql_port': mysql_port, 'api_port': api_port,
              'scope': args.scope, 'mysql_regression': 'NOT_RUN',
              'tj_number_race': 'NOT_RUN', 'android_process_recreation': 'NOT_RUN'}
    result_key = 'tj_number_race' if args.scope == 'tj-race' else 'mysql_regression'
    result_label = 'TJ number race' if args.scope == 'tj-race' else 'MySQL regression'
    success_line = TJ_SUCCESS_LINE if args.scope == 'tj-race' else SUCCESS_LINE
    started = False
    exit_code = 1
    try:
        runner.emit(f'Log folder: {directory}')
        runner.emit(f'Test project: {project}; MySQL port: {mysql_port}; API port: {api_port}')
        _, version = runner.run([java, '-version'], show=False)
        if not re.search(r'version "21[.\"]', version):
            raise RuntimeError('This verification requires Java 21 in PATH. Found: ' + version)
        result['java'] = version
        _, engine = runner.run([docker, 'info', '--format', '{{.OSType}}'], show=False)
        if engine.strip() != 'linux':
            raise RuntimeError('Docker must be running Linux containers.')
        runner.run(compose + ['version'])
        command, hashes = prepare(repo, directory, env, bash, args.scope)
        result['script_sha256_lf'] = hashes
        with (directory / 'services/api/build/libs/api-0.0.1-SNAPSHOT.jar').open('rb') as jar:
            result['jar_sha256'] = hashlib.file_digest(jar, 'sha256').hexdigest()
        git = shutil.which('git', path=env.get('PATH'))
        if git:
            _, commit = runner.run([git, '-C', str(repo), 'rev-parse', 'HEAD'], show=False)
            result['commit'] = commit.strip()
        # Both an explicit project and an explicit generated file are always supplied.
        started = True
        runner.emit('[1/2] Starting the disposable MySQL container...')
        runner.run(compose + ['up', '-d', '--wait', '--wait-timeout', '180', 'mysql'], timeout=600)
        sql = 'SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE();'
        _, empty = runner.run(compose + ['exec', '-T', 'mysql', 'sh', '-lc',
            'MYSQL_PWD="$MYSQL_PASSWORD" mysql --protocol=tcp -h127.0.0.1 '
            '-u"$MYSQL_USER" "$MYSQL_DATABASE" --batch --skip-column-names -e ' + "'" + sql + "'"],
            show=False)
        if empty.strip() != '0':
            raise RuntimeError('Expected a completely empty test schema. Checks were not started.')
        runner.emit('[2/2] Migrating fresh DB to V7 and checking TJ-number races...'
                    if args.scope == 'tj-race' else
                    '[2/2] Running the existing V1 -> V7 migration and constraint checks...')
        _, output = runner.run(command, timeout=1800)
        if success_line not in output:
            raise RuntimeError('The verifier exited without its final success message.')
        result[result_key] = 'PASS'
        exit_code = 0
    except KeyboardInterrupt:
        runner.emit('Interrupted. Cleaning up this test project...')
        result[result_key] = 'INTERRUPTED'
        exit_code = 130
    except Exception as error:
        runner.emit('ERROR: ' + str(error))
        result[result_key] = 'FAIL'
        result['error'] = str(error).replace(password, '[REDACTED]').replace(root_password, '[REDACTED]')
    finally:
        if started:
            runner.emit('Removing this run\'s test container and test volume...')
            try:
                runner.run(compose + ['down', '--volumes', '--timeout', '10'], timeout=90)
                result['cleanup'] = 'PASS'
            except Exception as error:
                result['cleanup'] = 'FAIL'
                runner.emit('Cleanup needs attention: ' + str(error))
                runner.emit(f'Test project to inspect: {project}')
                exit_code = exit_code or 1
        else:
            result['cleanup'] = 'NOT_NEEDED'
        result['finished_utc'] = datetime.now(timezone.utc).isoformat()
        (directory / 'result.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
        runner.emit(f"{result_label}: {result[result_key]}; cleanup: {result['cleanup']}")
        runner.emit('Android account-storage process recreation: NOT RUN by this script.')
        runner.emit(f'Result: {directory / "result.json"}')
        runner.emit(f'Log: {runner.log_path}')
    return exit_code


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(errors='backslashreplace')
    try:
        sys.exit(main())
    except Exception as error:
        print('ERROR:', error, file=sys.stderr)
        sys.exit(1)
