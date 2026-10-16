"""One-time masked web credential entry. CurrentUser DPAPI; no secret CLI output."""
import json
import os
from pathlib import Path
import re
import secrets
import uuid
from r2_vault import _crypt, _secure

ROOT=Path(__file__).resolve().parents[1]
DIRECTORY=ROOT/'.local/workflow/experiment-web'
ROLE='experiment.web'
SCOPE='song_record_experiment_web:v1'
ORIGIN='https://song-record-beta-ksh321.duckdns.org'


class WebCredentialError(Exception):pass


def registration_fingerprint(value):
    # A UI-registration identity check for accidental key mix-ups, not an
    # authentication primitive. Provider verification remains authoritative.
    result=14695981039346656037
    for character in value:result=((result^ord(character))*1099511628211)&((1<<64)-1)
    return format(result,'016x')


def validate(record):
    keys={'scope','enabled','origin','google_client_id','kakao_rest_key','kakao_client_secret','rate_secret'}
    if not isinstance(record,dict) or set(record)!=keys or record['scope']!=SCOPE or type(record['enabled']) is not bool or record['origin']!=ORIGIN:
        raise WebCredentialError('WEB_SCOPE_REJECTED')
    patterns={'google_client_id':r'660802266773-[a-z0-9]+\.apps\.googleusercontent\.com','kakao_rest_key':r'[a-fA-F0-9]{32}','kakao_client_secret':r'[A-Za-z0-9_-]{16,256}','rate_secret':r'[a-f0-9]{64}'}
    if any(not isinstance(record[k],str) or not re.fullmatch(p,record[k]) for k,p in patterns.items()):
        raise WebCredentialError('WEB_CREDENTIAL_FORMAT_REJECTED')
    if record['kakao_rest_key']==record['kakao_client_secret']:
        raise WebCredentialError('WEB_CLIENT_SECRET_REQUIRED')


def load(directory=DIRECTORY):
    try:
        path=directory/'credentials.dpapi'
        if path.is_symlink():raise WebCredentialError('WEB_SCOPE_REJECTED')
        with path.open('rb') as file:encrypted=file.read(16385)
        if len(encrypted)>16384:raise WebCredentialError('WEB_SCOPE_REJECTED')
        record=json.loads(_crypt(encrypted,ROLE,True));validate(record)
        return record
    except Exception:raise WebCredentialError('SAVED_WEB_CREDENTIALS_UNAVAILABLE') from None


def register(rest_key,client_secret,public,directory=DIRECTORY):
    pending=None
    try:
        if public.get('scope')!='song_record_experiment_web_public:v1' or public.get('origin')!=ORIGIN:
            raise WebCredentialError('WEB_SCOPE_REJECTED')
        record={'scope':SCOPE,'enabled':False,'origin':ORIGIN,'google_client_id':public['google_client_id'],
                'kakao_rest_key':rest_key,'kakao_client_secret':client_secret,'rate_secret':secrets.token_hex(32)}
        validate(record)
        if public.get('kakao_rest_fingerprint')!=registration_fingerprint(rest_key):
            raise WebCredentialError('WEB_KEY_DOES_NOT_MATCH_PREPARED_REGISTRATION')
        native=json.loads((ROOT/'.local/workflow/p25-06/staging-public-auth.json').read_text(encoding='utf-8-sig')).get('KAKAO_NATIVE_APP_KEY')
        if rest_key==native:raise WebCredentialError('WEB_REST_KEY_REQUIRED')
        encrypted=_crypt(json.dumps(record).encode(),ROLE)
        verified=json.loads(_crypt(encrypted,ROLE,True));validate(verified)
        if verified!=record:raise WebCredentialError('WEB_ROUNDTRIP_FAILED')
        _secure(directory);target=directory/'credentials.dpapi'
        if target.is_symlink():raise WebCredentialError('WEB_SCOPE_REJECTED')
        pending=directory/(uuid.uuid4().hex+'.pending')
        with pending.open('xb') as file:file.write(encrypted);file.flush();os.fsync(file.fileno())
        pending.replace(target)
        return {'status':'REGISTERED_ENCRYPTED_DISABLED','oauth_verified':False,'server_transfer':False}
    except WebCredentialError:raise
    except Exception:raise WebCredentialError('WEB_REGISTRATION_FAILED_EXISTING_PRESERVED') from None
    finally:
        if pending is not None:pending.unlink(missing_ok=True)


def gui():
    import tkinter as tk
    from tkinter import ttk
    public=json.loads((ROOT/'.local/workflow/p25-06/web-ownership-public.json').read_text(encoding='utf-8'))
    window=tk.Tk();window.title('Song_Record — 카카오 웹 키 재등록 (전용 키 확인)')
    window.geometry('730x420')
    ttk.Label(window,text='전용 키 일치 확인 · 새 웹 키 재등록',font=('Malgun Gothic',15)).pack(pady=14)
    ttk.Label(window,text='기존 휴대폰 로그인 키·어드민 키는 사용하지 않습니다.\nWindows 계정으로 암호화하며 실제 웹 소유 확인은 연결 후 검사합니다.',justify='center').pack(pady=6)
    ttk.Label(window,text='키 이름: Song_Record staging web deletion\n이름이 일치하는 상세 화면의 REST API 키와 카카오 로그인 시크릿만 입력하세요.',justify='center').pack(pady=6)
    fields=[]
    for label in ['새 REST API 키','새 Client Secret (클라이언트 시크릿)']:
        ttk.Label(window,text=label).pack(anchor='w',padx=24)
        field=ttk.Entry(window,show='*');field.pack(fill='x',padx=24,pady=7);fields.append(field)
    status=tk.StringVar(value='비밀값·발급 화면은 채팅에 보내지 마세요. 등록만으로 서버에 전송하거나 웹을 공개하지 않습니다.')
    ttk.Label(window,textvariable=status,wraplength=680,justify='center').pack(pady=10)
    def submit():
        button.config(state='disabled')
        try:
            register(*(field.get().strip() for field in fields),public)
            for field in fields:field.delete(0,'end')
            status.set('카카오 웹 키 Windows 암호화 등록 완료 · 실제 소유 확인은 연결 후 검사')
        except WebCredentialError as error:
            status.set('전용 웹 키와 일치하지 않습니다. Song_Record staging web deletion의 REST API 키를 복사해 주세요. 기존 등록은 보존했습니다.' if str(error)=='WEB_KEY_DOES_NOT_MATCH_PREPARED_REGISTRATION' else '등록 실패. 새 REST API 키와 Client Secret을 확인해 주세요. 기존 등록은 보존했습니다.')
        except Exception:status.set('등록 실패. 기존 등록은 보존했습니다.')
        finally:button.config(state='normal')
    button=ttk.Button(window,text='Windows 계정 암호화 등록',command=submit);button.pack(pady=8)
    window.report_callback_exception=lambda *args:status.set('처리 실패. 비밀값은 기록하지 않았습니다.')
    def close():
        for field in fields:field.delete(0,'end')
        window.destroy()
    window.protocol('WM_DELETE_WINDOW',close);window.mainloop()


if __name__=='__main__':gui()
