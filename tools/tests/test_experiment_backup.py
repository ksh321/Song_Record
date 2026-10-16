import importlib.util
import json
from pathlib import Path
import sys
import unittest
import tempfile
from unittest.mock import Mock, patch

ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'infra/experiment'),str(ROOT/'tools')]
spec=importlib.util.spec_from_file_location('experiment_backup',ROOT/'infra/experiment/backup.py')
backup=importlib.util.module_from_spec(spec);spec.loader.exec_module(backup)


class ExperimentBackupTests(unittest.TestCase):
    def test_isolated_source_cannot_fall_back_to_shared_credentials(self):
        with tempfile.TemporaryDirectory() as folder,patch.object(backup,'R2') as transport:
            vault=Path(folder);(vault/'application-storage.json').write_text(json.dumps({'scope':'experiment','final_bucket':'song-record-experiment-final'}))
            (vault/'r2-staging.json').write_text('old shared credentials must not be read')
            with self.assertRaises(FileNotFoundError):backup.source_transport(vault)
            transport.assert_not_called()
            roles={role:{'access':'synthetic-'+role,'secret':'synthetic'} for role in ['experiment.api','experiment.worker','experiment.playback']}
            (vault/'r2-experiment.json').write_text(json.dumps({'scope':'song_record_experiment_application:v1','roles':roles}))
            backup.source_transport(vault)
            self.assertEqual(transport.call_args.args,('synthetic-experiment.playback','synthetic','song-record-experiment-final'))
    def test_wrong_compose_database_is_rejected_before_credentials_or_snapshot(self):
        with patch.object(backup,'bounded',return_value=b'song-record-validation\n') as run:
            with self.assertRaisesRegex(backup.BackupError,'EXPERIMENT_DATABASE_SCOPE_REJECTED'):
                backup.snapshot()
            self.assertEqual(run.call_count,1)

    def test_new_empty_catalog_mirror_is_verified_without_fake_ack(self):
        store=Mock();store.get.return_value=None;store.transport.list_objects.return_value=[]
        ledger=Mock();ledger.merge.return_value=[]
        ledger.prune.return_value={'removed_points':0,'removed_files':0,'absent_owners':[]}
        with patch.object(backup,'Ledger',return_value=ledger), \
             patch.object(backup,'operator',return_value=b'{"entries":[],"pending":[]}') as operator:
            self.assertEqual(backup.mirror_ledger(store,'synthetic-instance')['acknowledged'],0)
            self.assertEqual(operator.call_count,1)

    def test_unclassified_object_prevents_first_catalog_publication(self):
        store=Mock();store.get.return_value=None
        store.transport.list_objects.return_value=[{'key':'operational/v1/unknown.enc'}]
        ledger=Mock();ledger.merge.return_value=[]
        with patch.object(backup,'Ledger',return_value=ledger), \
             patch.object(backup,'operator',return_value=b'{"entries":[],"pending":[]}'):
            with self.assertRaisesRegex(backup.BackupError,'BACKUP_UNKNOWN_ARTIFACTS'):
                backup.mirror_ledger(store,'synthetic-instance')
            ledger.prune.assert_not_called()
