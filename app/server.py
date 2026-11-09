"""orders: a deliberately small HTTP service for the faulty-app lab.

Standard library only, so the image has nothing to install and every line can be
explained in an interview. Faults are injected from Kubernetes manifests, not from
code paths here; the only knob the app itself honours is CACHE_WARMUP_MB, which
models a release that preloads a bigger cache than its memory limit allows.
"""

import json
import os
import signal
import socket
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = os.environ.get("APP_VERSION", "dev")
PORT = int(os.environ.get("PORT", "8080"))
READY_DELAY_SECONDS = float(os.environ.get("READY_DELAY_SECONDS", "2"))
CACHE_WARMUP_MB = int(os.environ.get("CACHE_WARMUP_MB", "0"))

ORDERS = [
    {"id": "A-1001", "item": "keyboard", "qty": 1},
    {"id": "A-1002", "item": "monitor", "qty": 2},
    {"id": "A-1003", "item": "cable", "qty": 5},
]

_started_at = time.monotonic()
_cache = b""


def log(event, **fields):
    print(json.dumps({"ts": time.time(), "event": event, **fields}), flush=True)


def warm_cache(megabytes):
    """Allocate and touch `megabytes` of memory, so it is really resident."""
    global _cache
    if megabytes > 0:
        log("cache_warmup_start", mb=megabytes)
        _cache = b"\x01" * (megabytes * 1024 * 1024)
        log("cache_warmup_done", mb=megabytes)


def is_ready():
    return time.monotonic() - _started_at >= READY_DELAY_SECONDS


class Handler(BaseHTTPRequestHandler):
    server_version = "orders/" + VERSION

    def _send(self, status, body):
        payload = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if self.path == "/healthz":
            self._send(200, {"status": "alive"})
        elif self.path == "/readyz":
            if is_ready():
                self._send(200, {"status": "ready"})
            else:
                self._send(503, {"status": "warming up"})
        elif self.path == "/orders":
            self._send(200, {"orders": ORDERS, "pod": socket.gethostname()})
        elif self.path == "/":
            self._send(200, {"service": "orders", "version": VERSION, "pod": socket.gethostname()})
        else:
            self._send(404, {"error": "not found", "path": self.path})

    def log_message(self, fmt, *args):
        log("request", method=self.command, path=self.path, status=args[1] if len(args) > 1 else None)


def make_server(port=PORT):
    return ThreadingHTTPServer(("0.0.0.0", port), Handler)


def main():
    warm_cache(CACHE_WARMUP_MB)
    httpd = make_server()

    def shutdown(signum, _frame):
        log("shutdown", signal=signum)
        threading.Thread(target=httpd.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    log("listening", port=PORT, version=VERSION)
    httpd.serve_forever()
    httpd.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
