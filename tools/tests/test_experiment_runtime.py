import importlib.util
from pathlib import Path
import sys,unittest
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('isolated_runtime',ROOT/'infra/experiment/runtime.py')
runtime=importlib.util.module_from_spec(spec);spec.loader.exec_module(runtime)

class ExperimentRuntimeTests(unittest.TestCase):
    def test_observation_retention_is_explicit_thirty_days_and_worker_only(self):
        policy={'scope':'song_record_experiment_observation:v1','enabled':True,'retention_days':30}
        self.assertEqual(runtime.observation_settings('api',policy),{'songrecord.operations.retention.enabled':'false'})
        self.assertEqual(runtime.observation_settings('worker',policy),{'songrecord.operations.retention.enabled':'true'})
        self.assertEqual(runtime.observation_settings('worker',None),{'songrecord.operations.retention.enabled':'false'})
        for key,value in [('scope','prod'),('enabled','true'),('retention_days',90),('retention_days',True)]:
            invalid=dict(policy);invalid[key]=value
            with self.assertRaises(ValueError):runtime.observation_settings('worker',invalid)
    def test_worker_policy_cannot_enable_api_or_accept_string_flags(self):
        roles=self.roles();state={k:'synthetic' for k in ['db_password','tls_password','pagination','karaoke']}
        provider={k:'synthetic' for k in ['auth.google.enabled','auth.google.server-client-id','auth.kakao.enabled','auth.kakao.app-id','auth.kakao.native-app-key']}
        policy={'upload':True,'account_deletion':False}
        api=runtime.settings('api',state,roles,provider,'',b'',policy)
        worker=runtime.settings('worker',state,roles,provider,'',b'',policy)
        self.assertEqual(api['songrecord.upload.scheduling-enabled'],'false')
        self.assertEqual(worker['songrecord.upload.scheduling-enabled'],'true')
        self.assertEqual(worker['songrecord.account-deletion.worker.enabled'],'false')
        with self.assertRaises(ValueError):runtime.validate_policy({'upload':'false','account_deletion':False})
    def test_database_must_mount_existing_experiment_volume_and_match_database_user(self):
        row={'Config':{'Labels':{'com.docker.compose.project':'song-record-experiment'},'Env':['MYSQL_DATABASE=song_record_experiment','MYSQL_USER=song_record_experiment']},'Mounts':[{'Type':'volume','Name':'song-record-experiment_validation_db','Destination':'/var/lib/mysql'}]}
        runtime.verify_database(row)
        row['Mounts'][0]['Name']='user_developer_database'
        with self.assertRaises(ValueError):runtime.verify_database(row)
    def roles(self):return {'scope':'song_record_experiment_application:v1','roles':{role:{'access':str(i+1)*32,'secret':str(i+4)*64} for i,role in enumerate(sorted(runtime.ROLES))}}
    def test_only_three_separate_experiment_roles_are_accepted(self):
        runtime.validate_roles(self.roles())
        for scope in ['staging','prod','song_record_experiment_backup:v1']:
            row=self.roles();row['scope']=scope
            with self.assertRaises(ValueError):runtime.validate_roles(row)
        row=self.roles();row['roles']['experiment.api']=row['roles']['experiment.worker']
        with self.assertRaises(ValueError):runtime.validate_roles(row)
    def test_api_and_worker_cannot_receive_each_others_writer_secret(self):
        roles=self.roles();state={k:'synthetic-'+k for k in ['db_password','tls_password','pagination','karaoke']}
        provider={key:'synthetic' for key in ['auth.google.enabled','auth.google.server-client-id','auth.kakao.enabled','auth.kakao.app-id','auth.kakao.native-app-key']}
        for role,other in [('api','worker'),('worker','api')]:
            values=runtime.settings(role,state,roles,provider,'synthetic certificate',b'synthetic keystore')
            self.assertNotIn(roles['roles']['experiment.'+other]['secret'],values.values())
            self.assertNotIn('song-record-staging-dev-final',values.values())
            self.assertEqual(values['songrecord.storage.dev.final-bucket'],'song-record-experiment-final')
            self.assertEqual(values['songrecord.upload.scheduling-enabled'],'false')
            self.assertEqual(values['songrecord.deployment.storage-scope'],'experiment')
        with self.assertRaises(ValueError):runtime.settings('playback',state,roles,provider,'',b'')

class WebOwnershipSettingsTests(unittest.TestCase):
    def provider(self):
        return {'auth.google.enabled':'true','auth.google.server-client-id':'660802266773-native.apps.googleusercontent.com','auth.kakao.enabled':'true','auth.kakao.app-id':'1586938','auth.kakao.native-app-key':'1'*32}

    def web(self):
        return {'scope':'song_record_experiment_web:v1','enabled':True,'origin':'https://song-record-beta-ksh321.duckdns.org','google_client_id':'660802266773-web.apps.googleusercontent.com','kakao_rest_key':'2'*32,'kakao_client_secret':'synthetic-private-web-secret','rate_secret':'3'*64}

    def test_web_secrets_only_reach_api_and_native_audience_is_preserved(self):
        roles={'roles':{role:{'access':'synthetic-'+role,'secret':'synthetic-'+role} for role in runtime.ROLES}}
        state={k:'synthetic' for k in ['db_password','tls_password','pagination','karaoke']}
        for role in ['api','worker']:
            values=runtime.settings(role,state,roles,self.provider(),'',b'',web=self.web())
            self.assertEqual(values['auth.google.server-client-id'],self.provider()['auth.google.server-client-id'])
            if role=='api':self.assertEqual(values['account.deletion.web.kakao-client-secret'],self.web()['kakao_client_secret'])
            else:
                self.assertFalse(any(k.startswith('account.deletion.web.') for k in values))
                self.assertNotIn(self.web()['kakao_client_secret'],values.values())

    def test_absent_or_disabled_web_does_not_enable_or_inject_secrets(self):
        self.assertEqual(runtime.web_settings(None,self.provider()),{})
        row=self.web();row['enabled']=False
        self.assertEqual(runtime.web_settings(row,self.provider()),{'account.deletion.web.enabled':'false'})

    def test_explicit_beta_native_audience_preserves_original_and_rejects_arbitrary_provider_properties(self):
        roles={'roles':{role:{'access':'synthetic-'+role,'secret':'synthetic-'+role} for role in runtime.ROLES}}
        state={k:'synthetic' for k in ['db_password','tls_password','pagination','karaoke']}
        provider=self.provider();provider['auth.kakao.beta-native-app-key']='4'*32
        values=runtime.settings('api',state,roles,provider,'',b'',web=self.web())
        self.assertEqual(values['auth.kakao.native-app-key'],'1'*32)
        self.assertEqual(values['auth.kakao.beta-native-app-key'],'4'*32)
        for value in ['', 'invalid', '1'*32]:
            bad=dict(provider);bad['auth.kakao.beta-native-app-key']=value
            with self.assertRaises(ValueError):runtime.settings('api',state,roles,bad,'',b'')
        provider['auth.extra.trust']='untrusted'
        with self.assertRaises(ValueError):runtime.settings('api',state,roles,provider,'',b'')

    def test_wrong_origin_audience_native_key_and_missing_secret_fail_closed(self):
        for field,value in [('origin','http://localhost'),('origin','https://other.example'),('google_client_id',self.provider()['auth.google.server-client-id']),('kakao_rest_key',self.provider()['auth.kakao.native-app-key']),('kakao_client_secret',''),('rate_secret','short'),('enabled','true')]:
            row=self.web();row[field]=value
            with self.subTest(field=field,value=value),self.assertRaises(ValueError):runtime.web_settings(row,self.provider())
        row=self.web();row['extra']='injected'
        with self.assertRaises(ValueError):runtime.web_settings(row,self.provider())


if __name__=='__main__':unittest.main()
