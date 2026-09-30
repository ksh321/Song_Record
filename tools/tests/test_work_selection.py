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

    def test_repository_connect_grant_does_not_release_other_work(self):
        import json
        root = Path(__file__).resolve().parents[2]
        state = json.loads((root / 'docs/workflow-state.json').read_text(encoding='utf-8-sig'))
        planned = json.loads((root / 'docs/reference/search/tasks.json').read_text(encoding='utf-8-sig'))
        connect = next(u for u in state['units'] if u['id'] == 'P10-04b-CONNECT')
        permissions = set(connect['permissions'])
        self.assertEqual(permissions, {'worker.p10-04b-connect'})
        for u in state['units']:
            if u['id'] != connect['id']:
                self.assertFalse(permissions.intersection(u['permissions']))
        state['grants'] += list(permissions)
        state['facts'] += ['export.integrated', 'p10.remaining.analysis']
        result = select(state, [r['id'] for r in planned])
        self.assertNotIn('P10-05-NEXT', [r['id'] for r in result['ready']])


if __name__ == '__main__':
    unittest.main()
