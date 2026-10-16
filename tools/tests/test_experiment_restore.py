import importlib.util
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'infra/experiment'),str(ROOT/'tools')]
spec=importlib.util.spec_from_file_location('experiment_restore',ROOT/'infra/experiment/restore.py')
restore=importlib.util.module_from_spec(spec);spec.loader.exec_module(restore)


class ExperimentRestoreTests(unittest.TestCase):
    def test_cleanup_only_drops_entities_created_by_this_invocation(self):
        database='song_record_restore_'+'a'*32;user='sr_restore_'+'a'*16
        with patch.object(restore,'bounded') as command:
            restore.cleanup_created(database,user,['mysql'],False,False)
            command.assert_not_called()
            restore.cleanup_created(database,user,['mysql'],True,False)
            self.assertEqual(command.call_args.kwargs['data'],f'DROP DATABASE `{database}`;'.encode())
        with patch.object(restore,'bounded') as command:
            with self.assertRaises(restore.BackupError):restore.cleanup_created('song_record_experiment',user,['mysql'],True,True)
            command.assert_not_called()

    def test_only_generated_disposable_database_and_user_are_allowed(self):
        restore.require_scope('song_record_restore_'+'a'*32,'sr_restore_'+'b'*16)
        for database,user in [('song_record_experiment','root'),('song_record_validation','root'),
                              ('song_record_restore_'+'a'*32,'root'),('song_record_restore_abc','sr_restore_'+'b'*16)]:
            with self.assertRaisesRegex(restore.BackupError,'RESTORE_DATABASE_SCOPE_REJECTED'):
                restore.require_scope(database,user)

    def test_dump_cannot_select_or_create_another_database(self):
        for statement in (b'USE song_record_experiment;\n',b' CREATE DATABASE other;\n'):
            with self.assertRaisesRegex(restore.BackupError,'RESTORE_DATABASE_SCOPE_REJECTED'):
                restore.scoped_dump(statement)

    def test_object_definer_is_removed_but_user_text_is_not_rewritten(self):
        raw=b'CREATE DEFINER=`root`@`localhost` TRIGGER t BEFORE INSERT ON a FOR EACH ROW SET NEW.id=1;\nINSERT INTO note VALUES ("DEFINER=`customer`@`text`");\n'
        result=restore.scoped_dump(raw)
        self.assertNotIn(b'DEFINER=`root`',result)
        self.assertIn(b'DEFINER=`customer`@`text`',result)
