"""Local beta signing only. No upload, automatic credential rotation or API calls."""
import base64
from contextlib import contextmanager
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import uuid

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.scrypt import Scrypt
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID
from r2_vault import _crypt, _secure

ROOT=Path(__file__).resolve().parents[1]
DIRECTORY=ROOT/'.local/workflow/release/beta-signing'
ROLE='beta.signing'
SCOPE='song_record_android_beta_signing:v1'
PACKAGE='com.ksh321.songrecord.beta'
ALIAS='songrecord-beta'
LIMIT=65536
MAGIC=b'SRSG1'


class SigningError(Exception):pass


def _phrase(value):
    if not isinstance(value,str) or not 16<=len(value)<=512:
        raise SigningError('RECOVERY_PHRASE_REQUIRED')


def _encoded(row):return json.dumps(row,sort_keys=True,separators=(',',':')).encode()


def _guard_directory(directory):
    if not directory.is_absolute():raise SigningError('SIGNING_DIRECTORY_REJECTED')
    for path in (directory,*directory.parents):
        if path.is_symlink() or path.is_junction():raise SigningError('SIGNING_DIRECTORY_REJECTED')


def public_record(row):
    return {key:row[key] for key in ['scope','application_id','alias','created_utc','certificate_sha256','certificate_sha1','kakao_key_hash']}


def _new_record():
    now=dt.datetime.now(dt.timezone.utc)
    key=rsa.generate_private_key(public_exponent=65537,key_size=3072)
    name=x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,'Song Record Limited Beta')])
    cert=(x509.CertificateBuilder().subject_name(name).issuer_name(name)
          .public_key(key.public_key()).serial_number(x509.random_serial_number())
          .not_valid_before(now-dt.timedelta(days=1)).not_valid_after(now+dt.timedelta(days=365*30))
          .add_extension(x509.BasicConstraints(ca=False,path_length=None),critical=True)
          .sign(key,hashes.SHA256()))
    password=secrets.token_urlsafe(36)
    p12=pkcs12.serialize_key_and_certificates(ALIAS.encode(),key,cert,None,serialization.BestAvailableEncryption(password.encode()))
    der=cert.public_bytes(serialization.Encoding.DER)
    return {'scope':SCOPE,'application_id':PACKAGE,'alias':ALIAS,'created_utc':now.isoformat(),
            'pkcs12':base64.b64encode(p12).decode(),'store_password':password,
            'certificate_sha256':hashlib.sha256(der).hexdigest(),
            'certificate_sha1':hashlib.sha1(der).hexdigest(),
            'kakao_key_hash':base64.b64encode(hashlib.sha1(der).digest()).decode()}


def validate(row):
    try:
        fields={'scope','application_id','alias','created_utc','pkcs12','store_password','certificate_sha256','certificate_sha1','kakao_key_hash'}
        if not isinstance(row,dict) or set(row)!=fields or row['scope']!=SCOPE or row['application_id']!=PACKAGE or row['alias']!=ALIAS:raise ValueError()
        if not re.fullmatch(r'[A-Za-z0-9_-]{48}',row['store_password']):raise ValueError()
        if len(row['pkcs12'])>LIMIT:raise ValueError()
        value=pkcs12.load_pkcs12(base64.b64decode(row['pkcs12'],validate=True),row['store_password'].encode())
        if not isinstance(value.key,rsa.RSAPrivateKey) or value.key.key_size!=3072 or value.cert is None or value.cert.friendly_name!=ALIAS.encode():raise ValueError()
        cert=value.cert.certificate
        if value.key.public_key().public_numbers()!=cert.public_key().public_numbers():raise ValueError()
        der=cert.public_bytes(serialization.Encoding.DER)
        if row['certificate_sha256']!=hashlib.sha256(der).hexdigest() or row['certificate_sha1']!=hashlib.sha1(der).hexdigest() or row['kakao_key_hash']!=base64.b64encode(hashlib.sha1(der).digest()).decode():raise ValueError()
        stamp=dt.datetime.fromisoformat(row['created_utc'])
        if stamp.tzinfo is None:raise ValueError()
    except Exception:raise SigningError('SIGNING_RECORD_REJECTED') from None


def seal_recovery(row,phrase):
    _phrase(phrase);validate(row)
    salt=os.urandom(16);nonce=os.urandom(12)
    key=Scrypt(salt=salt,length=32,n=2**17,r=8,p=1).derive(phrase.encode())
    return MAGIC+salt+nonce+AESGCM(key).encrypt(nonce,_encoded(row),SCOPE.encode())


def open_recovery(data,phrase):
    try:
        _phrase(phrase)
        if not isinstance(data,bytes) or not 50<=len(data)<=LIMIT or not data.startswith(MAGIC):raise ValueError()
        key=Scrypt(salt=data[5:21],length=32,n=2**17,r=8,p=1).derive(phrase.encode())
        row=json.loads(AESGCM(key).decrypt(data[21:33],data[33:],SCOPE.encode()));validate(row)
        return row
    except Exception:raise SigningError('RECOVERY_AUTHENTICATION_FAILED') from None


def create(phrase,*,approved=False,directory=DIRECTORY):
    stage=None;created=[]
    try:
        if approved is not True:raise SigningError('EXPLICIT_LOCAL_CREATION_REQUIRED')
        _phrase(phrase)
        _guard_directory(directory)
        if directory.exists() or directory.is_symlink():raise SigningError('EXISTING_SIGNING_DIRECTORY_PRESERVED')
        row=_new_record();validate(row);raw=_encoded(row)
        encrypted=_crypt(raw,ROLE)
        if _crypt(encrypted,ROLE,True)!=raw:raise SigningError('WINDOWS_ENCRYPTION_UNCONFIRMED')
        recovery=seal_recovery(row,phrase)
        if open_recovery(recovery,phrase)!=row:raise SigningError('RECOVERY_ROUNDTRIP_UNCONFIRMED')
        _secure(directory.parent)
        stage=directory.parent/('.signing-pending-'+uuid.uuid4().hex);_secure(stage)
        outputs={'signing.dpapi':encrypted,'recovery.srsg':recovery,'public.json':_encoded(public_record(row))}
        for name,data in outputs.items():
            path=stage/name
            with path.open('xb') as file:
                created.append(path);file.write(data);file.flush();os.fsync(file.fileno())
        # Windows rename fails if the destination already exists; never replace a key.
        if os.name!='nt' or directory.exists() or directory.is_symlink():raise SigningError('EXISTING_SIGNING_DIRECTORY_PRESERVED')
        os.rename(stage,directory);stage=None
        return {'status':'BETA_SIGNING_ENCRYPTED_RECOVERY_VERIFIED','public':public_record(row),'off_device_backup':False}
    except SigningError:raise
    except Exception:raise SigningError('SIGNING_CREATION_UNCONFIRMED') from None
    finally:
        if stage is not None and stage.exists():
            for path in created:path.unlink(missing_ok=True)
            stage.rmdir()


def load(directory=DIRECTORY):
    try:
        _guard_directory(directory)
        path=directory/'signing.dpapi'
        if directory.is_symlink() or path.is_symlink():raise ValueError()
        with path.open('rb') as file:data=file.read(LIMIT+1)
        if len(data)>LIMIT:raise ValueError()
        row=json.loads(_crypt(data,ROLE,True));validate(row);return row
    except Exception:raise SigningError('SAVED_SIGNING_UNAVAILABLE') from None


@contextmanager
def build_files(directory=DIRECTORY):
    _guard_directory(directory)
    row=load(directory);folder=None;created=[]
    try:
        folder=directory.parent/('build-signing-'+uuid.uuid4().hex);_secure(folder)
        p12=folder/'beta.p12';properties=folder/'key.properties'
        values={'storeFile':p12.as_posix(),'storePassword':row['store_password'],'keyAlias':ALIAS,'keyPassword':row['store_password']}
        for path,data in [(p12,base64.b64decode(row['pkcs12'])),(properties,''.join(k+'='+v+'\n' for k,v in values.items()).encode())]:
            with path.open('xb') as file:
                created.append(path);file.write(data);file.flush();os.fsync(file.fileno())
        yield properties,public_record(row)
    finally:
        row.clear()
        for path in reversed(created):path.unlink(missing_ok=True)
        if folder is not None:folder.rmdir()


def gui():
    import tkinter as tk
    from tkinter import ttk
    window=tk.Tk();window.title('Song_Record — 베타 서명키 생성·복구 보관');window.geometry('760x440')
    ttk.Label(window,text='베타 앱 서명키 · 노트북 암호화 보관',font=('Malgun Gothic',15)).pack(pady=15)
    ttk.Label(window,text='새 베타 앱에만 사용하는 키입니다. 기존 검증 앱·녹음은 보존합니다.\n키는 Windows 계정으로 암호화하고 복구 암호로 보호된 복구 파일을 함께 만듭니다.\n이 창은 AWS/Google/카카오로 키를 보내거나 앱을 배포하지 않습니다.',justify='center').pack(pady=8)
    entries=[]
    for label in ['새 복구 암호 (추측하기 어려운 16자 이상 · 별도 안전하게 보관)','복구 암호 확인']:
        ttk.Label(window,text=label).pack(anchor='w',padx=24)
        entry=ttk.Entry(window,show='*');entry.pack(fill='x',padx=24,pady=6);entries.append(entry)
    consent=tk.BooleanVar(value=False)
    ttk.Checkbutton(window,text='새 베타 서명키 생성·암호화 보관을 허용하고 복구 암호를 별도 보관합니다.',variable=consent).pack(pady=10)
    status=tk.StringVar(value='암호·키·등록 화면은 채팅에 보내지 마세요. 아직 실제 키는 생성하지 않았습니다.')
    ttk.Label(window,textvariable=status,wraplength=710).pack(pady=8)
    def submit():
        button.config(state='disabled')
        try:
            if not consent.get() or entries[0].get()!=entries[1].get():raise SigningError('CONSENT_AND_MATCH_REQUIRED')
            create(entries[0].get(),approved=True)
            for entry in entries:entry.delete(0,'end')
            status.set('베타 서명키 생성·Windows 암호화·복구 암호 검사 완료 · 복구 파일 외부 사본은 아직 없습니다.')
        except SigningError as error:
            messages={'EXISTING_SIGNING_DIRECTORY_PRESERVED':'기존 키 보관함이 있어 덮어쓰지 않았습니다. AI에게 상태 문구만 알려 주세요.','CONSENT_AND_MATCH_REQUIRED':'생성 허용 체크와 두 암호 일치를 확인해 주세요.','RECOVERY_PHRASE_REQUIRED':'복구 암호는 16자 이상 입력해 주세요.'}
            status.set(messages.get(str(error),'생성 확인 실패. 키·암호는 출력하지 않았습니다. AI에게 상태 문구만 알려 주세요.'))
        except Exception:status.set('생성 확인 실패. 키·암호는 출력하지 않았습니다.')
        finally:button.config(state='normal')
    button=ttk.Button(window,text='새 베타 서명키 생성·암호화 보관',command=submit);button.pack(pady=8)
    window.report_callback_exception=lambda *args:status.set('처리 실패. 비밀값은 기록하지 않았습니다.')
    window.mainloop()


if __name__=='__main__':gui()
