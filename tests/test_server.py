import json
import os
import sys
import threading
import time
import unittest
import urllib.error
import urllib.request

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "app"))
import server  # noqa: E402


class ServerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.httpd = server.make_server(port=0)
        cls.base = "http://127.0.0.1:%d" % cls.httpd.server_address[1]
        threading.Thread(target=cls.httpd.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.httpd.server_close()

    def get(self, path):
        try:
            with urllib.request.urlopen(self.base + path, timeout=3) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())

    def test_liveness_answers_at_once(self):
        self.assertEqual(self.get("/healthz")[0], 200)

    def test_readiness_waits_for_warmup(self):
        old_start, old_delay = server._started_at, server.READY_DELAY_SECONDS
        try:
            server.READY_DELAY_SECONDS = 60
            server._started_at = time.monotonic()
            self.assertEqual(self.get("/readyz")[0], 503)
            server._started_at = time.monotonic() - 61
            self.assertEqual(self.get("/readyz")[0], 200)
        finally:
            server._started_at, server.READY_DELAY_SECONDS = old_start, old_delay

    def test_orders(self):
        status, body = self.get("/orders")
        self.assertEqual(status, 200)
        self.assertEqual(len(body["orders"]), 3)

    def test_the_probe_path_the_fault_uses_does_not_exist(self):
        # faults/readiness-probe points the probe at /ready; the app must answer 404.
        self.assertEqual(self.get("/ready")[0], 404)

    def test_cache_warmup_allocates(self):
        try:
            server.warm_cache(2)
            self.assertEqual(len(server._cache), 2 * 1024 * 1024)
        finally:
            server._cache = b""


if __name__ == "__main__":
    unittest.main()
