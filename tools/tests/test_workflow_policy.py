"""Cause accounting and B workflow tests; no real model or phone calls."""
import copy
import json
import unittest
from unittest.mock import patch

import test_sequential_runner as fixtures
from workflow_policy import bind_diagnosis, compact_context, simple_repair, stage_model
from workflow_runtime import Blocked, read_json


def diagnosis(data, key='new', cause='ambiguous import'):
    return dict(incident_id=key, cause=cause, evidence='compiler log and import lines',
                identity_basis='same binding mechanism' if key != 'new' else 'different mechanism',
                fix='restrict import to intended exported type', contract_basis='existing type declaration',
                kind='syntax_import', cause_clear=True, behavior_unchanged=True, checkable=True,
                files=['app.dart'], comparisons=[dict(id=k, relation='same' if key == k else 'different',
                evidence='code mechanism compared') for k in data.get('incidents', {})])


class CauseTests(unittest.TestCase):
    def setUp(self):
        self.data = {'task_id': 'P10-04', 'stage': 'IMPLEMENT', 'plan': {'risk': 'sensitive'},
                     'pending_failure': {'id': 'first'}}

    def bind(self, key='new', event='first'):
        self.data['pending_failure']['id'] = event
        return bind_diagnosis(self.data, diagnosis(self.data, key), 'source')

    def test_unrelated_failures_never_add_together(self):
        for n in range(6):
            self.bind(event=str(n))
            key = self.data['active_incident']
            self.data['repair_attempt'] = dict(incident_id=key, changed=True, maximum=False)
        self.assertEqual(len(self.data['incidents']), 6)
        self.assertTrue(all(i['total'] == 0 for i in self.data['incidents'].values()))
        self.assertEqual(stage_model(self.data, fixtures.models(), 'source')['effort'], 'medium')

    def test_same_cause_changed_wording_restart_and_duplicate_keep_budget(self):
        self.bind()
        key = self.data['active_incident']
        for n in range(3):
            self.data = json.loads(json.dumps(self.data))
            self.data['repair_attempt'] = dict(incident_id=key, changed=True, maximum=False)
            action = self.bind(key, str(n))
        self.assertEqual(action, 'ESCALATE')
        self.bind(key, '2')
        self.assertEqual(self.data['incidents'][key]['total'], 3)
        self.assertEqual(stage_model(self.data, fixtures.models(), 'source')['effort'], 'max')
        for n in range(3):
            self.data['repair_attempt'] = dict(incident_id=key, changed=True, maximum=True)
            action = self.bind(key, 'max' + str(n))
        self.assertEqual(action, 'BLOCKED')

    def test_different_cause_then_recurrence_retains_previous_count(self):
        self.bind(); first = self.data['active_incident']
        self.data['repair_attempt'] = dict(incident_id=first, changed=True)
        self.bind(first, 'repair1')
        self.bind(event='other')
        self.data['incidents'][first]['status'] = 'resolved'
        self.bind(first, 'return with new message')
        self.assertEqual(self.data['incidents'][first]['total'], 1)
        self.assertEqual(self.data['incidents'][first]['status'], 'open')

    def test_skipping_comparison_or_renaming_same_cause_rejected(self):
        self.bind()
        d = diagnosis(self.data); d['comparisons'] = []
        with self.assertRaises(Blocked): bind_diagnosis(self.data, d, 'source')
        d = diagnosis(self.data); d['comparisons'][0]['relation'] = 'same'
        with self.assertRaises(Blocked): bind_diagnosis(self.data, d, 'source')

    def test_reviewer_maximum_is_not_repair_maximum(self):
        self.bind(); key = self.data['active_incident']
        self.data.update(maximum_observed=True, repair_attempt=dict(incident_id=key, changed=True, maximum=False))
        self.bind(key, 'review failure')
        self.assertEqual(self.data['incidents'][key]['maximum'], 0)

    def test_ci_failure_after_local_review_keeps_its_repair_attempt(self):
        self.bind(); key = self.data['active_incident']
        issue = self.data['incidents'][key]
        issue['last_attempt'] = dict(incident_id=key, changed=True, maximum=True)
        issue['status'] = 'resolved'
        self.data.pop('repair_attempt', None)
        self.bind(key, 'ci:target')
        self.assertEqual((issue['total'], issue['maximum']), (1, 1))

    def test_simple_requires_all_three_conditions_and_contract(self):
        d = diagnosis(self.data)
        self.assertTrue(simple_repair(d))
        for key in ('cause_clear', 'behavior_unchanged', 'checkable', 'contract_basis', 'files'):
            changed = dict(d); changed.pop(key)
            self.assertFalse(simple_repair(changed), key)
        self.assertFalse(simple_repair(dict(d, kind='core')))

    def test_stale_diagnosis_and_core_review_never_downgrade(self):
        self.bind()
        self.assertEqual(stage_model(self.data, fixtures.models(), 'changed')['effort'], 'high')
        self.data['stage'] = 'REVIEW'
        self.assertEqual(stage_model(self.data, fixtures.models(), 'source')['model'], 'gpt-6-astra')

    def test_max_does_not_stick_to_diagnosis_or_records(self):
        self.bind(); self.data['incidents'][self.data['active_incident']]['total'] = 3
        self.data['stage'] = 'DIAGNOSE'
        self.assertEqual(stage_model(self.data, fixtures.models(), 'source')['effort'], 'high')
        self.data['stage'] = 'FINALIZE'
        self.assertEqual(stage_model(self.data, fixtures.models(), 'source'),
                         {'model': 'gpt-6.1-sol', 'effort': 'medium'})

    def test_environment_does_not_consume_code_budget(self):
        d = diagnosis(self.data); d['kind'] = 'environment'
        bind_diagnosis(self.data, d, 'source')
        self.assertEqual(self.data['incidents'][self.data['active_incident']]['total'], 0)


class BIntegrationTests(unittest.TestCase):
    setUp = fixtures.RunnerFixture.setUp
    tearDown = fixtures.RunnerFixture.tearDown
    plan = fixtures.RunnerFixture.plan
    fake_ai = fixtures.RunnerFixture.fake_ai

    def test_incomplete_implementation_continues_without_early_checks(self):
        self.runner.ai = self.fake_ai
        self.runner.step()
        def small(*args, **kwargs):
            (self.root / 'P10-02.txt').write_text('small slice\n')
            return {'complete': False, 'changed_files': ['P10-02.txt']}
        self.runner.ai = small
        self.runner.step()
        with patch('sequential_runner.execute') as execute:
            self.runner.step()
            execute.assert_not_called()
        self.assertEqual(self.runner.data['stage'], 'IMPLEMENT')
        self.assertFalse(self.runner.checks_valid())

    def test_complete_implementation_runs_all_checks_without_ai_and_reuses_only_same_source(self):
        self.runner.ai = self.fake_ai
        self.runner.step(); self.runner.step()
        self.assertEqual(self.runner.data['stage'], 'VALIDATE')
        with patch.object(self.runner, 'ai') as ai:
            self.runner.step()
            ai.assert_not_called()
        self.assertEqual(self.runner.data['stage'], 'REVIEW')
        self.runner.data['stage'] = 'VALIDATE'
        with patch('sequential_runner.execute') as execute:
            self.runner.step(); execute.assert_not_called()
        self.assertTrue(self.runner.checks_valid())
        (self.root / 'P10-02.txt').write_text('changed after quick\n')
        self.assertFalse(self.runner.checks_valid())
        self.runner.data['stage'] = 'VALIDATE'
        from workflow_runtime import execute as real_execute
        with patch('sequential_runner.execute', wraps=real_execute) as execute:
            self.runner.step(); self.assertEqual(execute.call_count, 1)

    def test_retained_fast_checkpoint_does_not_run_partial_checks(self):
        for complete, expected in ((False, 'IMPLEMENT'), (True, 'VALIDATE')):
            self.runner.data.update(stage='FAST_VALIDATE', implementation_done=complete)
            with patch('sequential_runner.execute') as execute:
                self.runner.step()
                execute.assert_not_called()
            self.assertEqual(self.runner.data['stage'], expected)

    def test_one_command_checks_preserves_main_checkpoint_and_does_not_call_ai(self):
        self.runner.ai = self.fake_ai
        self.runner.step(); self.runner.step()
        original = self.runner.path.read_bytes()
        with patch('sequential_runner.AppServer') as server:
            result = self.runner.local_checks()
            server.assert_not_called()
        self.assertEqual(result['status'], 'PASS')
        self.assertEqual(self.runner.path.read_bytes(), original)

    def test_one_command_failure_preserves_checkpoint_and_never_notifies(self):
        self.runner.ai = self.fake_ai
        self.runner.step(); self.runner.step()
        (self.root / 'P10-02.txt').write_text('original\n')
        from workflow_runtime import git
        git(self.root, 'add', '--', 'P10-02.txt')
        (self.root / 'P10-02.txt').write_text('trailing whitespace  \n')
        original = self.runner.path.read_bytes()
        with patch.object(fixtures.Runner, 'record_request') as notify:
            result = self.runner.local_checks()
            notify.assert_not_called()
        self.assertEqual(result['status'], 'FAIL')
        self.assertEqual(self.runner.path.read_bytes(), original)

    def test_final_facts_idempotent_and_completion_gates_retained(self):
        self.runner.ai = self.fake_ai
        while self.runner.data['stage'] != 'CI': self.runner.step()
        with self.assertRaises(Blocked): self.runner.write_final_facts()
        self.runner.data['ci'] = {'overall': 'NOT_REQUIRED'}
        self.runner.write_final_facts()
        evidence = self.root / self.runner.data['plan']['verification_file']
        before = evidence.read_bytes()
        self.runner.write_final_facts()
        self.assertEqual(before, evidence.read_bytes())
        self.assertEqual(read_json(self.runner.directory / 'final-facts.json')['commit'],
                         self.runner.data['target_commit'])

    def test_context_omits_raw_reports_and_preserves_evidence_paths(self):
        self.runner.data.update(stage='FINALIZE', plan=self.plan(),
            results=[{'stdout': 'large secret-free fixture' * 1000}], review={'approved': True})
        context = compact_context(self.runner.data)
        self.assertNotIn('results', context)
        self.assertIn('final-facts.json', context['record'])

    def test_failure_is_diagnosed_before_repair_and_not_counted_as_task_total(self):
        self.runner.queue_failure('test-failure', {'message': 'test fixture'})
        self.assertEqual(self.runner.data['stage'], 'DIAGNOSE')
        d = diagnosis(self.runner.data); d['files'] = ['P10-02.txt']
        self.runner.data['plan'] = self.plan()
        self.runner.ai = lambda *a, **k: d
        self.runner.step()
        self.assertEqual(self.runner.data['stage'], 'IMPLEMENT')
        self.assertEqual(self.runner.data['incidents'][self.runner.data['active_incident']]['total'], 0)
