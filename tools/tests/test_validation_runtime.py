import unittest,sys,tempfile,json,subprocess
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import validation_runtime as v
class ValidationRuntimeTests(unittest.TestCase):
 def test_connect_recreates_only_stateless_roles_and_waits_for_verified_tls_health(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d);(root/'https').mkdir();(root/'https/server.p12').write_bytes(b'synthetic-pfx');(root/'https/server.crt').write_text('synthetic-public-certificate')
   row={key:'synthetic-only' for key in ('db_password','tls_password','pagination','karaoke')}
   with patch.object(v,'DIRECTORY',root),patch.object(v,'state',return_value=row),patch.object(v,'containers',return_value={'mysql':'db','api':'api','worker':'worker'}),patch.object(v,'load',return_value=('synthetic-access','synthetic-secret')),patch.object(v,'run',return_value=b'[{"State":{"Health":{"Status":"healthy"}}}]') as call:
    with patch.object(v,'start_cost_monitor'),patch.object(v,'start_operations_monitor'),patch.object(v,'start_backup_monitor'),patch.object(v,'start_backup_ledger_monitor'):v.connect()
   calls=call.call_args_list
   self.assertEqual(calls[1].args[0],v.COMPOSE+['up','-d','--force-recreate','api','worker'])
   self.assertEqual(calls[-1].args[0],v.COMPOSE+['up','-d','--wait','--wait-timeout','90','api','worker'])
   injections=[c for c in calls if 'input' in c.kwargs]
   self.assertEqual(len(injections),2)
   self.assertTrue(all(json.loads(c.kwargs['input'])['server.crt']=='synthetic-public-certificate' for c in injections))
   self.assertFalse(any('synthetic-secret' in str(c.args) for c in calls))
 def test_missing_state_never_reinitializes_an_existing_database(self):
  with tempfile.TemporaryDirectory() as d,patch.object(v,'DIRECTORY',Path(d)),patch.object(v.subprocess,'run',return_value=subprocess.CompletedProcess([],0,b'volume exists',b'')),patch.object(v,'_secure') as protect:
   with self.assertRaisesRegex(RuntimeError,'preserve existing volume'):v.state()
   protect.assert_not_called();self.assertFalse((Path(d)/'runtime.dpapi').exists())
 def test_existing_private_state_is_scope_bound_and_never_rotated_on_resume(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d);p=root/'runtime.dpapi';p.write_bytes(b'encrypted')
   row={'scope':'song_record_validation:v1','instance_id':'synthetic','db_password':'synthetic-only'}
   with patch.object(v,'DIRECTORY',root),patch.object(v,'_crypt',return_value=json.dumps(row).encode()) as decrypt:
    self.assertEqual(v.state(),row);decrypt.assert_called_once_with(b'encrypted','staging.api',True);self.assertEqual(p.read_bytes(),b'encrypted')
   with patch.object(v,'DIRECTORY',root),patch.object(v,'_crypt',return_value=b'{"scope":"other"}'):
    with self.assertRaises(AssertionError):v.state()
 def test_runtime_secrets_are_stdin_not_command_line_or_environment(self):
  with patch.object(v.subprocess,'run',return_value=subprocess.CompletedProcess([],0,b'accepted',b'')) as call:
   self.assertEqual(v.run(['docker','exec','-i','fixture','python3','/app/inject-runtime.py'],input=b'synthetic-private-value'),b'accepted')
   self.assertNotIn('synthetic-private-value',str(call.call_args.args));self.assertNotIn('env',call.call_args.kwargs)
if __name__=='__main__':unittest.main()
