import contextlib
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import r2_vault as vault
import r2_credentials as r2

class VaultTests(unittest.TestCase):
    def test_production_and_path_traversal_are_rejected(self):
        for role in ('prod.worker','prod.api','../dev.worker'):
            for action in (lambda: vault.load(role),lambda: vault.save(role,'a'*32,'b'*64),lambda: vault.exists(role)):
                with self.assertRaises(vault.VaultError):action()
    @unittest.skipUnless(os.name=='nt','Real Windows DPAPI required')
    def test_real_dpapi_roundtrip_ciphertext_tamper_and_role_binding(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'credentials'
            output=io.StringIO()
            with contextlib.redirect_stdout(output),contextlib.redirect_stderr(output):
                vault.save('dev.worker','a'*32,'b'*64,path)
                self.assertEqual(vault.load('dev.worker',path),('a'*32,'b'*64))
            self.assertEqual(output.getvalue(),'')
            target=path/'dev.worker.dpapi';cipher=target.read_bytes()
            self.assertNotIn(b'b'*64,cipher);self.assertNotIn(b'a'*32,cipher)
            (path/'dev.api.dpapi').write_bytes(cipher)
            with self.assertRaises(vault.VaultError):vault.load('dev.api',path)
            changed=bytearray(cipher);changed[len(changed)//2]^=1;target.write_bytes(changed)
            with self.assertRaises(vault.VaultError) as result:vault.load('dev.worker',path)
            self.assertNotIn('b'*64,str(result.exception));self.assertIsNone(result.exception.__cause__)
    def test_failed_encryption_or_invalid_input_preserves_existing_registration(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory);target=path/'dev.worker.dpapi';target.write_bytes(b'existing-encrypted-fixture')
            with patch.object(vault,'_crypt',side_effect=RuntimeError('sensitive-provider-text')):
                with self.assertRaises(vault.VaultError) as result:vault.save('dev.worker','a'*32,'b'*64,path)
            self.assertNotIn('sensitive',str(result.exception));self.assertIsNone(result.exception.__cause__)
            self.assertEqual(target.read_bytes(),b'existing-encrypted-fixture')
            with self.assertRaises(vault.VaultError):vault.save('dev.worker','invalid','invalid',path)
            self.assertEqual(target.read_bytes(),b'existing-encrypted-fixture');self.assertEqual(len(list(path.iterdir())),1)
    def test_stored_key_used_only_in_child_stdin_and_fixed_result(self):
        worker='dev.temporary=ALLOWED\ndev.final=ALLOWED\nprod.temporary=DENIED\nprod.final=DENIED\n'
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory);(path/'checker-classpath.txt').write_text('fixture')
            with patch.object(vault,'load',return_value=('a'*32,'b'*64)) as load,patch.object(r2.subprocess,'run',return_value=subprocess.CompletedProcess([],0,worker,'sensitive-stderr')) as child:
                self.assertEqual(r2.check('dev.worker','java',directory=path),'PASS')
            load.assert_called_once_with('dev.worker')
            self.assertNotIn('b'*64,str(child.call_args.args));self.assertNotIn('env',child.call_args.kwargs)
            self.assertIn('b'*64,child.call_args.kwargs['input'])
            for target in path.rglob('*'):
                if target.is_file():
                    self.assertNotIn('b'*64,target.read_text());self.assertNotIn('sensitive-stderr',target.read_text())
    def test_missing_stored_key_fails_closed_and_removes_stale_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory);(path/'reports').mkdir();target=path/'reports/dev.worker.json';target.write_text('old pass')
            with patch.object(vault,'load',side_effect=vault.VaultError('unavailable')),patch.object(r2.subprocess,'run') as child:
                with self.assertRaises(r2.SecretError):r2.check('dev.worker','java',directory=path)
            self.assertFalse(target.exists());child.assert_not_called()

if __name__=='__main__':unittest.main()
