"""B policy: cause-based repair accounting and bounded stage context."""
import copy
import re
from workflow_runtime import Blocked, failure_action, record_failure, select_model, relative_path


def bind_diagnosis(data, diagnosis, source):
    """The read-only core-model diagnosis must compare every retained cause.

    Labels/test names alone are not identity. Retain closed causes as well so
    a recurring defect cannot obtain a fresh budget by changing its wording.
    """
    issues = data.setdefault('incidents', {})
    event = data['pending_failure']
    if not all(isinstance(diagnosis.get(k), str) and diagnosis[k].strip()
               for k in ('cause', 'evidence', 'fix', 'identity_basis')):
        raise Blocked('DIAGNOSIS_EVIDENCE_REQUIRED')
    comparisons = diagnosis.get('comparisons', [])
    if {c.get('id') for c in comparisons} != set(issues) or len(comparisons) != len(issues):
        raise Blocked('ALL_RETAINED_CAUSES_MUST_BE_COMPARED')
    if any(c.get('relation') not in ('same', 'different') or not c.get('evidence') for c in comparisons):
        raise Blocked('CAUSE_COMPARISON_EVIDENCE_REQUIRED')
    same = [c['id'] for c in comparisons if c['relation'] == 'same']
    key = diagnosis.get('incident_id')
    if len(same) > 1 or (same and key != same[0]) or (not same and key != 'new'):
        raise Blocked('CAUSE_IDENTITY_CONFLICT')
    if key == 'new':
        key = f"{data['task_id']}:cause-{len(issues) + 1}"
        issues[key] = {'id': key, 'cause': diagnosis['cause'], 'total': 0, 'maximum': 0, 'executions': []}
    issue = issues[key]
    attempt = issue.get('last_attempt', data.get('repair_attempt', {}))
    repaired = attempt.get('incident_id') == key and bool(attempt.get('changed'))
    # The maximum belongs to the repair, never to a subsequent reviewer.
    action = record_failure(issue, event['id'], maximum=bool(attempt.get('maximum')),
                            repaired=repaired, category='environment' if diagnosis.get('kind') == 'environment' else 'code')
    if action == 'BLOCKED_ENVIRONMENT':
        action = 'REPAIR'  # Let the supervising AI prepare/perform an authorized environment fix.
    if repaired:
        issue.pop('last_attempt', None)
    issue.update(status='open', evidence=diagnosis['evidence'])
    issue.setdefault('observations', []).append({'event': event['id'], 'diagnosis': copy.deepcopy(diagnosis)})
    data.update(active_incident=key, diagnosis=dict(diagnosis, incident_id=key, fingerprint=source))
    data.pop('repair_attempt', None)
    return action


def simple_repair(diagnosis):
    return (diagnosis.get('kind') in ('syntax_import', 'format', 'fixture_contract')
            and all(diagnosis.get(k) is True for k in
                    ('cause_clear', 'behavior_unchanged', 'checkable'))
            and all(isinstance(diagnosis.get(k), str) and diagnosis[k].strip()
                    for k in ('evidence', 'fix', 'contract_basis'))
            and bool(diagnosis.get('files')))


def simple_diagnostic_hint(root, data, source):
    """Conservative routing evidence, never permission to change behavior."""
    failure = data.get('pending_failure') or {}
    details = failure.get('details', {})
    check, result = details.get('check', {}), details.get('result', {})
    if (check.get('kind') != 'flutter-analyze' or result.get('status') != 'FAIL'
            or result.get('fingerprint') != source or not result.get('log_directory')):
        return None
    directory = relative_path(root, result['log_directory'])
    report = ''
    for name in ('stdout.log', 'stderr.log'):
        path = directory / name
        if path.is_file():
            if path.stat().st_size > 2_000_000:
                return None
            report += path.read_text(encoding='utf-8', errors='replace') + '\n'
    total = re.findall(r'(?m)^\s*(\d+) issues? found\.', report)
    rows = re.findall(r'(?m)^\s*(?:info|warning|error)\s+•\s+.+?\s+•\s+(.+?):(\d+):(\d+)\s+•\s+(\w+)\s*$', report)
    if len(total) != 1 or int(total[0]) != len(rows) or not rows:
        return None
    files = []
    for name, line, column, code in rows:
        if code not in ('unused_import', 'duplicate_import', 'unnecessary_import'):
            return None
        name = 'apps/mobile/' + name.replace('\\', '/')
        if name not in data.get('plan', {}).get('scope', []):
            return None
        path = relative_path(root, name)
        if not path.is_file():
            return None
        lines = path.read_text(encoding='utf-8').splitlines()
        index = int(line) - 1
        if index < 0 or index >= len(lines) or not re.fullmatch(r"\s*import\s+['\"].+['\"].*;\s*", lines[index]):
            return None
        files.append(name)
    return {'kind': 'verified_import_cleanup', 'event_id': failure['id'],
            'fingerprint': source, 'files': sorted(set(files)),
            'evidence': 'Complete analyzer report contains only unused/duplicate/unnecessary imports; source import lines verified.'}


def simple_diagnosis_route(data, source):
    hint = data.get('diagnosis_route') or {}
    return (not data.get('requires_core_diagnosis') and hint.get('kind') == 'verified_import_cleanup'
            and hint.get('fingerprint') == source
            and hint.get('event_id') == (data.get('pending_failure') or {}).get('id'))


def stage_model(data, models, source):
    stage = data['stage']
    risk = data.get('plan', {}).get('risk', 'sensitive' if data['task_id'].startswith(('P06-', 'P10-')) else 'general')
    if stage == 'PLAN':
        return select_model(models, 'sensitive' if data.get('plan_requires_core') else 'general')
    if stage == 'DIAGNOSE':
        return select_model(models, 'general' if simple_diagnosis_route(data, source) else 'sensitive')
    if stage == 'FINALIZE':
        return select_model(models, 'general')
    issue = data.get('incidents', {}).get(data.get('active_incident'), {})
    if stage == 'IMPLEMENT' and issue:
        action = failure_action(issue)
        if action == 'BLOCKED':
            raise Blocked('REPAIR_BUDGET_EXHAUSTED')
        if action == 'ESCALATE':
            return select_model(models, escalate=True)
        diagnosis = data.get('diagnosis', {})
        if diagnosis.get('fingerprint') == source and simple_repair(diagnosis):
            return select_model(models, 'general')
        # An unclear/core repair must not inherit a low-risk task's model.
        return select_model(models, 'sensitive')
    # No sticky maximum across unrelated problems, review, or reporting.
    return select_model(models, risk)


def compact_context(data):
    plan = data.get('plan', {})
    result = {k: data.get(k) for k in ('stage', 'next_action', 'user_result') if data.get(k) is not None}
    result['plan'] = {k: plan[k] for k in ('task_id', 'title', 'objective', 'risk', 'scope',
                                            'verification_file') if k in plan}
    result['acceptance'] = [{k: a[k] for k in ('id', 'criterion', 'basis', 'checks')} for a in plan.get('acceptance', [])]
    result['plan_evidence'] = '.local/workflow/runs/sequential/task-context.json'
    if data['stage'] == 'PLAN':
        result['plan_requires_core'] = data.get('plan_requires_core', False)
    if data['stage'] in ('IMPLEMENT', 'REVIEW'):
        result['checks'] = [{k: c[k] for k in ('id', 'kind', 'targets') if k in c} for c in plan.get('checks', [])]
    if data['stage'] == 'REVIEW':
        result['results'] = [{k: r[k] for k in ('id', 'status', 'exit_code', 'log_directory') if k in r}
                             for r in data.get('results', [])]
    if data['stage'] == 'IMPLEMENT':
        result['implementation'] = data.get('implementation')
    if data['stage'] in ('DIAGNOSE', 'IMPLEMENT'):
        failure = data.get('pending_failure') or {}
        details = failure.get('details', {})
        result['failure'] = {'id': failure.get('id'),
                             'log_directory': details.get('result', {}).get('log_directory'),
                             'excerpt': failure.get('excerpt'),
                             'evidence': '.local/workflow/runs/sequential/failure.json' if failure else None}
        result['diagnosis'] = data.get('diagnosis')
        result['diagnosis_route'] = data.get('diagnosis_route')
    if data['stage'] == 'DIAGNOSE':
        result['incidents'] = [{k: i.get(k) for k in ('id', 'cause', 'status', 'total', 'maximum')}
                               for i in data.get('incidents', {}).values()]
        result['incident_evidence'] = '.local/workflow/runs/sequential/checkpoint.json'
    if data['stage'] in ('IMPLEMENT', 'REVIEW', 'FINALIZE'):
        result['review'] = data.get('review')
    if data['stage'] == 'FINALIZE':
        result = {k: result[k] for k in ('stage', 'plan_evidence', 'review')}
        result['summary'] = {k: plan.get(k) for k in ('title', 'objective', 'verification_file')}
        result['record'] = '.local/workflow/runs/sequential/final-facts.json'
    return result
