import datetime as dt
import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import test_operational_backup as fixtures
from backup_ledger import Ledger, LEDGER, FILES, blocked
from backup_store import BackupError
from operational_backup import encoded, check_file, INDEX


class LedgerTests(unittest.TestCase):
    def setUp(self):
        fixture=fixtures.BackupTests();fixture.setUp()
        self.store,self.backup,self.file,self.day=fixture.store,fixture.backup,fixture.file,fixture.day
        self.transport=fixture.transport;self.ledger=Ledger(self.store,'fixture-instance')
    def row(self,kind='RECORDING_ASSET',state='COMMITTED',revision=1):
        row={'owner':self.file['owner'],'entity':self.file['recording'],'type':kind,'state':state,'revision':revision,'at':self.day.isoformat()}
        if kind=='RECORDING_ASSET':row['generation']=self.file['generation']
        if kind=='USER':row['entity']=self.file['owner']
        return row
    def test_missing_or_corrupt_ledger_never_allows_restore(self):
        with self.assertRaises(BackupError):self.ledger.require_restore([self.file])
        self.transport.rows[LEDGER]=b'corrupt'
        with self.assertRaises(BackupError):self.ledger.require_restore([self.file])
    def test_generation_only_blocks_old_copy_not_recording_or_other_generation(self):
        self.ledger.merge([self.row()])
        self.assertEqual(self.ledger.require_restore([self.file]),[])
        import uuid
        fresh={**self.file,'generation':str(uuid.uuid4())}
        fresh['key']=f"recordings/{fresh['owner']}/{fresh['recording']}/{fresh['generation']}.m4a"
        self.assertEqual(self.ledger.require_restore([fresh]),[fresh])
    def test_recording_and_user_scope_block_all_owned_generations(self):
        for kind in ('RECORDING','USER'):
            self.assertTrue(blocked(self.file,[self.row(kind)]))
    def test_committed_delete_survives_old_db_and_cancelled_replay(self):
        self.ledger.merge([self.row(state='REQUESTED')]);self.ledger.merge([self.row()])
        self.ledger.merge([self.row(state='CANCELLED',revision=99)])
        self.assertEqual(self.ledger.require_restore([self.file]),[])
    def test_cancelled_uncommitted_protection_change_reenables_file(self):
        self.ledger.merge([self.row(state='REQUESTED')]);self.ledger.merge([self.row(state='CANCELLED',revision=2)])
        self.assertEqual(self.ledger.require_restore([self.file]),[self.file])
    def test_seven_day_expiry_prunes_db_and_deleted_copy_keeps_active_copy(self):
        self.backup.once(self.day);self.ledger.merge([self.row()])
        result=self.ledger.prune(self.day+dt.timedelta(days=7))
        self.assertEqual((result['removed_points'],result['removed_files']),(1,1))
        self.assertIsNone(self.store.get(check_file(self.file)))
        self.assertEqual(self.ledger.read()[0]['state'],'COMMITTED')
    def test_active_file_survives_expired_db_point(self):
        self.backup.once(self.day);self.ledger.merge([])
        self.ledger.prune(self.day+dt.timedelta(days=7))
        self.assertIsNotNone(self.store.get(check_file(self.file)))
    def test_legacy_subject_unknown_cannot_confirm_owner_backup_absence(self):
        self.backup.once(self.day);self.ledger.merge([self.row('USER')])
        self.assertEqual(self.ledger.prune(self.day+dt.timedelta(days=1))['absent_owners'],[])
    def test_pruned_generation_does_not_make_old_point_restore_deleted_copy(self):
        self.backup.once(self.day);self.ledger.merge([self.row()]);self.backup.require_ledger=True
        path=check_file(self.file);self.store.delete(path)
        self.backup.verify(self.backup.catalog()['points'][0])

    def test_unknown_inventory_cannot_confirm_account_absence(self):
        self.backup.snapshot=lambda:(b'sql',[],[])
        self.backup.once(self.day);self.ledger.merge([self.row('USER')])
        listed=[{'key':'operational/v1/files/'+'a'*64+'.enc','at':self.day.isoformat()}]
        result=self.ledger.prune(self.day+dt.timedelta(days=1),listed)
        self.assertTrue(result['unknown_artifacts']);self.assertEqual(result['absent_owners'],[])

    def test_user_ledger_retirement_requires_thirty_days_and_confirmed_absence(self):
        row=self.row('USER');self.ledger.merge([row]);owner=row['owner']
        with self.assertRaises(BackupError):self.ledger.retire_owners([owner],self.day+dt.timedelta(days=29),[owner])
        with self.assertRaises(BackupError):self.ledger.retire_owners([owner],self.day+dt.timedelta(days=31),[])
        self.ledger.retire_owners([owner],self.day+dt.timedelta(days=31),[owner])
        self.assertEqual(self.ledger.read(),[])


if __name__=='__main__':unittest.main()
