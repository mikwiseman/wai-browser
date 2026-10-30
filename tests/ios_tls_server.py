from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler
from pathlib import Path
import ssl,threading,time
root=Path(__file__).resolve().parents[1]/'work/ios-certificates'
class Handler(BaseHTTPRequestHandler):
 protocol_version="HTTP/1.1"
 def do_GET(self):
  body=b'document.documentElement.dataset.cdn="loaded";' if self.path=='/probe.js' else b'<!doctype html><title>WAI TLS fixture</title><h1>Verified test connection</h1><input id="edit"><script src="https://static.allowed.127.0.0.1.nip.io:9546/probe.js"></script>'
  self.send_response(200);self.send_header('Content-Type','text/javascript' if self.path=='/probe.js' else 'text/html');self.send_header('Cache-Control','no-store');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
 def log_message(self,*args):pass
for port,name in [(9543,'allowed'),(9544,'expired'),(9545,'outside'),(9546,'cdn'),(9550,'wrong')]:
 server=ThreadingHTTPServer(('127.0.0.1',port),Handler);context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.load_cert_chain(root/(name+'-chain.pem'),root/(name+'.key'));server.socket=context.wrap_socket(server.socket,server_side=True);threading.Thread(target=server.serve_forever,daemon=True).start()
class BrowsingHandler(BaseHTTPRequestHandler):
 def do_GET(self):
  slow=self.path.startswith('/slow.txt?')
  if self.path == '/receipt.txt' or slow:
   body=b'Wai Browser test download\n';content_type='application/octet-stream'
  else:
   title='Second test page' if self.path.startswith('/second') else 'Wai Browser test'
   body=('<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><title>'+title+'</title><style>body{font:20px -apple-system;padding:24px}a{display:block;margin:24px 0}</style><h1>'+title+'</h1><p>Find this sentence.</p><a href="/second">Second page</a><a href="/receipt.txt" download>Download receipt</a>').encode()
   content_type='text/html'
  self.send_response(200);self.send_header('Content-Type',content_type);self.send_header('Content-Length',str(len(body)))
  if self.path == '/receipt.txt' or slow:self.send_header('Content-Disposition','attachment; filename="'+('slow-'+self.path.split('?')[1]+'.txt' if slow else 'receipt.txt')+'"')
  self.end_headers()
  if slow:self.wfile.write(body[:1]);self.wfile.flush();time.sleep(15);body=body[1:]
  self.wfile.write(body)
 def log_message(self,*args):pass
server=ThreadingHTTPServer(('127.0.0.1',9561),BrowsingHandler)
threading.Thread(target=server.serve_forever,daemon=True).start()
print('ready',flush=True);threading.Event().wait()
