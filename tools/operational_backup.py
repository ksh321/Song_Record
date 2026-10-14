"""Validation-only encrypted daily DB/final-object backup. No restore or source deletion."""
import datetime as dt
import hashlib
import json
import re
import time
import uuid
from backup_store import BackupError, MAX_BYTES

PREFIX = 'operational/v1/'
INDEX = PREFIX + 'catalog.enc'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':')).encode()


def check_file(row):
    try:
        owner, recording, generation = (str(uuid.UUID(row[k])) for k in ('owner', 'recording', 'generation'))
        if any(uuid.UUID(x).int == 0 for x in (owner, recording, generation)):
            raise ValueError()
        if row['key'] != f'recordings/{owner}/{recording}/{generation}.m4a':
            raise ValueError()
        if not re.fullmatch(r'[0-9a-f]{64}', row['sha256']) or type(row['size']) is not int or not 1 <= row['size'] <= 6291456:
            raise ValueError()
    except Exception:
        raise BackupError('INVALID_DB_FILE_LIST') from None
    return PREFIX + 'files/' + digest(encoded([owner, recording, generation, row['sha256']])) + '.enc'


class Backup:
    def __init__(self, store, source, snapshot, instance):
        self.store, self.source, self.snapshot, self.instance = store, source, snapshot, instance

    def catalog(self):
        data = self.store.get(INDEX)
        if data is None:
            return {'schema': 1, 'instance': self.instance, 'environment': 'staging', 'points': []}
        try:
            row = json.loads(data)
            if row['schema'] != 1 or row['instance'] != self.instance or row['environment'] != 'staging':
                raise ValueError()
            points = row['points']
            if len(points) > 7 or len({p['day'] for p in points}) != len(points):
                raise ValueError()
            for p in points:
                uuid.UUID(p['id'])
                dt.date.fromisoformat(p['day'])
                if not re.fullmatch(r'[0-9a-f]{64}', p['manifest_hash']):
                    raise ValueError()
            pending = row.get('pending_prune', [])
            if len(pending) > 100 or any(str(uuid.UUID(x)) in {p['id'] for p in points} for x in pending):
                raise ValueError()
            return row
        except Exception:
            raise BackupError('CATALOG_INVALID') from None

    def prune(self, catalog):
        pending = catalog.get('pending_prune', [])
        for ident in pending:
            old = PREFIX + 'points/' + str(uuid.UUID(ident)) + '/'
            self.store.delete(old + 'database.enc')
            self.store.delete(old + 'manifest.enc')
        if pending:
            catalog['pending_prune'] = []
            self.store.put(INDEX, encoded(catalog))

    def verify(self, point):
        base = PREFIX + 'points/' + str(uuid.UUID(point['id'])) + '/'
        manifest = self.store.get(base + 'manifest.enc')
        if manifest is None or digest(manifest) != point['manifest_hash']:
            raise BackupError('POINT_MANIFEST_INVALID')
        try:
            row = json.loads(manifest)
            if row['instance'] != self.instance or row['day'] != point['day'] or row['schema'] != 1:
                raise ValueError()
            sql = self.store.get(base + 'database.enc')
            if sql is None or digest(sql) != row['database_sha256']:
                raise ValueError()
            files = row['files']
            if len(files) > 100000 or len({f['key'] for f in files}) != len(files):
                raise ValueError()
            for file in files:
                data = self.store.get(check_file(file))
                if data is None or len(data) != file['size'] or digest(data) != file['sha256']:
                    raise ValueError()
        except BackupError:
            raise
        except Exception:
            raise BackupError('POINT_CONTENT_INVALID') from None
        return row

    def once(self, now=None):
        now = now or dt.datetime.now(dt.timezone.utc)
        day = now.date().isoformat()
        catalog = self.catalog()
        self.prune(catalog)
        existing = next((p for p in catalog['points'] if p['day'] == day), None)
        if existing:
            for point in catalog['points']:
                self.verify(point)
            row = self.verify(existing)
            return {'status': 'PASS', 'day': day, 'files': len(row['files']), 'reused_point': True, 'points': len(catalog['points'])}
        # Snapshot implementation returns bytes and the exact matching DB file list.
        sql, files = self.snapshot()
        if not sql or len(sql) > MAX_BYTES or len(files) > 100000:
            raise BackupError('SNAPSHOT_LIMIT')
        if len({f['key'] for f in files}) != len(files):
            raise BackupError('DUPLICATE_FILE_LIST')
        copied = 0
        for file in files:
            path = check_file(file)
            cached = self.store.get(path)
            if cached is None:
                cached = self.source.get(file['key'])
                if cached is None or len(cached) != file['size'] or digest(cached) != file['sha256']:
                    raise BackupError('SOURCE_FILE_MISSING_OR_CHANGED')
                self.store.put(path, cached)
                copied += 1
            if len(cached) != file['size'] or digest(cached) != file['sha256']:
                raise BackupError('INCREMENTAL_COPY_INVALID')
        ident = str(uuid.uuid4())
        base = PREFIX + 'points/' + ident + '/'
        self.store.put(base + 'database.enc', sql)
        manifest = {'schema': 1, 'instance': self.instance, 'day': day, 'created_utc': now.isoformat(),
                    'database_sha256': digest(sql), 'files': files, 'snapshot_method': 'mysql_global_read_lock_innodb'}
        raw = encoded(manifest)
        self.store.put(base + 'manifest.enc', raw)
        point = {'id': ident, 'day': day, 'manifest_hash': digest(raw)}
        self.verify(point)
        # No new PASS publication until all retained restore points remain verified.
        points = sorted(catalog['points'] + [point], key=lambda p: p['day'])
        retained, expired = points[-7:], points[:-7]
        for p in retained:
            self.verify(p)
        catalog['points'] = retained
        catalog['pending_prune'] = [p['id'] for p in expired]
        self.store.put(INDEX, encoded(catalog))
        # Only expired DB points owned by this catalog; active final copies never removed here.
        self.prune(catalog)
        return {'status': 'PASS', 'day': day, 'files': len(files), 'copied': copied,
                'points': len(retained), 'reused_point': False}
