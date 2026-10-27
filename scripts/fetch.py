#!/usr/bin/env python3
"""Fetch pinned upstream binaries; every archive is verified before extraction."""
from pathlib import Path
import hashlib,json,tarfile,urllib.request,urllib.parse
root=Path(__file__).resolve().parents[1];work=root/'work';work.mkdir(exist_ok=True)
for kind,lockfile in [('cef','engine.lock.json'),('sparkle','sparkle.lock.json')]:
 lock=json.loads((root/lockfile).read_text())
 url=lock.get('url') or 'https://cef-builds.spotifycdn.com/'+urllib.parse.quote(lock['filename'])
 name=lock.get('filename') or url.rsplit('/',1)[-1]
 destination=work/(name.removesuffix('.tar.bz2') if kind=='cef' else 'sparkle')
 if (destination/('include/cef_app.h' if kind=='cef' else 'Sparkle.framework')).exists():continue
 archive=work/name
 if not archive.exists():urllib.request.urlretrieve(url,archive)
 if hashlib.sha256(archive.read_bytes()).hexdigest()!=lock['sha256']:raise SystemExit('Archive checksum mismatch: '+name)
 if kind=='sparkle':destination.mkdir(exist_ok=True)
 with tarfile.open(archive) as f:f.extractall(work if kind=='cef' else destination,filter='data')
 print('Verified and extracted',name)
