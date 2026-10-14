"""Masked validation-backup credentials and portable recovery key registration."""
import base64
import json
import os
import queue
import threading
import uuid
from pathlib import Path
from cryptography.hazmat.primitives.kdf.scrypt import Scrypt
from backup_store import BACKUP_BUCKET, EncryptedStore, R2, seal, unseal, BackupError
from r2_vault import _crypt, _secure, load, save, exists
from r2_credentials import validate

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = ROOT / '.local/workflow/backup'


def recovery_wrap(key, phrase):
    if len(phrase) < 16:
        raise BackupError('RECOVERY_PHRASE_LENGTH')
    salt = os.urandom(16)
    derived = Scrypt(salt=salt, length=32, n=2**17, r=8, p=1).derive(phrase.encode())
    return b'SRR1' + salt + seal(derived, key, 'recovery-v1')


def recovery_unwrap(data, phrase):
    if not data.startswith(b'SRR1') or len(data) != 84:
        raise BackupError('RECOVERY_ENVELOPE_INVALID')
    derived = Scrypt(salt=data[4:20], length=32, n=2**17, r=8, p=1).derive(phrase.encode())
    key = unseal(derived, data[20:], 'recovery-v1')
    if len(key) != 32:
        raise BackupError('RECOVERY_KEY_INVALID')
    return key


def encryption_key():
    try:
        key = _crypt((DIRECTORY / 'master.dpapi').read_bytes(), 'staging.backup', True)
        if len(key) != 32:
            raise ValueError()
        return key
    except Exception:
        raise BackupError('BACKUP_KEY_UNAVAILABLE') from None


def check_scope(access, secret):
    validate(access, secret)
    backup = R2(access, secret, BACKUP_BUCKET)
    if backup.request('GET', query={'list-type': '2', 'max-keys': '1'})[0] != 200:
        raise BackupError('BACKUP_BUCKET_SCOPE')
    for environment in ('dev', 'prod', 'staging-dev'):
        for kind in ('temporary', 'final'):
            if R2(access, secret, f'song-record-{environment}-{kind}').request('GET', query={'list-type': '2', 'max-keys': '1'})[0] != 403:
                raise BackupError('BACKUP_KEY_BROAD_SCOPE')
    for role in ('staging.api', 'staging.worker', 'staging.playback'):
        a, s = load(role)
        transport = R2(a, s, BACKUP_BUCKET)
        if transport.request('GET', query={'list-type': '2', 'max-keys': '1'})[0] != 403:
            raise BackupError('APPLICATION_CAN_ACCESS_BACKUP')
        # Actual delete denial on a nonexistent randomized probe; no user object involved.
        if transport.request('DELETE', 'operational/v1/probes/' + str(uuid.uuid4()))[0] != 403:
            raise BackupError('APPLICATION_CAN_DELETE_BACKUP')
    path = 'operational/v1/probes/' + str(uuid.uuid4())
    store = EncryptedStore(backup, os.urandom(32))
    store.put(path, b'Song_Record encrypted backup scope probe')
    store.delete(path)


def gui():
    import tkinter as tk
    from tkinter import ttk
    _secure(DIRECTORY)
    window = tk.Tk()
    window.title('Song_Record — 백업 전용 키 암호화 등록')
    window.geometry('830x560')
    ttk.Label(window, text='staging.backup · 백업 버킷 하나만 · 최초 한 번 등록', font=('', 16)).pack(pady=18)
    ttk.Label(window, text='song-record-staging-backup / Object Read & Write\n기존 앱·작업자 키를 넣지 마세요. 키·등록 화면은 채팅에 보내지 마세요.').pack(pady=8)
    fields = []
    for label in ('Access Key ID', 'Secret Access Key', '백업 복구 암호 (16자 이상, 별도 안전한 곳에 보관)', '복구 암호 다시 입력'):
        ttk.Label(window, text=label).pack(anchor='w', padx=25)
        field = ttk.Entry(window, show='*'); field.pack(fill='x', padx=25, pady=6); fields.append(field)
    status = tk.StringVar(value='복구 암호는 저장하지 않습니다. 노트북 분실 시 암호와 recovery-key.enc가 필요합니다.')
    ttk.Label(window, textvariable=status, wraplength=770).pack(pady=12)
    messages = queue.Queue(); busy = False

    def submit():
        nonlocal busy
        if busy:
            return
        values = [f.get() for f in fields]
        for field in fields:
            field.delete(0, 'end')
        busy = True; button.config(state='disabled'); status.set('권한·암호화·자동 사용 확인 중…')

        def work():
            try:
                access, secret, phrase, again = values
                if phrase != again or len(phrase) < 16:
                    raise BackupError('RECOVERY_PHRASE_MISMATCH')
                check_scope(access, secret)
                master = DIRECTORY / 'master.dpapi'
                # Rollover cannot silently replace the encryption key of existing backups.
                if not master.exists() and R2(access, secret, BACKUP_BUCKET).get('operational/v1/catalog.enc') is not None:
                    raise BackupError('EXISTING_BACKUP_RECOVERY_REQUIRED')
                key = encryption_key() if master.exists() else os.urandom(32)
                wrapped = recovery_wrap(key, phrase)
                if recovery_unwrap(wrapped, phrase) != key:
                    raise BackupError('RECOVERY_KEY_CHECK_FAILED')
                save('staging.backup', access, secret)
                check_scope(*load('staging.backup'))
                R2(access, secret, BACKUP_BUCKET).put_verified('operational/v1/recovery-key.enc', wrapped)
                for path, data in ((master, _crypt(key, 'staging.backup')), (DIRECTORY / 'recovery-key.enc', wrapped)):
                    pending = path.with_suffix('.pending'); pending.write_bytes(data); pending.replace(path)
                if encryption_key() != key:
                    raise BackupError('AUTOMATIC_KEY_CHECK_FAILED')
                receipt = {'status': 'PASS', 'role': 'staging.backup', 'application_backup_access': 'DENIED', 'secret_values_logged': False, 'recovery_verified': True}
                text = '백업 키 암호화 등록·자동 사용·복구 키 확인 완료'
            except Exception:
                receipt = {'status': 'FAIL', 'secret_values_logged': False}
                text = '등록 확인 실패. 버킷 하나만 선택한 전용 키·복구 암호를 확인하세요. 키는 채팅에 보내지 마세요.'
            finally:
                values.clear()
            (DIRECTORY / 'registration.json').write_text(json.dumps(receipt), encoding='utf-8')
            messages.put(text)
        threading.Thread(target=work, daemon=True).start()

    def poll():
        nonlocal busy
        try:
            status.set(messages.get_nowait()); busy = False; button.config(state='normal')
        except queue.Empty:
            pass
        window.after(200, poll)

    def close():
        if not busy:
            window.destroy()
    window.report_callback_exception = lambda *args: status.set('처리 실패. 비밀값 출력 없음.')
    button = ttk.Button(window, text='권한 확인 후 암호화 등록', command=submit); button.pack(pady=10)
    window.protocol('WM_DELETE_WINDOW', close); window.after(200, poll); window.mainloop()


if __name__ == '__main__':
    gui()
