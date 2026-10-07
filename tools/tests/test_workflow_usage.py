"""Offline usage accounting: no model generation or network."""
import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from sequential_runner import Runner
from workflow_usage import html_report, markdown, summarize, task_totals, write_report, record_subscription, subscription_delta


def usage(n=100):
    return dict(input_tokens=n, cached_input_tokens=n//2, output_tokens=10,
                reasoning_output_tokens=3, total_tokens=n+10)


def add(a, b):
    return {k: a[k]+b[k] for k in a}


def record(turn, response, value, total=None):
    return {'type': 'token_usage_record', 'payload': {
        'turn_id': turn, 'response_id': response, 'usage': value,
        'turn_token_usage': total or value}}


class UsageTests(unittest.TestCase):
    def test_html_table_preserves_group_values_and_fixed_headers(self):
        self.write(self.rollout, [record('a', 'one', usage())])
        report = summarize(self.events, [self.rollout])
        page = html_report(report)
        self.assertIn('position:sticky;top:0', page)
        self.assertIn('left:90px', page)
        self.assertEqual(page.count('<th scope="col"'), 14)
        self.assertIn('총 토큰량', page)
        self.assertIn('<td>110</td>', page)
        self.assertEqual(page.count('<tr data-task='), len(report['groups']) + len(task_totals(report['groups'])))
        self.assertIn('입력 합계', page)
        self.assertIn('<td>50</td>', page)
        self.assertNotIn('https://', page)
        self.assertNotIn('PRIVATE_SENTINEL', page)

    def test_task_totals_merge_models_and_preserve_missing_usage(self):
        self.write(self.events, self.call('a') + self.call('b', stage='REVIEW'))
        self.write(self.rollout, [record('a', 'one', usage())])
        report = summarize(self.events, [self.rollout])
        original = json.dumps(report)
        total = task_totals(report['groups'])[0]
        self.assertEqual(total['calls'], 2)
        self.assertEqual(total['responses'], 1)
        self.assertEqual(total['known_tokens']['input_tokens'], 100)
        self.assertEqual(total['unknown_calls'], 1)
        self.assertEqual(json.dumps(report), original)
        for group in report['groups']:
            group['known_tokens'] = None
        self.assertIsNone(task_totals(report['groups'])[0]['known_tokens'])

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.events = self.root / 'events.jsonl'
        self.rollout = self.root / 'rollout.jsonl'
        self.write(self.events, self.call('a'))

    def test_subscription_delta_and_reset_are_not_inferred_from_tokens(self):
        def raw(value, reset=9000):
            return {'accountId': 'PRIVATE_SENTINEL', 'rateLimitsByLimitId': {'codex': {
                'limitId': 'codex', 'primary': {'usedPercent': value,
                'windowDurationMins': 10080, 'resetsAt': reset}}}}
        record_subscription(self.root, raw(15), 'P10-07', 'start')
        record_subscription(self.root, raw(18), 'P10-07', 'start')
        result = record_subscription(self.root, raw(22), 'P10-07', 'end')
        self.assertEqual(subscription_delta(result, 'P10-07'), 'codex: 7%p')
        self.assertEqual(subscription_delta(result, 'P10-06'), '미확인')
        self.assertNotIn('PRIVATE_SENTINEL', json.dumps(result))
        result['tasks']['P10-07']['end']['windows'][0]['resetsAt'] = 9999
        self.assertEqual(subscription_delta(result, 'P10-07'), '초기화·기간 변경')

    def test_request_baseline_survives_plan_and_resume(self):
        def raw(value):
            return {'rateLimits': {'primary': {'usedPercent': value,
                    'windowDurationMins': 10080, 'resetsAt': 9000}}}
        initial = record_subscription(self.root, raw(10), 'P10-08', 'request')['tasks']['P10-08']['start']
        record_subscription(self.root, raw(12), 'P10-08', 'start')
        record_subscription(self.root, raw(14), 'P10-08', 'request')
        saved = record_subscription(self.root, raw(20), 'P10-08', 'end')
        self.assertEqual(saved['tasks']['P10-08']['start'], initial)
        self.assertEqual(initial['basis'], 'user_request_first_observation')
        self.assertEqual(subscription_delta(saved, 'P10-08'), 'default: 10%p')

    def test_missing_request_measurement_does_not_create_baseline(self):
        with self.assertRaisesRegex(ValueError, 'REQUEST_USAGE_UNAVAILABLE'):
            record_subscription(self.root, {}, 'P10-08', 'request')
        self.assertFalse((self.root / 'subscription-usage.json').exists())

    def tearDown(self):
        self.temp.cleanup()

    def write(self, path, rows):
        path.write_text(''.join(json.dumps(r, ensure_ascii=False)+'\n' for r in rows), encoding='utf-8')

    def call(self, turn, stage='IMPLEMENT'):
        return [
            {'utc': '2026-10-07T00:00:00+00:00', 'kind': 'model_intent', 'data': {
                'task_id': 'P10-05', 'stage': stage, 'requested_model': 'sol', 'requested_effort': 'medium'}},
            {'kind': 'model_accepted', 'data': {'turn_id': turn}},
            {'utc': '2026-10-07T00:00:02+00:00', 'kind': 'model_completed', 'data': {
                'turn_id': turn, 'status': 'completed', 'text': 'PRIVATE_SENTINEL',
                'observation': {'model': 'astra', 'effort': 'high'},
                'usage': {'total': {'inputTokens': 999999999}, 'last': {'inputTokens': 1}}}}]

    def test_response_dedup_including_duplicate_log_and_completed_event(self):
        a, b = usage(100), usage(200)
        self.write(self.events, self.call('a')+[self.call('a')[-1]])
        self.write(self.rollout, [record('a', 'r1', a), record('a', 'r2', b, add(a,b)), record('a','r2',b,add(a,b))])
        report = summarize(self.events, [self.rollout, self.rollout])
        self.assertEqual(len(report['calls']), 1)
        g = report['groups'][0]
        self.assertEqual((g['calls'],g['responses'],g['measured_calls']), (1,2,1))
        self.assertEqual(g['known_tokens']['input_tokens'], 300)
        self.assertEqual(g['known_tokens']['uncached_input_tokens'], 150)
        self.assertEqual(g['measured_seconds'], 2)
        self.assertNotIn('PRIVATE_SENTINEL', json.dumps(report)+markdown(report))
        self.assertIsNone(report['subscription_usage_percent'])

    def test_missing_and_partial_are_not_zero_or_complete(self):
        self.write(self.events, self.call('a')+self.call('b','REVIEW'))
        self.write(self.rollout, [record('a','r2',usage(),add(usage(),usage()))])
        report = summarize(self.events,[self.rollout])
        self.assertEqual([r['coverage'] for r in report['calls']], ['PARTIAL','UNKNOWN'])
        self.assertIsNone(report['groups'][1]['known_tokens'])
        self.assertIn('미확인', markdown(report))

    def test_conflicting_duplicate_and_invalid_numeric_data_are_excluded(self):
        self.write(self.rollout, [record('a','same',usage()), record('a','same',usage(200)),
                                 record('a','bad',dict(usage(),cached_input_tokens=1000)),
                                 record('a','bool',dict(usage(),input_tokens=True))])
        report = summarize(self.events,[self.rollout])
        self.assertEqual(report['calls'][0]['coverage'],'UNKNOWN')
        self.assertIsNone(report['calls'][0]['tokens'])

    def test_explicit_historical_prompt_and_observed_model(self):
        legacy=self.call('a')
        legacy[0]['data']={}
        legacy[-1]['data'].pop('observation')
        self.write(self.events,legacy)
        self.write(self.rollout,[{'type':'event_msg','payload':{'type':'task_started','turn_id':'a'}},
            {'type':'turn_context','payload':{'turn_id':'a','model':'gpt-6-astra','effort':'high'}},
            {'type':'response_item','payload':{'role':'user','content':[{'type':'input_text',
                'text':'현재 P번호 P10-05, 기존 단위 P10-05-NEXT.\n'+json.dumps({'stage':'DIAGNOSE'})}]}},
            record('a','r',usage())])
        g=summarize(self.events,[self.rollout])['groups'][0]
        self.assertEqual((g['task_id'],g['stage'],g['model'],g['effort']),
                         ('P10-05','DIAGNOSE','gpt-6-astra','high'))

    def test_other_turns_and_thread_totals_not_charged_to_runner(self):
        self.write(self.rollout,[record('external','x',usage(5000)),
            {'type':'event_msg','payload':{'type':'token_count','info':{'total_token_usage':usage(999999)}}},
            record('a','r',usage())])
        g=summarize(self.events,[self.rollout])['groups'][0]
        self.assertEqual(g['known_tokens']['input_tokens'],100)
        self.assertEqual(g['model'],'astra')

    def test_incomplete_json_is_reported_without_raw_data(self):
        self.rollout.write_text('{"PRIVATE_SENTINEL":',encoding='utf-8')
        report=summarize(self.events,[self.rollout])
        self.assertEqual(report['log_issues']['unreadable_rows'],1)
        self.assertEqual(report['calls'][0]['coverage'],'UNKNOWN')
        self.assertNotIn('PRIVATE_SENTINEL',json.dumps(report))

    def test_requested_model_does_not_replace_missing_observation(self):
        events=self.call('a')
        events[-1]['data'].pop('observation')
        events[-1].pop('utc')
        self.write(self.events,events)
        self.write(self.rollout,[record('a','r',usage())])
        report=summarize(self.events,[self.rollout])
        self.assertEqual(report['calls'][0]['requested_model'],'sol')
        self.assertEqual(report['calls'][0]['model'],'unknown')
        self.assertIsNone(report['calls'][0]['seconds'])
        self.assertIn('미확인',markdown(report))

    def test_report_preserves_checkpoint_events_and_uses_no_provider(self):
        home=self.root/'codex'
        (home/'sessions').mkdir(parents=True)
        self.write(home/'sessions/rollout-thread-a.jsonl',[record('a','r',usage())])
        checkpoint=self.root/'checkpoint.json'
        checkpoint.write_text('{"thread_id":"thread-a","stage":"BLOCKED"}',encoding='utf-8')
        before=(checkpoint.read_bytes(), self.events.read_bytes())
        with patch('sequential_runner.AppServer') as provider:
            report=write_report(self.root, home)
            provider.assert_not_called()
        self.assertEqual(before,(checkpoint.read_bytes(), self.events.read_bytes()))
        self.assertEqual(report['calls'][0]['coverage'],'COMPLETE')
        self.assertTrue((self.root/'usage-report.md').exists())

    def test_completion_hook_records_scope_and_report_failure_does_not_repeat_ai(self):
        runner=object.__new__(Runner)
        runner.directory=self.root
        runner.path=self.root/'checkpoint.json'
        runner.data={'task_id':'P10-05','stage':'DIAGNOSE','thread_id':'thread-a'}
        runner.client=SimpleNamespace(thread_path=str(self.rollout))
        runner.checkpoint('intent',{'requested_model':'astra','requested_effort':'high'})
        runner.checkpoint('accepted',{'turn_id':'a'})
        with patch('sequential_runner.write_usage_report', side_effect=RuntimeError) as report:
            runner.checkpoint('completed',{'turn_id':'a','status':'failed'})
            report.assert_called_once_with(self.root)
        events=[json.loads(line) for line in self.events.read_text(encoding='utf-8').splitlines()]
        self.assertEqual(events[-2]['data']['stage'],'DIAGNOSE')
        self.assertEqual(events[-2]['data']['task_id'],'P10-05')
        self.assertEqual(events[-1]['kind'],'usage_report_unavailable')
        self.assertEqual(runner.data['call']['phase'],'completed')


if __name__ == '__main__':
    unittest.main()
