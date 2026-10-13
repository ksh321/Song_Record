import unittest,tempfile,json,sys,urllib.error,datetime as dt
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import cloudflare_metrics as m
class Reply:
 def __enter__(self):return self
 def __exit__(self,*args):pass
 def read(self,n):return json.dumps({'data':{'viewer':{'accounts':[{'r2OperationsAdaptiveGroups':[],'r2StorageAdaptiveGroups':[]}]}}}).encode()
class Client:
 def open(self,request,timeout):
  if request.full_url.endswith('/r2/buckets'):raise urllib.error.HTTPError(request.full_url,403,'denied',None,None)
  self.request=request;return Reply()
class MetricsTests(unittest.TestCase):
 def test_token_identifier_is_rejected_without_network(self):
  with self.assertRaisesRegex(m.MetricsError,'TOKEN_ID_OR_NAME_INSTEAD_OF_SECRET'):m.verify('a'*32)
 def test_new_token_authentication_has_bounded_retry_before_any_storage(self):
  class Verified(Reply):
   def read(self,n):return b'{"success":true,"result":{"status":"active"}}'
  errors=[urllib.error.HTTPError('https://api.cloudflare.com/',401,'denied',None,None)]*2
  with patch.object(m.urllib.request,'build_opener') as factory,patch.object(m.time,'sleep') as pause:
   factory.return_value.open.side_effect=errors+[Verified()]
   m.verify('cfat_synthetic-token-only-000000000000')
   self.assertEqual(factory.return_value.open.call_count,3)
   self.assertEqual([c.args[0] for c in pause.call_args_list],[2,5])
 def test_query_avoids_objects_notes_and_token_in_url_or_body(self):
  c=Client();token='synthetic-metrics-token-only-0000'
  with patch.object(m.urllib.request,'build_opener',return_value=c):r=m.fetch(token,scope_check=True)
  self.assertEqual(r['account'],m.ACCOUNT);self.assertNotIn(token,c.request.full_url);self.assertNotIn(token,c.request.data.decode());self.assertNotIn('objectName',m.QUERY)
 def test_management_access_is_rejected(self):
  class Broad(Client):
   def open(self,*args,**kwargs):return Reply()
  with patch.object(m.urllib.request,'build_opener',return_value=Broad()):
   with self.assertRaisesRegex(m.MetricsError,'R2_MANAGEMENT_SCOPE_TOO_BROAD'):m.fetch('synthetic-metrics-token-only-0000',scope_check=True)
 def test_wrong_vault_scope_is_rejected_without_exposing_token(self):
  with tempfile.TemporaryDirectory() as d,patch.object(m,'DIRECTORY',Path(d)),patch.object(m,'_crypt',return_value=b'{"scope":"other","account":"wrong","token":"synthetic-value"}'):
   (Path(d)/'analytics.dpapi').write_bytes(b'synthetic-encrypted')
   with self.assertRaisesRegex(m.MetricsError,'VAULT_SCOPE_UNCONFIRMED'):m.load()
 def test_query_range_and_header_injection_are_rejected_before_network(self):
  with self.assertRaises(m.MetricsError):m.fetch('synthetic-metrics-token-only-0000\nheader')
  now=dt.datetime.now(dt.timezone.utc)
  with self.assertRaisesRegex(m.MetricsError,'QUERY_RANGE_INVALID'):m.fetch('synthetic-metrics-token-only-0000',start=now-dt.timedelta(days=32),end=now)
if __name__=='__main__':unittest.main()
