"""Controller acceptance tests. No model generation, network, or real notifications."""
import copy
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from codex_transport import AppServer, ProviderError
from select_work import select
from sequential_runner import Runner, next_task, original_tasks, validate_plan, verify_report
from workflow_runtime import (Blocked, RunLock, atomic_json, execute, failure_action, fingerprint,
                              git, observation_matches, quota_available, read_json,
                              record_failure, recover_json, select_model)


def models():
    return [{'model': m, 'supportedReasoningEfforts': [{'reasoningEffort': e} for e in
             ('low', 'medium', 'high', 'xhigh', 'max', 'ultra')]}
            for m in ('gpt-6.1-sol', 'gpt-6-astra')]


def unit(name):
    return {'id': name, 'state': 'pending', 'owner': 'AI', 'resume': 'continue current unit',
            'action': 'implement', 'reads': [], 'writes': [], 'permissions': [], 'requires': []}


def state():
    return {'execution_mode': 'strict_sequential', 'sequence_start': 'P10-02-NEXT',
            'units': [unit('P10-02-NEXT'), unit('P10-10-NEXT')],
            'priority_order': ['P10-02-NEXT', 'P10-10-NEXT'], 'grants': [], 'facts': [],
            'coverage': {k: {'disposition': 'preserved_scope', 'basis': 'preserved historical evidence'}
                         for k in ('P10-02', 'P10-10')}, 'runner': {'enabled': True}}


class ModelPolicyTests(unittest.TestCase):
    def test_w61_general_sol_medium(self):
        self.assertEqual(select_model(models()), {'model': 'gpt-6.1-sol', 'effort': 'medium'})

    def test_w62_sensitive_astra_high(self):
        self.assertEqual(select_model(models(), 'sensitive'), {'model': 'gpt-6-astra', 'effort': 'high'})

    def test_w63_complex_high_same_task_model(self):
        self.assertEqual(select_model(models(), 'complex'), {'model': 'gpt-6.1-sol', 'effort': 'high'})

    def test_w65_no_silent_fallback(self):
        with self.assertRaises(Blocked):
            select_model(models()[1:])
        values = models()
        values[0]['supportedReasoningEfforts'] = [{'reasoningEffort': 'low'}]
        with self.assertRaises(Blocked):
            select_model(values)

    def test_w66_unknown_not_observed(self):
        self.assertFalse(observation_matches({'model': 'unknown', 'effort': 'unknown'}, select_model(models())))
        self.assertFalse(observation_matches({'model': 'gpt-6.1-sol', 'effort': 'medium', 'source': 'AI says so'}, select_model(models())))

    def test_w67_three_plus_three_and_restart(self):
        incident = {}
        self.assertEqual(record_failure(incident, 'initial'), 'REPAIR')
        self.assertEqual(incident['total'], 0)
        for i in range(3):
            action = record_failure(incident, str(i), repaired=True)
        self.assertEqual(action, 'ESCALATE')
        incident = json.loads(json.dumps(incident))
        for i in range(3):
            action = record_failure(incident, 'max' + str(i), maximum=True, repaired=True)
        self.assertEqual(action, 'BLOCKED')
        self.assertEqual((incident['total'], incident['maximum']), (6, 3))

    def test_w68_initial_maximum_three_only(self):
        incident = {}
        for i in range(3):
            action = record_failure(incident, str(i), maximum=True, repaired=True)
        self.assertEqual(action, 'BLOCKED')
        self.assertEqual(incident['total'], 3)

    def test_early_escalation_preserves_failures(self):
        incident = {}
        record_failure(incident, '1', repaired=True)
        for i in range(3):
            action = record_failure(incident, 'max' + str(i), maximum=True, repaired=True)
        self.assertEqual(action, 'BLOCKED')
        self.assertEqual(incident['total'], 4)

    def test_duplicate_failure_and_environment(self):
        incident = {}
        record_failure(incident, '1', repaired=True)
        record_failure(incident, '1', repaired=True)
        self.assertEqual(incident['total'], 1)
        self.assertEqual(record_failure(incident, 'network', category='environment'), 'BLOCKED_ENVIRONMENT')
        self.assertEqual(incident['total'], 1)

    def test_w69_new_general_task_resets_selection_not_incident(self):
        self.assertEqual(select_model(models(), escalate=True)['effort'], 'max')
        self.assertEqual(select_model(models())['effort'], 'medium')

    def test_w72_ultra_excluded_quota_not_estimated_from_tokens(self):
        self.assertEqual(select_model(models(), escalate=True)['effort'], 'max')
        self.assertFalse(quota_available({'rate_limits': {'ordinaryUsageAllowed': False}}))
        self.assertFalse(quota_available({'rate_limits': {'rateLimits': {'spendControlReached': True}}}))
        self.assertTrue(quota_available({'rate_limits': {'ordinaryUsageAllowed': True}}))

    def test_subscription_only(self):
        client = object.__new__(AppServer)
        client.call = lambda *a: {'account': {'type': 'apiKey'}}
        with self.assertRaises(ProviderError):
            client.capabilities()


class SequentialTests(unittest.TestCase):
    def test_w02_w46_block_never_skips(self):
        data = state()
        data['units'][0]['blocker'] = 'manual result'
        result = select(data, ['P10-02', 'P10-10'])
        self.assertEqual(result['ready'], [])
        self.assertEqual(result['decision'], 'WAIT')

    def test_w03_w04_done_advances_in_recorded_order(self):
        data = state()
        self.assertEqual(next_task(data, [{'id': 'P10-02'}, {'id': 'P10-10'}])[0][1], 'P10-02')
        data['units'][0].update(state='done', evidence='existing verified result')
        self.assertEqual(next_task(data, [{'id': 'P10-02'}, {'id': 'P10-10'}])[0][1], 'P10-10')

    def test_w45_existing_unit_preserved_and_phase_original_numbers(self):
        self.assertEqual(original_tasks('P10-04b-CONNECT', []), ['P10-04'])
        self.assertEqual(original_tasks('P11-PHASE', [{'id': 'P11-01'}, {'id': 'P11-02'}]), ['P11-01', 'P11-02'])

    def test_w47_missing_or_typo_mode_rejected(self):
        for mode in (None, 'strict_sequental', 'parallel'):
            data = state()
            data['execution_mode'] = mode
            with self.assertRaises(ValueError):
                select(data, ['P10-02', 'P10-10'])

    def test_multiple_active_rejected(self):
        data = state()
        for u in data['units']:
            u['state'] = 'active'
        with self.assertRaises(ValueError):
            select(data, ['P10-02', 'P10-10'])


class DurableTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def test_w36_atomic_backup_contains_previous_not_new(self):
        path = self.root / 'checkpoint.json'
        atomic_json(path, {'value': 1})
        atomic_json(path, {'value': 2})
        self.assertEqual(read_json(path), {'value': 2})
        self.assertEqual(read_json(str(path) + '.bak'), {'value': 1})
        path.write_text('{broken', encoding='utf-8')
        self.assertEqual(recover_json(path), ({'value': 1}, True))
        atomic_json(path, {'value': 3})
        self.assertEqual(read_json(str(path) + '.bak'), {'value': 1})

    def test_w29_second_runner_lock_rejected(self):
        with RunLock(self.root / 'lock'):
            with self.assertRaises(Blocked):
                with RunLock(self.root / 'lock'):
                    self.fail('Second writer acquired lock')
        with RunLock(self.root / 'lock'):
            pass

    def test_w17_external_failure_and_log_retained(self):
        result = execute([sys.executable, '-c', 'print("failure evidence"); raise SystemExit(7)'],
                         self.root, self.root / 'command', 10)
        self.assertEqual(result['exit_code'], 7)
        self.assertEqual(result['status'], 'FAIL')
        self.assertIn('failure evidence', (self.root / 'command/stdout.log').read_text())

    def test_timeout_never_passes(self):
        result = execute([sys.executable, '-c', 'import time; time.sleep(10)'], self.root,
                         self.root / 'command', .1)
        self.assertEqual(result['status'], 'TIMED_OUT')

    def test_w18_zero_tests_refused(self):
        (self.root / 'stdout.log').write_text('{"type":"done","success":true}\n')
        self.assertFalse(verify_report({'kind': 'flutter-test'}, {'status': 'PASS'}, self.root, self.root))
        (self.root / 'stdout.log').write_text('{"type":"testDone","result":"success","hidden":false}\n{"type":"done","success":true}\n')
        self.assertTrue(verify_report({'kind': 'flutter-test'}, {'status': 'PASS'}, self.root, self.root))

    def test_missing_api_report_refused(self):
        self.assertFalse(verify_report({'kind': 'api-test'}, {'status': 'PASS', 'started': '2026-10-02T00:00:00+00:00'}, self.root, self.root))


class RunnerFixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / 'repo'
        self.root.mkdir()
        for path in ('docs/reference/search', 'docs/verification', 'tools'):
            (self.root / path).mkdir(parents=True, exist_ok=True)
        atomic_json(self.root / 'docs/reference/search/tasks.json', [{'id': 'P10-02'}, {'id': 'P10-10'}])
        atomic_json(self.root / 'docs/workflow-state.json', state())
        (self.root / 'docs/reference/search/plan.txt').write_text('Original acceptance')
        (self.root / 'docs/verification/user-action-records.md').write_text('# User records\n', encoding='utf-8')
        (self.root / '내가할일.md').write_text('사용자 확인 대기 0건\n현재 직접 할 일 없음\n', encoding='utf-8')
        (self.root / 'docs/progress.md').write_text('Progress')
        (self.root / 'AGENTS.md').write_text('test fixture only')
        (self.root / '.gitignore').write_text('.local/\n')
        subprocess.run(['git', 'init', '-b', 'main', str(self.root)], check=True, capture_output=True)
        git(self.root, 'config', 'user.email', 'fixture@example.invalid')
        git(self.root, 'config', 'user.name', 'Fixture')
        git(self.root, 'add', '--', 'docs', 'tools', 'AGENTS.md', '.gitignore', '내가할일.md')
        git(self.root, 'commit', '-m', 'fixture')
        self.origin = Path(self.temp.name) / 'origin.git'
        subprocess.run(['git', 'init', '--bare', str(self.origin)], check=True, capture_output=True)
        git(self.root, 'remote', 'add', 'origin', str(self.origin))
        git(self.root, 'push', 'origin', 'main')
        self.runner = Runner(self.root)
        item, _ = next_task(state(), self.runner.tasks)
        self.runner.initialize_task(item, 'P10-10')

    def tearDown(self):
        self.temp.cleanup()

    def plan(self):
        task = self.runner.data['task_id']
        return {'task_id': task, 'title': '검증용 작업', 'objective': 'test workflow only', 'risk': 'sensitive',
                'acceptance': [{'id': 'A1', 'criterion': 'fixture changed', 'basis': 'original', 'checks': ['diff', 'review']}],
                'sources': ['docs/reference/search/plan.txt'], 'scope': [task + '.txt'],
                'checks': [{'id': 'diff', 'kind': 'diff', 'targets': [], 'timeout': 10}],
                'manual': {'required': False, 'reason': 'fixture only'},
                'verification_file': 'docs/verification/' + task + '.md'}

    def fake_ai(self, instruction, expected, read_only=False):
        if expected == 'plan':
            return self.plan()
        if expected == 'implemented':
            (self.root / (self.runner.data['task_id'] + '.txt')).write_text('implemented\n')
            return {'changed_files': [self.runner.data['task_id'] + '.txt']}
        if expected == 'reviewed':
            return {'approved': True, 'findings': [], 'acceptance_reviewed': ['A1']}
        if expected == 'finalized':
            (self.root / self.runner.data['plan']['verification_file']).write_text(self.runner.data['target_commit'])
            return {'acceptance_passed': ['A1']}
        self.fail('unexpected AI stage')

    def test_w01_w03_w33_two_complete_original_tasks_no_result_commit(self):
        # Real local Git and command execution; fake only the provider and remote CI service.
        base_count = int(git(self.root, 'rev-list', '--count', 'HEAD'))
        self.runner.ai = self.fake_ai
        for task in ('P10-02', 'P10-10'):
            while self.runner.data['stage'] != 'CI':
                self.runner.step()
            self.assertEqual(git(self.root, 'ls-remote', 'origin', 'refs/heads/main').split()[0], self.runner.data['target_commit'])
            self.runner.data.update(ci={'overall': 'NOT_REQUIRED'}, stage='FINALIZE', status='READY')
            self.runner.step()
            self.assertEqual(self.runner.data['stage'], 'COMPLETE')
            if task == 'P10-02':
                item, _ = next_task(self.runner.state(), self.runner.tasks)
                self.runner.initialize_task(item, 'P10-10')
        self.assertEqual(int(git(self.root, 'rev-list', '--count', 'HEAD')) - base_count, 2)
        self.assertTrue(all(u['state'] == 'done' for u in self.runner.state()['units']))
        self.assertIn('docs/verification/P10-10.md', git(self.root, 'status', '--porcelain'))

    def test_w41_source_and_contract_changes_invalidate(self):
        before = self.runner.source()
        (self.root / 'docs/verification/other-contract.md').write_text('input changed')
        self.assertNotEqual(before, self.runner.source())

    def test_w50_ci_success_without_review_cannot_complete(self):
        self.runner.data.update(plan=self.plan(), ci={'overall': 'PASS'})
        with self.assertRaises(Blocked):
            self.runner.complete({'acceptance_passed': ['A1']})

    def test_w24_w25_w37_user_event_bound_to_revision_and_stop(self):
        self.runner.data.update(stage='MANUAL', status='WAITING_USER', request={
            'item_id': 'USER-001', 'revision': 2, 'task_id': 'P10-02', 'build': self.runner.source(), 'resolved': False})
        self.runner.save()
        atomic_json(self.runner.stop_path, {'stop': True})
        event = self.root / '.local/event.json'
        data = dict(self.runner.data['request'], outcome='passed', evidence='Explicit human report')
        data['revision'] = 1
        atomic_json(event, data)
        with self.assertRaises(Blocked):
            self.runner.accept_event(event)
        data['revision'] = 2
        atomic_json(event, data)
        self.assertEqual(self.runner.accept_event(event), 'RECORDED_EXPLICIT_RESUME_REQUIRED')
        self.assertEqual(self.runner.accept_event(event), 'ALREADY_APPLIED')
        self.assertTrue(self.runner.stop_path.exists())

    def test_blocked_without_steps_still_notifies_with_honest_fallback(self):
        with patch('sequential_runner.execute', return_value={'exit_code': 0}) as send:
            self.runner.record_request('EXECUTION_BLOCKED')
            self.runner.record_request('EXECUTION_BLOCKED')
            self.assertEqual(send.call_count, 1)
        self.assertEqual(self.runner.data['notification_pending']['owner'], 'AI')
        self.assertIn('request', self.runner.data)
        todo = (self.root / '내가할일.md').read_text(encoding='utf-8')
        self.assertIn('아직 특정 조작 방법은 확인되지 않았으므로', todo)
        self.assertIn('중단 원인과 해결 절차 알려줘', todo)

    def test_startup_block_sends_alert_without_overwriting_work_checkpoint(self):
        from sequential_runner import main
        original = self.runner.path.read_bytes() if self.runner.path.exists() else None
        startup = Runner(self.root)
        with patch('sequential_runner.Runner', return_value=startup), \
             patch.object(startup, 'run', side_effect=Blocked('CHATGPT_SUBSCRIPTION_LOGIN_REQUIRED')), \
             patch('sys.argv', ['runner', 'run', '--end-task', 'P10-02']), \
             patch('sequential_runner.execute', return_value={'exit_code': 0}) as send:
            self.assertEqual(main(), 2)
            self.assertEqual(send.call_count, 1)
        self.assertTrue((self.runner.directory / 'startup-alert/checkpoint.json').exists())
        if original is not None:
            self.assertEqual(self.runner.path.read_bytes(), original)

    def test_w39_notification_unknown_not_resent(self):
        self.runner.data['next_action'] = dict(preparation='폰 잠금 해제', steps='폰 설정에서 USB 디버깅 허용을 누릅니다.', expected='연결 허용', reply='승인 여부')
        with patch('sequential_runner.execute', side_effect=OSError('unavailable')) as send:
            self.runner.record_request('ENVIRONMENT_REQUIRES_ACTION')
            self.runner.record_request('ENVIRONMENT_REQUIRES_ACTION')
            self.assertEqual(send.call_count, 1)

    def test_w70_recover_completed_turn_without_invocation(self):
        self.runner.data.update(thread_id='known', call={'stage': 'PLAN', 'phase': 'intent', 'prior_turn_ids': ['old']})
        client = object.__new__(AppServer)
        client.call = lambda *a: {'thread': {'status': {'type': 'idle'}, 'path': None, 'turns': [
            {'id': 'old', 'status': 'completed'}, {'id': 'new', 'status': 'completed', 'items': [
                {'type': 'agentMessage', 'text': '{"action":"plan","payload":"{}","summary":"recovered"}'}]}]}}
        self.runner.client = client
        self.runner.reconcile_call()
        self.assertEqual(self.runner.data['recovered_turn_result']['turn_id'], 'new')

    def test_w64_w70_active_turn_not_relaunched(self):
        self.runner.data.update(thread_id='known', call={'stage': 'PLAN', 'phase': 'accepted', 'turn_id': 'active'})
        client = object.__new__(AppServer)
        client.call = lambda *a: {'thread': {'status': {'type': 'active'}}}
        self.runner.client = client
        with self.assertRaisesRegex(Blocked, 'STILL_ACTIVE'):
            self.runner.reconcile_call()

    def test_w71_ci_wait_calls_no_ai_and_wrong_sha_not_passed(self):
        self.runner.data.update(stage='CI', status='WAITING_EXTERNAL', target_commit='a'*40,
                                push_base_commit='b'*40, ci_started=__import__('time').time(), ci_errors=0)
        atomic_json(self.root / ('.local/workflow/ci-' + 'a'*40 + '.json'), {'commit': 'c'*40, 'overall': 'PASS'})
        with patch('sequential_runner.execute', return_value={'exit_code': 2}), patch.object(self.runner, 'ai') as ai:
            self.runner.ci_once()
            ai.assert_not_called()
        self.assertEqual(self.runner.data['status'], 'WAITING_EXTERNAL')
        self.assertEqual(self.runner.data['ci_errors'], 1)

    def test_w26_push_response_loss_does_not_duplicate_commit(self):
        self.runner.ai = self.fake_ai
        while self.runner.data['stage'] != 'PUSH':
            self.runner.step()
        target = self.runner.data['target_commit']
        git(self.root, 'push', 'origin', 'HEAD:main')
        self.runner.push()
        self.assertEqual(git(self.root, 'rev-parse', 'HEAD'), target)
        self.assertEqual(self.runner.data['stage'], 'CI')

    def test_w38_run_loop_stops_at_authorized_endpoint(self):
        atomic_json(self.root / '.local/workflow/runner-verification.json', {'controller_hash': 'fixture', 'status': 'PASS'})
        atomic_json(self.root / '.local/workflow/phone/confirmed.json', {'status': 'HUMAN_CONFIRMED'})
        atomic_json(self.root / '.local/workflow/phone/receipt.json', {'status': 'SERVER_ACCEPTED', 'kind': 'Intervention'})
        self.runner.ai = self.fake_ai
        self.runner.data['end_task'] = 'P10-02'
        self.runner.save()
        def ci_complete():
            self.runner.data.update(ci={'overall': 'NOT_REQUIRED'}, stage='FINALIZE', status='READY')
        self.runner.ci_once = ci_complete
        with patch('sequential_runner.controller_hash', return_value='fixture'), patch('sequential_runner.AppServer'), patch.object(self.runner, 'notify_completion') as notice:
            self.runner.run()
            notice.assert_called_once()
        self.assertEqual(self.runner.data['status'], 'RUN_FINISHED')
        self.assertEqual(self.runner.data['task_id'], 'P10-02')
        self.assertFalse((self.root / 'P10-10.txt').exists())

    def test_git_never_waits_for_account_picker(self):
        with patch('workflow_runtime.subprocess.run') as command:
            command.return_value.returncode = 0
            command.return_value.stdout = 'ok'
            self.assertEqual(git(self.root, 'ls-remote', 'origin'), 'ok')
            args, kwargs = command.call_args
            self.assertIn('credential.interactive=false', args[0])
            self.assertEqual(kwargs['env']['GIT_TERMINAL_PROMPT'], '0')
            self.assertEqual(kwargs['env']['GCM_INTERACTIVE'], 'Never')
            self.assertEqual(kwargs['timeout'], 120)
        with patch('workflow_runtime.subprocess.run', side_effect=subprocess.TimeoutExpired('git', 120)):
            with self.assertRaisesRegex(Blocked, 'GIT_TIMEOUT:ls-remote'):
                git(self.root, 'ls-remote', 'origin')

    def test_completion_notice_once_after_restart(self):
        self.runner.data.update(stage='COMPLETE', status='RUN_FINISHED', reason='APPROVED_END_REACHED')
        with patch('sequential_runner.execute', return_value={'exit_code': 0}) as send:
            self.runner.notify_completion()
            self.runner.load()
            self.runner.notify_completion()
            self.assertEqual(send.call_count, 1)
            self.assertIn('Completion', send.call_args.args[0])
        self.assertEqual(self.runner.data['completion_notification']['status'], 'SERVER_ACCEPTED')

    def test_completion_unknown_not_resent_or_claimed_received(self):
        self.runner.data.update(stage='COMPLETE', status='RUN_FINISHED', reason='APPROVED_END_REACHED')
        with patch('sequential_runner.execute', side_effect=OSError('response lost')) as send:
            self.runner.notify_completion()
            self.runner.load()
            self.runner.notify_completion()
            self.assertEqual(send.call_count, 1)
        self.assertEqual(self.runner.data['completion_notification']['status'], 'UNKNOWN')

    def test_completion_notice_rejects_incomplete_run(self):
        with patch('sequential_runner.execute') as send:
            with self.assertRaises(Blocked):
                self.runner.notify_completion()
            send.assert_not_called()

    def test_w37_run_after_stop_never_invokes_provider(self):
        atomic_json(self.root / '.local/workflow/runner-verification.json', {'controller_hash': 'fixture', 'status': 'PASS'})
        atomic_json(self.root / '.local/workflow/phone/confirmed.json', {'status': 'HUMAN_CONFIRMED'})
        atomic_json(self.root / '.local/workflow/phone/receipt.json', {'status': 'SERVER_ACCEPTED', 'kind': 'Intervention'})
        atomic_json(self.runner.stop_path, {'requested': True})
        with patch('sequential_runner.controller_hash', return_value='fixture'), patch('sequential_runner.AppServer') as provider:
            with self.assertRaisesRegex(Blocked, 'EXPLICIT_RESUME_REQUIRED'):
                self.runner.run()
            provider.assert_not_called()


if __name__ == '__main__':
    unittest.main()
