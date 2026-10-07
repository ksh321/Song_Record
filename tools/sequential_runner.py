"""Song_Record single-controller workflow. Start explicitly; never a boot daemon.

The existing selector owns order, workflow-state owns completion, and run checkpoints
own process/turn/command recovery. No duplicate manual task database is introduced.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import time
import uuid
from pathlib import Path

from codex_transport import AppServer, ProviderError
from workflow_usage import write_report as write_usage_report
from workflow_status import publish as publish_status, start as start_status_monitor, without_panel
from select_work import select
from workflow_policy import (bind_diagnosis, compact_context, stage_model,
                             simple_diagnostic_hint, simple_diagnosis_route, simple_repair)
from workflow_runtime import (Blocked, RunLock, atomic_json, execute,
                              fingerprint, git, observation_matches, quota_available,
                              read_json, recover_json, relative_path,
                              select_model, utc, process_alive, redact)

ROOT = Path(__file__).resolve().parents[1]
HANDOFF = {'type': 'object', 'additionalProperties': False,
           'properties': {'action': {'type': 'string', 'enum': [
               'plan', 'diagnosed', 'implemented', 'reviewed', 'finalized', 'continue', 'wait']},
               'payload': {'type': 'string'}, 'summary': {'type': 'string'}},
           'required': ['action', 'payload', 'summary']}
PROTECTED = ('tools', 'AGENTS.md', 'docs/workflow-state.json', '.github')


def controller_hash(root):
    digest = hashlib.sha256()
    for name in ('tools/sequential_runner.py', 'tools/codex_transport.py', 'tools/workflow_runtime.py', 'tools/select_work.py', 'tools/workflow_policy.py', 'tools/workflow_usage.py', 'tools/workflow_status.py'):
        path = Path(root) / name
        digest.update(name.encode() + path.read_bytes())
    return digest.hexdigest()


def original_tasks(unit_id, tasks):
    exact = re.match(r'^(P\d{2}-\d{2})', unit_id)
    if exact:
        return [exact[1]]
    phase = re.fullmatch(r'(P\d{2})-PHASE', unit_id)
    if phase:
        return [t['id'] for t in tasks if t['id'].startswith(phase[1] + '-')]
    raise Blocked('UNMAPPED_ORIGINAL_TASK:' + unit_id)


def next_task(state, tasks):
    result = select(state, [t['id'] for t in tasks])
    rows = result['ready'] or result['running']
    if not rows:
        return None, result
    unit = next(u for u in state['units'] if u['id'] == rows[0]['id'])
    for task in original_tasks(unit['id'], tasks):
        if task not in unit.get('task_evidence', {}):
            return (unit, task), result
    raise Blocked('UNIT_COMPLETION_RECONCILIATION_REQUIRED')


def validate_plan(root, plan, task_id):
    if plan.get('task_id') != task_id or plan.get('risk') not in ('general', 'complex', 'sensitive'):
        raise Blocked('INVALID_TASK_PLAN')
    for key in ('acceptance', 'sources', 'scope', 'checks', 'manual'):
        if not plan.get(key):
            raise Blocked('PLAN_MISSING:' + key)
    check_ids = [c['id'] for c in plan['checks']]
    if len(check_ids) != len(set(check_ids)):
        raise Blocked('DUPLICATE_CHECK')
    for criterion in plan['acceptance']:
        if not criterion.get('criterion') or not criterion.get('basis') or not criterion.get('checks'):
            raise Blocked('ACCEPTANCE_WITHOUT_EVIDENCE')
        if any(c not in check_ids + ['manual', 'review'] for c in criterion['checks']):
            raise Blocked('UNKNOWN_ACCEPTANCE_CHECK')
    for name in plan['sources'] + plan['scope']:
        relative_path(root, name)
    if not any('reference/search/plan' in p for p in plan['sources']):
        raise Blocked('ORIGINAL_PLAN_REFERENCE_REQUIRED')
    if not isinstance(plan['manual'].get('required'), bool) or not plan['manual'].get('reason'):
        raise Blocked('MANUAL_DECISION_REQUIRED')
    if plan['manual']['required'] and not all(plan['manual'].get(k) for k in ('preparation', 'steps', 'expected', 'reply')):
        raise Blocked('CONCRETE_MANUAL_STEPS_REQUIRED')
    if len({a['id'] for a in plan['acceptance']}) != len(plan['acceptance']):
        raise Blocked('DUPLICATE_ACCEPTANCE_ID')
    # Retained fast_checks are historical; new plans use one complete check set.
    for check in plan['checks'] + plan.get('fast_checks', []):
        resolve_check(root, check)
    if plan.get('fast_checks') and len({c['id'] for c in plan['fast_checks']}) != len(plan['fast_checks']):
        raise Blocked('DUPLICATE_FAST_CHECK')
    if not plan.get('verification_file', '').startswith('docs/verification/'):
        raise Blocked('EXISTING_VERIFICATION_LOCATION_REQUIRED')
    relative_path(root, plan['verification_file'])


def resolve_check(root, check):
    kind, targets = check['kind'], check.get('targets', [])
    for target in targets:
        if not re.fullmatch(r'[\w./-]+', target) or target.startswith('-') or '..' in target.split('/'):
            raise Blocked('INVALID_CHECK_TARGET')
    flutter = shutil.which('flutter') or 'C:/flutter/bin/flutter.bat'
    if kind == 'flutter-test':
        if not targets or any(not t.startswith('test/') or not t.endswith('.dart') for t in targets):
            raise Blocked('TARGETED_FLUTTER_TESTS_REQUIRED')
        return [flutter, 'test', '--no-pub', '--reporter', 'json', *targets], root / 'apps/mobile'
    if kind == 'flutter-analyze':
        return [flutter, 'analyze', '--no-pub', *targets], root / 'apps/mobile'
    if kind == 'flutter-build-dev':
        return [flutter, 'build', 'apk', '--debug', '--flavor', 'dev', '--no-pub'], root / 'apps/mobile'
    if kind == 'api-test':
        if not targets:
            raise Blocked('TARGETED_API_TESTS_REQUIRED')
        args = [str(root / 'services/api/gradlew.bat'), 'test', '--offline', '--no-daemon', '--rerun-tasks']
        for target in targets:
            args += ['--tests', target]
        return args, root / 'services/api'
    if kind == 'workflow-quick':
        return ['pwsh', '-NoProfile', '-File', 'tools/workflow.ps1', '-Mode', 'Quick'], root
    if kind == 'sources':
        return [sys.executable, 'tools/index_sources.py', '--check'], root
    if kind == 'diff':
        return ['git', '-c', 'safe.directory=' + root.as_posix(), 'diff', '--check'], root
    raise Blocked('UNREGISTERED_COMMAND:' + kind)


def verify_report(check, result, directory, root):
    if result['status'] != 'PASS':
        return False
    if check['kind'] == 'flutter-test':
        rows = []
        for line in (directory / 'stdout.log').read_text(encoding='utf-8').splitlines():
            try:
                rows.append(json.loads(line))
            except ValueError:
                pass
        done = [r for r in rows if r.get('type') == 'done']
        tests = [r for r in rows if r.get('type') == 'testDone' and not r.get('hidden') and not r.get('skipped')]
        return bool(done and done[-1].get('success') and tests and all(t.get('result') == 'success' for t in tests))
    if check['kind'] == 'api-test':
        import xml.etree.ElementTree as ET
        from datetime import datetime
        start = datetime.fromisoformat(result['started']).timestamp()
        reports = list((root / 'services/api/build/test-results/test').glob('TEST-*.xml'))
        reports = [p for p in reports if p.stat().st_mtime >= start - 2]
        if not reports:
            return False
        suites = [ET.parse(p).getroot() for p in reports]
        return (sum(int(s.get('tests', 0)) - int(s.get('skipped', 0)) for s in suites) > 0
                and not any(int(s.get('failures', 0)) or int(s.get('errors', 0)) for s in suites))
    if check['kind'] == 'flutter-build-dev':
        path = root / 'apps/mobile/build/app/outputs/flutter-apk/app-dev-debug.apk'
        if not path.is_file():
            return False
        result['artifact'] = {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    return True


class Runner:
    def __init__(self, root=ROOT):
        self.root = Path(root).resolve()
        self.directory = self.root / '.local/workflow/runs/sequential'
        self.path = self.directory / 'checkpoint.json'
        self.stop_path = self.directory / 'stop.json'
        self.state_path = self.root / 'docs/workflow-state.json'
        self.tasks = read_json(self.root / 'docs/reference/search/tasks.json')
        self.data = {}
        self.client = None
        self.status_display = False

    def save(self):
        self.data['updated'] = utc()
        atomic_json(self.path, self.data)
        if getattr(self, 'status_display', False):
            try:
                publish_status(self.root, self.data, True)
            except (OSError, ValueError):
                self.event('status_display_unavailable', {'reason': 'LOCAL_DISPLAY_WRITE_FAILED'})

    def event(self, kind, data):
        self.directory.mkdir(parents=True, exist_ok=True)
        with (self.directory / 'events.jsonl').open('a', encoding='utf-8') as stream:
            stream.write(json.dumps({'utc': utc(), 'kind': kind, 'data': data}, ensure_ascii=False) + '\n')
            stream.flush()
            os.fsync(stream.fileno())

    def stopped(self):
        return self.stop_path.exists()

    def load(self):
        if self.path.exists():
            self.data, recovered = recover_json(self.path)
            if recovered:
                self.data['status'] = 'BLOCKED'
                self.data['reason'] = 'RECOVERED_CHECKPOINT_REQUIRES_RECONCILIATION'
                self.save()
            if self.data.get('root') != str(self.root):
                raise Blocked('CHECKPOINT_WORKSPACE_MISMATCH')

    def source(self):
        record = self.data.get('plan', {}).get('verification_file')
        return fingerprint(self.root, [record] if record else [])

    def state(self):
        return read_json(self.state_path)

    def plan_only(self):
        state = self.state()
        item, selection = next_task(state, self.tasks)
        return {'selection': selection, 'next': item[1] if item else None,
                'unit': item[0]['id'] if item else None,
                'enabled': state.get('runner', {}).get('enabled', False),
                'head': git(self.root, 'rev-parse', 'HEAD')}

    def guards(self):
        state = self.state()
        if state.get('execution_mode') != 'strict_sequential':
            raise Blocked('STRICT_SEQUENTIAL_REQUIRED')
        if self.data and self.data['branch'] != git(self.root, 'branch', '--show-current'):
            raise Blocked('BRANCH_CHANGED')
        if self.data and self.data.get('stage') != 'COMPLETE':
            current, _ = next_task(state, self.tasks)
            if current is None:
                raise Blocked('CURRENT_SEQUENCE_PREREQUISITE_BLOCKED')
            if current and (current[0]['id'], current[1]) != (self.data['unit_id'], self.data['task_id']):
                raise Blocked('SEQUENCE_CHANGED_DURING_TASK')
            order = hashlib.sha256(json.dumps([state['sequence_start'], state['priority_order']]).encode()).hexdigest()
            if self.data.get('order_hash', order) != order:
                raise Blocked('ORDER_POLICY_CHANGED_RECONCILE_FIRST')
        return state

    def pause(self, status, reason):
        self.data.update(status=status, reason=reason)
        self.save()
        self.event('pause', {'status': status, 'reason': reason})

    def notify_completion(self):
        """Notify once after durable completion; uncertain delivery is never retried."""
        if self.data.get('status') != 'RUN_FINISHED' or self.data.get('stage') != 'COMPLETE':
            raise Blocked('COMPLETION_NOTIFICATION_REQUIRES_FINISHED_RUN')
        if self.data.get('reason') not in ('APPROVED_END_REACHED', 'NO_REMAINING_WORK_IN_APPROVED_RANGE'):
            raise Blocked('COMPLETION_NOTIFICATION_REQUIRES_APPROVED_END')
        if self.data.get('completion_notification'):
            return
        key = hashlib.sha256(json.dumps([self.data.get('created'), self.data.get('end_task'),
                                        self.data.get('target_commit')]).encode()).hexdigest()
        notice = {'key': key, 'status': 'UNKNOWN', 'task_id': self.data['task_id'], 'created': utc()}
        self.data['completion_notification'] = notice
        self.save()
        try:
            result = execute(['pwsh', '-NoProfile', '-File', 'tools/phone-notify.ps1',
                              '-Mode', 'Send', '-TaskId', self.data['task_id'],
                              '-Kind', 'Completion', '-CompletionKey', key],
                             self.root, self.directory / ('completion-' + key), 90)
            notice['status'] = 'SERVER_ACCEPTED' if result['exit_code'] == 0 else 'UNCONFIRMED'
        except Exception:
            pass
        self.save()
        self.event('completion_notification', notice)

    def record_request(self, reason):
        """Use the existing USER record and sender, never send arbitrary provider output."""
        if reason == 'PROVIDER_APPROVAL_REQUIRED':
            # A provider sandbox approval is an AI handoff, not evidence that
            # a human must act. The supervising Codex turn inspects the saved
            # command and uses its normal authorization tools; never auto-accept
            # arbitrary provider commands or ask the user to diagnose them.
            self.pause('WAITING_AI', 'PROVIDER_APPROVAL_TRIAGE_REQUIRED')
            self.data['ai_handoff'] = {'reason': reason, 'owner': 'AI',
                                       'status': 'NEEDS_HOST_TRIAGE', 'created': utc()}
            self.save()
            self.event('ai_handoff', self.data['ai_handoff'])
            return
        records_path = self.root / 'docs/verification/user-action-records.md'
        todo_path = self.root / '내가할일.md'
        records, todo = records_path.read_text(encoding='utf-8'), todo_path.read_text(encoding='utf-8')
        existing = self.data.get('request')
        if existing and existing.get('reason') == reason and not existing.get('resolved'):
            return
        number = max([int(n) for n in re.findall(r'USER-(\d{3})', records + todo)] + [0]) + 1
        item = f'USER-{number:03}'
        task = self.data['task_id']
        revision = 1
        manual = self.data.get('plan', {}).get('manual', {})
        details = self.data.get('next_action') or {}
        guidance = manual if reason == 'MANUAL_TEST_REQUIRED' else details
        required = ('preparation', 'steps', 'expected', 'reply')
        if not all(isinstance(guidance.get(key), str) and guidance[key].strip() for key in required):
            self.data['notification_pending'] = {'reason': reason, 'needs': list(required),
                                                 'owner': 'AI', 'status': 'NEEDS_ACTIONABLE_GUIDANCE'}
            labels = {
                'SUBSCRIPTION_QUOTA': '구독 사용량 한도',
                'PROVIDER_APPROVAL_REQUIRED': '명령 실행 또는 접근 승인',
                'REPAIR_BUDGET_EXHAUSTED': '같은 문제의 수정 한도 소진',
                'CI_UNCONFIRMED': '필수 CI 결과 미확인',
                'EXECUTION_BLOCKED': '실행 환경 또는 인증 오류',
                'PROVIDER_TURN_FAILED': '개발 모델 호출 실패',
            }
            label = labels.get(reason, '자동 처리가 불가능한 문제')
            guidance = {
                'preparation': f'{task} 작업이 {label} 때문에 정지했습니다. 현재 Codex 대화를 열어 주세요.',
                'steps': f'현재 대화에 "{item} 중단 원인과 해결 절차 알려줘"라고 보내 주세요. '
                         'AI가 저장된 오류를 확인해 실제 필요한 로그인 화면·승인 버튼 또는 판단 사항을 안내합니다. '
                         '아직 특정 조작 방법은 확인되지 않았으므로 임의 설정 변경은 필요 없습니다.',
                'expected': '구체적 해결 절차 또는 필요한 판단을 확인하고, 해결 후 같은 작업의 조건을 다시 검증합니다.',
                'reply': f'{item} 중단 원인과 해결 절차 알려줘',
            }
            self.event('notification_fallback_guidance', {'reason': reason, 'task_id': task})
        instructions = guidance['steps']
        if not isinstance(instructions, str):
            instructions = json.dumps(instructions, ensure_ascii=False)
        instructions = instructions.replace('\n', ' / ')
        build = self.data.get('validated_fingerprint', 'not-built')
        request = {'item_id': item, 'revision': revision, 'task_id': task, 'reason': reason,
                   'build': build, 'created': utc(), 'resolved': False}
        self.data['request'] = request
        self.save()
        records += (f'\n### {item} — {task} 실행기 확인\n\n- 상태: **확인 필요**\n'
                    f'- 작업 ID: {task}\n- 요청 판본: {revision}\n- 알림 종류: Intervention\n'
                    f'- 알림 행동: Details\n- 요청 시각: {utc()}\n- 대상: {build}\n'
                    f'- 이유: {reason}\n- 준비·결과: {instructions}\n')
        records_path.write_text(records, encoding='utf-8')
        todo = todo.replace('현재 직접 할 일 없음', '').rstrip()
        todo += (f'\n\n- [ ] {item} — {task}: 실행기 확인\n'
                 f"  - 준비: {guidance['preparation']}\n"
                 f'  - 순서: {instructions}\n'
                 f"  - 정상 결과: {guidance['expected']}\n"
                 f"  - AI에게 알려줄 결과: {item} 판본 {revision}, {guidance['reply']}\n")
        count = len(re.findall(r'^- \[ \] USER-\d{3}', todo, re.M))
        todo = re.sub(r'사용자 확인 대기 \d+건', f'사용자 확인 대기 {count}건', todo)
        todo_path.write_text(todo, encoding='utf-8')
        attempt = self.directory / f'notify-{item}-{revision}.json'
        atomic_json(attempt, {'status': 'UNKNOWN', 'request': request})
        try:
            result = execute(['pwsh', '-NoProfile', '-File', 'tools/phone-notify.ps1',
                              '-Mode', 'Send', '-TaskId', task, '-Kind', 'Intervention',
                              '-ItemId', item, '-Revision', str(revision), '-Action', 'Details'],
                             self.root, self.directory / f'notify-{item}', 60)
            atomic_json(attempt, {'status': 'SERVER_ACCEPTED' if result['exit_code'] == 0 else 'UNCONFIRMED',
                                  'request': request})
        except Exception:
            pass  # UNKNOWN is never automatically resent. Chat/local state remains the fallback.

    def checkpoint(self, phase, data):
        if phase == 'intent':
            self.data['call'] = {'stage': self.data['stage']}
        call = self.data.setdefault('call', {})
        call.update(data)
        call['phase'] = phase
        self.save()
        self.event('model_' + phase, dict(data, task_id=self.data.get('task_id'),
                   stage=call.get('stage', self.data.get('stage')), thread_id=self.data.get('thread_id'),
                   rollout_path=getattr(self.client, 'thread_path', None)))
        if phase == 'completed':
            try:
                write_usage_report(self.directory)
            except Exception:
                # Optional accounting must not turn an already executed call into a retry.
                self.event('usage_report_unavailable', {'reason': 'LOCAL_REPORT_WRITE_OR_READ_FAILED'})

    def ai(self, instruction, expected, read_only=False):
        caps = self.client.capabilities()
        if not quota_available(caps):
            self.pause('PAUSED_QUOTA', 'SUBSCRIPTION_QUOTA')
            self.record_request('SUBSCRIPTION_QUOTA')
            return None
        selected = stage_model(self.data, caps['models'], self.source())
        escalate = selected == select_model(caps['models'], escalate=True)
        if escalate:
            proof = self.root / '.local/workflow/model-activation.json'
            activation = read_json(proof) if proof.exists() else {}
            if not any(observation_matches(o, selected) for o in activation.get('observations', [])):
                raise Blocked('MAXIMUM_CONNECTION_PROOF_REQUIRED_BEFORE_REPAIR')
        self.data['selected'] = selected
        opened = self.client.open_thread(self.root, **selected,
                                         thread_id=self.data.get('thread_id'), read_only=read_only)
        self.data['thread_id'] = opened['thread']['id']
        self.save()
        atomic_json(self.directory / 'task-context.json', {'plan': self.data.get('plan'), 'source_refs': self.data.get('source_refs')})
        prompt = ('현재 P번호 ' + self.data['task_id'] + ', 기존 단위 ' + self.data['unit_id'] + '. '
                  '단일 실행기의 현재 단계만 수행한다. 하위 에이전트·Ultra·유료 API·리셋권 금지. '
                  '직접 Git 쓰기·알림·CI 조회·실행기 파일 변경 금지. 관련 파일은 직접 읽고 편집한다. '
                  '완료 이력·사용자 변경·기존 ID를 보존한다.\n' + instruction + '\n'
                  '출력은 action,payload(JSON 문자열),summary. 기대 action=' + expected + '. '
                  '작업 중이면 continue와 구체적 다음 행동. AI가 해결할 일반 명령 오류는 사용자에게 넘기지 않는다. '
                  '사람 조치가 정말 필요하면 wait payload에 preparation,steps,expected,reply를 구체적인 한국어 문자열로 모두 제공한다. '
                  'steps는 어느 기기/앱/화면에서 무엇을 누를지 순서대로, expected는 성공 모습, reply는 전달할 결과를 적는다.\n'
                  '같은 스레드에서 이미 확인한 문서를 무조건 다시 읽지 않는다. 현재 변경·오류·필요한 원문 절만 읽는다. '
                  '전달된 현재 단계 근거를 우선 사용한다. 재개 위치는 checkpoint.json, 계획은 task-context.json에서 필요한 항목만 확인한다. '
                  '문서는 rg -n으로 해당 P번호·요구사항을 찾고 '
                  '관련 절·함수와 연결된 계약만 읽는다. 전체 파일 출력 대신 한 번에 120줄 이내를 읽고 근거가 부족할 때 확대한다. '
                  '성공 로그는 상태·개수·경로로 확인하고 실패 로그는 오류 주변부터 읽는다. 중요한 지적·완료 조건을 생략하지 않는다. '
                  '원문 완료 기준과 검토 근거는 task-context.json 및 연결된 원문에서 확인한다. '
                  'AI가 문서의 검사 수치·SHA를 재작성하지 않는다. 제어기가 사실 기록을 만든다.\n'
                  + json.dumps(compact_context(self.data), ensure_ascii=False))
        self.event('prompt_context', {'stage': self.data['stage'], 'characters': len(prompt)})
        protected_names = ['AGENTS.md', 'docs/workflow-state.json']
        protected_names += git(self.root, 'ls-files', 'tools', '.github').splitlines()
        protected = {p: git(self.root, 'hash-object', p) for p in protected_names}
        head = git(self.root, 'rev-parse', 'HEAD')
        result = self.data.pop('recovered_turn_result', None)
        if result is None:
            result = self.client.turn(self.data['thread_id'], prompt, **selected, schema=HANDOFF,
                                      checkpoint=self.checkpoint, stop=self.stopped, read_only=read_only)
        if any(git(self.root, 'hash-object', p) != h for p, h in protected.items()) or git(self.root, 'rev-parse', 'HEAD') != head:
            raise Blocked('AI_MODIFIED_CONTROLLER_OR_GIT_STATE')
        if self.stopped():
            self.pause('PAUSED_USER', 'USER_STOP')
            return None
        if result['requests']:
            self.record_request('PROVIDER_APPROVAL_REQUIRED')
            return None
        if result['status'] != 'completed':
            # No speculative retry of provider errors and no code retry count increase.
            updated_caps = self.client.capabilities()
            quota = not quota_available(updated_caps)
            self.pause('PAUSED_QUOTA' if quota else 'BLOCKED', 'SUBSCRIPTION_QUOTA' if quota else 'PROVIDER_TURN_' + result['status'].upper())
            self.record_request('SUBSCRIPTION_QUOTA' if quota else 'PROVIDER_TURN_FAILED')
            return None
        observed = result['observation']
        self.data['maximum_observed'] = (selected == select_model(caps['models'], escalate=True)
                                          and observation_matches(observed, selected))
        if escalate and not self.data['maximum_observed']:
            raise Blocked('ESCALATION_APPLICATION_UNVERIFIED')
        response = json.loads(result['text'])
        payload = json.loads(response['payload'])
        if response['action'] == 'wait':
            self.data['call']['phase'] = 'consumed'
            self.data['next_action'] = payload
            self.pause('WAITING_USER', 'AI_IDENTIFIED_REQUIRED_ACTION')
            self.record_request('AI_IDENTIFIED_REQUIRED_ACTION')
            return None
        if response['action'] == 'continue':
            self.data['call']['phase'] = 'consumed'
            if payload.get('reclassify'):
                if self.data['stage'] == 'PLAN':
                    self.data['plan_requires_core'] = True
                elif self.data['stage'] == 'DIAGNOSE':
                    self.data['requires_core_diagnosis'] = True
                else:
                    self.data.setdefault('diagnosis', {})['kind'] = 'core'
            signature = hashlib.sha256((self.source() + response['payload']).encode()).hexdigest()
            if signature == self.data.get('last_continue'):
                # Exact duplicate handoff is invalid, not an invented numeric retry budget.
                raise Blocked('IDENTICAL_HANDOFF_WITHOUT_PROGRESS')
            self.data.update(last_continue=signature, next_action=payload)
            self.save()
            return None
        if response['action'] != expected:
            raise Blocked('UNEXPECTED_STAGE_RESPONSE')
        if expected == 'reviewed':
            payload['summary'] = response.get('summary', '')
        self.data.pop('last_continue', None)
        return payload

    def queue_failure(self, event_id, details):
        excerpt = ''
        log_dir = details.get('result', {}).get('log_directory')
        if log_dir:
            directory = relative_path(self.root, log_dir)
            for name in ('stderr.log', 'stdout.log'):
                path = directory / name
                if path.is_file():
                    # Bounded initial clue, with the full local evidence retained.
                    with path.open('rb') as stream:
                        stream.seek(max(0, path.stat().st_size - 4096))
                        excerpt += name + ':\n' + stream.read(4096).decode('utf-8', errors='replace') + '\n'
        failure = {'id': event_id, 'details': details, 'excerpt': redact(excerpt)[-6000:]}
        atomic_json(self.directory / 'failure.json', failure)
        self.data.update(stage='DIAGNOSE', status='READY',
                         pending_failure=failure, requires_core_diagnosis=False, diagnosis_route=None)
        self.save()

    def review_valid(self):
        review = self.data.get('review', {})
        required = {a['id'] for a in self.data['plan']['acceptance']}
        return (review.get('approved') is True and not review.get('findings')
                and set(review.get('acceptance_reviewed', [])) == required
                and self.data.get('reviewed_fingerprint') == self.source())

    def completion_gates(self):
        if not self.checks_valid() or not self.review_valid():
            raise Blocked('FINAL_CHECKS_INVALID')
        if self.data['plan']['manual']['required'] and not self.data.get('manual_pass'):
            raise Blocked('FINAL_MANUAL_MISSING')
        ci = self.data.get('ci', {})
        if (ci.get('overall') not in ('PASS', 'NOT_REQUIRED')
                or ci.get('commit') != self.data.get('target_commit')
                or ci.get('base_commit') != self.data.get('push_base_commit')):
            raise Blocked('FINAL_CI_MISSING_OR_MISMATCHED')
        if git(self.root, 'rev-parse', 'HEAD') != self.data.get('target_commit'):
            raise Blocked('HEAD_CHANGED_BEFORE_COMPLETION')

    def write_final_facts(self):
        """Write verified facts once without a generative round trip."""
        self.completion_gates()
        facts = {'task_id': self.data['task_id'], 'commit': self.data['target_commit'],
                 'base_commit': self.data['push_base_commit'], 'ci': self.data['ci'],
                 'checks': [], 'manual_required': self.data['plan']['manual']['required'],
                 'manual_pass': self.data.get('manual_pass'),
                 'review_summary': self.data['review'].get('summary', ''),
                 'acceptance_reviewed': self.data['review']['acceptance_reviewed']}
        for row in self.data['results']:
            item = {k: row[k] for k in ('id', 'status', 'exit_code', 'log_directory') if k in row}
            if 'test' in row.get('argv', []) and '--reporter' in row['argv']:
                events = []
                for line in (self.root / row['log_directory'] / 'stdout.log').read_text(encoding='utf-8').splitlines():
                    try:
                        events.append(json.loads(line))
                    except ValueError:
                        pass
                item['passed_tests'] = sum(e.get('type') == 'testDone' and not e.get('hidden')
                    and not e.get('skipped') and e.get('result') == 'success' for e in events)
            facts['checks'].append(item)
        atomic_json(self.directory / 'final-facts.json', facts)
        marker = f"<!-- runner-facts:{facts['task_id']}:{facts['commit']} -->"
        body = (f"\n{marker}\n### {facts['task_id']} 실행기 검증 사실\n\n"
                f"- 대상 커밋: {facts['commit']}\n- 푸시 기준: {facts['base_commit']}\n"
                f"- 필수 CI 판정: {facts['ci']['overall']}\n"
                + ''.join(f"- {c['id']}: {c['status']}" +
                          (f" / 테스트 {c['passed_tests']}개" if 'passed_tests' in c else '') + '\n'
                          for c in facts['checks']) +
                '- 검토 완료 기준: ' + ', '.join(facts['acceptance_reviewed']) + '\n'
                '- 현재 모델 검토: ' + (facts['review_summary'] or '등록된 모든 완료 기준 검토 승인') + '\n'
                '- 원시 근거: .local/workflow/runs/sequential/final-facts.json\n')
        path = relative_path(self.root, self.data['plan']['verification_file'])
        text = path.read_text(encoding='utf-8') if path.exists() else ''
        if marker not in text:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text.rstrip() + '\n' + body, encoding='utf-8')
        progress = self.root / 'docs/progress.md'
        text = progress.read_text(encoding='utf-8')
        if marker not in text:
            progress.write_text(text.rstrip() + '\n\n' + marker + '\n' +
                f"{facts['task_id']} 검증·검토·필수 CI 확인: {facts['commit']}. " +
                f"근거: {self.data['plan']['verification_file']}. 최종 판정은 제어기 관문에서 확인한다.\n", encoding='utf-8')

    def local_checks(self):
        """Run the retained plan without AI, Git writes, or advancing its checkpoint."""
        with RunLock(self.directory / 'runner.lock'):
            data = read_json(self.path)
            if data.get('root') != str(self.root):
                raise Blocked('CHECKPOINT_WORKSPACE_MISMATCH')
            validate_plan(self.root, data.get('plan', {}), data.get('task_id'))
            check = Runner(self.root)
            check.directory = self.root / '.local/workflow/runs' / ('checks-' + str(uuid.uuid4()))
            check.path = check.directory / 'checkpoint.json'
            check.data = {'root': str(self.root), 'task_id': data['task_id'],
                          'plan': data['plan'], 'stage': 'VALIDATE', 'status': 'READY'}
            check.validate()
            return {'status': 'PASS' if check.checks_valid() else 'FAIL',
                    'task_id': data['task_id'], 'report': str(check.path)}

    def validate(self):
        current = self.source()
        previous = self.data.get('results', [])
        self.data['results'] = []
        self.save()
        checks = self.data['plan']['checks']
        for check in checks:
            execution_id = str(uuid.uuid4())
            directory = self.directory / 'commands' / execution_id
            argv, cwd = resolve_check(self.root, check)
            self.data['command'] = {'id': execution_id, 'check': check, 'status': 'INTENT'}
            self.save()
            cached = next((r for r in previous if r.get('id') == check['id']
                           and r.get('fingerprint') == current and r.get('argv') == argv
                           and r.get('status') == 'PASS'), None)
            if cached:
                directory = self.root / cached['log_directory']
                execution_id = cached['execution_id']
                result = dict(cached, reused_result=True)
            else:
                result = execute(argv, cwd, directory, min(int(check.get('timeout', 1800)), 7200), self.stopped)
            result.update(id=check['id'], fingerprint=current, execution_id=execution_id,
                          log_directory=str(directory.relative_to(self.root)))
            if not verify_report(check, result, directory, self.root):
                result['status'] = 'FAIL' if result['status'] == 'PASS' else result['status']
            self.data['results'].append(result)
            self.data['command']['status'] = result['status']
            self.save()
            if result['status'] != 'PASS':
                if self.stopped():
                    self.pause('PAUSED_USER', 'USER_STOP')
                    return
                self.queue_failure(execution_id, {'check': check, 'result': result})
                return
        if self.source() != current:
            raise Blocked('SOURCE_CHANGED_DURING_VALIDATION')
        self.data.update(stage='REVIEW', validated_fingerprint=current)
        self.save()

    def checks_valid(self):
        return (self.data.get('validated_fingerprint') == self.source()
                and self.data.get('results')
                and all(r['status'] == 'PASS' for r in self.data['results'])
                and {r['id'] for r in self.data['results']} == {c['id'] for c in self.data['plan']['checks']})

    def commit(self):
        if not self.checks_valid() or not self.review_valid():
            raise Blocked('GIT_GATE_NOT_VALIDATED')
        if self.data['plan']['manual']['required'] and not self.data.get('manual_pass'):
            raise Blocked('MANUAL_GATE_REQUIRED')
        paths = git(self.root, '-c', 'core.quotepath=false', 'diff', '--name-only', 'HEAD').splitlines()
        paths += git(self.root, 'ls-files', '--others', '--exclude-standard').splitlines()
        allowed = self.data['plan']['scope'] + [self.data['plan']['verification_file'], 'docs/progress.md',
                                              'docs/workflow-state.json', '내가할일.md', 'docs/verification/user-action-records.md']
        for name, expected_hash in self.data.get('pending_records', {}).items():
            path = relative_path(self.root, name)
            content = path.read_bytes() if path.is_file() else b''
            if name == '내가할일.md' and path.is_file():
                content = without_panel(content.decode('utf-8')).encode('utf-8')
            if not path.is_file() or hashlib.sha256(content).hexdigest() != expected_hash:
                raise Blocked('CARRIED_EVIDENCE_CHANGED:' + name)
            allowed.append(name)
        for path in paths:
            if not any(path == a or path.startswith(a.rstrip('/') + '/') for a in allowed):
                raise Blocked('UNOWNED_CHANGE:' + path)
            if path.startswith(('.local/', '.env')) or path.endswith(('.jks', '.keystore')):
                raise Blocked('PRIVATE_FILE_IN_COMMIT')
        if git(self.root, 'diff', '--cached', '--name-only'):
            raise Blocked('UNEXPECTED_STAGED_CHANGES')
        remote = git(self.root, 'ls-remote', 'origin', 'refs/heads/' + self.data['branch']).split()[0]
        self.data['push_base_commit'] = remote
        self.data['git_intent'] = {'operation': 'commit', 'parent': git(self.root, 'rev-parse', 'HEAD'), 'paths': paths}
        self.save()
        if paths:
            git(self.root, 'add', '--', *paths)
            git(self.root, 'diff', '--cached', '--check')
            message = self.directory / 'commit-message.txt'
            message.write_text(f"[{self.data['unit_id']}] feat: {self.data['plan']['title']}\n\n"
                               f"작업: {self.data['task_id']}\n변경 이유와 내용: {self.data['plan']['objective']}\n"
                               '검증: 등록한 로컬 검사·현재 모델 코드 검토 완료.\n'
                               '남은 일: 현재 push 범위에 필요한 원격 CI와 최종 판정.\n', encoding='utf-8')
            git(self.root, 'commit', '--file', str(message))
        target = git(self.root, 'rev-parse', 'HEAD')
        if not self.checks_valid():
            raise Blocked('COMMIT_HOOK_CHANGED_VALIDATED_SOURCE')
        self.data.update(target_commit=target, stage='PUSH', git_intent={'operation': 'push', 'target': target})
        self.data['pending_records'] = {}
        self.save()

    def push(self):
        target = self.data['target_commit']
        if git(self.root, 'rev-parse', 'HEAD') != target:
            raise Blocked('HEAD_CHANGED_BEFORE_PUSH')
        remote = git(self.root, 'ls-remote', 'origin', 'refs/heads/' + self.data['branch']).split()[0]
        if remote != target:
            if remote != self.data['push_base_commit']:
                raise Blocked('REMOTE_CHANGED_PRESERVE_AND_INTEGRATE')
            git(self.root, 'push', 'origin', f"{target}:refs/heads/{self.data['branch']}")
            if git(self.root, 'ls-remote', 'origin', 'refs/heads/' + self.data['branch']).split()[0] != target:
                raise Blocked('REMOTE_PUSH_UNCONFIRMED')
        self.data.update(stage='CI', status='WAITING_EXTERNAL', ci_started=time.time(), ci_errors=0)
        self.save()

    def ci_once(self):
        target, base = self.data['target_commit'], self.data['push_base_commit']
        if base == target:
            # No new push; do not erase older mandatory checks with an empty range.
            raise Blocked('EXISTING_COMMIT_CI_EVIDENCE_REQUIRED')
        directory = self.directory / 'commands' / str(uuid.uuid4())
        query_started = time.time()
        result = execute(['pwsh', '-NoProfile', '-File', 'tools/github-check.ps1',
                          '-Commit', target, '-BaseCommit', base, '-Account', 'ksh321'],
                         self.root, directory, 180, self.stopped)
        report_path = self.root / '.local/workflow' / ('ci-' + target + '.json')
        report = read_json(report_path) if report_path.exists() else {}
        self.data['ci'] = report
        if not report_path.exists() or report_path.stat().st_mtime < query_started or report.get('commit') != target:
            self.data['ci_errors'] += 1
        elif report.get('base_commit') != base:
            self.data['ci_errors'] += 1
        elif report.get('overall') in ('PASS', 'NOT_REQUIRED') and result['exit_code'] == 0:
            self.data.update(stage='FINALIZE', status='READY', ci_errors=0)
        elif report.get('overall') == 'FAIL':
            self.queue_failure('ci:' + target, {'ci_report': str(report_path)})
        elif result['exit_code'] not in (0, 2):
            self.data['ci_errors'] += 1
        else:
            self.data['ci_errors'] = 0
        if self.data['ci_errors'] >= 3 or time.time()-self.data['ci_started'] >= 43200:
            self.pause('BLOCKED', 'CI_UNCONFIRMED')
            self.record_request('CI_UNCONFIRMED')
        self.save()

    def complete(self, result):
        self.completion_gates()
        required = {a['id'] for a in self.data['plan']['acceptance']}
        if set(result.get('acceptance_passed', [])) != required:
            raise Blocked('FINAL_ACCEPTANCE_MISSING')
        evidence = relative_path(self.root, self.data['plan']['verification_file'])
        if not evidence.is_file() or self.data['target_commit'] not in evidence.read_text(encoding='utf-8'):
            raise Blocked('FINAL_DURABLE_EVIDENCE_MISSING')
        state = self.guards()
        unit = next(u for u in state['units'] if u['id'] == self.data['unit_id'])
        unit.setdefault('task_evidence', {})[self.data['task_id']] = {
            'commit': self.data['target_commit'], 'path': self.data['plan']['verification_file'], 'utc': utc()}
        if set(original_tasks(unit['id'], self.tasks)) <= set(unit['task_evidence']):
            unit.update(state='done', evidence=self.data['plan']['verification_file'])
        atomic_json(self.state_path, state, backup_path=self.directory / 'workflow-state.previous.json')
        self.data.update(stage='COMPLETE', status='COMPLETE')
        self.data.setdefault('pending_records', {})[self.data['plan']['verification_file']] = hashlib.sha256(evidence.read_bytes()).hexdigest()
        self.save()

    def step(self):
        stage = self.data['stage']
        if stage == 'PLAN':
            instruction = (
                'AGENTS.md의 필수 규칙과 최신 감사 절을 준수한다. progress/development-workflow/verification/requirements/decisions 및 '
                'reference/search/plan.txt와 design.txt에서 현재 P번호·요구사항을 검색하여 관련 절과 연결된 계약·코드만 읽는다. '
                '문서 전체를 일괄 출력하지 않는다. 기존 성과를 보존하여 남은 전체 범위를 확정한다. '
                'Sol 단계에서는 기존 승인 문서의 사실·남은 일·검사를 정리하며 새 동작 정책을 판단하지 않는다. '
                '계약 충돌·새 동작 판단·불명확함이 있으면 편집 없이 continue payload에 reclassify=true와 이유를 남긴다. '
                'plan_requires_core=true이면 Astra로 해당 판단을 수행한다. '
                '설명과 payload는 한국어. 제품 파일 편집은 아직 하지 않는다. '
                'payload keys: task_id,title,objective,risk(general/complex/sensitive),'
                'acceptance(array of {id,criterion,basis,checks:[check_id or review or manual]}),'
                'sources(repo paths),scope(repo paths),verification_file(existing file),source_only(boolean:기존 근거의 사실 정리만 했는지),'
                'checks(array {id,kind,targets,timeout}),manual({required:boolean,reason:string,preparation,steps,expected,reply}). '
                'check kinds: flutter-test,flutter-analyze,flutter-build-dev,api-test,workflow-quick,sources,diff. '
                'checks에 같은 P번호의 연결된 구현 완료 후 필요한 로컬 검사를 빠짐없이 한 번씩 선언한다. '
                'scope는 필요한 제품·테스트로 한정한다. 동기화·인증·DB 핵심은 sensitive로 지정한다.')
            result = self.ai(instruction, 'plan', read_only=True)
            if result:
                if not self.data.get('plan_requires_core') and result.get('source_only') is not True:
                    self.data.update(plan_requires_core=True, next_action={'reason': 'Plan requires core judgment or explicit source-only evidence.'})
                    self.save()
                    return
                validate_plan(self.root, result, self.data['task_id'])
                if self.data['task_id'].startswith(('P06-', 'P10-')) or any(
                        re.search(r'auth|sync|database|migration', path, re.I) for path in result['scope']):
                    result['risk'] = 'sensitive'
                self.data.update(plan=result, stage='IMPLEMENT')
                self.data['source_refs'] = {name: hashlib.sha256(relative_path(self.root, name).read_bytes()).hexdigest()
                                            for name in result['sources'] if relative_path(self.root, name).is_file()}
                self.save()
        elif stage == 'DIAGNOSE':
            source = self.source()
            self.data['diagnosis_route'] = simple_diagnostic_hint(self.root, self.data, source)
            light = simple_diagnosis_route(self.data, source)
            result = self.ai(
                '읽기 전용 원인 분류. failure의 실제 로그/코드를 읽고 전달된 incidents의 모든 원인 ID와 비교한다. '
                'comparisons에는 현재 P번호의 전달된 ID만 정확히 포함한다. 전체 근거는 incident_evidence에서 확인한다. '
                '오류 문구나 테스트 이름만으로 다른 문제로 만들지 않는다. 원인이 같으면 기존 ID를 재사용한다. '
                'payload={incident_id:existing_id or new,cause,evidence,fix,identity_basis,'
                'comparisons:[{id,relation:same/different,evidence}],kind:syntax_import/format/fixture_contract/core/environment,'
                'cause_clear:boolean,behavior_unchanged:boolean,checkable:boolean,contract_basis,files:[repo path]}. '
                '단순 수정은 원인·방법 명확/행동 계약 불변/검증 가능 세 조건과 기존 계약 출처가 모두 있어야 한다. '
                'verified_import_cleanup으로 Sol에 배정됐어도 실제 코드에서 세 조건을 확인한다. '
                '테스트 기대값·동작 변경·불명확함이 있으면 편집 없이 continue payload에 reclassify=true와 이유를 반환해 Astra로 전환한다. '
                '테스트 기대값을 통과 목적으로 바꾸지 않는다. 인증·동기화·DB 의미 변경 또는 불명확하면 core. '
                '실제 사람이 해야 하는 환경 조치는 wait와 구체적 절차; AI가 해결 가능한 환경은 environment.',
                'diagnosed', read_only=True)
            if result:
                if light and (not simple_repair(result) or result.get('kind') != 'syntax_import'
                              or not set(result.get('files', [])) <= set(self.data['diagnosis_route']['files'])
                              or self.source() != source):
                    self.data.update(requires_core_diagnosis=True, rejected_light_diagnosis=result)
                    self.save()
                    return
                for name in result.get('files', []):
                    relative_path(self.root, name)
                    if name not in self.data['plan']['scope']:
                        raise Blocked('DIAGNOSIS_OUTSIDE_APPROVED_SCOPE')
                action = bind_diagnosis(self.data, result, self.source())
                self.data['stage'] = 'IMPLEMENT'
                if action == 'BLOCKED':
                    self.pause('BLOCKED', 'REPAIR_BUDGET_EXHAUSTED')
                    self.record_request('REPAIR_BUDGET_EXHAUSTED')
                elif result.get('kind') == 'environment':
                    self.pause('WAITING_AI', 'ENVIRONMENT_REQUIRES_HOST_TRIAGE')
                    self.data['ai_handoff'] = {'owner': 'AI', 'status': 'NEEDS_HOST_TRIAGE',
                                              'reason': 'Inspect diagnosis and perform authorized environment recovery first.'}
                self.save()
        elif stage == 'IMPLEMENT':
            before = self.source()
            issue_id = self.data.get('active_incident')
            result = self.ai('같은 P번호의 승인된 연결 구현 전체를 이번 작업에서 완료한 뒤 인계한다. '
                             '파일이나 작은 구현 단위마다 인계하지 않는다. 완료 후 checks 전체를 제어기가 한 단계에서 실행한다. '
                             '구체적인 오류 확인에 필요한 최소 검사는 직접 할 수 있으나 최종 검사와 불필요하게 중복하지 않는다. '
                             '진행 중 문서 재작성·포맷 명령은 생략한다. 의미 변경이 필요해 단순 분류가 틀렸다면 편집 전 '
                             'continue payload에 reclassify=true와 이유를 적어 핵심 분류로 돌린다. '
                             '단순 수정은 diagnosis.files와 fix만 따른다. 환경 문제도 가능한 안전한 조치를 직접 처리한다. '
                             'payload={changed_files:[...],reason:string,complete:boolean}. '
                             '불가피하게 구현이 남으면 complete=false와 남은 범위·이유를 기록한다. '
                             'false이면 검사 없이 같은 P번호 구현을 계속하며 true이면 전체 지정 검증과 현재 모델 검토로 진행한다.',
                             'implemented')
            if result:
                if not isinstance(result.get('complete', True), bool):
                    raise Blocked('IMPLEMENTATION_COMPLETE_MUST_BE_BOOLEAN')
                changed = before != self.source()
                if issue_id and not changed:
                    raise Blocked('FAILED_CHECK_REPAIR_WITHOUT_CHANGE')
                if issue_id:
                    self.data['repair_attempt'] = {'incident_id': issue_id, 'changed': changed,
                        'maximum': self.data.get('maximum_observed', False), 'turn_id': self.data['call']['turn_id']}
                    self.data['incidents'][issue_id]['last_attempt'] = dict(self.data['repair_attempt'])
                self.data.update(stage='VALIDATE' if result.get('complete', True) else 'IMPLEMENT', implementation=result,
                                 implementation_done=result.get('complete', True))
                self.save()
        elif stage == 'FAST_VALIDATE':
            # Migrate retained checkpoints without repeating the old slice loop.
            self.data['stage'] = 'VALIDATE' if self.data.get('implementation_done', False) else 'IMPLEMENT'
            self.save()
        elif stage == 'VALIDATE':
            self.validate()
        elif stage == 'REVIEW':
            result = self.ai('현재 모델의 별도 코드 검토 단계다. 원문·승인 변경·전체 diff·회귀·실행 로그·'
                             '데이터 보존·미연결 범위를 대조한다. 지적에는 해결이 필요한 사항만 넣고 모든 지적이 해소돼야 승인한다. '
                             '판정 이유와 후속 경계는 summary에 짧게 남긴다. 정상 완료 정리는 제어기가 담당한다. 독립 검수라고 표현하지 않는다. '
                             'payload={approved:boolean,findings:[...],acceptance_reviewed:[id,...]}.', 'reviewed', read_only=True)
            if result:
                if set(result.get('acceptance_reviewed', [])) != {a['id'] for a in self.data['plan']['acceptance']}:
                    raise Blocked('REVIEW_COVERAGE_INCOMPLETE')
                self.data['review'] = result
                if result.get('approved') is True and not result.get('findings') and self.checks_valid():
                    self.data['reviewed_fingerprint'] = self.source()
                    for issue in self.data.get('incidents', {}).values():
                        issue['status'] = 'resolved'
                    self.data.pop('active_incident', None)
                    self.data.pop('repair_attempt', None)
                    self.data.pop('pending_failure', None)
                    self.data.pop('diagnosis', None)
                    if self.data['plan']['manual']['required']:
                        self.data['stage'] = 'MANUAL'
                        self.pause('WAITING_USER', 'MANUAL_TEST_REQUIRED')
                        self.record_request('MANUAL_TEST_REQUIRED')
                    else:
                        self.data['stage'] = 'COMMIT'
                else:
                    self.queue_failure('review:' + self.data['call']['turn_id'], {'review': result})
                self.save()
        elif stage == 'COMMIT':
            self.commit()
        elif stage == 'PUSH':
            self.push()
        elif stage == 'CI':
            self.ci_once()
        elif stage == 'FINALIZE':
            self.write_final_facts()
            self.complete({'acceptance_passed': self.data['review']['acceptance_reviewed']})
        else:
            raise Blocked('UNKNOWN_STAGE:' + stage)

    def initialize_task(self, item, end_task):
        unit, task = item
        history = self.data.get('history', [])
        if self.data.get('task_id'):
            history += [{k: self.data.get(k) for k in ('task_id', 'unit_id', 'target_commit', 'incident', 'incidents', 'stage')}]
        thread = self.data.get('thread_id')
        pending_records = self.data.get('pending_records', {})
        self.data = {'schema': 2, 'root': str(self.root), 'branch': git(self.root, 'branch', '--show-current'),
                     'task_id': task, 'unit_id': unit['id'], 'end_task': end_task, 'stage': 'PLAN',
                     'status': 'READY', 'task_base_commit': git(self.root, 'rev-parse', 'HEAD'),
                     'thread_id': thread, 'history': history, 'pending_records': pending_records, 'created': utc()}
        state = self.state()
        self.data['order_hash'] = hashlib.sha256(json.dumps([state['sequence_start'], state['priority_order']]).encode()).hexdigest()
        self.save()

    def run(self, end_task=None, resume=False):
        with RunLock(self.directory / 'runner.lock'):
            self.load()
            state = self.guards()
            if self.data.get('status') == 'RUN_FINISHED':
                self.notify_completion()
                return
            if self.data.get('incident') and not self.data.get('incidents'):
                self.pause('WAITING_AI', 'LEGACY_CAUSE_RECONCILIATION_REQUIRED')
                self.data['ai_handoff'] = {'owner': 'AI', 'status': 'NEEDS_HOST_TRIAGE',
                    'reason': 'Preserve legacy attempts; assign causes from original evidence before resuming.'}
                self.save()
                return
            if not state.get('runner', {}).get('enabled'):
                raise Blocked('RUNNER_NOT_ACTIVATED')
            activation_path = self.root / '.local/workflow/runner-verification.json'
            activation = read_json(activation_path) if activation_path.exists() else {}
            if activation.get('controller_hash') != controller_hash(self.root) or activation.get('status') != 'PASS':
                raise Blocked('THIS_INSTALLATION_VALIDATION_REQUIRED')
            receipt_path = self.root / '.local/workflow/phone/confirmed.json'
            if not receipt_path.exists():
                receipt_path = self.root / '.local/workflow/phone/receipt.json'
            receipt = read_json(receipt_path) if receipt_path.exists() else {}
            if state['runner'].get('notification_required', True) and receipt.get('status') != 'HUMAN_CONFIRMED':
                raise Blocked('THIS_LAPTOP_NOTIFICATION_CONFIRMATION_REQUIRED')
            if self.stopped() or self.data.get('status') in ('PAUSED_USER', 'PAUSED_QUOTA', 'BLOCKED', 'WAITING_USER', 'WAITING_AI'):
                if not resume:
                    raise Blocked('EXPLICIT_RESUME_REQUIRED')
                if self.data.get('request') and not self.data['request'].get('resolved'):
                    raise Blocked('MATCHING_USER_RESULT_REQUIRED')
                if self.data.get('ai_handoff', {}).get('status') == 'NEEDS_HOST_TRIAGE':
                    raise Blocked('HOST_AI_TRIAGE_REQUIRED')
                if self.data.get('reason') in ('REPAIR_BUDGET_EXHAUSTED', 'RECOVERED_CHECKPOINT_REQUIRES_RECONCILIATION'):
                    raise Blocked('EXPLICIT_RECONCILIATION_REQUIRED')
                if self.stop_path.exists():
                    self.stop_path.unlink()
                self.data['status'] = 'READY'
            if not self.data:
                if git(self.root, 'status', '--porcelain'):
                    raise Blocked('PRESERVE_EXISTING_WORK_BEFORE_START')
                item, _ = next_task(state, self.tasks)
                if not item:
                    raise Blocked('NO_READY_WORK')
                if not end_task or end_task not in [t['id'] for t in self.tasks]:
                    raise Blocked('EXPLICIT_END_TASK_REQUIRED')
                ids = [t['id'] for t in self.tasks]
                if ids.index(end_task) < ids.index(item[1]):
                    raise Blocked('END_TASK_PRECEDES_CURRENT')
                if git(self.root, 'branch', '--show-current') != 'main':
                    raise Blocked('CURRENT_AUTOMATION_REQUIRES_MAIN')
                self.initialize_task(item, end_task)
            start_status_monitor(self.root)
            self.status_display = True
            self.save()
            with AppServer(str(self.root)) as client:
                self.client = client
                self.reconcile_call()
                command = self.data.get('command', {})
                if command.get('status') in ('INTENT', 'RUNNING'):
                    record_path = self.directory / 'commands' / command['id'] / 'command.json'
                    record = read_json(record_path) if record_path.exists() else {}
                    if record.get('status') == 'RUNNING' and record.get('pid') and process_alive(record['pid']):
                        raise Blocked('OWNED_COMMAND_STILL_RUNNING_DO_NOT_DUPLICATE')
                    # An interrupted command is never a PASS; rerun its required validation stage.
                    self.data.update(stage='VALIDATE', command={'status': 'INTERRUPTED'})
                    self.save()
                while not self.stopped() and self.data['status'] in ('READY', 'WAITING_EXTERNAL', 'COMPLETE'):
                    self.guards()
                    if self.data['stage'] == 'COMPLETE':
                        if self.data['task_id'] == self.data['end_task']:
                            self.pause('RUN_FINISHED', 'APPROVED_END_REACHED')
                            self.notify_completion()
                            break
                        item, _ = next_task(self.state(), self.tasks)
                        if not item:
                            self.pause('BLOCKED', 'NEXT_SEQUENCE_PREREQUISITE')
                            self.record_request('NEXT_SEQUENCE_PREREQUISITE')
                            break
                        ids = [t['id'] for t in self.tasks]
                        if ids.index(item[1]) > ids.index(self.data['end_task']):
                            self.pause('RUN_FINISHED', 'NO_REMAINING_WORK_IN_APPROVED_RANGE')
                            self.notify_completion()
                            break
                        self.initialize_task(item, self.data['end_task'])
                    previous_stage = self.data['stage']
                    self.step()
                    if previous_stage == 'CI' and self.data['status'] == 'WAITING_EXTERNAL':
                        # No AI invocation while waiting. Stop remains responsive.
                        for _ in range(120):
                            if self.stopped():
                                break
                            time.sleep(1)
                if self.stopped():
                    self.pause('PAUSED_USER', 'USER_STOP')

    def accept_event(self, path):
        with RunLock(self.directory / 'runner.lock'):
            self.load()
            result = read_json(path)
            request = self.data.get('request', {})
            expected = {k: request.get(k) for k in ('item_id', 'revision', 'task_id', 'build')}
            if not request or any(result.get(k) != v for k, v in expected.items()):
                raise Blocked('STALE_OR_WRONG_USER_RESULT')
            if request.get('resolved'):
                return 'ALREADY_APPLIED'
            if result.get('outcome') not in ('passed', 'failed', 'resolved') or not result.get('evidence'):
                raise Blocked('EXPLICIT_USER_EVIDENCE_REQUIRED')
            if request['build'] != 'not-built' and request['build'] != self.source():
                raise Blocked('USER_RESULT_SOURCE_CHANGED')
            self.data['user_result'] = result
            self.data['request']['resolved'] = True
            if self.data['stage'] == 'MANUAL':
                if result['outcome'] == 'passed':
                    self.data.update(manual_pass=True, stage='COMMIT')
                else:
                    self.data['stage'] = 'IMPLEMENT'
            # Event acceptance never starts AI and never clears an explicit user stop.
            self.save()
            self.event('user_result', result)
            todo_path = self.root / '내가할일.md'
            todo = todo_path.read_text(encoding='utf-8')
            todo = re.sub(r'(?ms)^- \[ \] ' + re.escape(request['item_id']) + r' —.*?(?=^- \[[ x]\] USER-|\Z)', '', todo)
            count = len(re.findall(r'^- \[ \] USER-\d{3}', todo, re.M))
            todo = re.sub(r'사용자 확인 대기 \d+건', f'사용자 확인 대기 {count}건', todo)
            if not count and '현재 직접 할 일 없음' not in todo:
                todo += '\n현재 직접 할 일 없음\n'
            todo_path.write_text(todo, encoding='utf-8')
            records_path = self.root / 'docs/verification/user-action-records.md'
            records = records_path.read_text(encoding='utf-8')
            pattern = r'(?ms)(^### ' + re.escape(request['item_id']) + r' —.*?)(?=^#{1,3} |\Z)'
            records = re.sub(pattern, lambda m: m[0].replace('- 상태: **확인 필요**', '- 상태: **응답 수신**') +
                             '\n- 사용자 결과: ' + result['evidence'] + '\n', records)
            records_path.write_text(records, encoding='utf-8')
            return 'RECORDED_EXPLICIT_RESUME_REQUIRED'

    def reconcile_call(self):
        call = self.data.get('call', {})
        if call.get('stage') != self.data.get('stage'):
            return
        if call.get('phase') == 'completed' and call.get('status') == 'completed':
            self.data['recovered_turn_result'] = {k: call[k] for k in
                ('turn_id', 'status', 'text', 'requests', 'error', 'usage', 'observation')}
            return
        if call.get('phase') not in ('intent', 'accepted'):
            return
        if not self.data.get('thread_id'):
            raise Blocked('UNCERTAIN_THREAD_REQUIRES_RECONCILIATION')
        result = self.client.call('thread/read', {'threadId': self.data['thread_id'], 'includeTurns': True})
        thread = result['thread']
        if thread.get('status', {}).get('type') == 'active':
            raise Blocked('ORIGINAL_TURN_STILL_ACTIVE_DO_NOT_DUPLICATE')
        turns = [t for t in thread['turns'] if t['id'] not in call.get('prior_turn_ids', [])]
        if call.get('turn_id'):
            turns = [t for t in turns if t['id'] == call['turn_id']]
        if len(turns) != 1 or turns[0]['status'] != 'completed':
            raise Blocked('UNCERTAIN_TURN_NOT_COMPLETED_NO_AUTOMATIC_RETRY')
        turn = turns[0]
        messages = [i['text'] for i in turn.get('items', []) if i.get('type') == 'agentMessage' and i.get('phase') != 'commentary']
        if not messages:
            raise Blocked('COMPLETED_TURN_RESULT_MISSING')
        self.client.thread_path = thread.get('path')
        self.data['recovered_turn_result'] = {'turn_id': turn['id'], 'status': 'completed', 'text': messages[-1],
                                             'requests': [], 'error': None, 'usage': None,
                                             'observation': self.client.observe_turn(turn['id'])}
        self.data['call']['phase'] = 'reconciled'
        self.save()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('plan', 'status', 'run', 'resume', 'stop', 'event', 'doctor', 'checks', 'usage'))
    parser.add_argument('--end-task')
    parser.add_argument('--event-file', type=Path)
    args = parser.parse_args()
    runner = Runner()
    try:
        if args.mode == 'usage':
            report = write_usage_report(runner.directory)
            print(json.dumps({'calls': len(report['calls']), 'log_issues': report['log_issues'],
                              'report': str(runner.directory / 'usage-report.md')}, ensure_ascii=True))
            return 0
        elif args.mode == 'checks':
            result = runner.local_checks()
            print(json.dumps(result, ensure_ascii=True, indent=2))
            return 0 if result['status'] == 'PASS' else 1
        elif args.mode == 'plan':
            print(json.dumps(runner.plan_only(), ensure_ascii=True, indent=2))
        elif args.mode == 'status':
            runner.load()
            print(json.dumps(runner.data, ensure_ascii=True, indent=2))
        elif args.mode == 'stop':
            atomic_json(runner.stop_path, {'requested': utc()})
            print('Stop requested; no automatic resume.')
        elif args.mode == 'event':
            print(runner.accept_event(args.event_file))
        elif args.mode == 'doctor':
            with AppServer(str(ROOT)) as client:
                caps = client.capabilities()
                atomic_json(ROOT / '.local/workflow/capabilities.json', caps)
                print(json.dumps({'authentication': caps['authentication'],
                                  'normal': select_model(caps['models']),
                                  'sensitive': select_model(caps['models'], 'sensitive'),
                                  'maximum': select_model(caps['models'], escalate=True),
                                  'usage_allowed': quota_available(caps)}, indent=2))
        else:
            runner.run(args.end_task, resume=args.mode == 'resume')
            if runner.data.get('status') == 'WAITING_AI':
                print('WAITING_AI: supervising Codex must inspect call.requests and resolve or prepare a genuine user action; no phone alert sent.')
    except Exception as error:
        if args.mode in ('run', 'resume') and not runner.data:
            runner.directory = runner.directory / 'startup-alert'
            runner.path = runner.directory / 'checkpoint.json'
            if runner.path.exists():
                runner.load()
            else:
                runner.data = {'root': str(runner.root), 'task_id': 'WORKFLOW-09', 'status': 'BLOCKED'}
        if runner.data and runner.data.get('status') not in ('PAUSED_USER', 'PAUSED_QUOTA', 'WAITING_USER', 'WAITING_AI'):
            runner.pause('BLOCKED', str(error))
            if args.mode in ('run', 'resume'):
                runner.record_request('EXECUTION_BLOCKED')
        print('BLOCKED: ' + str(error), file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
