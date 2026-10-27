import {chromium} from 'playwright';
import {readFile,writeFile,rm} from 'node:fs/promises';
import {spawn,execFileSync} from 'node:child_process';
import {createServer} from 'node:net';
import assert from 'node:assert/strict';
const setup=JSON.parse(await readFile('work/browser-test.json','utf8'));
const reservation=createServer();await new Promise(r=>reservation.listen(0,'127.0.0.1',r));
const port=reservation.address().port;await new Promise(r=>reservation.close(r));
const results=[];const endpoint='http://127.0.0.1:'+port;let browser,passed=false;
const delay=ms=>new Promise(r=>setTimeout(r,ms));
async function launch(){
 execFileSync('/usr/bin/open',['-g','-n','--stderr',setup.folder+'/browser.stderr',setup.app,'--args','--use-mock-keychain','--user-data-dir='+setup.profile,'--remote-debugging-port='+port,'--host-resolver-rules=MAP *.wai.test 127.0.0.1, MAP allowed.wai.test.evil.test 127.0.0.1','--url=about:blank']);
 for(let i=0;i<100;i++){try{browser=await chromium.connectOverCDP(endpoint,{timeout:500});return browser.contexts()[0].pages()[0];}catch{await delay(200);}}
 throw new Error('Browser did not start');
}
async function stop(){
 if(!browser)return;
 try{await (await browser.newBrowserCDPSession()).send('Browser.close');}catch{}
 await browser.close().catch(()=>{});browser=undefined;
 for(let i=0;i<80;i++){
  try{execFileSync('python3',['-c','import fcntl,sys; f=open(sys.argv[1],"a"); fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)',setup.profile+'/.wai.lock'],{stdio:'ignore'});return;}catch{await delay(200);}
 }
 throw new Error('Profile lock did not close');
}
const server=spawn('python3',['tests/tls_server.py'],{stdio:['ignore','pipe','pipe']});
try{
 await new Promise((resolve,reject)=>{server.stdout.once('data',resolve);server.once('exit',code=>reject(new Error('TLS fixture server exited '+code)));});
 let p=await launch();
 await p.goto('https://allowed.wai.test:9443/',{waitUntil:'load'});
 assert.equal(await p.title(),'WAI TLS fixture');
 assert.equal(await p.locator('html').getAttribute('data-cdn'),'loaded');results.push('allowed page and cross-origin script');
 await p.evaluate(()=>{localStorage.setItem('wai-test','persisted');document.cookie='wai-test=persisted; Secure; SameSite=Lax';});
 for(const [name,url] of [
  ['outside domain','https://outside.wai.test:9445/'],
  ['hostname mismatch','https://wrong.allowed.wai.test:9443/'],
  ['expired leaf','https://allowed.wai.test:9444/'],
  ['unrelated root','https://allowed.wai.test:9450/'],
  ['domain suffix spoof','https://allowed.wai.test.evil.test:9449/'],
  ['IPv4 SAN','https://127.0.0.1:9447/'],
  ['IPv6 SAN','https://[::1]:9448/']]){
   await p.goto('about:blank');
   const errorLoaded=p.waitForEvent('load',{timeout:10000}).catch(()=>{});
   let failure;try{await p.goto(url,{waitUntil:'load',timeout:10000});}catch(e){failure=e.message;}
   assert.match(failure??'',/ERR_CERT_/,'Expected certificate rejection: '+name);results.push(name+' blocked');
   await errorLoaded;
 }
 await stop();
 await writeFile(setup.profile+'/trust.json',JSON.stringify({enabled:false,domains:['allowed.wai.test']}));
 p=await launch();
 await p.goto('about:blank');await assert.rejects(p.goto('https://allowed.wai.test:9443/'),/ERR_CERT_AUTHORITY_INVALID/);results.push('disabled trust after restart');
 await stop();
 await writeFile(setup.profile+'/trust.json',JSON.stringify({enabled:true,domains:['allowed.wai.test']}));
 p=await launch();await p.goto('https://allowed.wai.test:9443/',{waitUntil:'load'});assert.equal(await p.title(),'WAI TLS fixture');
 assert.equal(await p.evaluate(()=>localStorage.getItem('wai-test')),'persisted');
 assert.match(await p.evaluate(()=>document.cookie),/wai-test=persisted/);results.push('profile storage and cookies persist');
 await writeFile('work/browser-test-results.json',JSON.stringify({passed:true,checks:results},null,2));
 passed=true;
 console.log(JSON.stringify({passed:true,checks:results},null,2));
}finally{await stop();server.kill('SIGTERM');if(passed)await rm(setup.folder,{recursive:true});}
