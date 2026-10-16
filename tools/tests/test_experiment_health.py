import datetime as dt
import importlib.util
from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'infra/experiment'))
spec=importlib.util.spec_from_file_location('experiment_health',ROOT/'infra/experiment/health.py')
health=importlib.util.module_from_spec(spec);spec.loader.exec_module(health)


class ExperimentHealthTests(unittest.TestCase):
    def test_jdbc_reconciliation_is_utc_but_general_monitor_requires_zone(self):
        raw='2026-10-15T05:03:06.845'
        self.assertIsNone(health.timestamp(raw))
        self.assertEqual(health.reconciliation_timestamp(raw),dt.datetime(2026,10,15,5,3,6,845000,tzinfo=dt.timezone.utc))
        self.assertIsNone(health.reconciliation_timestamp('2026-10-15 05:03:06'))
    def test_worker_reconciliation_requires_actual_fresh_zero_issue_evidence(self):
        now=dt.datetime.now(dt.timezone.utc)
        rows={'worker_connected':True,'observation':{'status':'PASS','observed_utc':now.isoformat(),'capacity':{}},'cost':{'status':'PASS','queried_utc':now.isoformat()}}
        self.assertEqual(health.evaluate(rows,now),['worker_reconciliation_has_issues','worker_reconciliation_stale_or_unconfirmed'])
        rows['observation']['capacity']={'reconciliation_at':now.isoformat(),'reconciliation_locked':False,'reconciliation_issue_count':0}
        self.assertEqual(health.evaluate(rows,now),[])
    def setUp(self):
        self.now=dt.datetime(2026,10,15,2,tzinfo=dt.timezone.utc)
        self.rows={'observation':{'status':'PASS','observed_utc':self.now.isoformat()},
                   'cost':{'status':'PASS','queried_utc':self.now.isoformat()}}

    def test_fresh_connected_monitors_and_java_nanoseconds(self):
        self.rows['observation']['observed_utc']='2026-10-15T02:00:00.000000000Z'
        self.assertEqual(health.evaluate(self.rows,self.now),[])

    def test_backup_connection_requires_ledger_and_restore_evidence(self):
        self.rows['backup']={'status':'PASS','observed_utc':self.now.isoformat(),'data_created_utc':self.now.isoformat()}
        self.assertEqual(health.evaluate(self.rows,self.now),['backup_ledger_stale_or_unconfirmed','restore_goals_or_cleanup_unconfirmed','restore_stale_or_unconfirmed'])
        for kind in ['backup_ledger','restore']:self.rows[kind]={'status':'PASS','observed_utc':self.now.isoformat()}
        self.rows['restore'].update(rpo_goal_met=True,data_restore_rto_goal_met=True,disposable_copy_removed=True)
        self.assertEqual(health.evaluate(self.rows,self.now),[])
        self.rows['backup_failure']={'observed_utc':(self.now+dt.timedelta(seconds=1)).isoformat()}
        self.assertEqual(health.evaluate(self.rows,self.now),['backup_latest_attempt_failed'])

    def test_new_failure_overrides_last_good_but_older_failure_does_not(self):
        self.rows['cost_failure']={'queried_utc':(self.now-dt.timedelta(seconds=1)).isoformat()}
        self.assertEqual(health.evaluate(self.rows,self.now),[])
        self.rows['cost_failure']['queried_utc']=(self.now+dt.timedelta(seconds=1)).isoformat()
        self.assertEqual(health.evaluate(self.rows,self.now),['cost_latest_attempt_failed'])

    def test_absent_stale_and_future_observation_are_unconfirmed(self):
        for at in [None,(self.now-dt.timedelta(minutes=16)).isoformat(),(self.now+dt.timedelta(seconds=1)).isoformat()]:
            self.rows['observation']['observed_utc']=at
            self.assertEqual(health.evaluate(self.rows,self.now),['observation_stale_or_unconfirmed'])
