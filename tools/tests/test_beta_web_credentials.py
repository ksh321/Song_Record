import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import beta_web_credentials as web
from r2_vault import _crypt


class WebCredentialTests(unittest.TestCase):
    def record(self):return {'scope':web.SCOPE,'enabled':False,'origin':web.ORIGIN,'google_client_id':'660802266773-syntheticweb.apps.googleusercontent.com','kakao_rest_key':'1'*32,'kakao_client_secret':'synthetic-secret-value','rate_secret':'2'*64}

    def public(self):return {'scope':'song_record_experiment_web_public:v1','origin':web.ORIGIN,'google_client_id':self.record()['google_client_id'],'kakao_rest_fingerprint':web.registration_fingerprint(self.record()['kakao_rest_key'])}

    def test_wrong_scope_origin_and_missing_secret_are_rejected(self):
        for key,value in [('scope','song_record_experiment_application:v1'),('origin','https://other.example'),('enabled','true'),('google_client_id','other-project.apps.googleusercontent.com'),('kakao_client_secret',''),('rate_secret','short')]:
            record=self.record();record[key]=value
            with self.subTest(field=key),self.assertRaises(web.WebCredentialError):web.validate(record)
        record=self.record();record['extra']='injected'
        with self.assertRaises(web.WebCredentialError):web.validate(record)

    def test_invalid_or_encryption_failure_preserves_existing_ciphertext(self):
        with tempfile.TemporaryDirectory() as folder:
            folder=Path(folder);path=folder/'credentials.dpapi';path.write_bytes(b'old-encrypted-record')
            with patch.object(web,'_crypt',side_effect=OSError('synthetic failure')):
                with self.assertRaises(web.WebCredentialError):web.register('1'*32,'synthetic-secret-value',self.public(),folder)
            self.assertEqual(path.read_bytes(),b'old-encrypted-record')
            with self.assertRaises(web.WebCredentialError):web.register('1'*32,'',self.public(),folder)
            self.assertEqual(path.read_bytes(),b'old-encrypted-record')

    def test_real_windows_role_entropy_separates_web_from_application(self):
        raw=json.dumps(self.record()).encode();encrypted=_crypt(raw,web.ROLE)
        self.assertEqual(_crypt(encrypted,web.ROLE,True),raw)
        with self.assertRaises(Exception):_crypt(encrypted,'experiment.application',True)
        corrupted=bytearray(encrypted);corrupted[-1]^=1
        with self.assertRaises(Exception):_crypt(bytes(corrupted),web.ROLE,True)

    def test_oversized_record_fails_before_decryption(self):
        with tempfile.TemporaryDirectory() as folder,patch.object(web,'_crypt') as crypt:
            folder=Path(folder);(folder/'credentials.dpapi').write_bytes(b'x'*16385)
            with self.assertRaises(web.WebCredentialError):web.load(folder)
            crypt.assert_not_called()

    def test_other_well_formed_rest_key_rejected_before_encryption(self):
        with tempfile.TemporaryDirectory() as folder,patch.object(web,'_crypt') as crypt:
            folder=Path(folder);path=folder/'credentials.dpapi';path.write_bytes(b'existing-encrypted-record')
            with self.assertRaisesRegex(web.WebCredentialError,'WEB_KEY_DOES_NOT_MATCH_PREPARED_REGISTRATION'):
                web.register('9'*32,'synthetic-secret-value',self.public(),folder)
            crypt.assert_not_called()
            self.assertEqual(path.read_bytes(),b'existing-encrypted-record')

    def test_missing_expected_registration_cannot_accept_a_key(self):
        public=self.public();del public['kakao_rest_fingerprint']
        with tempfile.TemporaryDirectory() as folder,patch.object(web,'_crypt') as crypt:
            with self.assertRaisesRegex(web.WebCredentialError,'WEB_KEY_DOES_NOT_MATCH_PREPARED_REGISTRATION'):
                web.register('1'*32,'synthetic-secret-value',public,Path(folder))
            crypt.assert_not_called()

    def test_matching_registration_roundtrips_in_windows_encryption(self):
        with tempfile.TemporaryDirectory() as folder:
            folder=Path(folder)
            result=web.register('1'*32,'synthetic-secret-value',self.public(),folder)
            restored=web.load(folder)
            self.assertEqual(result['status'],'REGISTERED_ENCRYPTED_DISABLED')
            self.assertEqual(restored['kakao_rest_key'],'1'*32)
            self.assertFalse(restored['enabled'])


if __name__=='__main__':unittest.main()
