"""Bounded sealed stdin -> role-private tmpfs; never prints configuration or secret values."""
import base64,json,os,sys
from pathlib import Path
root=Path('/run/runtime')
try:
 raw=sys.stdin.buffer.read(131073)
 if len(raw)>131072:raise ValueError()
 values=json.loads(raw);os.umask(0o077)
 if not isinstance(values,dict) or not 1<=len(values)<=64:raise ValueError()
 for name,value in values.items():
  if not isinstance(name,str) or not name or len(name)>128 or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-' for c in name) or name=='ready':raise ValueError()
  if not isinstance(value,str) or len(value)>65536:raise ValueError()
  path=root/name
  if path.exists() or path.is_symlink():raise ValueError()
  content=base64.b64decode(value,validate=True) if name.endswith('.p12') else value.encode('utf-8')
  with path.open('xb') as f:f.write(content);f.flush();os.fsync(f.fileno())
 (root/'ready').write_text('ready',encoding='ascii')
 print('Runtime configuration loaded; values suppressed')
except Exception:
 print('Runtime configuration rejected; values suppressed',file=sys.stderr);sys.exit(2)
