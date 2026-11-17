"""Disposable native UI fixture; accounts are in memory and never logged."""
import json
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

accounts = {}
release_gate = threading.Event()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, status, value):
        data = json.dumps(value).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except BrokenPipeError:
            pass

    def do_GET(self):
        if self.path == "/finish-release":
            release_gate.set()
        elif self.path == "/reset-release":
            release_gate.clear()
        self.reply(200, {"players": 0, "tankCount": 0, "capacity": 32, "leaders": []})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        key = body.get("publicToken")
        if self.path == "/api/callsigns":
            self.reply(200, {"names": [{"seat": i, "name": name, "available": True}
                                      for i, name in enumerate(body.get("names", []))]})
        elif self.path == "/api/account/create":
            accounts.setdefault(key, body["name"])
            self.reply(200, {"names": [accounts[key]], "totalNames": 1})
        elif self.path == "/api/account" and key in accounts:
            self.reply(200, {"names": [accounts[key]], "totalNames": 1})
        elif self.path == "/api/account/release" and key in accounts:
            release_gate.wait(timeout=45)
            if accounts[key].startswith("FAIL"):
                self.reply(503, {"code": "server_busy"})
            else:
                accounts.pop(key)
                self.reply(200, {"released": True})
        else:
            self.reply(401, {"code": "account_key_invalid"})


ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
