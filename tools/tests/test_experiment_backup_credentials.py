import base64
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import experiment_backup_credentials as credentials


class ExperimentBackupCredentialsTests(unittest.TestCase):
    def crypt(self, data, role, decrypt=False):
        self.assertEqual(role,'experiment.backup')
        return data[4:] if decrypt else b'ENC:'+data

    def test_new_registration_and_roll_preserve_master_and_instance(self):
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(credentials,'DIRECTORY',Path(directory)), \
             patch.object(credentials,'_secure'),patch.object(credentials,'_crypt',side_effect=self.crypt), \
             patch.object(credentials,'check_scope',return_value=Mock(get=Mock(return_value=None))):
            phrase='synthetic-long-recovery-phrase'
            credentials.register('a'*32,'b'*64,phrase,phrase)
            first=credentials.load()
            credentials.register('c'*32,'d'*64,phrase,phrase)
            second=credentials.load()
            self.assertEqual(first['master'],second['master']);self.assertEqual(first['instance'],second['instance'])
            self.assertEqual(second['access'],'c'*32)
            self.assertNotIn(phrase,(Path(directory)/'credentials.dpapi').read_text())
            self.assertEqual(credentials.recovery_unwrap(base64.b64decode(second['recovery']),phrase),base64.b64decode(second['master']))

    def test_existing_remote_catalog_without_local_master_is_never_reinitialized(self):
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(credentials,'DIRECTORY',Path(directory)),patch.object(credentials,'_secure'), \
             patch.object(credentials,'check_scope',return_value=Mock(get=Mock(return_value=b'existing'))):
            with self.assertRaisesRegex(credentials.BackupError,'EXISTING_BACKUP_RECOVERY_REQUIRED'):
                credentials.register('a'*32,'b'*64,'synthetic-long-phrase','synthetic-long-phrase')
            self.assertFalse((Path(directory)/'credentials.dpapi').exists())

    def test_new_key_scope_rejects_access_to_previous_backup(self):
        own=Mock();own.request.return_value=(200,b'')
        denied=Mock();denied.request.return_value=(403,b'')
        def transport(access,secret,bucket):
            return own if bucket in (credentials.BUCKET,'song-record-staging-backup') else denied
        with patch.object(credentials,'R2',side_effect=transport),patch.object(credentials,'EncryptedStore') as store:
            with self.assertRaisesRegex(credentials.BackupError,'EXPERIMENT_BACKUP_KEY_TOO_BROAD'):
                credentials.check_scope('a'*32,'b'*64)
            store.assert_not_called()
