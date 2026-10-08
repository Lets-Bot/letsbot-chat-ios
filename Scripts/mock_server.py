#!/usr/bin/env python3
"""Local mock of the LetsBot In-App Chat SDK API (API.md v1) for end-to-end tests of the chat screen.

Serves `config`, `session`, `identify`, `logout`, `device`, `unread` and a minimal `ui` page that speaks the
page <-> native bridge: posts `ready`, and on `LetsBotHost.boot(...)` echoes the boot payload back as a `message`
event, reports `unread` 0 and then asks to `close`.

Usage: python3 Scripts/mock_server.py [port]   (default 8765, binds 127.0.0.1)
"""
import json
import os
import secrets
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UI_HTML = """<!doctype html>
<html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>LetsBot mock</title></head>
<body><p>LetsBot mock chat · Powered by LetsBot</p>
<script>
  function post(o) { window.webkit.messageHandlers.letsbot.postMessage(JSON.stringify(o)); }
  window.LetsBotHost = {
    boot: function (p) {
      post({lb: "unread", count: 0});
      post({lb: "message", t: JSON.stringify(p)});
    },
    setContext: function (c) { post({lb: "message", t: "ctx:" + JSON.stringify(c)}); },
    setTheme: function (t) { post({lb: "message", t: "theme:" + t}); }
  };
  window.addEventListener("load", function () { post({lb: "ready"}); });
  window.lbClose = function () { post({lb: "close"}); };
</script></body></html>"""


class Handler(BaseHTTPRequestHandler):
    server_version = "LetsBotMock/1.0"

    def log_message(self, format, *args):  # quiet unless MOCK_VERBOSE=1
        if os.environ.get("MOCK_VERBOSE") == "1":
            super().log_message(format, *args)

    def _route(self):
        parts = self.path.split("?")[0].strip("/").split("/")
        # api/sdk/v1/{key}/{route}
        if len(parts) == 5 and parts[:3] == ["api", "sdk", "v1"]:
            return parts[3], parts[4]
        return None, None

    def _json(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store, private")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _check(self, route):
        if self.headers.get("X-LB-Platform") != "ios" or not self.headers.get("X-LB-App-Id"):
            self._json(403, {"error": "app_not_registered"})
            return False
        if route not in ("config", "ui", "session") and not self.headers.get("X-LB-Visitor"):
            self._json(401, {"error": "invalid_visitor"})
            return False
        return True

    def _handle(self, method):
        key, route = self._route()
        if key is None or key == "unknown":
            return self._json(404, {"error": "not_found"})
        length = int(self.headers.get("Content-Length") or 0)
        if length:
            self.rfile.read(length)
        if route == "ui" and method == "GET":
            # The WebView request carries the SDK headers too, but browsers may drop custom headers on reloads.
            body = UI_HTML.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if not self._check(route):
            return
        if route == "config" and method == "GET":
            return self._json(200, {"title": "Mock", "color": "#0e7c66", "push": {"configured": True}})
        if route == "session" and method == "POST":
            token = self.headers.get("X-LB-Visitor") or (secrets.token_hex(20) + "." + secrets.token_urlsafe(32)[:43])
            return self._json(200, {"token": token})
        if route == "identify" and method == "POST":
            return self._json(200, {"verified": True})
        if route in ("logout", "device") and method in ("POST", "PUT", "DELETE"):
            return self._json(200, {"ok": True})
        if route == "unread" and method == "GET":
            return self._json(200, {"count": 1, "last": {"t": "Hello", "at": "2026-10-08T12:00:00+03:00"}})
        return self._json(404, {"error": "not_found"})

    def do_GET(self):
        self._handle("GET")

    def do_POST(self):
        self._handle("POST")

    def do_PUT(self):
        self._handle("PUT")

    def do_DELETE(self):
        self._handle("DELETE")


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
