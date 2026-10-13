import sys,unittest,datetime as dt,copy
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import r2_cost as c
from cloudflare_metrics import MetricsError
class CostTests(unittest.TestCase):
 def snapshot(self):
  return {'period_start':'2026-10-08T00:00:00+00:00','period_end':'2026-10-13T00:00:00+00:00','queried_utc':'2026-10-13T00:00:00+00:00','operations':[{'dimensions':{'actionType':'PutObject','responseStatusCode':200,'bucketName':'song-record-dev-temporary'},'sum':{'requests':100}}], 'storage':[{'dimensions':{'bucketName':b,'datetime':'2026-10-12T23:00:00Z'},'max':{'payloadSize':0,'metadataSize':0}} for b in c.BUCKETS]}
 def test_free_tier_is_account_wide_and_rounding_matches_provider_units(self):
  self.assertEqual(c.usd(10,1000000,10000000),0);self.assertEqual(c.usd(10.1,1000001,10000001),c.D('4.875'))
 def test_cycle_uses_observed_day_eight_across_year_and_leap_month(self):
  for date,expect in [('2027-01-01','2026-12-08'),('2028-03-01','2028-02-08')]:self.assertEqual(c.cycle(dt.datetime.fromisoformat(date+'T00:00:00+00:00'))[0].date().isoformat(),expect)
 def test_temp_and_backup_bytes_are_not_excluded_from_cost(self):
  s=self.snapshot();s['storage'][0]['max']['payloadSize']=100000000000
  registry=dict(c.BUCKETS);registry['song-record-backup']='backup';s['storage'].append({'dimensions':{'bucketName':'song-record-backup','datetime':'2026-10-12T23:00:00Z'},'max':{'payloadSize':100000000000,'metadataSize':0}})
  r=c.estimate(s,{'krw_per_usd':'1300'},registry);self.assertEqual(r['current_bytes_by_category']['backup'],100000000000);self.assertGreater(r['r2_projected_month_krw'],0)
 def test_uncovered_unknown_buckets_classes_and_stale_storage_are_not_zero(self):
  for change in ('missing','unknown','stale'):
   s=self.snapshot()
   if change=='missing':s['storage'].pop()
   elif change=='unknown':s['storage'][0]['dimensions']['bucketName']='unregistered'
   else:s['storage'][0]['dimensions']['datetime']='2026-10-09T00:00:00Z'
   with self.assertRaises(MetricsError):c.estimate(s,{'krw_per_usd':'1300'})
 def test_unauthorized_and_free_deletions_are_not_charged_unknown_action_rejected(self):
  s=self.snapshot();s['operations'][0]['dimensions']['responseStatusCode']=401;self.assertEqual(c.estimate(s,{'krw_per_usd':'1300'})['class_a_observed'],0)
  s['operations'][0]['dimensions'].update(actionType='newUnknown',responseStatusCode=200)
  with self.assertRaises(MetricsError):c.estimate(s,{'krw_per_usd':'1300'})
 def test_forecast_thresholds_use_rounded_krw_and_do_not_claim_invoice(self):
  s=self.snapshot();s['operations'][0]['sum']['requests']=10000000
  first=c.estimate(s,{'krw_per_usd':'1300'});usd=c.D(first['r2_projected_month_usd'])
  for krw,level in ((49999,'NORMAL'),(50000,'NOTICE'),(60000,'WARNING'),(70000,'LOCK')):
   r=c.estimate(s,{'krw_per_usd':str((c.D(krw)-c.D('.25'))/usd)});self.assertEqual(r['level'],level);self.assertIsNone(r['invoice_actual_krw'])
 def test_observed_management_reads_are_separate_and_never_assumed_free(self):
  s=self.snapshot();s['operations'][0]['dimensions']['actionType']='GetBucketSippyConfiguration';s['operations'][0]['sum']['requests']=10000000
  r=c.estimate(s,{'krw_per_usd':'1300'});self.assertEqual(r['unclassified_management_operations'],10000000);self.assertEqual(r['class_a_observed'],0);self.assertGreater(r['r2_projected_month_krw'],70000)
if __name__=='__main__':unittest.main()
