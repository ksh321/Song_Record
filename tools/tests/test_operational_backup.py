import datetime as dt
import hashlib
import os
import sys
import unittest
import uuid
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from backup_store import EncryptedStore, BackupError, seal, unseal
from backup_credentials import recovery_wrap, recovery_unwrap
from operational_backup import Backup, INDEX, check_file


class Memory:
    def __init__(self):
        self.rows = {}; self.writes = []; self.deletes = []
    def get(self, key):
        return self.rows.get(key)
    def put_verified(self, key, data):
        self.rows[key] = data; self.writes.append(key)
    def delete(self, key):
        self.rows.pop(key, None); self.deletes.append(key)


class BackupTests(unittest.TestCase):
    def setUp(self):
        self.transport = Memory(); self.source = Memory()
        self.key = os.urandom(32); self.store = EncryptedStore(self.transport, self.key)
        self.data = b'synthetic audio'; ids = [str(uuid.uuid4()) for _ in range(3)]
        self.file = dict(zip(('owner','recording','generation'), ids))
        self.file.update(key=f'recordings/{ids[0]}/{ids[1]}/{ids[2]}.m4a', sha256=hashlib.sha256(self.data).hexdigest(), size=len(self.data))
        self.source.rows[self.file['key']] = self.data
        self.backup = Backup(self.store, self.source, lambda: (b'-- synthetic SQL', [self.file.copy()]), 'fixture-instance')
        self.day = dt.datetime(2026, 10, 1, tzinfo=dt.timezone.utc)

    def test_ciphertext_tamper_scope_and_wrong_key_rejected(self):
        value = seal(self.key, b'secret fixture', 'scope')
        self.assertNotIn(b'secret fixture', value)
        for key, data, scope in [(os.urandom(32), value, 'scope'), (self.key, value, 'other'),
                                 (self.key, value[:-1]+bytes([value[-1]^1]), 'scope')]:
            with self.assertRaises(BackupError): unseal(key, data, scope)

    def test_incremental_copies_reused_but_verified_and_daily_deduped(self):
        first = self.backup.once(self.day); second = self.backup.once(self.day + dt.timedelta(days=1))
        self.assertEqual((first['copied'], second['copied']), (1,0))
        calls = len(self.transport.writes)
        self.assertTrue(self.backup.once(self.day+dt.timedelta(days=1))['reused_point'])
        self.assertEqual(len(self.transport.writes), calls)
        self.assertEqual(sum(k.startswith('operational/v1/files/') for k in self.transport.rows), 1)

    def test_seven_points_retained_with_active_file_copy(self):
        for offset in range(8): self.backup.once(self.day+dt.timedelta(days=offset))
        self.assertEqual(len(self.backup.catalog()['points']), 7)
        self.assertEqual(len(self.transport.deletes), 2)
        self.assertIn(check_file(self.file), self.transport.rows)

    def test_interrupted_pruning_is_persisted_and_retried(self):
        for offset in range(7): self.backup.once(self.day+dt.timedelta(days=offset))
        original = self.store.delete
        self.store.delete = lambda path: (_ for _ in ()).throw(BackupError('failure'))
        with self.assertRaises(BackupError): self.backup.once(self.day+dt.timedelta(days=7))
        self.assertEqual(len(self.backup.catalog()['pending_prune']),1)
        self.store.delete = original
        self.assertTrue(self.backup.once(self.day+dt.timedelta(days=7))['reused_point'])
        self.assertEqual(self.backup.catalog()['pending_prune'],[])

    def test_missing_source_does_not_publish_success(self):
        self.source.rows.clear()
        with self.assertRaises(BackupError): self.backup.once(self.day)
        self.assertNotIn(INDEX, self.transport.rows)

    def test_wrong_hash_does_not_replace_valid_catalog(self):
        self.backup.once(self.day); catalog = self.transport.rows[INDEX]
        self.file['generation'] = str(uuid.uuid4())
        self.file['key'] = f"recordings/{self.file['owner']}/{self.file['recording']}/{self.file['generation']}.m4a"
        self.source.rows[self.file['key']] = b'wrong source'
        with self.assertRaises(BackupError): self.backup.once(self.day+dt.timedelta(days=1))
        self.assertEqual(self.transport.rows[INDEX], catalog)

    def test_corrupt_existing_copy_blocks_new_point(self):
        self.backup.once(self.day)
        self.transport.rows[check_file(self.file)] = b'corrupt'
        with self.assertRaises(BackupError): self.backup.once(self.day+dt.timedelta(days=1))

    def test_database_and_manifest_corruption_not_healthy(self):
        self.backup.once(self.day); point=self.backup.catalog()['points'][0]
        path=f"operational/v1/points/{point['id']}/database.enc"
        self.transport.rows[path]=seal(self.key,b'wrong SQL',path)
        with self.assertRaises(BackupError): self.backup.verify(point)

    def test_unsafe_or_temporary_path_rejected(self):
        for key in ('temporary/object','../recordings/object','recordings/wrong'):
            row={**self.file,'key':key}
            with self.assertRaises(BackupError): check_file(row)

    def test_wrong_instance_catalog_not_adopted(self):
        self.backup.once(self.day)
        other=Backup(self.store,self.source,self.backup.snapshot,'other')
        with self.assertRaises(BackupError): other.catalog()

    def test_duplicate_db_entries_rejected(self):
        self.backup.snapshot=lambda:(b'sql',[self.file,self.file])
        with self.assertRaises(BackupError): self.backup.once(self.day)

    def test_portable_recovery_and_wrong_phrase(self):
        wrapped=recovery_wrap(self.key,'fixture strong recovery phrase 12345')
        self.assertEqual(recovery_unwrap(wrapped,'fixture strong recovery phrase 12345'),self.key)
        with self.assertRaises(BackupError): recovery_unwrap(wrapped,'wrong phrase')


if __name__=='__main__': unittest.main()
