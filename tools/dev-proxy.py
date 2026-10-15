#!/usr/bin/env python3
"""
DeskPet development proxy — keeps your Anthropic API key out of the app.

DeskPet's "backend proxy" setting sends Messages API requests here *without* a
key; this proxy adds the key from its own environment and forwards them.

    export ANTHROPIC_API_KEY=sk-ant-...
    python3 tools/dev-proxy.py            # listens on http://127.0.0.1:8787
    # DeskPet › Settings › AI › Backend proxy: http://127.0.0.1:8787/v1/messages

Standard library only. Binds to localhost. Enforces a model allowlist and a
max_tokens cap, and never logs message contents.

This is a *development* reference, not a production service: a real deployment
must authenticate each user (e.g. sign-in tokens) and rate-limit per user,
otherwise anyone who can reach it can spend your API credit.
"""
import http.server
import json
import os
import sys
import urllib.error
import urllib.request

UPSTREAM = "https://api.anthropic.com/v1/messages"
ALLOWED_MODELS = {"claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5"}
MAX_TOKENS_CAP = 16000
MAX_BODY_BYTES = 2_000_000
PASS_HEADERS = ("anthropic-version", "anthropic-beta")


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/v1/messages":
            return self._error(404, "not_found_error", "Only /v1/messages is proxied.")
        length = int(self.headers.get("content-length") or 0)
        if length <= 0 or length > MAX_BODY_BYTES:
            return self._error(413, "request_too_large", "Body missing or too large.")
        try:
            body = json.loads(self.rfile.read(length))
        except ValueError:
            return self._error(400, "invalid_request_error", "Body is not JSON.")
        if body.get("model") not in ALLOWED_MODELS:
            return self._error(400, "invalid_request_error", "Model not allowed by proxy.")
        body["max_tokens"] = min(int(body.get("max_tokens") or 1024), MAX_TOKENS_CAP)

        req = urllib.request.Request(UPSTREAM, data=json.dumps(body).encode(), method="POST")
        req.add_header("content-type", "application/json")
        req.add_header("x-api-key", API_KEY)
        for h in PASS_HEADERS:
            if self.headers.get(h):
                req.add_header(h, self.headers[h])
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                self._send(resp.status, resp.read())
        except urllib.error.HTTPError as e:
            self._send(e.code, e.read())
        except urllib.error.URLError:
            self._error(502, "api_error", "Upstream unreachable.")

    def _send(self, code, payload):
        self.send_response(code)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _error(self, code, kind, message):
        self._send(code, json.dumps({"type": "error", "error": {"type": kind, "message": message}}).encode())

    def log_message(self, fmt, *args):
        # Log only method/path/status — never request or response bodies.
        sys.stderr.write("%s %s\n" % (self.command, args[1] if len(args) > 1 else ""))


if __name__ == "__main__":
    API_KEY = os.environ.get("ANTHROPIC_API_KEY", "").strip()
    if not API_KEY:
        sys.exit("Set ANTHROPIC_API_KEY in this shell first.")
    port = int(os.environ.get("PORT", "8787"))
    print(f"DeskPet dev proxy on http://127.0.0.1:{port}/v1/messages (Ctrl-C to stop)")
    http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
