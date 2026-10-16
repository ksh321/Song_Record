import datetime as dt
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import r2_cost


class ExperimentFxTests(unittest.TestCase):
    def test_namespaced_public_ecb_cross_rate(self):
        raw=b'<Envelope xmlns="urn:ecb"><Cube><Cube time="2026-10-15"><Cube currency="USD" rate="1.1"/><Cube currency="KRW" rate="1540"/></Cube></Cube></Envelope>'
        self.assertEqual(r2_cost.exchange_xml(raw, dt.datetime(2026,10,15,tzinfo=dt.timezone.utc))['krw_per_usd'], '1.40E+3')

    def test_missing_future_stale_or_nonfinite_rate_never_becomes_zero(self):
        now=dt.datetime(2026,10,15,tzinfo=dt.timezone.utc)
        for day,rate in [('2026-10-16','1540'),('2026-10-01','1540'),('2026-10-15','NaN'),('2026-10-15','0')]:
            raw=f'<Cube time="{day}"><Cube currency="USD" rate="1"/><Cube currency="KRW" rate="{rate}"/></Cube>'.encode()
            with self.assertRaises(r2_cost.MetricsError):r2_cost.exchange_xml(raw,now)
        with self.assertRaises(r2_cost.MetricsError):r2_cost.exchange_xml(b'<Cube/>',now)
