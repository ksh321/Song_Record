import importlib.util,json,sys,tempfile,types,unittest
from pathlib import Path
from unittest.mock import Mock,patch
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'infra/experiment'),str(ROOT/'tools')]
spec=importlib.util.spec_from_file_location('experiment_ledger',ROOT/'infra/experiment/ledger.py')
ledger=importlib.util.module_from_spec(spec);spec.loader.exec_module(ledger)

class ExperimentLedgerTests(unittest.TestCase):
    def exercise(self,pending):
        source={'entries':[],'pending':pending}
        mirror={'status':'PASS','observed_utc':'2026-10-15T01:00:00+00:00','entries':0,'acknowledged':0}
        with tempfile.TemporaryDirectory() as folder,patch.object(ledger,'DIRECTORY',Path(folder)),patch.object(ledger.os,'getuid',return_value=0,create=True),patch.dict(sys.modules,{'fcntl':types.SimpleNamespace(flock=Mock(),LOCK_EX=1,LOCK_NB=2)}),patch.object(ledger,'operator',return_value=json.dumps(source).encode()),patch.object(ledger,'credentials',return_value=({'access':'synthetic','secret':'synthetic','bucket':'synthetic','instance':'synthetic'},b'x'*32,b'')),patch.object(ledger,'R2'),patch.object(ledger,'EncryptedStore'),patch.object(ledger,'mirror_ledger',side_effect=lambda *args:dict(mirror)) as call:
            first=ledger.once();second=ledger.once()
            self.assertFalse(first['unchanged_remote_reused'])
            self.assertEqual(call.call_count,2 if pending else 1)
            self.assertEqual(second['unchanged_remote_reused'],not bool(pending))
    def test_unchanged_acknowledged_outbox_reuses_only_recent_full_remote_check(self):self.exercise([])
    def test_pending_ack_always_runs_verified_remote_mirror(self):self.exercise([{'id':'synthetic-pending'}])

if __name__=='__main__':unittest.main()
