import hashlib,importlib.util,sys,unittest
from pathlib import Path
from unittest.mock import Mock
ROOT=Path(__file__).resolve().parents[2];sys.path[:0]=[str(ROOT/'infra/experiment'),str(ROOT/'tools')]
spec=importlib.util.spec_from_file_location('experiment_audit',ROOT/'infra/experiment/audit.py')
audit=importlib.util.module_from_spec(spec);spec.loader.exec_module(audit)

class ExperimentAuditTests(unittest.TestCase):
    def test_missing_extra_and_corrupt_objects_are_reported_without_deletion(self):
        reader=Mock();reader.get.return_value=b'changed'
        result=audit.compare([('missing',1,'a'*64),('corrupt',7,'b'*64)],[{'key':'corrupt','size':7},{'key':'unreferenced','size':1}],[],reader)
        self.assertEqual(result['status'],'WARNING');self.assertEqual(result['missing_files'],1)
        self.assertEqual(result['unreferenced_objects'],1);self.assertEqual(result['invalid_files'],1)
        reader.delete.assert_not_called();reader.put_verified.assert_not_called()
        self.assertEqual(result['objects_deleted'],0);self.assertFalse(result['upload_gate_changed'])
    def test_verified_read_only_files_are_not_a_physical_playback_claim(self):
        reader=Mock();reader.get.return_value=b'synthetic'
        result=audit.compare([('recording',9,hashlib.sha256(b'synthetic').hexdigest())],[{'key':'recording','size':9}],[],reader)
        self.assertEqual(result['status'],'PASS');self.assertEqual(result['verified_files'],1)
        self.assertFalse(result['release_ready']);self.assertFalse(result['worker_started'])

if __name__=='__main__':unittest.main()
