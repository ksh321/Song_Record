"""Owned laptop validation snapshot and daily encrypted backup; credentials are stdin/tmpfs only."""
import datetime as dt
import os
import json
import subprocess
import sys
import threading
import time
from pathlib import Path
import validation_runtime as runtime
from backup_store import BackupError, EncryptedStore, R2, BACKUP_BUCKET, FINAL_BUCKET, MAX_BYTES
from backup_credentials import encryption_key
from operational_backup import Backup
from r2_vault import load, _secure
from workflow_runtime import RunLock, atomic_json

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = ROOT / '.local/workflow/backup'


def bounded(args, limit=MAX_BYTES, input_data=None, timeout=30):
    # stderr discarded, never serialized to a report. Bounded stdout cannot fill host disk/memory.
    process = subprocess.Popen(args, stdin=subprocess.PIPE if input_data is not None else subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                               creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    timer = threading.Timer(timeout, process.kill); timer.start()
    try:
        if input_data is not None:
            process.stdin.write(input_data); process.stdin.close()
        value = process.stdout.read(limit + 1)
        if len(value) > limit:
            process.kill(); raise BackupError('SNAPSHOT_LIMIT')
        if process.wait(timeout=3) != 0:
            raise BackupError('SNAPSHOT_COMMAND_FAILED')
        return value
    finally:
        timer.cancel()
        if process.poll() is None:
            process.kill()
        process.wait(); process.stdout.close()


def snapshot():
    target = runtime.containers()['mysql']
    if not target:
        raise BackupError('VALIDATION_DB_UNAVAILABLE')
    # Scope cannot be switched by an environment variable to a developer/production DB.
    scope = bounded(['docker', 'inspect', '--format', '{{ index .Config.Labels "com.docker.compose.project" }}', target], 256).strip()
    if scope != b'song-record-validation':
        raise BackupError('VALIDATION_DB_SCOPE')
    config = '/run/runtime/backup-client.cnf'
    bounded(['docker', 'exec', '-u', '0', target, 'sh', '-c',
             'umask 077; printf "[client]\\nuser=root\\npassword=%s\\n" "$(cat /run/runtime/root-password)" > /run/runtime/backup-client.cnf'], 256)
    mysql = ['docker', 'exec', '-i', '-u', '0', target, 'mysql', '--defaults-extra-file=' + config,
             '--batch', '--raw', '--skip-column-names', '--unbuffered', 'song_record_validation']
    lock = None; watchdog = None
    try:
        # Limit lock lifetime, including a hung remote Docker client. Server session ends when killed.
        lock = subprocess.Popen(mysql, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                               creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        watchdog = threading.Timer(30, lock.kill); watchdog.start()
        lock.stdin.write(b"SET SESSION lock_wait_timeout=5; SET SESSION wait_timeout=30; FLUSH TABLES WITH READ LOCK; SELECT 'LOCKED';\n"); lock.stdin.flush()
        if lock.stdout.readline(32).strip() != b'LOCKED':
            raise BackupError('SNAPSHOT_LOCK_UNAVAILABLE')
        engines = bounded(mysql, 4096, b"SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='song_record_validation' AND table_type='BASE TABLE' AND engine<>'InnoDB';\n", 8)
        if engines.strip() != b'0':
            raise BackupError('NONTRANSACTIONAL_DB_TABLE')
        pending = bounded(mysql, 256, b"SELECT COUNT(*) FROM app_user WHERE status='DELETING';\n", 8)
        if pending.strip() != b'0':
            raise BackupError('BACKUP_ACCOUNT_PURGE_PENDING')
        subjects = bounded(mysql, 4 * 1024 * 1024, b"SELECT BIN_TO_UUID(id) FROM app_user ORDER BY id;\n", 8).decode('ascii').splitlines()
        query = b"SELECT BIN_TO_UUID(a.user_id),BIN_TO_UUID(a.recording_id),BIN_TO_UUID(a.generation),a.object_key,a.sha256,a.verified_size FROM recording_asset a WHERE a.cloud_state IN ('STORED','DELETING') ORDER BY a.recording_id;\n"
        rows = bounded(mysql, 32 * 1024 * 1024, query, 8)
        files = []
        for line in rows.decode('utf-8').splitlines():
            owner, recording, generation, key, sha, size = line.split('\t')
            files.append({'owner': owner, 'recording': recording, 'generation': generation,
                          'key': key, 'sha256': sha, 'size': int(size)})
        dump = bounded(['docker', 'exec', '-u', '0', target, 'mysqldump', '--defaults-extra-file=' + config,
                        '--single-transaction', '--skip-lock-tables', '--hex-blob', '--no-tablespaces',
                        '--set-gtid-purged=OFF', '--routines', '--triggers', '--events', 'song_record_validation'], timeout=20)
        if lock.poll() is not None:
            raise BackupError('SNAPSHOT_LOCK_EXPIRED')
        lock.stdin.write(b'UNLOCK TABLES;\n'); lock.stdin.close()
        if lock.wait(timeout=3) != 0:
            raise BackupError('SNAPSHOT_LOCK_RELEASE_FAILED')
        return dump, files, subjects
    except BackupError:
        raise
    except Exception:
        raise BackupError('SNAPSHOT_FAILED') from None
    finally:
        if watchdog:
            watchdog.cancel()
        if lock:
            if lock.poll() is None:
                lock.kill()
            lock.wait(); lock.stdout.close()
        bounded(['docker', 'exec', '-u', '0', target, 'rm', '-f', config], 256, timeout=8)


def once():
    _secure(DIRECTORY)
    with RunLock(DIRECTORY / 'execution.lock'):
        try:
            row = runtime.state()
            transport = R2(*load('staging.backup'), BACKUP_BUCKET)
            # Portable envelope is already password-encrypted; no passphrase is read or stored here.
            wrapped = (DIRECTORY / 'recovery-key.enc').read_bytes()
            if len(wrapped) != 84 or not wrapped.startswith(b'SRR1'):
                raise BackupError('RECOVERY_ENVELOPE_INVALID')
            if transport.get('operational/v1/recovery-key.enc') != wrapped:
                transport.put_verified('operational/v1/recovery-key.enc', wrapped)
            backup = EncryptedStore(transport, encryption_key())
            source = R2(*load('staging.playback'), FINAL_BUCKET)
            result = Backup(backup, source, snapshot, row['instance_id'], require_ledger=True).once()
            result.update(observed_utc=dt.datetime.now(dt.timezone.utc).isoformat(), environment='staging',
                          source_deletion=False, restore_test='P24-07_PENDING', ledger_reapply='P24-06_PENDING')
            atomic_json(DIRECTORY / 'latest.json', result)
            atomic_json(DIRECTORY / 'status.json', result)
            return result
        except Exception as error:
            allowed = {'BACKUP_KEY_UNAVAILABLE', 'R2_READ_FAILED', 'R2_TRANSPORT_FAILED',
                       'BACKUP_AUTHENTICATION_FAILED', 'BACKUP_WRITE_VERIFICATION_FAILED',
                       'ENCRYPTED_READBACK_FAILED', 'BACKUP_DELETE_FAILED', 'CATALOG_INVALID',
                       'POINT_MANIFEST_INVALID', 'POINT_CONTENT_INVALID', 'INVALID_DB_FILE_LIST',
                       'SNAPSHOT_LIMIT', 'DUPLICATE_FILE_LIST', 'SOURCE_FILE_MISSING_OR_CHANGED',
                       'INCREMENTAL_COPY_INVALID', 'VALIDATION_DB_UNAVAILABLE', 'VALIDATION_DB_SCOPE',
                       'SNAPSHOT_COMMAND_FAILED', 'SNAPSHOT_LOCK_UNAVAILABLE', 'NONTRANSACTIONAL_DB_TABLE',
                       'SNAPSHOT_LOCK_EXPIRED', 'SNAPSHOT_LOCK_RELEASE_FAILED', 'SNAPSHOT_FAILED'}
            allowed.add('RECOVERY_ENVELOPE_INVALID')
            code = str(error) if isinstance(error, BackupError) and str(error) in allowed else 'BACKUP_UNCONFIRMED'
            atomic_json(DIRECTORY / 'status.json', {'status': 'FAIL', 'observed_utc': dt.datetime.now(dt.timezone.utc).isoformat(),
                                                   'code': code, 'previous_valid_point_preserved': True})
            raise BackupError('BACKUP_UNCONFIRMED') from None


def watch():
    _secure(DIRECTORY)
    with RunLock(DIRECTORY / 'watch.lock'):
        atomic_json(DIRECTORY / 'process.json', {'pid': os.getpid(), 'started_utc': dt.datetime.now(dt.timezone.utc).isoformat(),
                                                'interval_seconds': 3600, 'ai_calls': False})
        while True:
            try:
                status = json.loads((DIRECTORY / 'status.json').read_text(encoding='utf-8')) if (DIRECTORY / 'status.json').exists() else {}
                if status.get('status') != 'PASS' or status.get('day') != dt.datetime.now(dt.timezone.utc).date().isoformat():
                    once()
            except Exception:
                pass  # Fixed failure state remains; operational alert connection belongs to P24-10.
            time.sleep(3600)


if __name__ == '__main__':
    try:
        if sys.argv[1:] == ['watch']:
            watch()
        elif sys.argv[1:] == ['once']:
            print(json.dumps(once()))
        else:
            raise BackupError('INVALID_BACKUP_ACTION')
    except Exception:
        print('Backup unconfirmed; values suppressed.', file=sys.stderr); sys.exit(2)
