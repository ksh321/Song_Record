import sys
import unittest
import uuid
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from backup_overlay import statements
from backup_store import BackupError


class OverlayTests(unittest.TestCase):
    def setUp(self):
        self.db='song_record_restore_'+uuid.uuid4().hex
        self.owner,self.recording,self.generation=[str(uuid.uuid4()) for _ in range(3)]
        self.tables={'recording_asset':{'columns':['user_id','recording_id'],'parents':['recording']},'recording':{'columns':['user_id','id'],'parents':['app_user']},'app_user':{'columns':['id'],'parents':[]}}
        self.row={'owner':self.owner,'entity':self.recording,'generation':self.generation,'type':'RECORDING_ASSET','state':'COMMITTED','revision':1,'at':'2026-10-14T00:00:00+00:00'}
    def test_source_and_arbitrary_database_rejected_before_sql(self):
        for target in ['song_record_validation','mysql','song_record_restore_bad','../x']:
            with self.assertRaises(BackupError):statements(target,self.tables,[self.row])
    def test_generation_cleared_without_deleting_record_or_other_generation(self):
        sql=statements(self.db,self.tables,[self.row]).decode()
        self.assertIn("cloud_state='NONE'",sql);self.assertIn(self.generation.replace('-',''),sql)
        self.assertNotIn('DELETE FROM recording ',sql)
    def test_cancelled_entry_preserves_active_asset(self):
        sql=statements(self.db,self.tables,[{**self.row,'state':'CANCELLED'}]).decode()
        self.assertNotIn("cloud_state='NONE'",sql)
    def test_unknown_user_owned_table_fails_closed(self):
        self.tables['unreviewed']={'columns':['user_id'],'parents':[]}
        with self.assertRaises(BackupError):statements(self.db,self.tables,[self.row])
    def test_owner_children_deleted_before_owner_without_cross_owner_predicate(self):
        row={**self.row,'type':'USER','entity':self.owner};row.pop('generation')
        sql=statements(self.db,self.tables,[row]).decode()
        self.assertLess(sql.index('DELETE FROM `recording_asset`'),sql.index('DELETE FROM `recording`'))
        self.assertLess(sql.index('DELETE FROM `recording`'),sql.index('DELETE FROM app_user'))
        self.assertEqual(sql.count(self.owner.replace('-','')),3)


if __name__=='__main__':unittest.main()
