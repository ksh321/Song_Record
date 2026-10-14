"""Independent encrypted deletion mirror, restore filtering and seven-day backup cleanup."""
import datetime as dt
import json
import uuid
import re
from operational_backup import INDEX, PREFIX, digest, encoded, check_file, Backup
from backup_store import BackupError

LEDGER = PREFIX + 'deletion-ledger.enc'
FILES = PREFIX + 'file-inventory.enc'
TYPES = {'USER','SONG','RECORDING','RECORDING_ASSET','PLAYLIST','PLAYLIST_ITEM','TAG','CONDITION'}


def subject(row):
    try:
        owner, entity = str(uuid.UUID(row['owner'])), str(uuid.UUID(row['entity']))
        kind = row['type']; generation = row.get('generation')
        if kind not in TYPES or (kind=='RECORDING_ASSET') != bool(generation) or (kind=='USER' and owner!=entity):
            raise ValueError()
        if uuid.UUID(owner).int==0 or uuid.UUID(entity).int==0:
            raise ValueError()
        if generation:
            generation = str(uuid.UUID(generation))
            if uuid.UUID(generation).int==0:raise ValueError()
        return owner,kind,entity,generation
    except Exception:
        raise BackupError('BACKUP_LEDGER_INVALID') from None


def valid(row):
    subject(row)
    if row.get('state') not in ('REQUESTED','COMMITTED','CANCELLED') or type(row.get('revision')) is not int or row['revision']<1:
        raise BackupError('BACKUP_LEDGER_INVALID')
    stamp=dt.datetime.fromisoformat(row['at'])
    if stamp.tzinfo is None:raise BackupError('BACKUP_LEDGER_INVALID')
    return row


def blocked(file, entries):
    check_file(file)
    for row in entries:
        if row['state']=='CANCELLED' or row['owner']!=file['owner']:continue
        if row['type']=='USER' or row['type']=='RECORDING' and row['entity']==file['recording'] or row['type']=='RECORDING_ASSET' and row['entity']==file['recording'] and row['generation']==file['generation']:
            return True
    return False


class Ledger:
    def __init__(self, store, instance):self.store,self.instance=store,instance
    def read(self, allow_missing=False):
        raw=self.store.get(LEDGER)
        if raw is None:
            if allow_missing:return []
            raise BackupError('BACKUP_LEDGER_UNAVAILABLE')
        try:
            value=json.loads(raw)
            if value['schema']!=1 or value['instance']!=self.instance or len(value['entries'])>100000:
                raise ValueError()
            entries=[valid(row) for row in value['entries']]
            if len({subject(row) for row in entries})!=len(entries):raise ValueError()
            return entries
        except Exception:raise BackupError('BACKUP_LEDGER_INVALID') from None

    def merge(self, source):
        entries={subject(row):row for row in self.read(allow_missing=True)}
        for incoming in source:
            row=valid(incoming);key=subject(row);old=entries.get(key)
            # Confirmed permanent deletions cannot be cancelled or overwritten by old restored DB data.
            if old and old['state']=='COMMITTED':continue
            if row['state']=='COMMITTED':
                row=dict(row);row['revision']=max(row['revision'],old['revision']+1 if old else 1)
                entries[key]=row;continue
            if old and old['revision']>row['revision']:continue
            if old and old['revision']==row['revision'] and old['state']!=row['state']:
                raise BackupError('BACKUP_LEDGER_REVISION_CONFLICT')
            entries[key]=row
        rows=sorted(entries.values(),key=lambda r:encoded(subject(r)))
        raw=encoded({'schema':1,'instance':self.instance,'entries':rows})
        if self.store.get(LEDGER)!=raw:self.store.put(LEDGER,raw)
        # Caller may acknowledge only after authenticated remote readback.
        if self.read()!=rows:raise BackupError('BACKUP_LEDGER_READBACK_FAILED')
        return rows

    def prune(self, now, listed=None):
        rows=self.read(); raw=self.store.get(INDEX)
        if raw is None:return {'removed_points':0,'removed_files':0,'absent_owners':[]}
        catalog=json.loads(raw)
        if catalog.get('instance')!=self.instance:raise BackupError('CATALOG_INVALID')
        # Unfinished expired DB deletion cannot be treated as owner absence.
        if catalog.get('pending_prune'):Backup(self.store,None,None,self.instance).prune(catalog)
        points=[]; expired=[]; manifests=[]; all_manifests=[]
        for point in catalog['points']:
            base=PREFIX+'points/'+str(uuid.UUID(point['id']))+'/'
            data=self.store.get(base+'manifest.enc')
            if data is None or digest(data)!=point['manifest_hash']:raise BackupError('POINT_MANIFEST_INVALID')
            manifest=json.loads(data);stamp=dt.datetime.fromisoformat(manifest['created_utc'])
            all_manifests.append(manifest)
            if stamp.tzinfo is None or stamp>now:raise BackupError('POINT_TIME_INVALID')
            if now-stamp>=dt.timedelta(days=7):expired.append(point)
            else:points.append(point);manifests.append(manifest)
        inventory_raw=self.store.get(FILES)
        inventory=json.loads(inventory_raw) if inventory_raw is not None else []
        mapped={check_file(file):file for file in inventory}
        for manifest in all_manifests:
            for file in manifest['files']:mapped[check_file(file)]=file
        inventory_encoded=encoded(list(mapped.values()))
        if inventory_raw!=inventory_encoded:self.store.put(FILES,inventory_encoded)
        # Persist cleanup before issuing deletion, so crashes are replayable by the daily executor.
        if expired:
            catalog['points']=points
            catalog['pending_prune']=catalog.get('pending_prune',[])+[p['id'] for p in expired]
            self.store.put(INDEX,encoded(catalog))
            for point in expired:
                base=PREFIX+'points/'+str(uuid.UUID(point['id']))+'/'
                self.store.delete(base+'database.enc');self.store.delete(base+'manifest.enc')
            catalog['pending_prune']=[];self.store.put(INDEX,encoded(catalog))
        removed=0;deleted_paths=set()
        # Deletion rows are kept independently. Active generations and other owners are untouched.
        for path,file in list(mapped.items()):
            relevant=[r for r in rows if r['state']=='COMMITTED' and blocked(file,[r]) and now-dt.datetime.fromisoformat(r['at'])>=dt.timedelta(days=7)]
            if relevant:
                if self.store.get(path) is not None:self.store.delete(path);removed+=1
                deleted_paths.add(path)
                del mapped[path]
        final_inventory=encoded(list(mapped.values()))
        if final_inventory!=inventory_encoded:self.store.put(FILES,final_inventory)
        unknown=False
        if listed is not None:
            known={INDEX,LEDGER,FILES,PREFIX+'recovery-key.enc'}|set(mapped)
            known|={PREFIX+'points/'+p['id']+'/'+name for p in points for name in ('database.enc','manifest.enc')}
            for item in listed:
                path=item['key']
                if path in known:continue
                if path in deleted_paths:continue
                # Previously indexed objects deleted above are not unknown artifacts.
                if path in {check_file(f) for m in all_manifests for f in m['files']} and self.store.get(path) is None:continue
                if any(path.startswith(PREFIX+'points/'+p['id']+'/') for p in expired):continue
                stamp=dt.datetime.fromisoformat(item['at'].replace('Z','+00:00'))
                orphan=re.fullmatch(re.escape(PREFIX)+r'points/([0-9a-f-]{36})/(database|manifest)\.enc',path)
                if orphan and now-stamp>=dt.timedelta(days=7):
                    uuid.UUID(orphan.group(1));self.store.delete(path)
                else:unknown=True
        absent=[]
        for row in rows:
            if row['type']!='USER' or row['state']=='CANCELLED':continue
            # Legacy points lacking an all-owner DB subject list conservatively block absence.
            if not unknown and all('subjects' in m and row['owner'] not in m['subjects'] for m in manifests) and not any(f['owner']==row['owner'] for f in mapped.values()):absent.append(row['owner'])
        return {'removed_points':len(expired),'removed_files':removed,'absent_owners':absent,'unknown_artifacts':unknown}

    def retire_owners(self, owners, now, absent_owners):
        rows=self.read();retired=set()
        for owner in owners:
            if owner not in absent_owners:raise BackupError('BACKUP_RETIREMENT_AUTHORITY')
            evidence=next((row for row in rows if row['type']=='USER' and row['owner']==owner and row['state']=='COMMITTED'),None)
            if evidence is None or now-dt.datetime.fromisoformat(evidence['at'])<dt.timedelta(days=30):raise BackupError('BACKUP_RETIREMENT_AUTHORITY')
            retired.add(owner)
        if retired:self.store.put(LEDGER,encoded({'schema':1,'instance':self.instance,'entries':[r for r in rows if r['owner'] not in retired]}))

    def require_restore(self, files):
        entries=self.read()
        return [file for file in files if not blocked(file,entries)]
