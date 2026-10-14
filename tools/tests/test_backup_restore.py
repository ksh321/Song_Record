import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from backup_restore import scoped_dump


class RestoreTests(unittest.TestCase):
    def test_scoped_trigger_definers_changed_without_altering_user_notes(self):
        raw=b"/*!50017 DEFINER=`root`@`localhost`*/\nINSERT INTO recording(note) VALUES('DEFINER=`root`@`localhost`');\n"
        value=scoped_dump(raw)
        self.assertEqual(value.splitlines()[0],b'/*!50017 */')
        self.assertEqual(value.splitlines()[1],raw.splitlines()[1])
    def test_ordinary_dump_byte_content_unchanged(self):
        raw=b'CREATE TABLE sample(id BINARY(16));\nINSERT INTO sample VALUES(0x0012);\n'
        self.assertEqual(scoped_dump(raw),raw)
    def test_plain_create_trigger_definer_uses_scoped_user(self):
        raw=b"CREATE DEFINER=`old-user`@`%` TRIGGER sample BEFORE UPDATE ON t FOR EACH ROW SET @value=1;\n"
        self.assertNotIn(b'DEFINER=',scoped_dump(raw))
        self.assertIn(b'TRIGGER sample',scoped_dump(raw))


if __name__=='__main__':unittest.main()
