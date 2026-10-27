"""Local TLS fixtures, including cross-origin scripts and IPv4/IPv6 names."""
from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler
from pathlib import Path
import ssl,threading,json,socket
root=Path(__file__).resolve().parents[1]/'work/test-certificates'
class Handler(BaseHTTPRequestHandler):
 def do_GET(self):
  if self.path=='/probe.js':body=b'document.documentElement.dataset.cdn="loaded";';kind='text/javascript'
  else:body=b'<!doctype html><title>WAI TLS fixture</title><h1>Verified test connection</h1><script src="https://static.allowed.wai.test:9446/probe.js"></script>';kind='text/html'
  self.send_response(200);self.send_header('Content-Type',kind);self.send_header('Cache-Control','no-store');self.end_headers();self.wfile.write(body)
 def log_message(self,*args):pass
class IPv6Server(ThreadingHTTPServer):address_family=socket.AF_INET6
servers=[]
for port,name in [(9443,'allowed'),(9444,'expired'),(9445,'outside'),(9446,'cdn'),(9447,'ip'),(9448,'ip6'),(9449,'spoof'),(9450,'wrong')]:
 server=(IPv6Server if name=='ip6' else ThreadingHTTPServer)(('::1' if name=='ip6' else '127.0.0.1',port),Handler)
 context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.load_cert_chain(root/(name+'-chain.pem'),root/(name+'.key'));server.socket=context.wrap_socket(server.socket,server_side=True)
 threading.Thread(target=server.serve_forever,daemon=True).start();servers.append(server)
print(json.dumps({'ready':True,'ports':[s.server_port for s in servers]}),flush=True)
threading.Event().wait()
