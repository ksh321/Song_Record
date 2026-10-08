"""Current-user Windows DPAPI storage. No CLI or logging of decrypted values."""
import ctypes
from ctypes import wintypes
import json
import os
from pathlib import Path
import subprocess
import uuid
DIRECTORY=Path(__file__).resolve().parents[1]/'.local/workflow/cloudflare/credentials'
ROLES=('dev.api','dev.worker')
class VaultError(Exception): pass
class Blob(ctypes.Structure):
    _fields_=[('size',wintypes.DWORD),('data',ctypes.POINTER(ctypes.c_ubyte))]
def _role(role):
    if role not in ROLES: raise VaultError('Development credentials only')
def _crypt(data,role,decrypt=False):
    _role(role)
    if os.name!='nt': raise VaultError('Windows account encryption required')
    source=ctypes.create_string_buffer(data);entropy=ctypes.create_string_buffer(('Song_Record:R2:v1:'+role).encode())
    incoming=Blob(len(data),ctypes.cast(source,ctypes.POINTER(ctypes.c_ubyte)))
    extra=Blob(len(entropy.value),ctypes.cast(entropy,ctypes.POINTER(ctypes.c_ubyte)));outgoing=Blob()
    crypt32=ctypes.WinDLL('crypt32',use_last_error=True);kernel32=ctypes.WinDLL('kernel32',use_last_error=True)
    kernel32.LocalFree.argtypes=[ctypes.c_void_p];kernel32.LocalFree.restype=ctypes.c_void_p
    function=crypt32.CryptUnprotectData if decrypt else crypt32.CryptProtectData
    function.argtypes=[ctypes.POINTER(Blob),ctypes.c_void_p if decrypt else wintypes.LPCWSTR,ctypes.POINTER(Blob),ctypes.c_void_p,ctypes.c_void_p,wintypes.DWORD,ctypes.POINTER(Blob)]
    function.restype=wintypes.BOOL
    try:
        # UI forbidden, current-user scope; never CRYPTPROTECT_LOCAL_MACHINE.
        if not function(ctypes.byref(incoming),None if decrypt else 'Song_Record development R2',ctypes.byref(extra),None,None,1,ctypes.byref(outgoing)):
            raise VaultError('Credential encryption unavailable')
        return ctypes.string_at(outgoing.data,outgoing.size)
    finally:
        ctypes.memset(source,0,len(source))
        if outgoing.data:
            ctypes.memset(outgoing.data,0,outgoing.size);kernel32.LocalFree(outgoing.data)
def _secure(directory):
    if os.name!='nt': raise VaultError('Windows account encryption required')
    directory.mkdir(parents=True,exist_ok=True)
    identity=subprocess.run(['whoami','/user','/fo','csv','/nh'],capture_output=True,check=True)
    import re
    match=re.search(rb'S-1-5-\d+(?:-\d+)+',identity.stdout)
    if not match: raise VaultError('Credential directory protection unavailable')
    sid=match.group().decode('ascii')
    subprocess.run(['icacls',str(directory),'/inheritance:r','/grant:r','*'+sid+':(OI)(CI)F','*S-1-5-18:(OI)(CI)F'],capture_output=True,check=True)
def exists(role,directory=DIRECTORY):
    _role(role);return (directory/(role+'.dpapi')).is_file()
def save(role,access,secret,directory=DIRECTORY):
    _role(role);temporary=None
    try:
        from r2_credentials import validate
        validate(access,secret)
        encrypted=_crypt(json.dumps({'version':1,'role':role,'access':access,'secret':secret}).encode(),role)
        _secure(directory)
        temporary=directory/(uuid.uuid4().hex+'.tmp')
        with temporary.open('xb') as stream:
            stream.write(encrypted);stream.flush();os.fsync(stream.fileno())
        temporary.replace(directory/(role+'.dpapi'))
    except Exception: raise VaultError('Credential registration failed; existing registration preserved') from None
    finally:
        if temporary is not None: temporary.unlink(missing_ok=True)
def load(role,directory=DIRECTORY):
    _role(role)
    try:
        with (directory/(role+'.dpapi')).open('rb') as stream: encrypted=stream.read(16385)
        if len(encrypted)>16384: raise VaultError('Invalid credential record')
        record=json.loads(_crypt(encrypted,role,True))
        if record.get('version')!=1 or record.get('role')!=role: raise VaultError('Invalid credential record')
        from r2_credentials import validate
        validate(record['access'],record['secret'])
        return record['access'],record['secret']
    except Exception: raise VaultError('Saved credentials unavailable; register again') from None
