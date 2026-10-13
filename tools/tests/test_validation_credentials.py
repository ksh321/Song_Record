import unittest,sys,subprocess,tempfile
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import validation_credentials as v
class ValidationCredentialsTests(unittest.TestCase):
 def report(self,role):return '\n'.join(f'{key}={value}' for key,value in {'staging.temporary':'DENIED' if role=='staging.playback' else 'ALLOWED','staging.final':'DENIED' if role=='staging.api' else 'ALLOWED',**{f'{e}.{k}':'DENIED' for e in ('dev','prod') for k in ('temporary','final')}}.items())
 def test_all_denied_cannot_pass_and_existing_buckets_must_be_denied(self):
  for role in v.ROLES:
   good=self.report(role);self.assertTrue(v.parse(good,role));self.assertFalse(v.parse(good.replace('ALLOWED','DENIED'),role));self.assertFalse(v.parse(good.replace('dev.final=DENIED','dev.final=ALLOWED'),role))
 def test_unknown_duplicate_and_secret_output_are_rejected(self):
  good=self.report('staging.api')
  for bad in (good+'\nsecret=value',good+'\nstaging.final=DENIED',good.replace('ALLOWED','ERROR'),good+'\nSDK log'):
   with self.assertRaises(ValueError):v.parse(bad,'staging.api')
 def test_read_scope_alone_is_not_evidence_of_write_permissions(self):
  for role in v.ROLES:
   outputs=self.report(role)+'\nwrite.temporary='+('DENIED' if role=='staging.playback' else 'VERIFIED')+'\nwrite.final='+('VERIFIED' if role=='staging.worker' else 'DENIED')
   self.assertTrue(v.parse(outputs,role,full=True));self.assertFalse(v.parse(self.report(role),role,full=True))
   with self.assertRaises(ValueError):v.parse(outputs.replace('VERIFIED','CLEANUP_FAILED'),role,full=True) if role!='staging.playback' else v.parse(outputs+'\nsecret=value',role,full=True)
 def test_scope_checker_never_puts_keys_in_args_environment_or_report(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d);cp=root/'.local/workflow/cloudflare';cp.mkdir(parents=True);(cp/'checker-classpath.txt').write_text('test-only-classpath')
   with patch.object(v,'ROOT',root),patch.object(v.subprocess,'run',return_value=subprocess.CompletedProcess([],0,self.report('staging.api'),'sensitive stderr')) as call:
    self.assertTrue(v.check('staging.api','a'*32,'b'*64));self.assertNotIn('b'*64,str(call.call_args.args));self.assertNotIn('env',call.call_args.kwargs);self.assertIn('b'*64,call.call_args.kwargs['input'])
if __name__=='__main__':unittest.main()
