import contextlib,io,json,subprocess,sys,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import r2_credentials as r2
GOOD='dev.temporary=ALLOWED\ndev.final=DENIED\nprod.temporary=DENIED\nprod.final=DENIED\n'
class R2CredentialsTests(unittest.TestCase):
 def test_audio_report_is_closed_and_requires_development_worker(self):
  self.assertEqual(r2.parse_report('audio.temporary=VERIFIED','dev.worker',audio=True)['status'],'PASS')
  for value in ('ERROR','BYTES_MISMATCH','VALIDATION_FAILED','CLEANUP_FAILED'):
   self.assertEqual(r2.parse_report('audio.temporary='+value,'dev.worker',audio=True)['status'],'FAIL')
  for output,label in [('audio.temporary=VERIFIED\nsecret=value','dev.worker'),('audio.temporary=secret','dev.worker'),('audio.temporary=VERIFIED','prod.worker')]:
   with self.assertRaises(r2.SecretError):r2.parse_report(output,label,audio=True)
 def test_audio_uses_stdin_and_persists_only_closed_status(self):
  with tempfile.TemporaryDirectory() as f:
   d=Path(f);(d/'checker-classpath.txt').write_text('fixture')
   with patch.object(r2.shutil,'which',return_value='C:/tools/audio.exe'),patch.object(r2.subprocess,'run',return_value=subprocess.CompletedProcess([],0,'audio.temporary=VERIFIED','sensitive-output')) as run:
    self.assertEqual(r2.check('dev.worker','java','a'*32,'b'*64,d,audio=True),'PASS')
   self.assertNotIn('b'*64,str(run.call_args.args));self.assertIn('diagnostic.mode=audio-validation',run.call_args.kwargs['input'])
   report=(d/'audio-reports/dev.worker.json').read_text()
   self.assertNotIn('b'*64,report);self.assertNotIn('sensitive',report)
   for label in ('dev.api','prod.worker','prod.api'):
    with self.assertRaises(r2.SecretError):r2.check(label,'java','a'*32,'b'*64,d,audio=True)
 def test_strict_scope(self):
  self.assertEqual(r2.parse_report(GOOD,'dev.api')['status'],'PASS')
  self.assertEqual(r2.parse_report(GOOD.replace('ALLOWED','DENIED'),'dev.api')['status'],'FAIL')
  self.assertEqual(r2.parse_report(GOOD,'dev.worker')['status'],'FAIL')
  for bad in [GOOD+'secret=value',GOOD+'dev.final=DENIED',GOOD.replace('ALLOWED','sensitive')]:
   with self.assertRaises(r2.SecretError):r2.parse_report(bad,'dev.api')
 def test_no_secret_persistence_or_vault_read(self):
  with tempfile.TemporaryDirectory() as f:
   d=Path(f);(d/'checker-classpath.txt').write_text('fixture-classpath')
   output=subprocess.CompletedProcess([],0,GOOD,'sensitive-provider-output');out=io.StringIO()
   with patch.object(r2.subprocess,'run',return_value=output) as run,patch.object(Path,'read_bytes',side_effect=AssertionError('No vault access')),contextlib.redirect_stdout(out),contextlib.redirect_stderr(out):
    self.assertEqual(r2.check('dev.api','java','a'*32,'b'*64,d),'PASS')
   self.assertNotIn('b'*64,str(run.call_args.args));self.assertIn('b'*64,run.call_args.kwargs['input']);self.assertNotIn('env',run.call_args.kwargs);self.assertEqual(out.getvalue(),'')
   self.assertFalse((d/'vault').exists())
   for p in d.rglob('*'):
    if p.is_file():self.assertNotIn('b'*64,p.read_text());self.assertNotIn('sensitive',p.read_text())
 def test_failure_invalidates_prior_pass_without_echo(self):
  with tempfile.TemporaryDirectory() as f:
   d=Path(f);(d/'reports').mkdir();p=d/'reports/dev.api.json';p.write_text('old PASS')
   with self.assertRaises(r2.SecretError) as error:r2.check('dev.api','java','sensitive','bad',d)
   self.assertFalse(p.exists());self.assertNotIn('sensitive',str(error.exception))
 def test_child_failure_never_copies_output(self):
  with tempfile.TemporaryDirectory() as f:
   d=Path(f);(d/'checker-classpath.txt').write_text('fixture')
   with patch.object(r2.subprocess,'run',return_value=subprocess.CompletedProcess([],2,'secret','secret')):
    with self.assertRaises(r2.SecretError):r2.check('dev.api','java','a'*32,'b'*64,d)
   self.assertFalse((d/'reports/dev.api.json').exists())
 def test_development_probe_requires_write_roundtrip_and_keeps_read_reports(self):
  full=GOOD+'write.temporary=VERIFIED\nwrite.final=DENIED\n'
  self.assertEqual(r2.parse_report(full,'dev.api',True)['status'],'PASS')
  self.assertEqual(r2.parse_report(full.replace('VERIFIED','CLEANUP_FAILED'),'dev.api',True)['status'],'FAIL')
  for detail in ('PUT_HTTP_400','GET_HTTP_403','ANONYMOUS_HTTP_400','PUT_TRANSPORT_ERROR','BYTES_MISMATCH'):
   result=r2.parse_report(full.replace('VERIFIED',detail),'dev.api',True)
   self.assertEqual(result['status'],'FAIL');self.assertEqual(result['checks']['write.temporary'],detail)
  with self.assertRaises(r2.SecretError):r2.parse_report(full.replace('VERIFIED','PUT_HTTP_400_secret'),'dev.api',True)
  with tempfile.TemporaryDirectory() as f:
   d=Path(f);(d/'checker-classpath.txt').write_text('fixture');(d/'reports').mkdir();old=d/'reports/dev.api.json';old.write_text('read evidence')
   with patch.object(r2.subprocess,'run',return_value=subprocess.CompletedProcess([],0,full,'')):
    self.assertEqual(r2.check('dev.api','java','a'*32,'b'*64,d,full=True),'PASS')
   self.assertEqual(old.read_text(),'read evidence');self.assertTrue((d/'development-reports/dev.api.json').exists())
  with self.assertRaises(r2.SecretError):r2.check('prod.api','java','a'*32,'b'*64,full=True)
 def test_signed_probe_only_accepts_fixed_results_and_dev_api(self):
  self.assertEqual(r2.parse_report('signed.temporary=VERIFIED\n','dev.api',signed=True)['status'],'PASS')
  for unsafe in ('signed.temporary=https://secret.invalid', 'signed.temporary=VERIFIED\nsecret=key'):
   with self.assertRaises(r2.SecretError):r2.parse_report(unsafe,'dev.api',signed=True)
  with tempfile.TemporaryDirectory() as f:
   d=Path(f);(d/'checker-classpath.txt').write_text('fixture')
   with patch.object(r2.subprocess,'run',return_value=subprocess.CompletedProcess([],0,'signed.temporary=VERIFIED','secret')) as run:
    self.assertEqual(r2.check('dev.api','java','a'*32,'b'*64,d,signed=True),'PASS')
   self.assertIn('diagnostic.mode=signed-put',run.call_args.kwargs['input'])
   self.assertNotIn('secret',(d/'signed-put-reports/dev.api.json').read_text())
  with self.assertRaises(r2.SecretError):r2.check('prod.api','java','a'*32,'b'*64,signed=True)
 def test_playback_reader_requires_final_only_and_denied_writes(self):
  scope='dev.temporary=DENIED\ndev.final=ALLOWED\nprod.temporary=DENIED\nprod.final=DENIED\nwrite.temporary=DENIED\nwrite.final=DENIED\n'
  self.assertEqual(r2.parse_report(scope,'dev.playback',True)['status'],'PASS')
  for wrong in (scope.replace('write.final=DENIED','write.final=VERIFIED'),scope.replace('dev.temporary=DENIED','dev.temporary=ALLOWED'),scope.replace('prod.final=DENIED','prod.final=ALLOWED')):
   self.assertEqual(r2.parse_report(wrong,'dev.playback',True)['status'],'FAIL')
  with tempfile.TemporaryDirectory() as f:
   d=Path(f);(d/'checker-classpath.txt').write_text('fixture')
   with patch.object(r2.subprocess,'run',return_value=subprocess.CompletedProcess([],0,scope,'')) as child:
    self.assertEqual(r2.check('dev.playback','java','a'*32,'b'*64,d),'PASS')
   self.assertIn('diagnostic.mode=development-write',child.call_args.kwargs['input'])
   self.assertNotIn('b'*64,(d/'development-reports/dev.playback.json').read_text())
 def test_invalid_role(self):
  with self.assertRaises(r2.SecretError):r2.check('../escape','java','a'*32,'b'*64)
if __name__=='__main__':unittest.main()
