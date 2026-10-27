from pathlib import Path
import subprocess,tempfile,json,shutil,os,plistlib
root=Path(__file__).resolve().parents[1]
subprocess.run(['python3',str(root/'tests/make_fixtures.py')],check=True)
folder=Path(tempfile.mkdtemp(prefix='wai-browser-qa-')).resolve();app=folder/'Wai Browser.app';profile=folder/'profile';profile.mkdir()
subprocess.run(['ditto',str(root/'build/Wai Browser.app'),str(app)],check=True)
plist_path=app/'Contents/Info.plist';plist=plistlib.loads(plist_path.read_bytes())
plist['CFBundleIdentifier']='is.waiwai.browser.qa';plist['CFBundleDisplayName']='Wai Browser QA';plist['SUFeedURL']=''
plist_path.write_bytes(plistlib.dumps(plist))
for name in ['root','intermediate']:shutil.copy2(root/'work/test-certificates'/f'{name}.der',app/'Contents/Resources/certificates'/f'{name}.der')
# Inner code is unchanged; only re-sign the bundle after swapping public test certificates.
subprocess.run(['codesign','--force','--sign',os.environ.get('WAI_SIGN_IDENTITY','79F4FFC61B54D0E56B37B4D0643C331F73C3BDC2'),'--options','runtime','--timestamp','--entitlements',str(root/'resources/chromium.entitlements'),str(app)],check=True)
(profile/'trust.json').write_text(json.dumps({'enabled':True,'domains':['allowed.wai.test']}))
(root/'work/browser-test.json').write_text(json.dumps({'folder':str(folder),'app':str(app),'profile':str(profile)},indent=2))
print('Prepared disposable browser fixture')
