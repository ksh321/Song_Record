import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from workflow_status import BEGIN, TODO, observe, process_identity, publish, render, close_task, elapsed_label


class StatusTests(unittest.TestCase):
    def data(self):
        return dict(task_id='P10-06', stage='IMPLEMENT', status='READY',
                    call=dict(stage='IMPLEMENT', phase='accepted',
                              requested_model='gpt-6-astra', requested_effort='high'))

    def test_seven_lines_and_requested_model(self):
        text = render(self.data(), True, '증분 변경 수신', '')
        self.assertEqual(len(text.splitlines()), 7)
        self.assertIn('🟢 실행 중', text)
        self.assertIn('Astra / High — 요청 설정', text)

    def test_elapsed_uses_original_start_through_wait_and_resume(self):
        data = self.data()
        data.update(created='2026-10-07T00:00:00Z', updated='2026-10-07T01:00:00Z')
        now = datetime(2026, 10, 7, 1, 2, 3, tzinfo=timezone.utc)
        for state in ['READY', 'WAITING_AI', 'WAITING_USER', 'WAITING_EXTERNAL']:
            data['status'] = state
            self.assertEqual(elapsed_label(data, now), '62분 3초 · 중단·사용자 대기 포함')
        self.assertEqual(elapsed_label({}, now), '미확인')
        data['created'] = '2026-10-08T00:00:00Z'
        self.assertEqual(elapsed_label(data, now), '0분 0초 · 중단·사용자 대기 포함')

    def test_dead_process_and_ai_handoff_are_red(self):
        data = self.data()
        self.assertIn('🔴 비정상 종료', render(data, False, '', ''))
        data['status'] = 'WAITING_AI'
        text = render(data, True, '', '')
        self.assertIn('🔴 비정상 종료', text)
        self.assertIn('AI 확인 필요', text)
        self.assertIn('AI: 사용 안 함', text)

    def test_old_call_not_reported_as_active_ai(self):
        data = self.data(); data['stage'] = 'CI'
        text = render(data, True, '', '')
        self.assertIn('CI 결과 대기', text)
        self.assertIn('AI: 사용 안 함', text)

    def test_normal_completion_and_user_stop_remove_panel(self):
        for status in ['RUN_FINISHED', 'PAUSED_USER']:
            data = self.data(); data['status'] = status
            self.assertEqual(render(data, False, '', ''), '')

    def setup_root(self, root):
        (root / 'docs/reference/search').mkdir(parents=True)
        (root / 'docs/reference/search/tasks.json').write_text(
            json.dumps([dict(id='P10-06', title='증분 변경 수신')]), encoding='utf-8')
        (root / TODO).write_text('사용자 확인 대기 1건\n- [ ] USER-001 — 폰 확인\n', encoding='utf-8')
        return (root / TODO).read_text(encoding='utf-8')

    def test_publish_preserves_user_tasks_idempotently(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); original = self.setup_root(root)
            publish(root, self.data(), True)
            publish(root, self.data(), True)
            text = (root / TODO).read_text(encoding='utf-8')
            self.assertEqual(text.count(BEGIN), 1)
            self.assertTrue(text.endswith(original))
            self.assertIn('사용자 직접 할 일: USER-001 — 폰 확인', text)
            data = self.data(); data['status'] = 'RUN_FINISHED'
            publish(root, data, False)
            self.assertEqual((root / TODO).read_text(encoding='utf-8'), original)

    def test_observer_detects_reused_pid_without_changing_checkpoint(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); self.setup_root(root)
            folder = root / '.local/workflow/runs/sequential'; folder.mkdir(parents=True)
            (folder / 'status-monitor.json').write_text(json.dumps(dict(token='run1',pid=123,identity='old')))
            checkpoint = folder / 'checkpoint.json'
            checkpoint.write_text(json.dumps(self.data()))
            before = checkpoint.read_bytes()
            with patch('workflow_status.process_identity', return_value='new'):
                observe(root, 'run1')
            self.assertIn('🔴 비정상 종료', (root / TODO).read_text(encoding='utf-8'))
            self.assertEqual(before, checkpoint.read_bytes())

    def test_superseded_observer_does_not_overwrite(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); original = self.setup_root(root)
            folder = root / '.local/workflow/runs/sequential'; folder.mkdir(parents=True)
            (folder / 'status-monitor.json').write_text(json.dumps(dict(token='new')))
            observe(root, 'old')
            self.assertEqual((root / TODO).read_text(encoding='utf-8'), original)

    def test_current_process_has_stable_identity(self):
        identity = process_identity(os.getpid())
        self.assertIsNotNone(identity)
        self.assertEqual(identity, process_identity(os.getpid()))

    def test_completion_removes_only_matching_task_and_keeps_user_requests(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); original = self.setup_root(root)
            path = root / TODO
            path.write_text(original + 'AI 현재 작업: [P10-06] 구현 중\n- P10-06 증분 수신\n- P10-07 충돌 처리\n', encoding='utf-8')
            close_task(root, 'P10-06')
            text = path.read_text(encoding='utf-8')
            self.assertNotIn('P10-06', text)
            self.assertIn('P10-07', text)
            self.assertIn('USER-001', text)
            self.assertIn('AI 현재 작업: 없음', text)

    def test_no_trailing_whitespace_when_title_missing(self):
        for line in render(self.data(), True, '', '').splitlines():
            self.assertEqual(line, line.rstrip())

    def test_live_observer_checks_again_after_thirty_seconds(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); self.setup_root(root)
            folder = root / '.local/workflow/runs/sequential'; folder.mkdir(parents=True)
            (folder / 'status-monitor.json').write_text(json.dumps(dict(token='one',pid=123,identity='same')))
            (folder / 'checkpoint.json').write_text(json.dumps(self.data()))
            with patch('workflow_status.process_identity', side_effect=['same', None]), patch('workflow_status.time.sleep') as sleep:
                observe(root, 'one')
                sleep.assert_called_once_with(30)
            self.assertIn('🔴 비정상 종료', (root / TODO).read_text(encoding='utf-8'))


if __name__ == '__main__':
    unittest.main()
