"""Local Codex App Server transport; no API keys, paid API, or delegated agents."""
import json
import os
import queue
import shutil
import subprocess
import threading
import time


class ProviderError(RuntimeError):
    pass


class AppServer:
    def __init__(self, cwd, executable=None):
        exe = executable or shutil.which('codex')
        if not exe:
            raise ProviderError('CODEX_UNAVAILABLE')
        env = os.environ.copy()
        for key in ('OPENAI_API_KEY', 'CODEX_API_KEY', 'OPENAI_BASE_URL'):
            env.pop(key, None)
        self.process = subprocess.Popen(
            [exe, 'app-server', '--stdio', '-c', 'forced_login_method="chatgpt"',
             '-c', 'model_provider="openai"', '-c', 'features.multi_agent=false'],
            cwd=cwd, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, text=True, encoding='utf-8',
            creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        self.messages = queue.Queue()
        self.events = []
        self.counter = 0
        self.thread_path = None
        threading.Thread(target=self._read, daemon=True).start()
        self.call('initialize', {'clientInfo': {'name': 'song_record_workflow',
                  'title': 'Song Record sequential workflow', 'version': '1.2.0'},
                  'capabilities': {'experimentalApi': True}})
        self.send({'method': 'initialized'})

    def _read(self):
        try:
            for line in self.process.stdout:
                try:
                    self.messages.put(json.loads(line))
                except json.JSONDecodeError:
                    pass
        finally:
            self.messages.put(None)

    def send(self, data):
        self.process.stdin.write(json.dumps(data) + '\n')
        self.process.stdin.flush()

    def receive(self, timeout=60):
        try:
            message = self.messages.get(timeout=timeout)
        except queue.Empty:
            raise ProviderError('PROVIDER_TIMEOUT') from None
        if message is None:
            raise ProviderError('PROVIDER_DISCONNECTED')
        return message

    def call(self, method, params, timeout=60):
        self.counter += 1
        request_id = self.counter
        self.send({'id': request_id, 'method': method, 'params': params})
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            msg = self.receive(max(.01, deadline-time.monotonic()))
            if msg.get('id') == request_id and 'method' not in msg:
                if 'error' in msg:
                    # Arbitrary provider error text can include user data. Keep it private.
                    code = msg['error'].get('code', 'unknown')
                    raise ProviderError(f'RPC_REJECTED:{method}:{code}')
                return msg['result']
            self.events.append(msg)
        raise ProviderError('PROVIDER_TIMEOUT')

    def capabilities(self):
        account = self.call('account/read', {'refreshToken': False})
        kind = (account.get('account') or {}).get('type')
        if kind != 'chatgpt':
            raise ProviderError('CHATGPT_SUBSCRIPTION_LOGIN_REQUIRED')
        models, cursor = [], None
        while True:
            params = {'includeHidden': False}
            if cursor:
                params['cursor'] = cursor
            result = self.call('model/list', params)
            models.extend(result['data'])
            cursor = result.get('nextCursor')
            if not cursor:
                break
        raw_limits = self.call('account/rateLimits/read', {})
        limits = {key: raw_limits.get(key) for key in
                  ('ordinaryUsageAllowed', 'rateLimits', 'rateLimitsByLimitId')}
        return {'authentication': kind, 'models': models, 'rate_limits': limits}

    def open_thread(self, cwd, model, effort, thread_id=None, read_only=False):
        params = {'cwd': str(cwd), 'model': model, 'modelProvider': 'openai',
                  'approvalPolicy': 'on-request', 'approvalsReviewer': 'user',
                  'sandbox': 'read-only' if read_only else 'workspace-write',
                  'serviceTier': 'default',
                  'config': {'model_reasoning_effort': effort,
                             'features.multi_agent': False},
                  'developerInstructions': (
                      'Single sequential Song_Record controller. No subagents, workers, reviewers, '
                      'paid API, reset credits or purchases. Do only the current requested stage. '
                      'Never edit tools/, AGENTS.md, docs/workflow-state.json or .local/workflow/runs/sequential/. '
                      'Never run git add/commit/push, notifications, or CI polling: the controller owns them. '
                      'Preserve all existing user data. Do not lower tests or acceptance criteria. '
                      'On Windows every PowerShell command must begin with '
                      '[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new(); '
                      '$OutputEncoding = [Console]::OutputEncoding; '
                      'Read text with Get-Content -Encoding UTF8. For read-only Git use '
                      'git -c safe.directory=C:/Users/ksh/Documents/GitHub/Song_Record; never change global Git config. '
                      'Return the requested structured handoff; do not advance to another P number.')}
        if thread_id:
            params.update(threadId=thread_id, excludeTurns=True)
        result = self.call('thread/resume' if thread_id else 'thread/start', params)
        self.thread_path = result['thread'].get('path')
        return result

    def turn(self, thread_id, prompt, model, effort, schema, checkpoint,
             stop=lambda: False, read_only=False, timeout=3600):
        """Persist intent BEFORE sending; never retry an uncertain request automatically."""
        before = self.call('thread/read', {'threadId': thread_id, 'includeTurns': True})
        checkpoint('intent', {'requested_model': model, 'requested_effort': effort,
                             'prior_turn_ids': [t['id'] for t in before['thread']['turns']]})
        response = self.call('turn/start', {
            'threadId': thread_id, 'model': model, 'effort': effort,
            'serviceTierForTurn': 'default', 'approvalPolicy': 'on-request',
            'sandboxPolicy': {'type': 'readOnly', 'networkAccess': False} if read_only else {
                'type': 'workspaceWrite', 'writableRoots': [], 'networkAccess': False},
            'input': [{'type': 'text', 'text': prompt}], 'outputSchema': schema})
        turn_id = response['turn']['id']
        checkpoint('accepted', {'turn_id': turn_id, 'observed_model': 'unknown',
                                'observed_effort': 'unknown'})
        deadline = time.monotonic() + timeout
        final, requests, usage = '', [], None
        interrupted = False
        interrupted_at = None
        while True:
            if interrupted_at and time.monotonic() - interrupted_at > 20:
                raise ProviderError('INTERRUPT_COMPLETION_UNCONFIRMED')
            if (stop() or time.monotonic() > deadline) and not interrupted:
                self.call('turn/interrupt', {'threadId': thread_id, 'turnId': turn_id})
                interrupted = True
                interrupted_at = time.monotonic()
            if self.events:
                msg = self.events.pop(0)
            else:
                try:
                    msg = self.receive(1)
                except ProviderError as error:
                    if str(error) == 'PROVIDER_TIMEOUT':
                        continue
                    raise
            if 'id' in msg and 'method' in msg:
                # No blanket approval. Preserve a reviewable request, cancel this turn.
                requests.append({'method': msg['method'], 'params': msg.get('params')})
                self.send({'id': msg['id'], 'error': {'code': -32000,
                           'message': 'Controller requires human action for this request.'}})
                if not interrupted:
                    self.call('turn/interrupt', {'threadId': thread_id, 'turnId': turn_id})
                    interrupted = True
                    interrupted_at = time.monotonic()
            method, params = msg.get('method'), msg.get('params', {})
            if params.get('threadId') not in (None, thread_id):
                continue
            if method == 'thread/tokenUsage/updated':
                usage = params.get('tokenUsage')
            if method == 'item/completed':
                item = params.get('item', {})
                if item.get('type') == 'agentMessage' and item.get('phase') != 'commentary':
                    final = item.get('text', '')
            if method == 'turn/completed' and params['turn']['id'] == turn_id:
                turn = params['turn']
                for item in turn.get('items', []):
                    if item.get('type') == 'agentMessage' and item.get('phase') != 'commentary':
                        final = item.get('text', '')
                result = {'turn_id': turn_id, 'status': turn['status'], 'text': final,
                          'requests': requests, 'error': turn.get('error'), 'usage': usage,
                          'observation': self.observe_turn(turn_id)}
                checkpoint('completed', result)
                return result

    def observe_turn(self, turn_id):
        """Per-turn runtime context, not model self-report or global config."""
        from pathlib import Path
        observed = {'model': 'unknown', 'effort': 'unknown', 'source': 'unavailable'}
        if self.thread_path:
            try:
                for line in Path(self.thread_path).read_text(encoding='utf-8').splitlines():
                    row = json.loads(line)
                    payload = row.get('payload', {})
                    if row.get('type') == 'turn_context' and payload.get('turn_id') == turn_id:
                        observed = {'model': payload.get('model', 'unknown'),
                                    'effort': payload.get('effort', 'unknown'),
                                    'source': 'local turn_context', 'turn_id': turn_id}
            except (OSError, ValueError):
                pass
        return observed

    def close(self):
        if self.process.poll() is None:
            self.process.stdin.close()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.terminate()
                self.process.wait(timeout=5)

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()
