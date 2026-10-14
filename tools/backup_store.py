"""Bounded R2 transport and authenticated encrypted backup objects. Never log responses."""
import datetime as dt
import hashlib
import hmac
import json
import os
import urllib.error
import urllib.parse
import urllib.request

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from r2_credentials import ACCOUNT

BACKUP_BUCKET = 'song-record-staging-backup'
FINAL_BUCKET = 'song-record-staging-dev-final'
MAX_BYTES = 256 * 1024 * 1024


class BackupError(Exception):
    """Fixed diagnostic, never attach raw transport or database output."""


def seal(key, data, scope):
    if len(key) != 32 or len(data) > MAX_BYTES:
        raise BackupError('ENCRYPTION_LIMIT')
    nonce = os.urandom(12)
    return b'SRB1' + nonce + AESGCM(key).encrypt(nonce, data, scope.encode('ascii'))


def unseal(key, data, scope):
    try:
        if not data.startswith(b'SRB1') or len(data) > MAX_BYTES + 32:
            raise ValueError()
        return AESGCM(key).decrypt(data[4:16], data[16:], scope.encode('ascii'))
    except Exception:
        raise BackupError('BACKUP_AUTHENTICATION_FAILED') from None


class R2:
    def __init__(self, access, secret, bucket):
        self.access, self.secret, self.bucket = access, secret, bucket
        self.host = ACCOUNT + '.r2.cloudflarestorage.com'
        self.client = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def request(self, method, key='', data=b'', query=None):
        # Account and bucket are explicit, redirects must never receive signed credentials.
        path = '/' + self.bucket + ('/' + urllib.parse.quote(key, safe='/~') if key else '')
        encoded = sorted((urllib.parse.quote(str(k), safe='~'), urllib.parse.quote(str(v), safe='~'))
                         for k, v in (query or {}).items())
        qs = '&'.join(k + '=' + v for k, v in encoded)
        now = dt.datetime.now(dt.timezone.utc)
        day, stamp = now.strftime('%Y%m%d'), now.strftime('%Y%m%dT%H%M%SZ')
        hashed = hashlib.sha256(data).hexdigest()
        names = 'host;x-amz-content-sha256;x-amz-date'
        canonical = '\n'.join([method, path, qs, f'host:{self.host}\nx-amz-content-sha256:{hashed}\nx-amz-date:{stamp}\n', names, hashed])
        scope = day + '/auto/s3/aws4_request'
        signing = ('AWS4' + self.secret).encode()
        for part in (day, 'auto', 's3', 'aws4_request'):
            signing = hmac.new(signing, part.encode(), hashlib.sha256).digest()
        signature = hmac.new(signing, ('AWS4-HMAC-SHA256\n' + stamp + '\n' + scope + '\n' + hashlib.sha256(canonical.encode()).hexdigest()).encode(), hashlib.sha256).hexdigest()
        headers = {'x-amz-date': stamp, 'x-amz-content-sha256': hashed,
                   'Authorization': f'AWS4-HMAC-SHA256 Credential={self.access}/{scope}, SignedHeaders={names}, Signature={signature}'}
        request = urllib.request.Request('https://' + self.host + path + ('?' + qs if qs else ''),
                                        data=data if method in ('PUT', 'POST') else None, headers=headers, method=method)
        # Suppress exception objects and raw HTTP bodies, which may contain credential IDs.
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, *args, **kwargs):
                return None
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
        try:
            with opener.open(request, timeout=45) as reply:
                body = reply.read(MAX_BYTES + 33)
                if len(body) > MAX_BYTES + 32:
                    raise BackupError('OBJECT_LIMIT')
                return reply.status, body
        except urllib.error.HTTPError as error:
            status = error.code
            error.close()
            return status, b''
        except BackupError:
            raise
        except Exception:
            raise BackupError('R2_TRANSPORT_FAILED') from None

    def get(self, key):
        status, data = self.request('GET', key)
        if status == 404:
            return None
        if status != 200:
            raise BackupError('R2_READ_FAILED')
        return data

    def put_verified(self, key, data):
        status, _ = self.request('PUT', key, data)
        if status != 200 or self.get(key) != data:
            raise BackupError('BACKUP_WRITE_VERIFICATION_FAILED')

    def delete(self, key):
        if not key.startswith('operational/v1/'):
            raise BackupError('BACKUP_DELETE_SCOPE')
        status, _ = self.request('DELETE', key)
        if status != 204:
            raise BackupError('BACKUP_DELETE_FAILED')


class EncryptedStore:
    def __init__(self, transport, key):
        self.transport, self.key = transport, key

    def get(self, path):
        data = self.transport.get(path)
        return None if data is None else unseal(self.key, data, path)

    def put(self, path, data):
        encrypted = seal(self.key, data, path)
        self.transport.put_verified(path, encrypted)
        if self.get(path) != data:
            raise BackupError('ENCRYPTED_READBACK_FAILED')

    def delete(self, path):
        self.transport.delete(path)
