from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler
from pathlib import Path
import ssl,threading
root=Path(__file__).resolve().parents[1]/'work/ios-certificates'
class Handler(BaseHTTPRequestHandler):
 protocol_version="HTTP/1.1"
 def do_GET(self):
  body=b'document.documentElement.dataset.cdn="loaded";' if self.path=='/probe.js' else b'<!doctype html><title>WAI TLS fixture</title><h1>Verified test connection</h1><input id="edit"><script src="https://static.allowed.127.0.0.1.nip.io:9546/probe.js"></script>'
  self.send_response(200);self.send_header('Content-Type','text/javascript' if self.path=='/probe.js' else 'text/html');self.send_header('Cache-Control','no-store');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
 def log_message(self,*args):pass
for port,name in [(9543,'allowed'),(9544,'expired'),(9545,'outside'),(9546,'cdn'),(9550,'wrong')]:
 server=ThreadingHTTPServer(('127.0.0.1',port),Handler);context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.load_cert_chain(root/(name+'-chain.pem'),root/(name+'.key'));server.socket=context.wrap_socket(server.socket,server_side=True);threading.Thread(target=server.serve_forever,daemon=True).start()
print('ready',flush=True);threading.Event().wait()
