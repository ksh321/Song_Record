import sys
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from backup_credentials import check_scope
from backup_store import BACKUP_BUCKET, BackupError


class ScopeTests(unittest.TestCase):
    def check(self, broad=False, application_delete=False):
        class Transport:
            def __init__(self, access, secret, bucket):
                self.access, self.bucket = access, bucket; self.objects={}
            def request(self, method, key='', data=b'', query=None):
                if self.access=='a'*32:
                    return (200 if self.bucket==BACKUP_BUCKET or broad else 403), b''
                return (204 if method=='DELETE' and application_delete else 403), b''
            def put_verified(self, key, data):self.objects[key]=data
            def get(self,key):return self.objects.get(key)
            def delete(self,key):self.objects.pop(key,None)
        with patch('backup_credentials.R2',Transport),patch('backup_credentials.load',return_value=('c'*32,'d'*64)):
            check_scope('a'*32,'b'*64)

    def test_narrow_backup_and_denied_application_scope(self):self.check()
    def test_backup_key_reaching_source_bucket_rejected(self):
        with self.assertRaises(BackupError):self.check(broad=True)
    def test_application_delete_permission_rejected_even_if_list_denied(self):
        with self.assertRaises(BackupError):self.check(application_delete=True)


if __name__=='__main__':unittest.main()
