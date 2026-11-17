# Mock Tescom Connect cloud for the add-on's activation (docs/CLOUD-API.md).
#   python3 mockcloud.py PORT DRIVER_FILE [SERIAL CODE]
# One UPS is known: SERIAL (default PRIME0001) with CODE (default 123456).
# While a file named "down" exists next to DRIVER_FILE, every request gets 503.
import hashlib, json, os, sys, time
from http.server import BaseHTTPRequestHandler, HTTPServer
PORT, DRIVER = int(sys.argv[1]), sys.argv[2]
SERIAL = sys.argv[3] if len(sys.argv) > 3 else "PRIME0001"
CODE = sys.argv[4] if len(sys.argv) > 4 else "123456"
DOWN = os.path.join(os.path.dirname(os.path.abspath(DRIVER)), "down")
class H(BaseHTTPRequestHandler):
    def reply(self, status, data=None, raw=None):
        b = raw if raw is not None else json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/octet-stream" if raw is not None else "application/json")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_POST(self):
        if os.path.exists(DOWN): return self.reply(503, {"error": "down"})
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        print("POST", self.path, json.dumps(body), flush=True)
        if self.path != "/v1/addon/activate": return self.reply(404, {"error": "not found"})
        if body.get("serial") != SERIAL: return self.reply(404, {"error": "this serial number is not a Tescom UPS"})
        if body.get("code") != CODE: return self.reply(403, {"error": "wrong activation code"})
        sha = hashlib.sha256(open(DRIVER, "rb").read()).hexdigest()
        self.reply(200, {"token": "tok-" + SERIAL, "expires_at": int(time.time()) + 30 * 86400,
                         "model": "Prime 1102 XL", "driver": {"version": "0.04", "nut": "2.8.4", "sha256": sha}})
    def do_GET(self):
        if os.path.exists(DOWN): return self.reply(503, {"error": "down"})
        print("GET", self.path, self.headers.get("Authorization"), flush=True)
        if not self.path.startswith("/v1/addon/drivers/tescom_prime?arch="): return self.reply(404, {"error": "not found"})
        if self.headers.get("Authorization") != "Bearer tok-" + SERIAL: return self.reply(401, {"error": "not activated"})
        self.reply(200, raw=open(DRIVER, "rb").read())
    def log_message(self, *a): pass
HTTPServer(("0.0.0.0", PORT), H).serve_forever()
