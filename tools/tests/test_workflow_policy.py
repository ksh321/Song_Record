"""Cause accounting and B workflow tests; no real model or phone calls."""
import copy
import json
import unittest
from unittest.mock import patch

import test_sequential_runner as fixtures
from workflow_policy import (bind_diagnosis, compact_context, simple_repair, stage_model,
                             simple_diagnostic_hint, simple_diagnosis_route)
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

    def test_plan_starts_astra_medium_and_explicit_escalation_high(self):
        self.data['stage'] = 'PLAN'
        self.assertEqual(stage_model(self.data, fixtures.models(), 'source'), {'model': 'gpt-6-astra', 'effort': 'medium'})
        self.data['plan_requires_core'] = True
        self.assertEqual(stage_model(self.data, fixtures.models(), 'source')['model'], 'gpt-6-astra')
        self.assertEqual(stage_model(self.data, fixtures.models(), 'source')['effort'], 'high')
        self.data['stage'] = 'REVIEW'
        self.assertEqual(stage_model(self.data, fixtures.models(), 'source')['model'], 'gpt-6-astra')

    def test_unclear_repair_does_not_inherit_general_task_model(self):
        self.bind()
        self.data['plan']['risk'] = 'general'
        self.data['diagnosis']['kind'] = 'core'
        self.assertEqual(stage_model(self.data, fixtures.models(), 'source')['model'], 'gpt-6-astra')
        self.data['diagnosis']['kind'] = 'syntax_import'
        self.assertEqual(stage_model(self.data, fixtures.models(), 'changed')['model'], 'gpt-6-astra')

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

    def test_only_complete_verified_import_diagnostics_route_to_sol(self):
        target = self.root / 'apps/mobile/test/sample.dart'
        target.parent.mkdir(parents=True)
        target.write_text("import 'unused.dart';\nvoid main() {}\n", encoding='utf-8')
        self.runner.data.update(stage='DIAGNOSE', plan=dict(self.plan(), scope=['apps/mobile/test/sample.dart']))
        directory = self.runner.directory / 'commands' / 'analyzer'
        directory.mkdir(parents=True, exist_ok=True)
        report = directory / 'stdout.log'
        row = "warning • Unused import: 'unused.dart' • test/sample.dart:1:8 • unused_import\n"
        report.write_text(row + '1 issue found.\n', encoding='utf-8')
        source = self.runner.source()
        details = {'check': {'kind': 'flutter-analyze'}, 'result': {'status': 'FAIL',
                   'fingerprint': source, 'log_directory': str(directory.relative_to(self.root))}}
        self.runner.queue_failure('first', details)
        hint = simple_diagnostic_hint(self.root, self.runner.data, source)
        self.assertEqual(hint['files'], ['apps/mobile/test/sample.dart'])
        self.runner.data['diagnosis_route'] = hint
        self.assertEqual(stage_model(self.runner.data, fixtures.models(), source)['model'], 'gpt-6.1-sol')
        self.assertFalse(simple_diagnosis_route(self.runner.data, 'changed'))
        self.runner.data['pending_failure']['id'] = 'different-event'
        self.assertFalse(simple_diagnosis_route(self.runner.data, source))
        for text in (row, row + '2 issues found.\n', row.replace('unused_import', 'undefined_identifier') + '1 issue found.\n',
                     row + 'error • Invalid type • test/sample.dart:2:1 • invalid_assignment\n2 issues found.\n'):
            with self.subTest(report=text):
                report.write_text(text, encoding='utf-8')
                self.assertIsNone(simple_diagnostic_hint(self.root, self.runner.data, source))
        details['check']['kind'] = 'flutter-test'
        report.write_text(row + '1 issue found.\n', encoding='utf-8')
        self.assertIsNone(simple_diagnostic_hint(self.root, self.runner.data, source))

    def test_uncertain_light_diagnosis_returns_to_astra_before_repair_or_budget_change(self):
        self.runner.data.update(stage='DIAGNOSE', plan=self.plan(), pending_failure={'id': 'first'},
                                incidents={'old': {'id': 'old', 'total': 2, 'maximum': 0}})
        source = self.runner.source()
        hint = {'kind': 'verified_import_cleanup', 'event_id': 'first', 'fingerprint': source, 'files': ['P10-02.txt']}
        result = diagnosis(self.runner.data)
        result.update(kind='core', cause_clear=False, files=['P10-02.txt'])
        selected = []
        def diagnose(*args, **kwargs):
            selected.append(stage_model(self.runner.data, fixtures.models(), source)['model'])
            return result
        self.runner.ai = diagnose
        with patch('sequential_runner.simple_diagnostic_hint', return_value=hint):
            self.runner.step()
            self.assertEqual(self.runner.data['stage'], 'DIAGNOSE')
            self.assertEqual(self.runner.data['incidents']['old']['total'], 2)
            self.assertNotIn('active_incident', self.runner.data)
            self.runner.step()
        self.assertEqual(selected, ['gpt-6.1-sol', 'gpt-6-astra'])
        self.assertEqual(self.runner.data['stage'], 'IMPLEMENT')
        self.assertEqual(stage_model(self.runner.data, fixtures.models(), source)['model'], 'gpt-6-astra')

    def test_implementation_plan_does_not_force_a_second_plan_call(self):
        plan = self.plan()
        plan['source_only'] = False
        self.runner.ai = lambda *a, **k: plan
        self.runner.step()
        self.assertEqual(self.runner.data['stage'], 'IMPLEMENT')

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
        self.runner.data['ci'] = {'overall': 'NOT_REQUIRED', 'commit': self.runner.data['target_commit'],
                                  'base_commit': self.runner.data['push_base_commit']}
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

    def test_normal_completion_needs_no_ai_and_checkpoint_tracks_completion(self):
        self.runner.ai = self.fake_ai
        while self.runner.data['stage'] != 'CI': self.runner.step()
        self.runner.data.update(stage='FINALIZE', ci={'overall': 'NOT_REQUIRED',
            'commit': self.runner.data['target_commit'], 'base_commit': self.runner.data['push_base_commit']})
        with patch.object(self.runner, 'ai') as ai:
            self.runner.step()
            ai.assert_not_called()
        self.assertEqual(self.runner.data['stage'], 'COMPLETE')
        checkpoint = read_json(self.runner.path)
        self.assertEqual(checkpoint['stage'], 'COMPLETE')
        self.assertEqual(checkpoint['target_commit'], self.runner.data['target_commit'])
        self.assertFalse((self.runner.directory / 'task-summary.json').exists())
        self.assertNotIn('summary_evidence', compact_context(self.runner.data))
        self.assertIn('P10-02', self.runner.state()['units'][0]['task_evidence'])

    def test_automatic_completion_rejects_missing_or_conflicting_evidence(self):
        import copy
        self.runner.ai = self.fake_ai
        while self.runner.data['stage'] != 'CI': self.runner.step()
        self.runner.data.update(stage='FINALIZE', ci={'overall': 'PASS',
            'commit': self.runner.data['target_commit'], 'base_commit': self.runner.data['push_base_commit']})
        valid = copy.deepcopy(self.runner.data)
        cases = [
            {'reviewed_fingerprint': 'stale'},
            {'review': {'approved': True, 'findings': ['unresolved'], 'acceptance_reviewed': ['A1']}},
            {'review': {'approved': True, 'findings': [], 'acceptance_reviewed': []}},
            {'ci': dict(valid['ci'], commit='a' * 40)},
            {'ci': dict(valid['ci'], base_commit='b' * 40)},
            {'ci': dict(valid['ci'], overall='FAIL')},
            {'plan': dict(valid['plan'], manual={'required': True}), 'manual_pass': False},
        ]
        for change in cases:
            with self.subTest(change=change):
                self.runner.data = copy.deepcopy(valid)
                self.runner.data.update(change)
                with self.assertRaises(Blocked): self.runner.step()
                self.assertFalse((self.runner.directory / 'final-facts.json').exists())
                self.assertNotEqual(self.runner.state()['units'][0]['state'], 'done')

    def test_failure_excerpt_is_bounded_and_full_evidence_retained(self):
        directory = self.runner.directory / 'commands' / 'failure-fixture'
        directory.mkdir(parents=True, exist_ok=True)
        (directory / 'stderr.log').write_text('irrelevant\n' * 5000 + 'Error: expected tail\n')
        details = {'result': {'log_directory': str(directory.relative_to(self.root))}}
        self.runner.queue_failure('example', details)
        context = compact_context(self.runner.data)
        self.assertNotIn('pending_failure', context)
        self.assertIn('Error: expected tail', context['failure']['excerpt'])
        self.assertLessEqual(len(context['failure']['excerpt']), 6000)
        self.assertEqual(read_json(self.runner.directory / 'failure.json')['details'], details)

    def test_context_is_stage_specific_and_does_not_carry_legacy_fast_results(self):
        self.runner.data.update(stage='IMPLEMENT', plan=self.plan(),
            results=[{'id': 'diff', 'status': 'PASS', 'stdout': 'large' * 10000}],
            fast_results=[{'stdout': 'legacy' * 10000}], review={'approved': False})
        context = compact_context(self.runner.data)
        self.assertNotIn('results', context)
        self.assertNotIn('fast_results', context)
        self.assertIn('basis', context['acceptance'][0])
        self.runner.data['stage'] = 'REVIEW'
        context = compact_context(self.runner.data)
        self.assertEqual(context['results'], [{'id': 'diff', 'status': 'PASS'}])

    def test_failure_is_diagnosed_before_repair_and_not_counted_as_task_total(self):
        self.runner.queue_failure('test-failure', {'message': 'test fixture'})
        self.assertEqual(self.runner.data['stage'], 'DIAGNOSE')
        d = diagnosis(self.runner.data); d['files'] = ['P10-02.txt']
        self.runner.data['plan'] = self.plan()
        self.runner.ai = lambda *a, **k: d
        self.runner.step()
        self.assertEqual(self.runner.data['stage'], 'IMPLEMENT')
        self.assertEqual(self.runner.data['incidents'][self.runner.data['active_incident']]['total'], 0)
