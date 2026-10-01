"""Read-only work selection. Never launches commands or grants permissions."""
import argparse
import json
import posixpath
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def overlaps(left, right):
    def normalize(value):
        raw = value.replace('\\', '/').lower()
        if not raw or raw.startswith('/') or ':' in raw or '..' in raw.split('/'):
            raise ValueError('Use repository-relative paths without parent traversal')
        normalized = posixpath.normpath(raw)
        if normalized == '.':
            raise ValueError('Specify a file or directory, not the whole repository')
        return normalized
    a, b = normalize(left), normalize(right)
    return a == b or a.startswith(b + '/') or b.startswith(a + '/')


def select(state, planned_ids):
    # Coverage is an assessment, not a declaration of implementation completion.
    coverage = state['coverage']
    if set(coverage) != set(planned_ids):
        raise ValueError('Every source-plan task must be assessed; unknown coverage forbids waiting')
    for assessment in coverage.values():
        if not assessment.get('basis') or assessment.get('disposition') not in ('preserved_scope', 'tracked', 'unassessed'):
            raise ValueError('Coverage needs a disposition and evidence basis')
    units = state['units']
    by_id = {unit['id']: unit for unit in units}
    if len(by_id) != len(units):
        raise ValueError('Duplicate work unit')
    priority = state.get('priority_order', [])
    if len(set(priority)) != len(priority) or any(key not in by_id for key in priority):
        raise ValueError('Priority order requires unique existing work units')
    rank = {key: index for index, key in enumerate(priority)}
    units = sorted(units, key=lambda u: rank.get(u['id'], len(rank)))
    for assessment in coverage.values():
        if assessment['disposition'] == 'tracked' and (not assessment.get('units') or
                any(key not in by_id for key in assessment['units'])):
            raise ValueError('Tracked plan tasks need existing work units')
    grants = set(state['grants'])
    facts = set(state['facts'])
    active = [u for u in units if u['state'] == 'active']
    ready, blocked, running, selected = [], [], [], []
    for unit in units:
        if unit['state'] not in ('pending', 'active', 'done'):
            raise ValueError('Unknown state')
        if unit['state'] == 'done':
            if not unit.get('evidence'):
                raise ValueError('Done work needs evidence')
            continue
        for field in ('action', 'owner', 'resume', 'reads', 'writes', 'requires', 'permissions'):
            if field not in unit:
                raise ValueError(f'Missing {field}')
        if unit['state'] == 'active':
            running.append({'id': unit['id'], 'action': 'Collect current execution result; do not relaunch',
                            'owner': unit['owner'], 'resume': unit['resume']})
            continue
        reasons = []
        for dependency in unit['requires']:
            if dependency not in facts:
                reasons.append('prerequisite: ' + dependency)
        reasons += ['permission: ' + p for p in unit['permissions'] if p not in grants]
        if unit.get('blocker'):
            reasons.append(unit['blocker'])
        for other in active + selected:
            if other['id'] == unit['id']:
                continue
            if any(overlaps(a, b) for a in unit['writes'] for b in other['reads'] + other['writes']) or any(
                overlaps(a, b) for a in unit['reads'] for b in other['writes']
            ):
                reasons.append('file conflict: ' + other['id'])
        row = {'id': unit['id'], 'action': unit['action'], 'owner': unit['owner'],
               'resume': unit['resume'], 'reasons': reasons}
        (blocked if reasons else ready).append(row)
        if not reasons:
            selected.append(unit)
    unresolved = [key for key, value in coverage.items() if value['disposition'] == 'unassessed']
    if unresolved:
        ready.append({'id': 'ASSESS', 'action': 'Inspect unresolved tasks: ' + ', '.join(unresolved),
                      'owner': 'AI', 'resume': 'Record evidence-backed next work units', 'reasons': []})
    for row in blocked:
        if not row['owner'] or not row['resume']:
            raise ValueError('Blocked work needs an owner and resume condition')
    if state.get('execution_mode') == 'strict_sequential':
        start = state.get('sequence_start')
        if start is not None and start not in priority:
            raise ValueError('Sequential start must be in the recorded priority order')
        sequence = units if start is None else units[next(i for i, u in enumerate(units) if u['id'] == start):]
        first = next((u['id'] for u in sequence if u['state'] != 'done'), None)
        # Later work stays recorded, but cannot authorize skipping a blocker.
        ready = [r for r in ready if r['id'] == first]
        running = [r for r in running if r['id'] == first]
        for row in blocked:
            if row['id'] != first:
                row['reasons'].append('sequence: ' + str(first))
        if first is None and unresolved:
            ready = [{'id': 'ASSESS', 'action': 'Assess source-plan gaps before completion',
                      'owner': 'AI', 'resume': ', '.join(unresolved), 'reasons': []}]
    return {'decision': 'CONTINUE' if ready else 'IN_PROGRESS' if running else 'WAIT' if blocked else 'NO_OPEN_UNITS',
            'ready': ready, 'running': running, 'blocked': blocked, 'covered_tasks': len(coverage)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--state', type=Path, default=ROOT / 'docs/workflow-state.json')
    parser.add_argument('--check-stop', action='store_true')
    args = parser.parse_args()
    state = json.loads(args.state.read_text(encoding='utf-8-sig'))
    planned = json.loads((ROOT / 'docs/reference/search/tasks.json').read_text(encoding='utf-8-sig'))
    result = select(state, [r['id'] for r in planned])
    print(json.dumps(result, ensure_ascii=True, indent=2))
    return 1 if args.check_stop and (result['ready'] or result['running']) else 0


if __name__ == '__main__':
    raise SystemExit(main())
