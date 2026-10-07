"""AI-free, six-line todo status and independent runner liveness observer."""
import argparse
import ctypes
import json
import os
import re
import subprocess
import sys
import time
import uuid
from pathlib import Path

from workflow_runtime import Blocked, RunLock, atomic_json, read_json, utc

BEGIN = '<!-- workflow-live-status -->'
END = '<!-- /workflow-live-status -->'
TODO = '내가할일.md'
STAGES = {'PLAN': '계획', 'IMPLEMENT': '구현', 'VALIDATE': '로컬 검사',
          'DIAGNOSE': '오류 분석', 'REVIEW': '코드 검토', 'MANUAL': '실기 확인',
          'COMMIT': '커밋', 'PUSH': '푸시', 'CI': 'CI 확인', 'FINALIZE': '완료 정리',
          'COMPLETE': '완료 판정'}
ACTIVE = {'READY', 'WAITING_EXTERNAL', 'COMPLETE'}


def without_panel(text):
    return re.sub(re.escape(BEGIN) + r'.*?' + re.escape(END) + r'\s*', '', text, flags=re.S)


def close_task(root, task_id):
    """Remove a verified completed task from the live todo, preserving USER items."""
    root = Path(root)
    with RunLock(root / '.local/workflow/runs/sequential/status-display.lock'):
        path = root / TODO
        text = without_panel(path.read_text(encoding='utf-8'))
        text = re.sub(r'^- ' + re.escape(task_id) + r'(?=\s|:)[^\n]*\n?', '', text, flags=re.M)
        text = re.sub(r'^AI 현재 작업: \[' + re.escape(task_id) + r'\][^\n]*',
                      'AI 현재 작업: 없음 — 승인 범위 실행 종료. 다음 작업 시작 대기.', text, flags=re.M)
        path.write_text(text, encoding='utf-8')


def process_identity(pid):
    """Creation time prevents a recycled PID from looking like our runner."""
    if os.name == 'nt':
        from ctypes import wintypes
        kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        kernel.OpenProcess.restype = wintypes.HANDLE
        kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        kernel.GetProcessTimes.argtypes = [wintypes.HANDLE] + [ctypes.POINTER(wintypes.FILETIME)] * 4
        kernel.GetExitCodeProcess.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
        handle = kernel.OpenProcess(0x1000, False, pid)
        if not handle:
            return None
        try:
            code = wintypes.DWORD()
            if not kernel.GetExitCodeProcess(handle, ctypes.byref(code)) or code.value != 259:
                return None
            times = [wintypes.FILETIME() for _ in range(4)]
            if not kernel.GetProcessTimes(handle, *(ctypes.byref(t) for t in times)):
                return None
            return str((times[0].dwHighDateTime << 32) | times[0].dwLowDateTime)
        finally:
            kernel.CloseHandle(handle)
    try:
        return Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()[19]
    except OSError:
        return None


def render(data, alive, title, todo):
    # Normal completion and an explicit user stop are not abnormal exits.
    if data.get('status') in ('RUN_FINISHED', 'PAUSED_USER'):
        return ''
    running = alive and data.get('status') in ACTIVE
    stage = data.get('stage', '')
    call = data.get('call', {})
    ai_wait = running and call.get('stage') == stage and call.get('phase') in ('intent', 'accepted')
    if not running:
        action = 'AI 확인 필요' if data.get('status') == 'WAITING_AI' else '중단 원인 확인 필요'
    elif ai_wait:
        action = 'AI 응답 대기'
    elif stage == 'CI':
        action = 'CI 결과 대기'
    elif stage == 'VALIDATE':
        action = '로컬 검사 실행'
    else:
        action = '단계 처리 중'
    model = call.get('requested_model', '')
    model = 'Astra' if 'astra' in model else 'Sol' if 'sol' in model else model
    ai = f"{model} / {call.get('requested_effort', '').title()} — 요청 설정" if ai_wait else '사용 안 함'
    requests = re.findall(r'^- \[ \] (USER-\d+[^\n]*)', todo, re.M)
    human = ' / '.join(requests) if requests else '없음'
    return '\n'.join([
        '자동 개발: ' + ('🟢 실행 중' if running else '🔴 비정상 종료'),
        f"현재 작업: {data.get('task_id', '확인 필요')} {title}".rstrip(),
        f"현재 단계: {STAGES.get(stage, stage or '확인 필요')}",
        f'현재 동작: {action}', f'AI: {ai}', f'사용자 직접 할 일: {human}'])


def publish(root, data, alive):
    root = Path(root)
    directory = root / '.local/workflow/runs/sequential'
    try:
        with RunLock(directory / 'status-display.lock'):
            path = root / TODO
            original = path.read_text(encoding='utf-8')
            body = without_panel(original)
            tasks = read_json(root / 'docs/reference/search/tasks.json')
            title = next((t.get('title', '') for t in tasks if t['id'] == data.get('task_id')), '')
            panel = render(data, alive, title, body)
            text = f'{BEGIN}\n```yaml\n{panel}\n```\n{END}\n\n{body}' if panel else body
            # Do not overwrite a concurrent USER request update.
            if text != original and path.read_text(encoding='utf-8') == original:
                temp = directory / 'todo-display.tmp'
                temp.write_text(text, encoding='utf-8')
                os.replace(temp, path)
    except Blocked:
        pass  # Another publisher owns this short write; the next update retries.


def start(root):
    root = Path(root)
    directory = root / '.local/workflow/runs/sequential'
    token = uuid.uuid4().hex
    identity = process_identity(os.getpid())
    if identity is None:
        raise RuntimeError('RUNNER_PROCESS_IDENTITY_UNAVAILABLE')
    record = {'token': token, 'pid': os.getpid(), 'identity': identity, 'started': utc()}
    atomic_json(directory / 'status-monitor.json', record)
    subprocess.Popen([sys.executable, str(Path(__file__).resolve()), '--root', str(root), '--token', token],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0), close_fds=True)


def observe(root, token):
    root = Path(root)
    directory = root / '.local/workflow/runs/sequential'
    while True:
        record = read_json(directory / 'status-monitor.json')
        if record['token'] != token:
            return  # A later run superseded this observer.
        alive = process_identity(record['pid']) == record['identity']
        data = read_json(directory / 'checkpoint.json')
        publish(root, data, alive)
        record.update(checked=utc(), alive=alive)
        atomic_json(directory / 'status-observation.json', record)
        if not alive or data.get('status') in ('RUN_FINISHED', 'PAUSED_USER'):
            return
        time.sleep(30)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--token', required=True)
    args = parser.parse_args()
    observe(args.root, args.token)
