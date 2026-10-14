import datetime as dt, sys, unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import operational_checks as c
import tempfile
from unittest.mock import patch
class ChecksTests(unittest.TestCase):
    def setUp(self):
        self.now=dt.datetime(2026,10,14,tzinfo=dt.timezone.utc)
        self.rows={k:{'status':'PASS','observed_utc':self.now.isoformat()} for k in ('backup','ledger','observation','restore')}
        self.rows['cost']={'status':'PASS','level':'NORMAL','queried_utc':self.now.isoformat()}
    def test_real_evidence_passes_but_unconnected_daily_comparison_is_not_pass(self):
        report=c.evaluate(self.rows,self.now)
        self.assertEqual(report['status'],'PASS');self.assertEqual(report['checks']['daily_object_comparison'],'RELEASE_GATE_NOT_CONNECTED')
    def test_missing_failed_stale_and_future_backup_warn(self):
        for value in ({},{'status':'FAIL','observed_utc':self.now.isoformat()},{'status':'PASS','observed_utc':(self.now-dt.timedelta(hours=27)).isoformat()},{'status':'PASS','observed_utc':(self.now+dt.timedelta(seconds=1)).isoformat()}):
            self.rows['backup']=value;self.assertEqual(c.evaluate(self.rows,self.now)['checks']['backup'],'WARNING')
    def test_old_valid_restore_does_not_hide_monthly_due(self):
        self.rows['restore']['observed_utc']='2026-09-14T00:00:00+00:00'
        self.assertEqual(c.evaluate(self.rows,self.now)['checks']['monthly_restore'],'DUE_OR_UNCONFIRMED')
    def test_calendar_month_handles_short_month_and_year(self):
        self.assertEqual(c.next_month(dt.datetime(2026,1,31,tzinfo=dt.timezone.utc)).day,28)
        self.assertEqual(c.next_month(dt.datetime(2026,12,31,tzinfo=dt.timezone.utc)).year,2027)
    def test_actual_java_nanos_are_not_misclassified_as_missing(self):
        self.rows['observation']['observed_utc']='2026-10-14T00:00:00.123456789Z'
        report=c.evaluate(self.rows,self.now+dt.timedelta(seconds=1))
        self.assertEqual(report['checks']['observation'],'PASS')
    def test_unknown_cost_not_zero(self):
        self.rows['cost']['level']='UNCONFIRMED';self.assertEqual(c.evaluate(self.rows,self.now)['checks']['cost'],'WARNING')
    def test_failure_notification_deduplicates_and_recovery_rearms(self):
        with tempfile.TemporaryDirectory() as d,patch.object(c,'DIRECTORY',Path(d)),patch.object(c,'ROOT',Path(d)),patch.object(c.subprocess,'run') as call:
            call.return_value.returncode=0
            report={'checks':{'backup':'WARNING'}}
            c.notify(report);c.notify(report);self.assertEqual(call.call_count,1)
            c.notify({'checks':{'backup':'PASS'}});c.notify(report);self.assertEqual(call.call_count,2)
    def test_cost_keeps_own_alert_and_unknown_delivery_is_not_resent(self):
        with tempfile.TemporaryDirectory() as d,patch.object(c,'DIRECTORY',Path(d)),patch.object(c,'ROOT',Path(d)),patch.object(c.subprocess,'run') as call:
            c.notify({'checks':{'cost':'WARNING'}});call.assert_not_called()
            call.return_value.returncode=1;c.notify({'checks':{'backup':'WARNING'}});c.notify({'checks':{'backup':'WARNING'}});self.assertEqual(call.call_count,1)
if __name__=='__main__':unittest.main()
