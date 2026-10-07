"""Derived, offline usage reports. Never infer subscription quota from tokens."""
import json
import os
import re
from html import escape
from collections import defaultdict
from datetime import datetime
from pathlib import Path

from workflow_runtime import atomic_json, utc

FIELDS = ('input_tokens', 'cached_input_tokens', 'output_tokens',
          'reasoning_output_tokens', 'total_tokens')
STAGES = ('PLAN', 'IMPLEMENT', 'DIAGNOSE', 'REVIEW', 'FINALIZE', 'RECOVERY')


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
    stages = {'PLAN': '계획', 'IMPLEMENT': '구현', 'DIAGNOSE': '오류 분석',
              'REVIEW': '코드 검토', 'FINALIZE': '완료 정리', 'RECOVERY': '자동 복구 확인'}
    efforts = {'low': '낮음', 'medium': '중간', 'high': '높음',
               'xhigh': '매우 높음', 'max': '최대', 'unknown': '미확인'}
    models = {'gpt-6-astra': '아스트라', 'gpt-6.1-sol': '솔 6.1', 'gpt-6-sol': '솔 6'}
    lines = ['# 자동 개발 사용량', '',
             '[고정 헤더 표로 보기 — 권장](usage-report.html)', '',
             '최근 P번호부터 표시합니다. 각 숫자 옆에 항목 이름과 뜻을 함께 적었습니다.', '',
             '토큰은 AI가 글을 읽고 만드는 양을 세는 단위입니다. **주간 구독 사용량(%)이나 비용으로 환산한 값은 아닙니다.**',
             '기존 로그만 계산하며 보고서 갱신에 AI를 호출하지 않습니다. 부분 확인은 확인된 양만 표시하고, 미확인은 0으로 취급하지 않습니다.', '',
             '입력 합계에는 재사용 입력이, 출력 합계에는 추론 출력이 이미 포함됩니다. 포함 항목을 다시 더하지 마세요.', '']
    current_task = None
    for g in sorted(report['groups'], key=lambda row: row['task_id'], reverse=True):
        # Output only recognized IDs/labels and numeric facts, never raw model text.
        label = lambda value: re.sub(r'[^A-Za-z0-9_. /-]', '', str(value))[:100]
        task = label(g['task_id']) if g['task_id'] != 'unknown' else '작업 미확인'
        if current_task != task:
            lines.extend([f'## {task}', ''])
            current_task = task
        model = models.get(g['model'], label(g['model']) if g['model'] != 'unknown' else '모델 미확인')
        effort = efforts.get(g['effort'], '미확인')
        lines.extend([f"### {stages.get(g['stage'], '단계 미확인')} · {model} / 추론 {effort}", '',
                      '| 항목 | 사용량 | 뜻 |', '|---|---:|---|'])
        t = g['known_tokens']
        lines.extend([f"| AI 호출 | {g['calls']:,}회 | 실행기가 AI에 작업을 요청한 횟수 |",
                      f"| 내부 응답 | {g['responses']:,}회 | 도구 사용 후 이어지는 답변까지 포함한 응답 수 |"])
        for name, key, meaning in [
            ('입력 합계', 'input_tokens', 'AI가 읽은 양. 재사용 입력 포함'),
            ('재사용 입력', 'cached_input_tokens', '이전 입력을 캐시로 재사용한 양. 입력 합계의 일부'),
            ('새로 처리한 입력', 'uncached_input_tokens', '입력 합계에서 재사용 입력을 뺀 양'),
            ('출력 합계', 'output_tokens', 'AI가 생성한 양. 추론 출력 포함'),
            ('추론 출력', 'reasoning_output_tokens', '판단 과정에 사용된 양. 출력 합계의 일부')]:
            amount = f'{t[key]:,} 토큰' if t else '미확인'
            lines.append(f'| {name} | {amount} | {meaning} |')
        seconds = round(g['measured_seconds'])
        duration = f'{seconds // 60}분 {seconds % 60}초' if g['timed_calls'] else '미확인'
        lines.extend([f"| 호출 경과 시간 | {duration} | 도구 실행·대기 포함. 시간 확인 {g['timed_calls']}/{g['calls']}회 |",
                      f"| 집계 확인 상태 | 전체 확인 {g['measured_calls']}회 · 부분 확인 {g['partial_calls']}회 · 미확인 {g['unknown_calls']}회 | 호출별 사용량 기록의 확인 수준. 작업 완료 여부와 별개 |", ''])
    if not report['groups']:
        lines.append('\n기록된 AI 호출 없음. 사용량 0 또는 제품 완료를 뜻하지 않음.')
    if report['log_issues']:
        lines.append('\n일부 로그를 읽지 못했습니다. 위 집계 확인 상태를 참고하세요. 상세 오류 수는 같은 폴더의 JSON 원본 보고서에 보존했습니다.')
    return '\n'.join(lines) + '\n'


def record_subscription(directory, raw, task_id=None, phase='observation'):
    """Store only official limit windows, never account IDs, credits or credentials."""
    path = Path(directory) / 'subscription-usage.json'
    saved = json.loads(path.read_text(encoding='utf-8')) if path.exists() else {'tasks': {}}
    limits = raw.get('rateLimitsByLimitId') or {'default': raw.get('rateLimits')}
    windows = []
    for key, bucket in limits.items():
        if not isinstance(bucket, dict):
            continue
        for slot in ('primary', 'secondary'):
            w = bucket.get(slot)
            if not isinstance(w, dict) or not isinstance(w.get('usedPercent'), (float, int)):
                continue
            if not 0 <= w['usedPercent'] <= 100:
                continue
            windows.append({'bucket': str(bucket.get('limitId') or key), 'slot': slot,
                            **{k: w.get(k) for k in ('usedPercent', 'windowDurationMins', 'resetsAt')}})
    snapshot = {'utc': utc(), 'windows': windows}
    saved['current'] = snapshot
    if task_id and phase in ('start', 'end'):
        saved.setdefault('tasks', {}).setdefault(task_id, {}).setdefault(phase, snapshot)
    atomic_json(path, saved)
    return saved


def subscription_delta(subscription, task):
    pair = subscription.get('tasks', {}).get(task, {})
    if not pair.get('start') or not pair.get('end'):
        return '미확인'
    start, end = pair['start']['windows'], pair['end']['windows']
    values = []
    for a in start:
        if a.get('windowDurationMins') != 10080:
            continue
        b = next((w for w in end if all(w.get(k) == a.get(k) for k in
                 ('bucket', 'slot', 'windowDurationMins', 'resetsAt'))), None)
        if b is None or a.get('resetsAt') is None or b['usedPercent'] < a['usedPercent']:
            return '초기화·기간 변경'
        values.append(f"{a['bucket']}: {b['usedPercent'] - a['usedPercent']:g}%p")
    return ' / '.join(values) if values else '미확인'


def task_totals(groups):
    """Aggregate disjoint stage/model groups without treating missing usage as zero."""
    totals = {}
    counts = ('calls', 'measured_calls', 'partial_calls', 'unknown_calls',
              'responses', 'timed_calls', 'measured_seconds')
    for group in groups:
        total = totals.setdefault(group['task_id'], dict(
            task_id=group['task_id'], stage='TOTAL', model='ALL', effort='ALL',
            known_tokens=None, **{key: 0 for key in counts}))
        for key in counts:
            total[key] += group[key]
        if group['known_tokens'] is not None:
            if total['known_tokens'] is None:
                total['known_tokens'] = {key: 0 for key in group['known_tokens']}
            for key, value in group['known_tokens'].items():
                total['known_tokens'][key] += value
    return sorted(totals.values(), key=lambda row: row['task_id'], reverse=True)


def html_report(report):
    """Local spreadsheet-like view; no external assets or network requests."""
    stages = {'PLAN': '계획', 'IMPLEMENT': '구현', 'DIAGNOSE': '오류 분석',
              'REVIEW': '코드 검토', 'FINALIZE': '완료 정리', 'RECOVERY': '자동 복구 확인', 'TOTAL': '합계'}
    efforts = {'medium': '중간', 'high': '높음', 'xhigh': '매우 높음',
               'max': '최대', 'low': '낮음'}
    models = {'gpt-6-astra': '아스트라', 'gpt-6.1-sol': '솔 6.1', 'gpt-6-sol': '솔 6'}
    headers = [
        ('작업', 'P번호', '계획서 작업 번호'), ('단계', '작업 종류', 'AI가 수행한 단계'),
        ('모델 · 추론', '실제 관측', '로그에서 확인한 모델과 추론 수준'),
        ('AI 호출', '회', '실행기가 AI에 작업을 요청한 횟수'),
        ('내부 응답', '회', '도구 실행 뒤 이어진 응답까지 포함'),
        ('총 토큰량', '토큰 · 입력 + 출력', '입력 합계 + 출력 합계. 캐시·추론을 중복해서 더하지 않음'),
        ('입력 합계', '토큰 · 재사용 포함', 'AI가 읽은 전체 양'),
        ('재사용 입력', '토큰 · 입력의 일부', '캐시에서 재사용한 입력. 입력 합계에 이미 포함'),
        ('새 입력', '토큰', '입력 합계에서 재사용 입력을 뺀 양'),
        ('출력 합계', '토큰 · 추론 포함', 'AI가 생성한 전체 양'),
        ('추론 출력', '토큰 · 출력의 일부', '판단 과정에 사용된 양. 출력 합계에 이미 포함'),
        ('경과 시간', '분:초', 'AI 호출 안의 도구 실행·대기 포함. 전체 작업 시간과 다름'),
        ('집계 확인', '호출 기준', '전체 확인 / 부분 확인 / 미확인 호출 수. 제품 완료 여부와 별개')]
    headers.append(('구독 사용량 변화', '주간 · 계정 전체', 'P번호 시작·종료 공식 사용률 차이. 다른 대화 포함. 과거 시작 기록 없으면 미확인'))
    head = ''.join(f'<th scope="col" tabindex="0" title="{escape(tip)}">{name}<small>{unit}</small></th>'
                   for name, unit, tip in headers)
    rows_html = []
    tasks = []
    previous = None
    combined = task_totals(report['groups']) + sorted(report['groups'], key=lambda row: row['task_id'], reverse=True)
    detail_started = False
    for g in combined:
        if g['stage'] != 'TOTAL' and not detail_started:
            rows_html.append('<tr class="section"><td colspan="14">단계·모델별 상세</td></tr>')
            detail_started = True
        task = re.sub(r'[^A-Za-z0-9_-]', '', str(g['task_id']))[:40]
        task = '미확인' if task == 'unknown' else task
        if task not in tasks:
            tasks.append(task)
        t = g['known_tokens']
        nums = [f'{t[k]:,}' if t else '미확인' for k in
                ('total_tokens', 'input_tokens', 'cached_input_tokens', 'uncached_input_tokens', 'output_tokens', 'reasoning_output_tokens')]
        seconds = round(g['measured_seconds'])
        duration = f'{seconds // 60}:{seconds % 60:02}' if g['timed_calls'] else '미확인'
        coverage = (f"전체 {g['measured_calls']}" if not g['partial_calls'] and not g['unknown_calls'] else
                    f"전체 {g['measured_calls']} · 부분 {g['partial_calls']} · 미확인 {g['unknown_calls']}")
        cells = [task, stages.get(g['stage'], '미확인'),
                 ('전체 모델' if g['stage'] == 'TOTAL' else models.get(g['model'], '모델 미확인') + ' · ' + efforts.get(g['effort'], '미확인')),
                 f"{g['calls']:,}", f"{g['responses']:,}", *nums, duration, coverage]
        delta = subscription_delta(report.get('subscription', {}), g['task_id'])
        if g['task_id'] == 'P10-05' and delta == '미확인':
            delta = '약 12%p · 사용자 확인'
        estimate = report.get('subscription', {}).get('user_estimates', {}).get(g['task_id'])
        if delta == '미확인' and estimate and isinstance(estimate.get('percent_points'), (int, float)):
            delta = f"약 {estimate['percent_points']:g}%p · 사용자 추정"
        cells.append(delta if g['stage'] == 'TOTAL' else '—')
        values = []
        for i, value in enumerate(cells):
            hint = f' title="시간 확인 {g["timed_calls"]}/{g["calls"]}회"' if i == 11 else ''
            values.append(f'<td{hint}>{escape(value)}</td>')
        values = ''.join(values)
        row_class = 'summary' if g['stage'] == 'TOTAL' else 'new-task' if previous != task else ''
        rows_html.append(f'<tr data-task="{escape(task)}" class="{row_class}">{values}</tr>')
        previous = task
    options = ''.join(f'<option>{escape(task)}</option>' for task in tasks)
    stamp = escape(report.get('generated_utc', ''))
    notice = '일부 로그를 읽지 못했습니다. 부분·미확인 수치를 확인하세요.' if report['log_issues'] else '기존 로컬 로그 기준 · 표시 갱신에 AI 사용 없음'
    current = report.get('subscription', {}).get('current', {})
    quota = []
    for window in current.get('windows', []):
        minutes = window.get('windowDurationMins')
        period = '주간' if minutes == 10080 else f'{minutes}분 한도'
        quota.append(f"{escape(window['bucket'])} {period} <b>{window['usedPercent']:g}% 사용</b> · {100-window['usedPercent']:g}% 남음")
    quota_html = '<div>' + (' / '.join(quota) if quota else '구독 사용량: 미확인')
    if current.get('utc'):
        stamp_quota = escape(current['utc'])
        quota_html += f' <small>· 공식 조회 <time class="local-time" datetime="{stamp_quota}">{stamp_quota}</time></small>'
    quota_html += '<small> · 계정 전체 기준. 새로고침은 저장된 조회 값을 표시합니다.</small></div>'
    return '''<!doctype html><html lang="ko"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>자동 개발 사용량</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#f3f5f8;color:#172638;font:14px/1.5 "Segoe UI","Malgun Gothic",sans-serif}
main{height:100vh;display:flex;flex-direction:column;padding:24px;gap:14px}header{display:flex;justify-content:space-between;align-items:center;gap:20px}
h1{font-size:24px;margin:0 0 3px}p{margin:0;color:#58687a}label{white-space:nowrap}select{font:inherit;padding:8px 28px 8px 12px;border:1px solid #bbc8d6;border-radius:6px;background:white;margin-left:8px}
.sheet{flex:1;min-height:180px;overflow:auto;background:white;border:1px solid #cad3df;border-radius:8px}
table{border-collapse:separate;border-spacing:0;width:100%;min-width:1280px;font-size:13px;font-variant-numeric:tabular-nums}
th{position:sticky;top:0;z-index:3;background:#e8eef6;color:#263f5f;text-align:right;padding:12px 14px;border-bottom:2px solid #9baec4;white-space:nowrap}
th small{display:block;font-weight:400;font-size:11px;color:#60718a;margin-top:3px}td{padding:11px 14px;text-align:right;border-bottom:1px solid #e5eaf0;white-space:nowrap;background:white}
th:first-child,td:first-child{position:sticky;left:0;min-width:90px;width:90px;text-align:left}th:nth-child(2),td:nth-child(2){position:sticky;left:90px;min-width:100px;width:100px;text-align:left;box-shadow:2px 0 0 #d5dfe9}
td:first-child,td:nth-child(2){z-index:1}th:first-child,th:nth-child(2){z-index:4}td:first-child{font-weight:650;color:#245db0}td:nth-child(3),th:nth-child(3){text-align:left}td:nth-child(6){font-weight:650;background:#f4f8ff}tr:nth-child(even) td{background:#f8fafc}tr:nth-child(even) td:nth-child(6){background:#edf4ff}
tr:hover td{background:#eaf2ff}.new-task td{border-top:2px solid #bac9da}td:last-child{font-size:12px;color:#53677e}footer{font-size:12px;color:#62738a}footer p{margin:3px 0}.empty{padding:32px}button{font:inherit;cursor:pointer;background:white;border:1px solid #bbc8d6;border-radius:6px;padding:8px 12px;margin-left:10px}tr[hidden]{display:none}
tr.summary td{background:#eaf2ff;font-weight:650;border-bottom:1px solid #c3d5ed}tr.section td{position:static;text-align:left;background:#e8eef6;padding:13px 14px;font-weight:650;color:#263f5f;box-shadow:none}
@media(max-width:700px){main{padding:12px}header{align-items:flex-start;flex-direction:column;gap:10px}h1{font-size:20px}}
</style><main><header><div><h1>자동 개발 사용량</h1><p>위쪽 파란 행: P번호별 전체 합계 · 아래쪽: 단계·모델별 상세 · 제목과 왼쪽 열 고정</p></div>
<div><label>작업<select id="task"><option value="">전체 작업</option>''' + options + '''</select></label><button onclick="location.reload()">새로고침</button></div></header>
''' + quota_html + '''<div class="sheet" role="region" aria-label="단계별 사용량 표" tabindex="0"><table><thead><tr>''' + head + '''</tr></thead><tbody>''' + ''.join(rows_html) + '''</tbody></table>''' + ('' if rows_html else '<p class="empty">기록된 호출이 없습니다. 사용량 0을 뜻하지 않습니다.</p>') + '''</div>
<footer><p><b>입력·출력 단위: 토큰</b> (글을 처리한 양). 재사용 입력은 입력 합계에, 추론 출력은 출력 합계에 이미 포함됩니다. <b>주간 구독 사용률(%)·비용이 아닙니다.</b></p>
<p>항목 제목에 마우스를 올리거나 키보드로 선택하면 설명을 볼 수 있습니다. 경과 시간은 도구 실행·대기를 포함합니다.</p><p>''' + notice + ' · 집계 시각: <time id="stamp" datetime="' + stamp + '">' + stamp + '''</time></p></footer></main>
<script>document.getElementById('task').addEventListener('change',e=>{document.querySelectorAll('tbody tr[data-task]').forEach(r=>r.hidden=!!e.target.value&&r.dataset.task!==e.target.value)});document.querySelectorAll('time').forEach(t=>{const d=new Date(t.dateTime);if(!isNaN(d))t.textContent=d.toLocaleString('ko-KR')});</script></html>'''


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
    subscription_path = directory / 'subscription-usage.json'
    if subscription_path.exists():
        report['subscription'] = json.loads(subscription_path.read_text(encoding='utf-8'))
    directory.mkdir(parents=True, exist_ok=True)
    atomic_json(directory / 'usage-report.json', report)
    (directory / 'usage-report.md').write_text(markdown(report), encoding='utf-8')
    (directory / 'usage-report.html').write_text(html_report(report), encoding='utf-8')
    return report
