#!/usr/bin/env python3
"""Sign nested Mach-O code and bundles inside out; retain Chromium's sandbox."""
import argparse,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('app',type=Path);p.add_argument('--identity',default='-');args=p.parse_args()
app=args.app.resolve();root=Path(__file__).resolve().parents[1]
assert app.is_dir() and app.suffix=='.app'
common=['codesign','--force','--sign',args.identity,'--options','runtime','--timestamp' if args.identity!='-' else '--timestamp=none']
def sign(path):
 cmd=common.copy()
 if path==app or 'Wai Browser Helper' in path.name or path.name=='Wai Browser':cmd+=['--entitlements',str(root/'resources/chromium.entitlements')]
 else:cmd+=['--preserve-metadata=entitlements']
 result=subprocess.run(cmd+[str(path)],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,text=True)
 if result.returncode:raise SystemExit(result.stderr)
magic={b'\xcf\xfa\xed\xfe',b'\xce\xfa\xed\xfe',b'\xca\xfe\xba\xbe',b'\xca\xfe\xba\xbf'}
for path in sorted(app.rglob('*'),key=lambda p:len(p.parts),reverse=True):
 if path.is_symlink():continue
 if path.is_file():
  with path.open('rb') as f:is_macho=f.read(4) in magic
  if is_macho:sign(path)
 elif path.suffix in {'.framework','.app','.xpc'}:sign(path)
sign(app)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
print('Signed and verified:',app)
