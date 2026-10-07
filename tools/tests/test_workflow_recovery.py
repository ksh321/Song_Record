"""Recovery boundaries and end-to-end decisions without model calls or notifications."""
import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from workflow_recovery import eligible, registered_request, recover
from workflow_status import dispatch_recovery, render
from workflow_runtime import atomic_json


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.mobile = self.root / 'apps/mobile'
        (self.mobile / 'test').mkdir(parents=True)
        (self.mobile / 'test/sync_test.dart').write_text('test fixture')
        (self.mobile / 'build.yaml').write_text('targets: {}')
        self.data = dict(task_id='P10-07', end_task='P10-07', created='test-run',
            thread_id='existing', stage='IMPLEMENT', status='WAITING_AI', reason='approval',
            incidents={'keep': {'total': 2, 'maximum': 0}}, active_incident='keep',
            call={'phase': 'completed', 'requests': []},
            plan={'checks': [{'id': 'sync', 'kind': 'flutter-test',
                             'targets': ['test/sync_test.dart'], 'timeout': 600}]})
        self.directory = self.root / '.local/workflow/runs/sequential'
        self.directory.mkdir(parents=True)
        self.runner = Mock(root=self.root, directory=self.directory, data=self.data)
        self.runner.stopped.return_value = False
        self.runner.source.return_value = 'source-unchanged'
        self.runner.pause.side_effect = lambda status, reason: self.data.update(status=status, reason=reason)
        self.runner.save.side_effect = lambda: atomic_json(self.directory / 'checkpoint.json', self.data)
        self.client = Mock()
        self.client.capabilities.return_value = {'rate_limits': {}, 'models': [
            {'model': 'gpt-6-astra', 'supportedReasoningEfforts': [{'reasoningEffort': 'high'}]}]}
        self.client.turn.return_value = {'status': 'completed', 'text': json.dumps(dict(
            decision='retry_stage', reason='Confirmed local error; fix the recorded function', check_id='',
            preparation='', steps='', expected='', reply=''))}
        self.addCleanup(patch.stopall)
        patch('workflow_recovery.git', return_value='head').start()
        patch('workflow_usage.write_report').start()

    def request(self, command, **params):
        self.data['call']['requests'] = [{'method': 'item/commandExecution/requestApproval',
            'params': dict(cwd=str(self.mobile), commandActions=[{'command': command}], **params)}]

    def test_all_waits_stops_completion_and_budget_excluded(self):
        for status in ('RUN_FINISHED', 'COMPLETE', 'PAUSED_USER', 'PAUSED_QUOTA', 'WAITING_USER'):
            self.assertFalse(eligible(dict(self.data, status=status)))
        self.assertFalse(eligible(self.data, True))
        self.assertFalse(eligible(dict(self.data, request={'resolved': False})))
        self.data['incidents']['keep']['maximum'] = 3
        self.assertFalse(eligible(self.data))

    def test_registered_test_only_rebuilds_allowed_command(self):
        self.request('& "C:/flutter/bin/flutter.bat" test --no-pub test/sync_test.dart --reporter expanded')
        check = registered_request(self.root, self.data)
        self.assertEqual(check['targets'], ['test/sync_test.dart'])
        self.assertEqual(check['kind'], 'flutter-test')

    def test_shell_injection_unknown_target_executable_or_option_rejected(self):
        for command in (
            'C:/flutter/bin/flutter.bat test test/sync_test.dart; whoami',
            'C:/flutter/bin/flutter.bat test test/other.dart',
            'C:/evil/flutter.bat test test/sync_test.dart',
            'C:/flutter/bin/flutter.bat test test/sync_test.dart --update-goldens',
            'C:/flutter/bin/flutter.bat test test/../sync_test.dart',
            'C:/flutter/bin/flutter.bat test test/sync_test.dart && echo yes'):
            self.request(command)
            self.assertIsNone(registered_request(self.root, self.data), command)

    def test_codegen_only_in_implementation_and_does_not_delete_outputs(self):
        self.request('C:/flutter/bin/cache/dart-sdk/bin/dart.exe run build_runner build --delete-conflicting-outputs')
        check = registered_request(self.root, self.data)
        from workflow_recovery import command_argv
        self.assertNotIn('--delete-conflicting-outputs', command_argv(self.root, check)[0])
        self.data['stage'] = 'REVIEW'
        self.assertIsNone(registered_request(self.root, self.data))

    def test_known_permission_recovery_no_ai_no_notification_preserves_failures(self):
        self.request('C:/flutter/bin/flutter.bat test test/sync_test.dart')
        before = copy.deepcopy(self.data['incidents'])
        with patch('workflow_recovery.execute', return_value={'status': 'PASS', 'exit_code': 0}) as execute:
            self.assertTrue(recover(self.runner, self.client))
        execute.assert_called_once()
        self.client.turn.assert_not_called()
        self.runner.record_request.assert_not_called()
        self.assertEqual(self.data['status'], 'READY')
        self.assertEqual(self.data['incidents'], before)
        self.assertNotIn('validated_fingerprint', self.data)

    def test_failed_registered_check_routes_log_to_existing_diagnosis(self):
        self.request('C:/flutter/bin/flutter.bat test test/sync_test.dart')
        with patch('workflow_recovery.execute', return_value={'status': 'FAIL', 'exit_code': 1}):
            self.assertTrue(recover(self.runner, self.client))
        details = self.runner.queue_failure.call_args.args[1]
        self.assertIn('log_directory', details['result'])
        self.runner.record_request.assert_not_called()

    def test_unknown_error_one_readonly_ai_in_same_thread(self):
        self.assertTrue(recover(self.runner, self.client))
        self.client.turn.assert_called_once()
        self.assertEqual(self.client.turn.call_args.args[0], 'existing')
        self.assertTrue(self.client.turn.call_args.kwargs['read_only'])
        self.assertEqual(self.client.turn.call_args.kwargs['effort'], 'high')
        self.assertEqual(self.data['stage'], 'IMPLEMENT')

    def test_repeated_same_command_new_provider_ids_does_not_execute_twice(self):
        self.request('C:/flutter/bin/flutter.bat test test/sync_test.dart', itemId='first')
        with patch('workflow_recovery.execute', return_value={'status': 'PASS', 'exit_code': 0}) as execute:
            self.assertTrue(recover(self.runner, self.client))
            self.data.update(status='WAITING_AI', reason='approval')
            self.request('C:/flutter/bin/flutter.bat test test/sync_test.dart', itemId='second')
            self.assertFalse(recover(self.runner, self.client))
            execute.assert_called_once()
        self.runner.record_request.assert_called_once_with('AUTO_RECOVERY_UNRESOLVED')

    def test_interrupted_recovery_intent_never_repeats_ai(self):
        self.data.update(recovery_inflight='pending', recoveries={'pending': {'status': 'AI_INTENT'}})
        self.assertFalse(recover(self.runner, self.client))
        self.client.turn.assert_not_called()

    def test_uncertain_turn_or_git_stage_never_replayed(self):
        for stage, phase in [('IMPLEMENT', 'accepted'), ('PUSH', 'completed')]:
            self.data.update(stage=stage, recoveries={}, recovery_inflight=None)
            self.data['call']['phase'] = phase
            self.assertFalse(recover(self.runner, self.client))
        self.client.turn.assert_not_called()

    def test_quota_pauses_without_ai(self):
        self.client.capabilities.return_value['rate_limits'] = {'ordinaryUsageAllowed': False}
        self.assertFalse(recover(self.runner, self.client))
        self.assertEqual(self.data['status'], 'PAUSED_QUOTA')
        self.client.turn.assert_not_called()

    def test_human_action_guidance_is_preserved_and_notified(self):
        decision = dict(decision='user_action', reason='USB disconnected', check_id='',
                        preparation='Connect phone', steps='Unlock and approve USB', expected='Device connected', reply='Connected')
        self.client.turn.return_value['text'] = json.dumps(decision)
        self.assertFalse(recover(self.runner, self.client))
        self.assertEqual(self.data['next_action']['steps'], decision['steps'])
        self.runner.record_request.assert_called_once_with('AUTO_RECOVERY_UNRESOLVED')

    def test_existing_escalation_is_preserved_for_unknown_diagnosis(self):
        self.data['incidents']['keep']['total'] = 3
        self.client.capabilities.return_value['models'][0]['supportedReasoningEfforts'].append({'reasoningEffort': 'max'})
        self.assertTrue(recover(self.runner, self.client))
        self.assertEqual(self.client.turn.call_args.kwargs['effort'], 'max')
        self.assertEqual(self.data['incidents']['keep']['total'], 3)

    def test_ai_cannot_invent_unregistered_check(self):
        decision = json.loads(self.client.turn.return_value['text'])
        decision.update(decision='run_check', check_id='invented')
        self.client.turn.return_value['text'] = json.dumps(decision)
        with patch('workflow_recovery.execute') as execute:
            self.assertFalse(recover(self.runner, self.client))
            execute.assert_not_called()

    def test_readonly_diagnosis_modification_blocks_resume(self):
        def changed(*args, **kwargs):
            self.runner.source.return_value = 'changed'
            return {'status': 'completed', 'text': '{}'}
        self.client.turn.side_effect = changed
        self.assertFalse(recover(self.runner, self.client))
        self.assertEqual(self.data['status'], 'BLOCKED')

    def test_user_stop_during_diagnosis_no_resume_or_phone(self):
        self.client.turn.side_effect = lambda *a, **k: (setattr(self.runner.stopped, 'return_value', True) or
                                                      {'status': 'interrupted'})
        self.assertFalse(recover(self.runner, self.client))
        self.assertEqual(self.data['status'], 'PAUSED_USER')
        self.runner.record_request.assert_not_called()

    def test_monitor_dispatch_once_and_stale_token_or_stop_excluded(self):
        atomic_json(self.directory / 'status-monitor.json', {'token': 'one'})
        with patch('workflow_status.subprocess.Popen') as launch:
            launch.return_value.pid = 123
            self.assertFalse(dispatch_recovery(self.root, 'old', self.data))
            self.assertTrue(dispatch_recovery(self.root, 'one', self.data))
            self.assertFalse(dispatch_recovery(self.root, 'one', self.data))
            launch.assert_called_once()
            atomic_json(self.directory / 'stop.json', {})
            self.assertFalse(dispatch_recovery(self.root, 'one', self.data))

    def test_live_recovery_panel_reports_ai_only_when_called(self):
        self.data.update(recovery_active=True, recovery_inflight='key', recoveries={'key': {
            'call': {'phase': 'accepted', 'requested_model': 'gpt-6-astra', 'requested_effort': 'high'}}})
        panel = render(self.data, True, '', '')
        self.assertIn('🟢', panel)
        self.assertIn('AI 응답 대기', panel)
        self.assertIn('Astra / High', panel)


if __name__ == '__main__':
    unittest.main()
