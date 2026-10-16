import json
from pathlib import Path
import os,sys,tempfile,unittest
from unittest.mock import Mock,patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import experiment_credentials as c

class ExperimentCredentialsTests(unittest.TestCase):
    @unittest.skipUnless(os.name=='nt','Windows CurrentUser DPAPI required')
    def test_real_application_bundle_entropy_rejects_backup_and_tampering(self):
        from r2_vault import VaultError
        raw=os.urandom(64);cipher=c._crypt(raw,c.ENTROPY)
        self.assertEqual(c._crypt(cipher,c.ENTROPY,True),raw)
        with self.assertRaises(VaultError):c._crypt(cipher,'experiment.backup',True)
        damaged=bytearray(cipher);damaged[-1]^=1
        with self.assertRaises(VaultError):c._crypt(bytes(damaged),c.ENTROPY,True)
    def pairs(self):return {role:(str(i+1)*32,'a'*64) for i,role in enumerate(c.ROLES)}
    def row(self):return {'scope':c.SCOPE,'roles':{r:dict(zip(('access','secret'),p)) for r,p in self.pairs().items()}}
    def crypt(self,data,role,decrypt=False):
        self.assertEqual(role,'experiment.application');return data[4:] if decrypt else b'ENC:'+data
    def test_all_roles_and_separate_keys_are_required(self):
        c.validate_bundle(self.row())
        row=self.row();row['roles']['experiment.worker']=row['roles']['experiment.api']
        with self.assertRaises(c.BackupError):c.validate_bundle(row)
        row=self.row();row['scope']='song_record_validation'
        with self.assertRaises(c.BackupError):c.validate_bundle(row)
    def test_unexpected_write_permission_cleans_only_its_own_probe_then_fails(self):
        t=Mock();t.request.return_value=(200,b'');t.get.return_value=b'Song_Record experiment synthetic credential probe'
        with self.assertRaises(c.BackupError):c.probe_write(t,False)
        key=t.delete.call_args.args[0]
        self.assertTrue(key.startswith('operational/v1/credential-probes/'))
        self.assertEqual(t.request.call_args.args[1],key)
    def test_existing_bucket_delete_permission_is_rejected_even_when_list_denied(self):
        t=Mock();t.request.side_effect=[(403,b''),(204,b'')]
        with patch.object(c,'R2',return_value=t):
            with self.assertRaisesRegex(c.BackupError,'EXPERIMENT_KEY_CAN_DELETE_EXISTING_BUCKET'):c.check(self.row())
        t.delete.assert_not_called()
    def test_bad_registration_does_not_replace_existing_bundle(self):
        with tempfile.TemporaryDirectory() as directory,patch.object(c,'DIRECTORY',Path(directory)),patch.object(c,'_secure'),patch.object(c,'_crypt',side_effect=self.crypt),patch.object(c,'check',side_effect=[True,c.BackupError('NETWORK_UNCONFIRMED')]):
            target=Path(directory)/'credentials.dpapi';target.write_bytes(b'existing-encrypted-bundle')
            with self.assertRaises(c.BackupError):c.register(self.pairs())
            self.assertEqual(target.read_bytes(),b'existing-encrypted-bundle')
            self.assertFalse((Path(directory)/'registration.json').exists())
    def test_new_bundle_roundtrip_receipt_has_no_credentials(self):
        with tempfile.TemporaryDirectory() as directory,patch.object(c,'DIRECTORY',Path(directory)),patch.object(c,'_secure'),patch.object(c,'_crypt',side_effect=self.crypt),patch.object(c,'check',return_value=True):
            c.register(self.pairs());self.assertEqual(c.load(),self.row())
            report=(Path(directory)/'registration.json').read_text()
            self.assertNotIn('a'*64,report);self.assertNotIn('access',report)

if __name__=='__main__':unittest.main()
