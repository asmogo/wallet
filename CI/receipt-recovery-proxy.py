#!/usr/bin/env python3
"""Loopback-only fault proxy for interrupted receipt integration tests.

Run after start-nutshell.sh: python3 CI/receipt-recovery-proxy.py
POST /__receipt_test/interrupt-next-swap forwards the next swap, discards
its successful response, then keeps the client offline until POST reset.
POST /__receipt_test/offline blocks requests before they reach the mint.
"""
import argparse
import http.client
import http.server
import threading

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--port", type=int, default=3340)
parser.add_argument("--mint-port", type=int, default=3338)
args = parser.parse_args()
lock = threading.Lock()
state = {"armed": False, "offline": False}


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass  # Tokens and payment payloads must never appear in proxy logs.

    def respond(self, code, body=b"{}", content_type="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        self.handle_request()

    def do_GET(self):
        self.handle_request()

    def handle_request(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        if self.command == "POST" and self.path.startswith("/__receipt_test/"):
            action = self.path.rsplit("/", 1)[-1]
            with lock:
                if action == "reset":
                    state.update(armed=False, offline=False)
                elif action == "interrupt-next-swap":
                    state.update(armed=True, offline=False)
                elif action == "offline":
                    state.update(armed=False, offline=True)
                else:
                    return self.respond(404)
            return self.respond(200)
        with lock:
            if state["offline"]:
                return self.respond(503)
            interrupt = state["armed"] and self.path == "/v1/swap" and self.command == "POST"
            if interrupt:
                state["armed"] = False
        connection = http.client.HTTPConnection("127.0.0.1", args.mint_port, timeout=20)
        try:
            connection.request(self.command, self.path, body, {"Content-Type": "application/json"})
            response = connection.getresponse()
            result = response.read()
            if interrupt and 200 <= response.status < 300:
                with lock:
                    state["offline"] = True
                return self.respond(503)
            self.respond(response.status, result, response.getheader("Content-Type", "application/json"))
        except OSError:
            self.respond(503)
        finally:
            connection.close()


http.server.ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()
