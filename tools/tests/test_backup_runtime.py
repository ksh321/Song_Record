import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import backup_runtime as runtime
from backup_store import BackupError


class RuntimeTests(unittest.TestCase):
    def test_failure_never_erases_latest_good_point_or_leaks_exception(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder);previous={'status':'PASS','day':'2026-10-01'}
            (path/'latest.json').write_text(json.dumps(previous),encoding='utf-8')
            with patch.object(runtime,'DIRECTORY',path),patch.object(runtime,'_secure'),patch.object(runtime.runtime,'state',side_effect=RuntimeError('synthetic private error content')):
                with self.assertRaises(BackupError):runtime.once()
            self.assertEqual(json.loads((path/'latest.json').read_text()),previous)
            status=json.loads((path/'status.json').read_text())
            self.assertEqual(status['status'],'FAIL');self.assertEqual(status['code'],'BACKUP_UNCONFIRMED')
            self.assertNotIn('synthetic private',(path/'status.json').read_text())

    def test_known_failure_keeps_precise_fixed_diagnostic(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)
            with patch.object(runtime,'DIRECTORY',path),patch.object(runtime,'_secure'),patch.object(runtime.runtime,'state',side_effect=BackupError('SNAPSHOT_LOCK_EXPIRED')):
                with self.assertRaises(BackupError):runtime.once()
            self.assertEqual(json.loads((path/'status.json').read_text())['code'],'SNAPSHOT_LOCK_EXPIRED')

    def test_output_limit_kills_process_instead_of_retaining_large_snapshot(self):
        with self.assertRaises(BackupError):runtime.bounded([sys.executable,'-c','print("x"*10000)'],limit=256)


if __name__=='__main__':unittest.main()
