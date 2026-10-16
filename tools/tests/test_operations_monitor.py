import sys,unittest,tempfile,json
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import operations_monitor as m
class OperationsMonitorTests(unittest.TestCase):
 def test_only_aggregate_projection_is_saved_raw_logs_stay_in_memory(self):
  with tempfile.TemporaryDirectory() as d,patch.object(m,'DIRECTORY',Path(d)),patch.object(m.runtime,'containers',return_value={'api':'private-api','worker':'private-worker'}),patch.object(m.runtime,'run',side_effect=[b'{"observed_utc":"2026-10-13T00:00:00Z","demand":{"pin_limit_accounts":1}}',b'Bearer synthetic-private-token\nmemo synthetic-note\noperations_observation_failed\n',b'normal\n']) as calls:
   result=m.once();saved=(Path(d)/'latest.json').read_text();self.assertEqual(result['status'],'FAIL');self.assertEqual(result['observation_write_failures_last_hour'],1);self.assertNotIn('synthetic-private-token',saved);self.assertNotIn('synthetic-note',saved)
   self.assertFalse(any('password' in str(c.args).lower() for c in calls.call_args_list))
 def test_truncated_log_coverage_is_not_zero_failures(self):
  with patch.object(m.runtime,'containers',return_value={'api':'private-api','worker':'private-worker'}),patch.object(m.runtime,'run',side_effect=[b'{}',b'line\n'*20000]):
   with self.assertRaisesRegex(RuntimeError,'COVERAGE_UNCONFIRMED'):m.once()
 def test_retention_failure_is_reported_separately_without_raw_log(self):
  with tempfile.TemporaryDirectory() as d,patch.object(m,'DIRECTORY',Path(d)),patch.object(m.runtime,'containers',return_value={'api':'private-api','worker':'private-worker'}),patch.object(m.runtime,'run',side_effect=[b'{"observed_utc":"2026-10-15T00:00:00Z"}',b'normal\n',b'operations_retention_failed private synthetic content\n']):
   result=m.once();self.assertEqual(result['status'],'FAIL');self.assertEqual(result['observation_retention_failures_last_hour'],1);self.assertEqual(result['observation_write_failures_last_hour'],0);self.assertNotIn('synthetic content',(Path(d)/'latest.json').read_text())
if __name__=='__main__':unittest.main()
