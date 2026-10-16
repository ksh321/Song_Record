"""Freshness checks over connected experiment monitors; unconnected release gates stay explicit."""
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
from observe import atomic
from notify import send

ROOT = Path('/opt/song-record-experiment/operations')
HEALTH = ROOT/'operational-checks'


def timestamp(value):
    try:
        value = re.sub(r'(\.\d{6})\d+(?=Z|[+-]\d\d:\d\d$)', r'\1', value)
        point = dt.datetime.fromisoformat(value.replace('Z', '+00:00'))
        return point if point.tzinfo else None
    except (TypeError, ValueError, AttributeError):
        return None


def read(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return {}


def reconciliation_timestamp(value):
    # OperationsMetrics projects JDBC Timestamp from the fixed UTC experiment DB.
    # Other monitor timestamps still require their explicit timezone.
    point = timestamp(value)
    if point is not None:
        return point
    if isinstance(value, str) and re.fullmatch(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?', value):
        return timestamp(value+'Z')
    return None


def evaluate(rows, now):
    issues = []
    checks=[('observation', 'observed_utc', 15), ('cost', 'queried_utc', 26*60)]
    if 'backup' in rows:
        checks += [(kind,'observed_utc',minutes) for kind,minutes in [('backup',26*60),('backup_ledger',90),('restore',32*24*60)]]
    for kind, field, minutes in checks:
        success = rows.get(kind, {})
        at = timestamp(success.get(field))
        failed = timestamp(rows.get(kind+'_failure', {}).get(field))
        if success.get('status') != 'PASS' or at is None or not dt.timedelta(0) <= now-at <= dt.timedelta(minutes=minutes):
            issues.append(kind+'_stale_or_unconfirmed')
        elif failed and failed > at:
            issues.append(kind+'_latest_attempt_failed')
    if 'backup' in rows:
        created=timestamp(rows['backup'].get('data_created_utc'))
        if created is None or not dt.timedelta(0)<=now-created<=dt.timedelta(hours=26):
            issues.append('backup_data_stale_or_unconfirmed')
        restored=rows.get('restore',{})
        if not all(restored.get(key) is True for key in ('rpo_goal_met','data_restore_rto_goal_met','disposable_copy_removed')):
            issues.append('restore_goals_or_cleanup_unconfirmed')
    if rows.get('worker_connected'):
        capacity=rows.get('observation',{}).get('capacity',{})
        at=reconciliation_timestamp(capacity.get('reconciliation_at'))
        if at is None or not dt.timedelta(0)<=now-at<=dt.timedelta(hours=26):issues.append('worker_reconciliation_stale_or_unconfirmed')
        if capacity.get('reconciliation_locked') is not False or capacity.get('reconciliation_issue_count')!=0:issues.append('worker_reconciliation_has_issues')
    return sorted(issues)


def once():
    if os.getuid() != 0:
        raise ValueError('ROOT_REQUIRED')
    os.umask(0o077)
    HEALTH.mkdir(mode=0o700, exist_ok=True)
    now = dt.datetime.now(dt.timezone.utc)
    rows = {key:read(ROOT/name) for key,name in {
        'observation':'latest.json', 'observation_failure':'failure.json',
        'cost':'cost-latest.json', 'cost_failure':'cost-failure.json'}.items()}
    if Path('/etc/song-record-experiment/backup-experiment.json').is_file():
        rows.update({key:read(ROOT/name) for key,name in {
            'backup':'backup/latest.json','backup_failure':'backup/failure.json',
            'backup_ledger':'backup/ledger-latest.json','backup_ledger_failure':'backup/ledger-failure.json',
            'restore':'backup/restore-latest.json','restore_failure':'backup/restore-failure.json'}.items()})
        backup_failed=rows['backup_failure'];ledger_failed=rows['backup_ledger_failure']
        if (timestamp(backup_failed.get('observed_utc')) or dt.datetime.min.replace(tzinfo=dt.timezone.utc))>(timestamp(ledger_failed.get('observed_utc')) or dt.datetime.min.replace(tzinfo=dt.timezone.utc)):
            rows['backup_ledger_failure']=backup_failed
    rows['worker_connected']=read(Path('/etc/song-record-experiment/worker-policy.json')).get('upload') is True
    issues = evaluate(rows, now)
    if rows['worker_connected']:
        state=subprocess.run(['docker','inspect','--format','{{.State.Running}} {{.State.Health.Status}}','song-record-experiment-worker-1'],capture_output=True,timeout=10)
        if state.returncode or state.stdout.strip()!=b'true healthy':issues.append('worker_service_unhealthy_or_unconfirmed')
    certificate = Path('/etc/song-record-experiment/letsencrypt/live/experiment-ip/fullchain.pem')
    result = subprocess.run(['openssl','x509','-checkend','86400','-noout','-in',str(certificate)],
                            capture_output=True, timeout=10)
    if result.returncode:
        issues.append('https_certificate_due_or_unconfirmed')
    previous = read(HEALTH/'latest.json')
    key = previous.get('notification_key') if previous.get('issues') == issues else None
    if issues and not key:
        digest = hashlib.sha256('|'.join(issues).encode()).hexdigest()[:16]
        key = 'health-' + digest + '-' + str(int(now.timestamp()))
    report = {'status':'WARNING' if issues else 'PASS', 'observed_utc':now.isoformat(),
              'scope':'connected AWS observation/cost/HTTPS and approved backup freshness', 'issues':issues,
              'release_ready':False, 'notification_key':key if issues else None,
              'release_gates':{**{kind:('NOT_CONNECTED' if kind not in rows else 'UNCONFIRMED'
                  if any(issue.startswith(kind+'_') for issue in issues) else 'PASS')
                  for kind in ('backup','backup_ledger','restore')},
                  'physical_restore_playback':'NOT_EXERCISED','worker_reconciliation':('NOT_CONNECTED' if not rows['worker_connected'] else 'UNCONFIRMED' if any(item.startswith('worker_') for item in issues) else 'PASS')},
              'ai_calls':False}
    atomic(HEALTH/'latest.json', report)
    if issues:
        report['notification_status'] = send('OperationsWarning', key)
        atomic(HEALTH/'latest.json', report)
    return {k:report[k] for k in ['status','observed_utc','issues','release_ready']}


if __name__ == '__main__':
    try:
        print(json.dumps(once()))
    except Exception:
        try:
            atomic(ROOT/'health-failure.json', {'status':'FAIL',
                   'observed_utc':dt.datetime.now(dt.timezone.utc).isoformat(),
                   'diagnostic':'EXPERIMENT_HEALTH_CHECK_UNCONFIRMED'})
        except Exception:
            pass
        print('EXPERIMENT_HEALTH_CHECK_UNCONFIRMED: values suppressed')
        raise SystemExit(2)
