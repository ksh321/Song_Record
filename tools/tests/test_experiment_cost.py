import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT/'infra/experiment'), str(ROOT/'tools')]
import notify
spec = importlib.util.spec_from_file_location('experiment_cost', ROOT/'infra/experiment/cost.py')
cost = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cost)


class ExperimentCostTests(unittest.TestCase):
    def test_http200_requires_matching_message_receipt_and_does_not_expose_topic(self):
        from contextlib import nullcontext
        from unittest.mock import Mock
        for matches in (False, True):
            with tempfile.TemporaryDirectory() as directory:
                root=Path(directory);config=root/'monitoring.json';topic='sr-'+'0'*48
                config.write_text(json.dumps({'ntfy_topic':topic}))
                reply=Mock(status=200)
                reply.read.return_value=json.dumps({'event':'message','id':'synthetic-id',
                    'topic':topic if matches else 'different-topic','time':1}).encode()
                with patch.object(notify,'ROOT',root),patch.object(notify,'CONFIG',config), \
                     patch.object(notify.os,'getuid',return_value=0,create=True), \
                     patch.object(notify.urllib.request,'build_opener') as client:
                    client.return_value.open.return_value=nullcontext(reply)
                    if matches:self.assertEqual(notify.send('Trial','receipt-check'),'SERVER_ACCEPTED')
                    else:
                        with self.assertRaisesRegex(ValueError,'EXPERIMENT_ALERT_DELIVERY_UNCONFIRMED'):
                            notify.send('Trial','receipt-check')
                record=(root/'notification-receipt-check.json').read_text()
                self.assertNotIn(topic,record)
                self.assertEqual(json.loads(record)['status'],'SERVER_ACCEPTED' if matches else 'ATTEMPTED')

    def test_unknown_notification_result_is_not_automatically_resent(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            config=root/'monitoring.json'
            config.write_text(json.dumps({'ntfy_topic':'sr-'+'0'*48}))
            with patch.object(notify,'ROOT',root), patch.object(notify,'CONFIG',config), \
                 patch.object(notify.os,'getuid',return_value=0,create=True), \
                 patch.object(notify.urllib.request,'build_opener') as client:
                client.return_value.open.side_effect=TimeoutError()
                with self.assertRaises(TimeoutError):notify.send('Trial','USER-127')
                self.assertEqual(notify.send('Trial','USER-127'),'ATTEMPTED')
                self.assertEqual(client.return_value.open.call_count,1)
                self.assertNotIn('sr-',(root/'notification-USER-127.json').read_text())

    def test_query_failure_keeps_last_good_cost_and_never_applies_fake_zero(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);latest=root/'cost-latest.json';latest.write_text('{"status":"PASS","r2_projected_month_krw":70000}')
            with patch.object(cost,'ROOT',root),patch.object(cost.os,'getuid',return_value=0,create=True), \
                 patch.object(cost.Path,'read_text',side_effect=lambda *args,**kwargs: '{"analytics_token":"synthetic"}'), \
                 patch.object(cost.r2_cost,'check_pricing',return_value={}), \
                 patch.object(cost.metrics,'fetch',side_effect=cost.metrics.MetricsError('NETWORK_UNCONFIRMED')), \
                 patch.object(cost,'operator') as operator,patch.object(cost,'send') as send:
                with self.assertRaisesRegex(RuntimeError,'^EXPERIMENT_COST_CHECK_UNCONFIRMED$'):cost.once()
                operator.assert_not_called();send.assert_called_once()
            self.assertEqual(json.loads(latest.read_text())['r2_projected_month_krw'],70000)
            self.assertEqual(json.loads((root/'cost-failure.json').read_text())['level'],'UNCONFIRMED')
