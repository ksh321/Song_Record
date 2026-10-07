"""Derived, offline usage reports. Never infer subscription quota from tokens."""
import json
import os
import re
from collections import defaultdict
from datetime import datetime
from pathlib import Path

from workflow_runtime import atomic_json, utc

FIELDS = ('input_tokens', 'cached_input_tokens', 'output_tokens',
          'reasoning_output_tokens', 'total_tokens')
STAGES = ('PLAN', 'IMPLEMENT', 'DIAGNOSE', 'REVIEW', 'FINALIZE')


def rows(path, issues):
    try:
        with Path(path).open(encoding='utf-8-sig') as stream:
            for line in stream:
                try:
                    value = json.loads(line)
                    if not isinstance(value, dict):
                        raise ValueError()
                    yield value
                except ValueError:
                    issues['unreadable_rows'] += 1
    except OSError:
        issues['unavailable_logs'] += 1


def tokens(value):
    if not isinstance(value, dict):
        return None
    result = {key: value.get(key) for key in FIELDS}
    if any(type(v) is not int or v < 0 for v in result.values()):
        return None
    if (result['cached_input_tokens'] > result['input_tokens'] or
            result['reasoning_output_tokens'] > result['output_tokens'] or
            result['total_tokens'] != result['input_tokens'] + result['output_tokens']):
        return None
    return result


def elapsed(start, end):
    try:
        seconds = (datetime.fromisoformat(end) - datetime.fromisoformat(start)).total_seconds()
        return round(seconds, 3) if seconds >= 0 else None
    except (TypeError, ValueError):
        return None


def summarize(events_path, rollout_paths):
    issues = defaultdict(int)
    calls, pending = {}, {}
    for row in rows(events_path, issues):
        data = row.get('data', {})
        if not isinstance(data, dict):
            issues['unreadable_rows'] += 1
            continue
        kind = row.get('kind')
        if kind == 'model_intent':
            pending = {k: data.get(k) for k in ('task_id', 'stage', 'thread_id',
                                             'requested_model', 'requested_effort')}
            pending['started'] = row.get('utc')
        elif kind in ('model_accepted', 'model_completed') and data.get('turn_id'):
            turn = data['turn_id']
            if turn not in calls:
                calls[turn] = dict(pending)
            call = calls[turn]
            for key in ('task_id', 'stage', 'thread_id'):
                if data.get(key):
                    call[key] = data[key]
            call['status'] = data.get('status', 'accepted')
            if kind == 'model_completed':
                call['finished'] = row.get('utc')
                observation = data.get('observation') or {}
                if observation.get('model') not in (None, 'unknown'):
                    call['model'] = observation['model']
                    call['effort'] = observation.get('effort', 'unknown')
                pending = {}

    # Use response identities and per-response usage, never summed thread totals
    # or the final response's `last` value as the entire controller turn.
    responses, invalid, expected, conflicted = {}, set(), {}, set()
    for path in dict.fromkeys(map(str, rollout_paths)):
        current = None
        for row in rows(path, issues):
            kind, data = row.get('type'), row.get('payload', {})
            if not isinstance(data, dict):
                continue
            event = data.get('type')
            if kind == 'turn_context' or (kind == 'event_msg' and event == 'task_started'):
                current = data.get('turn_id')
            call = calls.get(current)
            if call is not None:
                if kind == 'turn_context':
                    call['model'] = data.get('model', call.get('model', 'unknown'))
                    call['effort'] = data.get('effort', call.get('effort', 'unknown'))
                elif kind == 'response_item' and data.get('role') == 'user':
                    message = '\n'.join(c.get('text', '') for c in data.get('content', [])
                                        if isinstance(c, dict))
                    task = re.match(r'^현재 P번호 (P\d{2}-\d{2})(?:,|\s)', message)
                    if task:
                        # Explicit original controller input supports historical logs.
                        call.setdefault('task_id', None)
                        call['task_id'] = call['task_id'] or task[1]
                        try:
                            context = json.loads(message.rsplit('\n', 1)[-1])
                            if context.get('stage') in STAGES and not call.get('stage'):
                                call['stage'] = context['stage']
                        except (ValueError, AttributeError):
                            pass
            if kind != 'token_usage_record' or data.get('turn_id') not in calls:
                continue
            turn = data['turn_id']
            response = data.get('response_id')
            value = tokens(data.get('usage'))
            if not response or value is None:
                invalid.add(turn)
                continue
            identity = (turn, response)
            if identity in responses and responses[identity] != value:
                conflicted.add(identity)
                invalid.add(turn)
            else:
                responses[identity] = value
            total = tokens(data.get('turn_token_usage'))
            if total is not None:
                previous = expected.get(turn)
                if previous is None or total['total_tokens'] > previous['total_tokens']:
                    expected[turn] = total
    for identity in conflicted:
        responses.pop(identity, None)
    groups = {}
    details = []
    for turn, call in calls.items():
        values = [value for (tid, _), value in responses.items() if tid == turn]
        total = {key: sum(v[key] for v in values) for key in FIELDS} if values else None
        complete = bool(total is not None and expected.get(turn) == total and turn not in invalid)
        coverage = 'COMPLETE' if complete else 'PARTIAL' if values else 'UNKNOWN'
        key = tuple(call.get(k) or 'unknown' for k in ('task_id', 'stage', 'model', 'effort'))
        group = groups.setdefault(key, dict(zip(('task_id', 'stage', 'model', 'effort'), key),
                    calls=0, measured_calls=0, partial_calls=0, unknown_calls=0,
                    responses=0, known_tokens={k: 0 for k in FIELDS},
                    measured_seconds=0, timed_calls=0))
        group['calls'] += 1
        group[{'COMPLETE': 'measured_calls', 'PARTIAL': 'partial_calls', 'UNKNOWN': 'unknown_calls'}[coverage]] += 1
        group['responses'] += len(values)
        if total is not None:
            for k in FIELDS:
                group['known_tokens'][k] += total[k]
        seconds = elapsed(call.get('started'), call.get('finished'))
        if seconds is not None:
            group['measured_seconds'] += seconds
            group['timed_calls'] += 1
        details.append(dict(zip(('task_id', 'stage', 'model', 'effort'), key),
                            turn_id=turn, status=call.get('status', 'unknown'),
                            requested_model=call.get('requested_model'),
                            requested_effort=call.get('requested_effort'),
                            coverage=coverage, responses=len(values), tokens=total, seconds=seconds))
    for group in groups.values():
        group['measured_seconds'] = round(group['measured_seconds'], 3)
        t = group['known_tokens']
        t['uncached_input_tokens'] = t['input_tokens'] - t['cached_input_tokens']
        if not group['responses']:
            group['known_tokens'] = None
    return {'schema': 1, 'generated_utc': utc(), 'calls': details,
            'groups': list(groups.values()), 'log_issues': dict(issues),
            'subscription_usage_percent': None,
            'note': '알려진 응답의 실측 합계. 캐시는 입력에, 추론은 출력에 포함. 주간 사용량으로 환산하지 않음.'}


def markdown(report):
    lines = ['# 자동 개발 단계별 사용량', '', report['note'], '',
             '추가 AI 호출 없이 기존 로컬 로그에서 계산. UNKNOWN은 0이 아니며 PARTIAL은 확인된 부분만 집계한다.',
             'AI 호출 수는 실행기가 시작한 작업 수, 응답 수는 도구 사용 후 이어진 내부 모델 응답까지 포함한다.', '',
             '| P번호 | 단계 | 실제 모델/추론 | 호출 | 확인/부분/미확인 | 응답 | 입력(캐시 포함) | 캐시 입력 | 비캐시 입력 | 출력(추론 포함) | 추론 출력 | 호출 시간(초) |',
             '|---|---|---|---:|---|---:|---:|---:|---:|---:|---:|---|']
    for g in report['groups']:
        # Output only recognized IDs/labels and numeric facts, never raw model text.
        label = lambda value: re.sub(r'[^A-Za-z0-9_. /-]', '', str(value))[:100]
        t = g['known_tokens']
        counts = [f'{t[k]:,}' if t else '미확인' for k in
                  ('input_tokens', 'cached_input_tokens', 'uncached_input_tokens',
                   'output_tokens', 'reasoning_output_tokens')]
        lines.append('| ' + ' | '.join([label(g['task_id']), label(g['stage']),
                     label(g['model']+'/'+g['effort']), str(g['calls']),
                     f"{g['measured_calls']}/{g['partial_calls']}/{g['unknown_calls']}",
                     str(g['responses']), *counts,
                     (f"{g['measured_seconds']:.1f} ({g['timed_calls']}/{g['calls']}건)"
                      if g['timed_calls'] else '미확인')]) + ' |')
    if not report['groups']:
        lines.append('\n기록된 AI 호출 없음. 사용량 0 또는 제품 완료를 뜻하지 않음.')
    if report['log_issues']:
        lines.append('\n로그 일부를 읽지 못했습니다. coverage와 log_issues를 확인하세요.')
    return '\n'.join(lines) + '\n'


def write_report(directory, codex_home=None):
    directory = Path(directory)
    home = Path(codex_home or os.environ.get('CODEX_HOME', Path.home() / '.codex'))
    paths, threads = set(), set()
    events = directory / 'events.jsonl'
    for row in rows(events, defaultdict(int)):
        data = row.get('data', {})
        if not isinstance(data, dict):
            continue
        if data.get('rollout_path'):
            paths.add(str(data['rollout_path']))
        if data.get('thread_id'):
            threads.add(str(data['thread_id']))
    checkpoint = directory / 'checkpoint.json'
    if checkpoint.exists():
        try:
            tid = json.loads(checkpoint.read_text(encoding='utf-8-sig')).get('thread_id')
            if tid:
                threads.add(str(tid))
        except (OSError, ValueError):
            pass
    for tid in threads:
        if re.fullmatch(r'[A-Za-z0-9_-]+', tid):
            for base in ('sessions', 'archived_sessions'):
                paths.update(str(p) for p in (home / base).rglob('*'+tid+'*.jsonl'))
    report = summarize(events, sorted(paths))
    directory.mkdir(parents=True, exist_ok=True)
    atomic_json(directory / 'usage-report.json', report)
    (directory / 'usage-report.md').write_text(markdown(report), encoding='utf-8')
    return report
