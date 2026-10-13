import sys,unittest,tempfile,json,datetime as dt
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import cost_monitor as c
from cloudflare_metrics import MetricsError
class MonitorTests(unittest.TestCase):
 def test_gate_uses_private_stdin_without_password_or_public_endpoint(self):
  with patch.object(c.runtime,'containers',return_value={'api':'isolated'}),patch.object(c.runtime,'run') as run:
   c.apply({'queried_utc':'2026-10-13T00:00:00Z','r2_projected_month_krw':70000})
   args=run.call_args;self.assertNotIn('70000',str(args.args));self.assertIn(b'krw=70000',args.kwargs['input']);self.assertIn('PropertiesLauncher',args.args[0][-1])
 def test_unknown_delivery_is_not_automatically_resent(self):
  with tempfile.TemporaryDirectory() as d,patch.object(c,'DIRECTORY',Path(d)),patch.object(c.subprocess,'run',side_effect=TimeoutError()) as send:
   r={'level':'LOCK','billing_start':'2026-10-08'}
   with self.assertRaises(MetricsError):c.notify(r)
   c.notify(r);self.assertEqual(send.call_count,1);self.assertEqual(json.loads((Path(d)/'event-LOCK.json').read_text())['status'],'ATTEMPTED')
 def test_query_failure_never_applies_fake_zero_or_erases_last_good_receipt(self):
  with tempfile.TemporaryDirectory() as d,patch.object(c,'DIRECTORY',Path(d)),patch.object(c,'REPORT',Path(d)/'latest.json'),patch.object(c.r2_cost,'check_pricing',return_value={}),patch.object(c.metrics,'load',side_effect=MetricsError('TOKEN_NOT_ACTIVE')),patch.object(c,'apply') as gate:
   c.REPORT.write_text('{"status":"PASS","r2_projected_month_krw":70000}')
   with self.assertRaises(MetricsError):c.once(False)
   gate.assert_not_called();self.assertEqual(json.loads(c.REPORT.read_text())['r2_projected_month_krw'],70000)
   self.assertEqual(json.loads((Path(d)/'failure.json').read_text())['diagnostic'],'TOKEN_NOT_ACTIVE')
if __name__=='__main__':unittest.main()
