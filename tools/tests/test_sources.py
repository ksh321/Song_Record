import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('sources', Path(__file__).parents[1] / 'index_sources.py')
sources = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sources)


class SourceTests(unittest.TestCase):
    def test_line_endings_only_are_equivalent(self):
        with tempfile.TemporaryDirectory() as tmp:
            a, b = Path(tmp)/'a.txt', Path(tmp)/'b.txt'
            a.write_bytes(b'policy\n'); b.write_bytes(b'policy\r\n')
            self.assertEqual(sources.digest(a), sources.digest(b))
            b.write_bytes(b'changed policy\r\n')
            self.assertNotEqual(sources.digest(a), sources.digest(b))

    def test_changed_external_source_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root/'original.txt').write_text('original')
            (root/'external.txt').write_text('changed')
            with patch.object(sources, 'ROOT', root), patch.object(sources, 'SOURCES', [('roles','external.txt','original.txt','role')]), patch.object(sources, 'APPROVED', {'roles': sources.digest(root/'original.txt')}):
                with self.assertRaisesRegex(ValueError, 'Source mismatch'):
                    sources.build(root)

    def test_cannot_regenerate_from_unapproved_original(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            original = root/'original.txt'
            original.write_text('approved')
            approved = sources.digest(original)
            original.write_text('changed')
            with patch.object(sources, 'ROOT', root), patch.object(sources, 'SOURCES', [('roles','external.txt','original.txt','role')]), patch.object(sources, 'APPROVED', {'roles': approved}):
                with self.assertRaisesRegex(ValueError, 'Unapproved original change'):
                    sources.build(None)


if __name__ == '__main__':
    unittest.main()
