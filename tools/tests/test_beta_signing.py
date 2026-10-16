"""All keys in these tests are synthetic and live only in temporary directories."""
import base64
import copy
from pathlib import Path
import sys,tempfile,unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import beta_signing as signing
from r2_vault import _crypt


class BetaSigningTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.record=signing._new_record();cls.phrase='synthetic recovery phrase for tests'

    def test_pkcs12_and_public_fingerprints_are_bound_to_same_certificate(self):
        signing.validate(self.record)
        for field in ['scope','application_id','alias','certificate_sha256','certificate_sha1','kakao_key_hash']:
            row=copy.deepcopy(self.record);row[field]='incorrect'
            with self.subTest(field=field),self.assertRaises(signing.SigningError):signing.validate(row)
        public=signing.public_record(self.record)
        self.assertNotIn('pkcs12',public);self.assertNotIn('store_password',public)

    def test_recovery_authenticates_password_and_tamper(self):
        sealed=signing.seal_recovery(self.record,self.phrase)
        self.assertEqual(signing.open_recovery(sealed,self.phrase),self.record)
        for data,phrase in [(sealed,'wrong recovery password'),(sealed[:-1]+bytes([sealed[-1]^1]),self.phrase),(b'SRSG1'+b'x'*65536,self.phrase)]:
            with self.assertRaises(signing.SigningError):signing.open_recovery(data,phrase)
        self.assertNotIn(self.record['store_password'].encode(),sealed)

    def test_explicit_creation_and_phrase_required_before_generating(self):
        with tempfile.TemporaryDirectory() as folder,patch.object(signing,'_new_record') as generate:
            target=Path(folder)/'beta-signing'
            for phrase,approved in [(self.phrase,False),('short',True)]:
                with self.assertRaises(signing.SigningError):signing.create(phrase,approved=approved,directory=target)
            generate.assert_not_called();self.assertFalse(target.exists())

    def test_existing_directory_preserved_without_generating_or_rotating(self):
        with tempfile.TemporaryDirectory() as folder,patch.object(signing,'_new_record') as generate:
            target=Path(folder)/'beta-signing';target.mkdir();(target/'existing').write_bytes(b'preserve')
            with self.assertRaises(signing.SigningError):signing.create(self.phrase,approved=True,directory=target)
            generate.assert_not_called();self.assertEqual((target/'existing').read_bytes(),b'preserve')

    def test_windows_roundtrip_role_isolation_and_no_plaintext_secret_file(self):
        with tempfile.TemporaryDirectory() as folder,patch.object(signing,'_new_record',return_value=self.record):
            target=Path(folder)/'beta-signing'
            result=signing.create(self.phrase,approved=True,directory=target)
            self.assertEqual(result['status'],'BETA_SIGNING_ENCRYPTED_RECOVERY_VERIFIED')
            self.assertEqual(signing.load(target),self.record)
            for path in target.iterdir():self.assertNotIn(self.record['store_password'].encode(),path.read_bytes())
            with self.assertRaises(Exception):_crypt((target/'signing.dpapi').read_bytes(),'experiment.web',True)
            with self.assertRaises(signing.SigningError):signing.create(self.phrase,approved=True,directory=target)

    def test_build_temporaries_removed_on_build_failure(self):
        with tempfile.TemporaryDirectory() as folder,patch.object(signing,'load',return_value=copy.deepcopy(self.record)):
            directory=Path(folder)/'beta-signing'
            with self.assertRaisesRegex(RuntimeError,'synthetic build failure'):
                with signing.build_files(directory) as (props,public):
                    self.assertTrue(props.is_file());self.assertEqual(public['application_id'],signing.PACKAGE)
                    self.assertIn('keyAlias=songrecord-beta',props.read_text())
                    temporary_parent=props.parent
                    raise RuntimeError('synthetic build failure')
            self.assertFalse(temporary_parent.exists())

    def test_oversized_ciphertext_rejected_before_decrypting(self):
        with tempfile.TemporaryDirectory() as folder,patch.object(signing,'_crypt') as crypt:
            target=Path(folder);(target/'signing.dpapi').write_bytes(b'x'*(signing.LIMIT+1))
            with self.assertRaises(signing.SigningError):signing.load(target)
            crypt.assert_not_called()

    def test_linked_parent_rejected_before_key_generation(self):
        with tempfile.TemporaryDirectory() as folder,patch.object(Path,'is_symlink',return_value=True),patch.object(signing,'_new_record') as generate:
            with self.assertRaisesRegex(signing.SigningError,'SIGNING_DIRECTORY_REJECTED'):
                signing.create(self.phrase,approved=True,directory=Path(folder)/'beta-signing')
            generate.assert_not_called()


if __name__=='__main__':unittest.main()
