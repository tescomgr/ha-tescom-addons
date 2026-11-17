# Mock Supervisor API for bashio: options, add-on info, discovery.
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
OPTS=json.load(open(sys.argv[1]))
class H(BaseHTTPRequestHandler):
    def _send(self, data):
        b=json.dumps({"result":"ok","data":data}).encode()
        self.send_response(200); self.send_header("Content-Type","application/json"); self.send_header("Content-Length",str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        if self.path.startswith("/addons/self/options/config"): return self._send(OPTS)
        if self.path.startswith("/addons/self/info"): return self._send({"hostname":"abcd1234-tescom-nut","slug":"abcd1234_tescom_nut"})
        print("GET", self.path, flush=True); self._send({})
    def do_POST(self):
        n=int(self.headers.get("Content-Length",0)); body=self.rfile.read(n).decode()
        print("POST", self.path, body, flush=True)
        self._send({"uuid":"0123"})
    def log_message(self,*a): pass
HTTPServer(("0.0.0.0",80),H).serve_forever()
