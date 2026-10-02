"""Durable primitives for the single local workflow controller (stdlib only)."""
import hashlib
import json
import os
import re
import subprocess
import time
from pathlib import Path


class Blocked(RuntimeError):
    pass


def utc():
    from datetime import datetime, timezone
    return datetime.now(timezone.utc).isoformat()


def process_alive(pid):
    if os.name == 'nt':
        import ctypes
        kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        kernel.OpenProcess.restype = ctypes.c_void_p
        handle = kernel.OpenProcess(0x1000, False, int(pid))
        if not handle:
            return ctypes.get_last_error() == 5  # Access denied is not proof of exit.
        try:
            code = ctypes.c_ulong()
            kernel.GetExitCodeProcess.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_ulong)]
            if not kernel.GetExitCodeProcess(handle, ctypes.byref(code)):
                return True
            return code.value == 259
        finally:
            kernel.CloseHandle.argtypes = [ctypes.c_void_p]
            kernel.CloseHandle(handle)
    try:
        os.kill(int(pid), 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def read_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def atomic_json(path, value, backup_path=None):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    data = json.dumps(value, ensure_ascii=False, indent=2) + '\n'
    json.loads(data)
    temporary = path.with_suffix(path.suffix + '.tmp')
    with temporary.open('w', encoding='utf-8', newline='\n') as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
    if path.exists():
        try:
            previous = read_json(path)
        except (ValueError, OSError):
            pass  # Never replace last known good with damaged bytes.
        else:
            backup = Path(backup_path) if backup_path else path.with_suffix(path.suffix + '.bak')
            backup.parent.mkdir(parents=True, exist_ok=True)
            backup_tmp = Path(str(backup) + '.tmp')
            backup_tmp.write_text(json.dumps(previous, ensure_ascii=False), encoding='utf-8')
            os.replace(backup_tmp, backup)
    os.replace(temporary, path)


def recover_json(path):
    try:
        return read_json(path), False
    except (ValueError, OSError):
        try:
            data = read_json(str(path) + '.bak')
        except (ValueError, OSError):
            raise Blocked('CHECKPOINT_UNRECOVERABLE') from None
        # A recovered checkpoint may predate a successful side effect. Reconcile first.
        return data, True


class RunLock:
    def __init__(self, path):
        self.path = Path(path)
        self.stream = None

    def __enter__(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.stream = self.path.open('a+b')
        if self.path.stat().st_size == 0:
            self.stream.write(b'0')
            self.stream.flush()
        self.stream.seek(0)
        try:
            if os.name == 'nt':
                import msvcrt
                msvcrt.locking(self.stream.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(self.stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            self.stream.close()
            raise Blocked('ANOTHER_RUNNER_OWNS_WORKSPACE') from None
        return self

    def __exit__(self, *args):
        if self.stream:
            self.stream.close()  # OS releases lock on crash too; never steal a live lock.


def git(root, *args):
    env = os.environ.copy()
    env.update(GIT_TERMINAL_PROMPT='0', GCM_INTERACTIVE='Never')
    try:
        result = subprocess.run(['git', '-c', 'safe.directory=' + Path(root).as_posix(),
                                 '-c', 'credential.interactive=false', *args],
                                cwd=root, capture_output=True, text=True, encoding='utf-8',
                                env=env, timeout=120)
    except subprocess.TimeoutExpired:
        raise Blocked('GIT_TIMEOUT:' + args[0]) from None
    if result.returncode:
        raise Blocked('GIT_FAILED:' + args[0])
    return result.stdout.strip()


def relative_path(root, name):
    root = Path(root).resolve()
    path = (root / name).resolve()
    if not path.is_relative_to(root) or path == root or '.git' in path.relative_to(root).parts:
        raise Blocked('PATH_OUTSIDE_WORKSPACE')
    return path


def fingerprint(root, record_paths=()):
    """Tracked + nonignored untracked source, with deletions; ignore only human status records."""
    root = Path(root)
    names = git(root, 'ls-files', '-z', '--cached', '--others', '--exclude-standard').split('\0')
    digest = hashlib.sha256()
    for name in sorted(set(names)):
        if not name or name in ('docs/progress.md', 'docs/workflow-state.json', '내가할일.md'):
            continue
        if name in set(record_paths) | {'docs/verification/user-action-records.md'}:
            continue
        path = relative_path(root, name)
        digest.update(name.encode('utf-8') + b'\0')
        digest.update(path.read_bytes() if path.is_file() else b'<deleted>')
    return digest.hexdigest()


def select_model(models, risk='general', escalate=False):
    model = 'gpt-6-astra' if risk == 'sensitive' or escalate else 'gpt-6.1-sol'
    found = next((m for m in models if m['model'] == model), None)
    if not found:
        raise Blocked('MODEL_UNSUPPORTED:' + model)
    supported = [v['reasoningEffort'] for v in found['supportedReasoningEfforts']]
    levels = [v for v in ('low', 'medium', 'high', 'xhigh', 'max') if v in supported]
    effort = levels[-1] if escalate and levels else 'high' if risk in ('sensitive', 'complex') else 'medium'
    if effort not in supported or effort == 'ultra':
        raise Blocked('EFFORT_UNSUPPORTED:' + effort)
    return {'model': model, 'effort': effort}


def quota_available(capabilities):
    limits = capabilities['rate_limits']
    if limits.get('ordinaryUsageAllowed') is False:
        return False
    buckets = list((limits.get('rateLimitsByLimitId') or {}).values())
    if limits.get('rateLimits'):
        buckets.append(limits['rateLimits'])
    return not any(b.get('spendControlReached') or b.get('rateLimitReachedType') for b in buckets)


def record_failure(incident, execution_id, maximum=False, repaired=False, category='code'):
    incident.setdefault('total', 0)
    incident.setdefault('maximum', 0)
    incident.setdefault('executions', [])
    if execution_id in incident['executions']:
        return failure_action(incident)
    incident['executions'].append(execution_id)
    if category != 'code':
        incident['environment'] = incident.get('environment', 0) + 1
        return 'BLOCKED_ENVIRONMENT'
    if repaired:
        incident['total'] += 1
        if maximum:
            incident['maximum'] += 1
    return failure_action(incident)


def failure_action(incident):
    if incident.get('maximum', 0) >= 3 or incident.get('total', 0) >= 6:
        return 'BLOCKED'
    if incident.get('total', 0) >= 3:
        return 'ESCALATE'
    return 'REPAIR'


def observation_matches(observed, selected):
    return all(observed.get(k) == selected[k] for k in ('model', 'effort')) and observed.get('source') == 'local turn_context'


def redact(text):
    text = re.sub(r'(?i)(authorization\s*[:=]\s*bearer\s+)\S+', r'\1[REDACTED]', text)
    text = re.sub(r'(?i)((?:api[_-]?key|access_token|refresh_token|password)\s*[:=]\s*)[^\s,;]+', r'\1[REDACTED]', text)
    return re.sub(r'https://ntfy\.sh/\S+|sr-[0-9a-f]{48}|\bsk-[A-Za-z0-9_-]+', '[REDACTED]', text)


def execute(argv, cwd, directory, timeout, stop=lambda: False):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    record = {'argv': argv, 'cwd': str(cwd), 'started': utc(), 'status': 'RUNNING'}
    atomic_json(directory / 'command.json', record)
    start = time.monotonic()
    # Batch files must be launched by PowerShell with an argument array, never string interpolation.
    if os.name == 'nt' and argv[0].lower().endswith(('.bat', '.cmd')):
        import base64
        encoded_args = base64.b64encode(json.dumps(argv).encode()).decode()
        script = ("$a=ConvertFrom-Json ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('" +
                  encoded_args + "'))); & $a[0] @($a | Select-Object -Skip 1); exit $LASTEXITCODE")
        argv = ['pwsh', '-NoProfile', '-EncodedCommand', base64.b64encode(script.encode('utf-16-le')).decode()]
    with (directory / 'stdout.log').open('wb') as out, (directory / 'stderr.log').open('wb') as err:
        process = subprocess.Popen(argv, cwd=cwd, stdout=out, stderr=err,
                                   creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        record['pid'] = process.pid
        atomic_json(directory / 'command.json', record)
        while process.poll() is None:
            if stop() or time.monotonic()-start > timeout:
                # Only the subprocess tree owned by this execution is stopped.
                if os.name == 'nt':
                    subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True)
                else:
                    process.terminate()
                process.wait(timeout=15)
                record['status'] = 'CANCELLED' if stop() else 'TIMED_OUT'
                break
            time.sleep(.2)
        else:
            record['status'] = 'PASS' if process.returncode == 0 else 'FAIL'
    record.update(exit_code=process.returncode, finished=utc(), duration_seconds=time.monotonic()-start)
    for name in ('stdout.log', 'stderr.log'):
        path = directory / name
        path.write_text(redact(path.read_text(encoding='utf-8', errors='replace')), encoding='utf-8')
    atomic_json(directory / 'command.json', record)
    return record
