import copy
from pathlib import Path
import sys,unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import build_beta as build


class BuildBetaTests(unittest.TestCase):
    def test_only_explicit_staging_https_and_public_provider_fields(self):
        row={'APP_ENV':'staging','API_BASE_URL':'https://example.test','GOOGLE_SERVER_CLIENT_ID':'660802266773-example.apps.googleusercontent.com','KAKAO_NATIVE_APP_KEY':'1'*32}
        build.validate_defines(row)
        for key,value in [('APP_ENV','prod'),('API_BASE_URL','http://example.test'),('API_BASE_URL','https://localhost'),('API_BASE_URL','https://example.test/v1'),('API_BASE_URL','https://user:password@example.test'),('GOOGLE_SERVER_CLIENT_ID','wrong'),('R2_SECRET','unexpected')]:
            changed=copy.deepcopy(row);changed[key]=value
            with self.subTest(field=key),self.assertRaises(build.BuildError):build.validate_defines(changed)

    def test_artifact_must_be_beta_with_expected_certificate_and_sdk(self):
        signature='Signer #1 certificate SHA-256 digest: '+'a'*64+'\n'
        badging="package: name='com.ksh321.songrecord.beta' versionCode='1' versionName='1.0.0'\nsdkVersion:'24'\ntargetSdkVersion:'36'\n"
        self.assertEqual(build.verify_metadata(signature,badging,'a'*64)['application_id'],'com.ksh321.songrecord.beta')
        for sig,bad in [(signature,badging.replace('.beta','.staging')),(signature,badging.replace("'24'","'23'")),(signature,badging.replace("'36'","'35'")),(signature.replace('a'*64,'b'*64),badging),(signature+signature,badging)]:
            with self.assertRaises(build.BuildError):build.verify_metadata(sig,bad,'a'*64)


if __name__=='__main__':unittest.main()
