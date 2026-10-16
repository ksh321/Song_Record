"""Hourly R2 observation and its cost-owned DB gate; AWS credit spending remains separate."""
import datetime as dt
import json
import os
from pathlib import Path
import sys

ROOT = Path('/opt/song-record-experiment/operations')
sys.path.insert(0, str(ROOT / 'modules'))
import cloudflare_metrics as metrics
import r2_cost
from observe import operator, atomic
from notify import send


def once():
    if os.getuid() != 0:
        raise ValueError('ROOT_REQUIRED')
    os.umask(0o077)
    now = dt.datetime.now(dt.timezone.utc)
    start, _ = r2_cost.cycle(now)
    try:
        token = json.loads(Path('/etc/song-record-experiment/monitoring.json').read_text())['analytics_token']
        pricing = r2_cost.check_pricing(now)
        snapshot = metrics.fetch(token, start=start, end=now, scope_check=True)
        del token
        report = r2_cost.estimate(snapshot, r2_cost.exchange(now))
        report['pricing_check'] = pricing
        report['separate_costs'].update(server='AWS experimental Free plan credits; remaining credit and VM/disk/IP/transfer spending must be checked separately',
                                       mysql='Existing AWS experiment VM; not a separate free hosted DB',
                                       monitoring='Existing AWS experiment native timer; no AI calls')
        payload = f"observed={report['queried_utc']}\nkrw={report['r2_projected_month_krw']}\n".encode()
        if operator('CostOperator', payload).strip() != b'COST_GATE_APPLIED':
            raise ValueError('EXPERIMENT_COST_GATE_UNCONFIRMED')
        atomic(ROOT / 'cost-latest.json', report)
        level = report['level']
        if level != 'NORMAL':
            kind = {'NOTICE': 'CostNotice', 'WARNING': 'CostWarning', 'LOCK': 'CostLock'}[level]
            send(kind, start.date().isoformat() + '-' + level)
        return {'status': 'PASS', 'level': level, 'queried_utc': report['queried_utc'],
                'gate_applied': True, 'aws_credit_cost_included': False}
    except Exception:
        atomic(ROOT / 'cost-failure.json', {'status': 'FAIL', 'level': 'UNCONFIRMED',
               'queried_utc': now.isoformat(), 'diagnostic': 'EXPERIMENT_COST_CHECK_UNCONFIRMED'})
        try:
            send('CostUnknown', start.date().isoformat() + '-UNCONFIRMED')
        except Exception:
            pass
        raise RuntimeError('EXPERIMENT_COST_CHECK_UNCONFIRMED') from None


if __name__ == '__main__':
    try:
        print(json.dumps(once()))
    except Exception:
        print('EXPERIMENT_COST_CHECK_UNCONFIRMED: values suppressed')
        raise SystemExit(2)
