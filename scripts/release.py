#!/usr/bin/env python3
"""Prepare a signed, notarized Sparkle release. Does not publish it."""
from pathlib import Path
import argparse,base64,json,os,plistlib,subprocess,tempfile,urllib.parse,xml.etree.ElementTree as ET
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--feed-url',required=True);p.add_argument('--download-prefix',required=True);p.add_argument('--build-number',required=True);args=p.parse_args()
for url in [args.feed_url,args.download_prefix]:
 parsed=urllib.parse.urlparse(url)
 if parsed.scheme!='https' or not parsed.netloc or parsed.username or parsed.password:raise SystemExit('Release URLs must be HTTPS')
run=lambda cmd:subprocess.run([str(x) for x in cmd],cwd=root,check=True)
run(['scripts/build.sh','-DWAI_UPDATE_FEED='+args.feed_url,'-DWAI_BUILD_NUMBER='+args.build_number])
run(['npm','ci','--ignore-scripts'])
run(['npm','run','test:browser'])
app=root/'build/Wai Browser.app';dist=root/'dist';dist.mkdir(exist_ok=True)
info=plistlib.loads((app/'Contents/Info.plist').read_bytes());version=info['CFBundleShortVersionString']
archive=dist/f'WaiBrowser-{version}-{args.build_number}-arm64.zip'
def package():
 if archive.exists():archive.unlink()
 run(['ditto','-c','-k','--sequesterRsrc','--keepParent',app,archive])
package()
config=json.loads((Path.home()/'.appstoreconnect/config.json').read_text())
result=subprocess.check_output(['xcrun','notarytool','submit',str(archive),'--key',config['key_filepath'],'--key-id',config['key_id'],'--issuer',config['issuer_id'],'--wait','--output-format','json'])
receipt=json.loads(result);(dist/'notarization.json').write_text(json.dumps(receipt,indent=2)+'\n')
if receipt.get('status')!='Accepted':raise SystemExit('Notarization did not succeed; see dist/notarization.json')
run(['xcrun','stapler','staple',app]);run(['spctl','--assess','--type','execute','--verbose=2',app]);package()
# A missing vault credential must stop the release, never generate a replacement key.
seed=subprocess.check_output(['op','read','op://Development/Wai Browser Sparkle EdDSA private key/password'],text=True).strip()
public=base64.b64encode(Ed25519PrivateKey.from_private_bytes(base64.b64decode(seed)).public_key().public_bytes(serialization.Encoding.Raw,serialization.PublicFormat.Raw)).decode()
if public!=info['SUPublicEDKey']:raise SystemExit('Vault key does not match the application public key')
with tempfile.TemporaryDirectory(prefix='wai-browser-signing-') as folder:
 key=Path(folder)/'key';fd=os.open(key,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
 with os.fdopen(fd,'w') as f:f.write(seed)
 feed=dist/'appcast.xml'
 previous={}
 if feed.exists():
  for enclosure in ET.fromstring(feed.read_bytes()).iter('enclosure'):
   url=enclosure.get('url','');previous[urllib.parse.unquote(urllib.parse.urlparse(url).path.rsplit('/',1)[-1])]=url
 run([root/'work/sparkle/bin/generate_appcast','--ed-key-file',key,'--download-url-prefix',args.download_prefix.rstrip('/')+'/',dist])
 # GitHub Releases replaces spaces in asset names with dots.
 feed=dist/'appcast.xml';xml=feed.read_text().split('<!-- sparkle-signatures:')[0]
 for enclosure in ET.fromstring(xml).iter('enclosure'):
  url=enclosure.get('url','');name=urllib.parse.unquote(urllib.parse.urlparse(url).path.rsplit('/',1)[-1])
  if name!=archive.name and name in previous:xml=xml.replace(url,previous[name])
 for delta in dist.glob('*.delta'):
  if ' ' not in delta.name:continue
  name=delta.name.replace(' ','.');target=delta.with_name(name)
  if target.exists() and target.read_bytes()!=delta.read_bytes():raise SystemExit('Conflicting delta: '+name)
  xml=xml.replace(urllib.parse.quote(delta.name),urllib.parse.quote(name));delta.rename(target)
 feed.write_text(xml)
 run([root/'work/sparkle/bin/sign_update','--ed-key-file',key,feed])
 run([root/'work/sparkle/bin/sign_update','--verify','--ed-key-file',key,dist/'appcast.xml'])
print('Release ready in',dist,'— not published')
