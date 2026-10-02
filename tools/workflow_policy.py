"""B policy: cause-based repair accounting and bounded stage context."""
import copy
from workflow_runtime import Blocked, failure_action, record_failure, select_model


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


def stage_model(data, models, source):
    stage = data['stage']
    risk = data.get('plan', {}).get('risk', 'sensitive' if data['task_id'].startswith(('P06-', 'P10-')) else 'general')
    if stage == 'DIAGNOSE':
        return select_model(models, 'sensitive')
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
    # No sticky maximum across unrelated problems, review, or reporting.
    return select_model(models, risk)


def compact_context(data):
    plan = data.get('plan', {})
    result = {k: data.get(k) for k in ('stage', 'next_action', 'user_result') if data.get(k) is not None}
    result['plan'] = {k: plan[k] for k in ('task_id', 'title', 'objective', 'risk', 'scope',
                                            'verification_file', 'fast_checks') if k in plan}
    result['acceptance'] = [{k: a[k] for k in ('id', 'criterion', 'checks')} for a in plan.get('acceptance', [])]
    result['plan_evidence'] = '.local/workflow/runs/sequential/task-context.json'
    result['checks'] = [{k: c[k] for k in ('id', 'kind', 'targets') if k in c} for c in plan.get('checks', [])]
    result['results'] = [{k: r[k] for k in ('id', 'status', 'exit_code', 'log_directory') if k in r}
                         for r in data.get('results', [])]
    result['fast_results'] = [{k: r[k] for k in ('id', 'status', 'exit_code', 'log_directory') if k in r}
                              for r in data.get('fast_results', [])]
    if data['stage'] == 'IMPLEMENT':
        result['last_slice'] = data.get('implementation')
    if data['stage'] in ('DIAGNOSE', 'IMPLEMENT'):
        result.update(pending_failure=data.get('pending_failure'), diagnosis=data.get('diagnosis'))
    if data['stage'] == 'DIAGNOSE':
        result['incidents'] = [{k: i.get(k) for k in ('id', 'cause', 'evidence', 'status', 'total', 'maximum')}
                               for i in data.get('incidents', {}).values()]
    if data['stage'] in ('IMPLEMENT', 'REVIEW', 'FINALIZE'):
        result['review'] = data.get('review')
    if data['stage'] == 'FINALIZE':
        result = {k: result[k] for k in ('stage', 'plan_evidence', 'review')}
        result['summary'] = {k: plan.get(k) for k in ('title', 'objective', 'verification_file')}
        result['record'] = '.local/workflow/runs/sequential/final-facts.json'
    return result
