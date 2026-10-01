import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from select_work import select


def unit(name, **extra):
    return dict(id=name, state='pending', action='Run relevant validation', owner='AI',
                resume='Required evidence available', reads=[], writes=[], requires=[], permissions=[], **extra)


class SelectionTests(unittest.TestCase):
    def setUp(self):
        self.state = dict(coverage={'P10-03': dict(disposition='preserved_scope', basis='source + current code')},
                          grants=[], facts=[], units=[])

    def result(self):
        return select(self.state, ['P10-03'])

    def test_strict_order_stops_at_first_blocked_and_advances_only_after_done(self):
        a, b = unit('a', blocker='user result'), unit('b')
        self.state.update(units=[b, a], priority_order=['a', 'b'],
                          execution_mode='strict_sequential')
        self.assertEqual(self.result()['decision'], 'WAIT')
        self.assertEqual(self.result()['ready'], [])
        del a['blocker']
        self.assertEqual([r['id'] for r in self.result()['ready']], ['a'])
        a['state'] = 'active'
        self.assertEqual(self.result()['decision'], 'IN_PROGRESS')
        a.update(state='done', evidence='verified')
        self.assertEqual([r['id'] for r in self.result()['ready']], ['b'])

    def test_priority_survives_partial_completion_and_skips_only_blocked(self):
        a, b, c = unit('a'), unit('b'), unit('c')
        self.state['units'] = [c, b, a]
        self.state['priority_order'] = ['a', 'b', 'c']
        self.assertEqual([r['id'] for r in self.result()['ready']], ['a', 'b', 'c'])
        a['blocker'] = 'phone result'
        self.assertEqual([r['id'] for r in self.result()['ready']], ['b', 'c'])
        del a['blocker']
        self.assertEqual(self.result()['ready'][0]['id'], 'a')
        a.update(state='done', evidence='verified')
        self.assertEqual(self.result()['ready'][0]['id'], 'b')

    def test_priority_rejects_unknown_or_duplicate_units(self):
        self.state['units'] = [unit('a')]
        for priority in [['missing'], ['a', 'a']]:
            self.state['priority_order'] = priority
            with self.assertRaises(ValueError): self.result()

    def test_phone_wait_does_not_stop_independent_work(self):
        self.state['units'] = [unit('phone', blocker='USER result'), unit('test')]
        self.assertEqual(self.result()['decision'], 'CONTINUE')
        self.assertEqual([r['id'] for r in self.result()['ready']], ['test'])

    def test_review_permission_is_not_context_consult_permission(self):
        self.state['grants'] = ['existing-chat-consult']
        u = unit('review'); u['permissions'] = ['cli-evidence-transfer']
        self.state['units'] = [u]
        self.assertEqual(self.result()['decision'], 'WAIT')

    def test_failed_predecessor_cannot_be_assumed_done(self):
        u = unit('commit'); u['requires'] = ['independent-review-pass']
        self.state['units'] = [u]
        self.assertEqual(self.result()['ready'], [])

    def test_active_parent_directory_write_conflicts_with_child_read(self):
        a, b = unit('writer'), unit('reader')
        a.update(state='active', writes=['apps/mobile'])
        b.update(reads=['APPS\\mobile\\lib/a.dart'])
        self.state['units'] = [a, b]
        self.assertEqual([r['id'] for r in self.result()['blocked']], ['reader'])

    def test_read_read_and_distinct_sibling_paths_are_safe(self):
        a, b = unit('a'), unit('b')
        a.update(state='active', reads=['lib/a'], writes=['lib/b'])
        b.update(reads=['lib/a'], writes=['lib/bb'])
        self.state['units'] = [a, b]
        self.assertEqual([r['id'] for r in self.result()['ready']], ['b'])
        self.assertEqual([r['id'] for r in self.result()['running']], ['a'])

    def test_incomplete_inventory_forbids_wait(self):
        self.state['coverage'] = {}
        with self.assertRaises(ValueError): self.result()

    def test_unassessed_task_requires_analysis_not_wait(self):
        self.state['coverage']['P10-03']['disposition'] = 'unassessed'
        self.assertEqual(self.result()['decision'], 'CONTINUE')

    def test_done_requires_evidence(self):
        a = unit('done'); a['state'] = 'done'; self.state['units'] = [a]
        with self.assertRaises(ValueError): self.result()

    def test_wait_requires_resume_owner(self):
        a = unit('blocked', blocker='permission'); a['owner'] = ''
        self.state['units'] = [a]
        with self.assertRaises(ValueError): self.result()

    def test_grant_releases_only_its_work(self):
        a, b = unit('review'), unit('phone', blocker='human test')
        a['permissions'] = ['cli-evidence-transfer']; self.state['units'] = [a,b]
        self.state['grants'] = ['cli-evidence-transfer']
        self.assertEqual([r['id'] for r in self.result()['ready']], ['review'])

    def test_tracked_plan_cannot_disappear_from_queue(self):
        self.state['coverage']['P10-03'].update(disposition='tracked', units=['missing'])
        with self.assertRaises(ValueError): self.result()

    def test_unknown_coverage_status_rejected(self):
        self.state['coverage']['P10-03']['disposition'] = 'assumed_done'
        with self.assertRaises(ValueError): self.result()

    def test_cli_stop_check_rejects_active_work_but_allows_only_blocked_wait(self):
        import contextlib
        import io
        import json
        import tempfile
        from unittest.mock import patch
        import select_work
        with tempfile.TemporaryDirectory(prefix='sr-stop-check-') as folder:
            root = Path(folder)
            (root / 'docs/reference/search').mkdir(parents=True)
            (root / 'docs/reference/search/tasks.json').write_text(
                json.dumps([{'id': 'P10-03'}]), encoding='utf-8')
            state_file = root / 'state.json'
            for status, blocker, expected in [('active', None, 1), ('pending', None, 1), ('pending', 'USER result', 0)]:
                with self.subTest(status=status, blocker=blocker):
                    work = unit('work'); work['state'] = status
                    if blocker: work['blocker'] = blocker
                    self.state['units'] = [work]
                    state_file.write_text(json.dumps(self.state), encoding='utf-8')
                    with patch.object(select_work, 'ROOT', root), patch.object(sys, 'argv',
                            ['select_work.py', '--state', str(state_file), '--check-stop']), contextlib.redirect_stdout(io.StringIO()):
                        self.assertEqual(select_work.main(), expected)

    def test_active_work_is_not_relaunched(self):
        a = unit('running'); a['state'] = 'active'; self.state['units'] = [a]
        self.assertEqual(self.result()['ready'], [])
        self.assertEqual(self.result()['decision'], 'IN_PROGRESS')

    def test_pending_candidates_are_serialized_on_shared_file(self):
        a, b = unit('a'), unit('b')
        a['writes'] = ['lib/shared.dart']; b['reads'] = ['lib/shared.dart']
        self.state['units'] = [a,b]
        self.assertEqual([r['id'] for r in self.result()['ready']], ['a'])
        self.assertEqual([r['id'] for r in self.result()['blocked']], ['b'])

    def test_equivalent_paths_cannot_bypass_pending_or_active_locks(self):
        for status in ('pending', 'active'):
            with self.subTest(status=status):
                a,b=unit('a'),unit('b')
                a.update(state=status,writes=['apps/mobile'])
                b.update(reads=['./apps//mobile/lib/a.dart'])
                self.state['units']=[a,b]
                self.assertEqual([r['id'] for r in self.result()['blocked']],['b'])

    def test_current_session_work_needs_no_delegation_grant(self):
        import json
        root = Path(__file__).resolve().parents[2]
        state = json.loads((root / 'docs/workflow-state.json').read_text(encoding='utf-8-sig'))
        planned = json.loads((root / 'docs/reference/search/tasks.json').read_text(encoding='utf-8-sig'))
        self.assertIn('current-session-only', state['execution_policy'])
        self.assertEqual(state['grants'], [])
        for u in state['units']:
            if u['state'] != 'done':
                self.assertFalse(any(p.startswith(('worker.', 'review.')) for p in u['permissions']))
        # Validate the live inventory without deleting active units referenced
        # by plan coverage. Runtime progress must not corrupt this fixture.
        select(state, [r['id'] for r in planned])
        connect = next(u.copy() for u in state['units'] if u['id'] == 'P10-04b-CONNECT')
        connect['state'] = 'pending'
        self.state['units'] = [connect]
        self.state['facts'] = ['export.integrated']
        result = self.result()
        self.assertIn('P10-04b-CONNECT', [r['id'] for r in result['ready']])
        self.state['facts'] = []
        self.assertEqual(self.result()['ready'], [])
        self.assertIn('prerequisite: export.integrated', self.result()['blocked'][0]['reasons'])


if __name__ == '__main__':
    unittest.main()
