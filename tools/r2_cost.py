"""Account-wide Standard R2 estimates from provider aggregates; never an invoice/billing cap."""
import calendar,datetime as dt,json,subprocess
from decimal import Decimal,ROUND_CEILING
from pathlib import Path
from cloudflare_metrics import MetricsError
D=Decimal
A=set('ListBuckets PutBucket ListObjects PutObject CopyObject CompleteMultipartUpload CreateMultipartUpload LifecycleStorageTierTransition ListMultipartUploads UploadPart UploadPartCopy ListParts PutBucketEncryption PutBucketCors PutBucketLifecycleConfiguration'.split())
B=set('HeadBucket HeadObject GetObject UsageSummary GetBucketEncryption GetBucketLocation GetBucketCors GetBucketLifecycleConfiguration'.split())
FREE=set('DeleteObject DeleteBucket AbortMultipartUpload'.split())
# Provider analytics reports these management reads but the published tariff does not classify them.
# Keep the count separate and conservatively budget at Standard's higher request rate, never as free.
MANAGEMENT_UNCLASSIFIED={'GetBucketSippyConfiguration','GetBucketNotificationConfiguration'}
BUCKETS={f'song-record-{env}-{kind}':kind for env in ('dev','prod','staging-dev') for kind in ('temporary','final')}
BUCKETS['song-record-staging-backup']='backup'
PRICE_SOURCE='https://raw.githubusercontent.com/cloudflare/cloudflare-docs/production/src/content/docs/r2/pricing.mdx'

def check_pricing(now):
 import urllib.request,re,hashlib
 client=urllib.request.build_opener(urllib.request.ProxyHandler({}))
 try:
  with client.open(PRICE_SOURCE,timeout=20) as reply:raw=reply.read(200001)
  if len(raw)>200000:raise ValueError()
  text=raw.decode('utf-8')
  expected=[r'^\|\s*Storage\s*\|\s*\$0\.015 / GB-month\s*\|',r'^\|\s*Class A Operations\s*\|\s*\$4\.50 / million requests\s*\|',r'^\|\s*Class B Operations\s*\|\s*\$0\.36 / million requests\s*\|',r'^\|\s*Storage\s*\|\s*10 GB-month / month\s*\|',r'^\|\s*Class A Operations\s*\|\s*1 million requests / month\s*\|',r'^\|\s*Class B Operations\s*\|\s*10 million requests / month\s*\|']
  if not all(re.search(p,text,re.M) for p in expected):raise ValueError()
  for marker,actions in (('Class A Operations include',A),('Class B Operations include',B),('Free operations include',FREE)):
   line=next(line for line in text.splitlines() if marker in line)
   if set(re.findall(r'`([A-Za-z]+)`',line))!=actions:raise ValueError()
 except Exception:raise MetricsError('PUBLISHED_PRICING_UNCONFIRMED') from None
 return {'source':PRICE_SOURCE,'sha256':hashlib.sha256(raw).hexdigest(),'checked_utc':now.isoformat(),'status':'MATCH'}

def cycle(now,day=8):
 if not 1<=day<=28:raise MetricsError('BILLING_ANCHOR_UNCONFIRMED')
 start=now.replace(day=day,hour=0,minute=0,second=0,microsecond=0)
 if now<start:start=(start.replace(day=1)-dt.timedelta(days=1)).replace(day=day)
 end=(start.replace(day=28)+dt.timedelta(days=4)).replace(day=day)
 return start,end

def usd(storage_gb_month,a,b):
 def units(value,free,unit):return max(D(0),(D(value)-D(free))/D(unit)).to_integral_value(rounding=ROUND_CEILING)
 return units(storage_gb_month,10,1)*D('.015')+units(a,1000000,1000000)*D('4.50')+units(b,10000000,1000000)*D('.36')

def exchange(now):
 # Windows certificate store, no insecure TLS fallback or API key. Output is public FX only.
 command="[xml]$r=(Invoke-WebRequest -Uri 'https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml' -TimeoutSec 20).Content; $r.DocumentElement.Cube.Cube | ForEach-Object { @{date=$_.time; USD=($_.Cube | Where-Object currency -eq 'USD').rate; KRW=($_.Cube | Where-Object currency -eq 'KRW').rate} | ConvertTo-Json -Compress }"
 p=subprocess.run(['pwsh','-NoProfile','-Command',command],capture_output=True,timeout=30)
 if p.returncode:raise MetricsError('FX_UNCONFIRMED')
 try:
  row=json.loads(p.stdout.decode('utf-8-sig'));age=(now.date()-dt.date.fromisoformat(row['date'])).days
  rate=D(row['KRW'])/D(row['USD'])
  if not 0<=age<=7 or not D(100)<=rate<=D(10000):raise ValueError()
 except Exception:raise MetricsError('FX_UNCONFIRMED') from None
 return {'source':'ECB EUR cross rate','date':row['date'],'krw_per_usd':str(rate)}

def estimate(snapshot,fx,registry=None):
 registry=registry or BUCKETS
 start=dt.datetime.fromisoformat(snapshot['period_start']);end=dt.datetime.fromisoformat(snapshot['period_end'])
 anchor,next_cycle=cycle(end)
 if start!=anchor or end<=start:raise MetricsError('BILLING_RANGE_UNCONFIRMED')
 a=b=free=unclassified=0
 for row in snapshot['operations']:
  dim=row['dimensions'];action=dim['actionType'];bucket=dim.get('bucketName')
  if bucket and bucket not in registry:raise MetricsError('BUCKET_CLASS_UNCONFIRMED')
  count=row['sum']['requests']
  if not isinstance(count,int) or count<0:raise MetricsError('REQUEST_COUNT_UNCONFIRMED')
  if str(dim.get('responseStatusCode'))=='401' or action in FREE:free+=count
  elif action in A:a+=count
  elif action in B:b+=count
  elif action in MANAGEMENT_UNCLASSIFIED:unclassified+=count
  else:raise MetricsError('REQUEST_CLASS_UNCONFIRMED')
 peaks={};by_day={};latest={}
 for row in snapshot['storage']:
  dim=row['dimensions'];bucket=dim['bucketName']
  if bucket not in registry:raise MetricsError('BUCKET_CLASS_UNCONFIRMED')
  stamp=dt.datetime.fromisoformat(dim['datetime'].replace('Z','+00:00'));v=row['max'];size=v['payloadSize']+v['metadataSize']
  if not isinstance(size,int) or size<0 or stamp<start-dt.timedelta(days=1) or stamp>end:raise MetricsError('STORAGE_OBSERVATION_UNCONFIRMED')
  peaks[bucket]=max(peaks.get(bucket,0),size);key=(stamp.date().isoformat(),bucket);by_day[key]=max(by_day.get(key,0),size)
  if bucket not in latest or stamp>latest[bucket][0]:latest[bucket]=(stamp,size)
 if set(latest)!=set(registry):raise MetricsError('STORAGE_COVERAGE_UNCONFIRMED')
 if any(end-stamp>dt.timedelta(hours=26) for stamp,size in latest.values()):raise MetricsError('STORAGE_STALE')
 # Provider samples of daily peaks. Missing samples are reported, never called an invoice total.
 observed_gbm=D(sum(by_day.values()))/D(1000000000)/D(30)
 # Conservative storage projection: all per-bucket observed peaks persist for the full cycle.
 projected_gbm=D(sum(peaks.values()))/D(1000000000)*D((next_cycle-anchor).days)/D(30)
 factor=D(str((next_cycle-anchor).total_seconds()))/D(str((end-anchor).total_seconds()))
 projected_usd=usd(projected_gbm,D(a+unclassified)*factor,D(b)*factor);rate=D(fx['krw_per_usd'])
 krw=int((projected_usd*rate).to_integral_value(rounding=ROUND_CEILING))
 category={kind:sum(size for bucket,(stamp,size) in latest.items() if registry[bucket]==kind) for kind in ('temporary','final','backup')}
 return {'status':'PASS','queried_utc':snapshot['queried_utc'],'billing_start':anchor.isoformat(),'billing_end':next_cycle.isoformat(),'billing_anchor_source':'R2 dashboard: day 8; UTC boundary assumption',
 'class_a_observed':a,'class_b_observed':b,'free_operations_observed':free,'unclassified_management_operations':unclassified,'unclassified_cost_assumption':'These two observed management reads are budgeted at higher Standard Class A rate; actual billing class unconfirmed. Other unknown actions fail closed.', 'current_bytes_by_category':category,'sampled_gb_month_to_date':str(observed_gbm),
 'r2_estimate_to_date_usd':str(usd(observed_gbm,a+unclassified,b)),'r2_projected_month_usd':str(projected_usd),'r2_projected_month_krw':krw,'fx':fx,
 'level':'LOCK' if krw>=70000 else 'WARNING' if krw>=60000 else 'NOTICE' if krw>=50000 else 'NORMAL',
 'estimate_assumptions':'Account-wide free tier once; Standard only; hourly samples of daily peaks, per-bucket historical peaks persist; requests continue at cycle-average pace; not invoice/cap.',
 'separate_costs':{'server':'Laptop validation: no new paid server','mysql':'Laptop Docker: no new paid DB','backup':'Backup R2 storage and requests included; missing provider samples are unconfirmed, not zero','monitoring':'Local scripts: no new paid monitor','tax':'Excluded: actual invoice tax unconfirmed','fx':'ECB dated spot reference; card settlement FX differs'},
 'invoice_actual_krw':None,'unknown_buckets_fail_closed':True}
