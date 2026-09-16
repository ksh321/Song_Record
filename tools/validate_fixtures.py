"""Validate fixtures, not the unimplemented Flutter/Spring product."""
import json, hashlib, unicodedata, re, uuid, subprocess
from pathlib import Path
from functools import cmp_to_key
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo
ROOT=Path(__file__).resolve().parents[1]
def read(p):return json.loads((ROOT/p).read_text(encoding='utf-8'))
def sha(p):return hashlib.sha256((ROOT/p).read_bytes()).hexdigest()
WS=''.join(chr(c) for c in [*range(9,14),32,133,160,5760,*range(8192,8203),8232,8233,8239,8287,12288])
def key(s):
 s=unicodedata.normalize('NFC',s.strip(WS)).translate(str.maketrans('ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'))
 if not s:g=4
 else:
  c=ord(s[0]);h=any(a<=c<=b for a,b in [(0xac00,0xd7a3),(0x1100,0x11ff),(0x3130,0x318f),(0xa960,0xa97f),(0xd7b0,0xd7ff)])
  g=0 if h else 1 if 'a'<=s[0]<='z' else 2 if '0'<=s[0]<='9' else 3
 tokens=[]
 for t in re.findall(r'[0-9]+|[^0-9]',s):
  if t.isascii() and t.isdigit():
   n=t.lstrip('0') or '0';tokens.append((0,len(n),n))
  else:tokens.append((1,ord(t)))
 return g,tokens
def stamp(s):return datetime.fromisoformat(s.replace('Z','+00:00')).timestamp()
def evaluate(c):
 i=c['input'];kind=c['kind']
 if kind=='title_sort':return {'ids':[r['id'] for r in sorted(i['rows'],key=lambda r:(key(r['title']),uuid.UUID(r['id']).bytes))]}
 if kind=='length':
  v=i['value'].replace('\r\n','\n').replace('\r','\n') if i['field']=='note' else i['value'].strip(WS)
  return {'actual':len(v),'valid':i['min']<=len(v)<=i['max']}
 if kind=='date_range':
  z=ZoneInfo(i['zone']);a=datetime.fromisoformat(i['from']).replace(tzinfo=z);b=datetime.fromisoformat(i['to']).replace(tzinfo=z)+timedelta(days=1)
  return {'start':a.astimezone(timezone.utc).isoformat().replace('+00:00','Z'),'end_exclusive':b.astimezone(timezone.utc).isoformat().replace('+00:00','Z')}
 if kind=='song_identity':
  a,b=i['existing'],i['incoming'];same=(a['account_id'],a['tj_number'])==(b['account_id'],b['tj_number'])
  return dict(same_identity=same,**({'existing_id':a['id']} if same else {}))
 if kind=='retention':
  rs=[r for r in i['recordings'] if r['lifecycle']=='ACTIVE' and r['metadata']=='SAVED' and r['valid_file_manifest']]
  recent=sorted(rs,key=lambda r:(-stamp(r['recorded_at']),uuid.UUID(r['id']).bytes))
  tiers=sorted([r for r in rs if r['tier'] is not None],key=lambda r:('DCBAS'.index(r['tier']),-stamp(r['recorded_at']),uuid.UUID(r['id']).bytes))
  rep=i['representative_id'] if i['representative_id'] in [r['id'] for r in rs] else None
  latest=recent[0]['id'] if recent else None;lowest=tiers[0]['id'] if tiers else None
  return dict(representative=rep,latest=latest,lowest=lowest,unique_ids=sorted(set(x for x in [rep,latest,lowest] if x)))
 if kind=='file_filter':
  desired='PRESENT' if i['filter']=='LOCAL_ONLY' else 'ABSENT';rs=[r for r in i['rows'] if not r['stored']]
  unknown=[r['id'] for r in rs if r['local']=='UNKNOWN']
  return dict(ids=[r['id'] for r in rs if r['local']==desired],unknown_ids=unknown,exact=not unknown)
 if kind=='offline_backup':return dict(included=[x for x in i['selected'] if x in i['local_audio']],missing=[x for x in i['selected'] if x not in i['local_audio']],scope='OFFLINE_PARTIAL')
 if kind=='classification':return {'valid':i['condition'] in [None,'VERY_GOOD','GOOD','NORMAL','BAD'] and len(i['tag_ids'])==len(set(i['tag_ids']))}
 raise AssertionError('Unhandled kind '+kind)
def main():
 index=read('fixtures/index.json');ids=set();pure=spec=0
 for f in index['files']:
  assert sha(f['path'])==f['sha256'],f['path']
  d=read(f['path']);assert d['schema_version']==1
  cases=d.get('cases',[]);assert f['case_ids']==[c['id'] for c in cases]
  for c in cases:
   assert c['id'] not in ids,c['id'];ids.add(c['id'])
   assert c['input'] and c['expected'] and c['refs']
   for ref in c['refs']:assert (ROOT/ref.split('#')[0]).exists(),ref
   if c['kind']=='integration_spec':spec+=1
   else:
    actual=evaluate(c);assert actual==c['expected'],(c['id'],actual,c['expected']);pure+=1
 for s in index['source_contracts']:assert sha(s['path'])==s['sha256_utf8'],s['path']
 e=read('fixtures/songs/entities.json');accounts={x['id'] for x in e['accounts']};songs={x['id'] for x in e['songs']}
 for group in ['accounts','songs','tags','playlists']:
  vals=[x['id'] for x in e[group]];assert len(vals)==len(set(vals))
  for v in vals:uuid.UUID(v)
 for x in e['songs']+e['tags']+e['playlists']:assert x['account_id'] in accounts
 for p in e['playlists']:
  for sid in p['song_ids']:assert sid in songs and next(s for s in e['songs'] if s['id']==sid)['account_id']==p['account_id']
 tags={x['id'] for x in e['tags']}
 for c in read('fixtures/contracts/conditions.json')['cases']:assert set(c['input']['tag_ids'])<=tags
 m=read('fixtures/files/manifest.json')
 for a in m['assets']:
  p=ROOT/a['path'];assert p.stat().st_size==a['size_bytes'];assert sha(a['path'])==a['sha256']
  result=subprocess.run(['ffmpeg','-v','error','-xerror','-i',str(p),'-f','null','-'],capture_output=True)
  assert (result.returncode==0)==a['expected_decode'],a['path']
  if a['expected_decode']:
   probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_format','-show_streams','-of','json',str(p)]))
   assert round(float(probe['format']['duration'])*1000)==a['duration_ms']
   assert probe['streams'][0]['codec_name']==a['codec']
 assert sha(m['mismatch_case']['path'])!=m['mismatch_case']['claimed_sha256']
 print(json.dumps(dict(status='PASS',case_count=len(ids),reference_evaluations=pure,integration_specs_not_executed=spec,media_assets_verified=len(m['assets']),product_tests_executed=0),indent=2))
if __name__=='__main__':main()
