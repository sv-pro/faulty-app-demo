"""The fault catalogue is ground truth for evals, so it must match the manifests.

For every faults/<id>/:
  - fault.yaml has the required fields and a known signal;
  - the overlay, rendered with kubectl kustomize, differs from the healthy base in
    exactly the paths fault.yaml lists under `changes`, and nowhere else.

The render check needs kubectl; without it those tests are skipped, not passed.
"""

import os
import shutil
import subprocess
import unittest

import yaml

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FAULTS = os.path.join(ROOT, "faults")
REQUIRED = {"id", "title", "layer", "changes", "symptoms", "root_cause", "fix", "signal", "service_available"}
SIGNALS = {"endpoints-empty", "image-pull-failed", "readiness-failed", "oom-killed"}
KUBECTL = shutil.which("kubectl")


def fault_ids():
    return sorted(d for d in os.listdir(FAULTS) if os.path.isfile(os.path.join(FAULTS, d, "fault.yaml")))


def load_fault(fid):
    with open(os.path.join(FAULTS, fid, "fault.yaml")) as f:
        return yaml.safe_load(f)


def render(path):
    out = subprocess.run([KUBECTL, "kustomize", path], check=True, capture_output=True, text=True).stdout
    return {"%s/%s" % (d["kind"], d["metadata"]["name"]): d for d in yaml.safe_load_all(out) if d}


def flatten(node, prefix=""):
    if isinstance(node, dict):
        items = {}
        for key, value in node.items():
            items.update(flatten(value, "%s.%s" % (prefix, key) if prefix else key))
        return items
    if isinstance(node, list):
        items = {}
        for i, value in enumerate(node):
            items.update(flatten(value, "%s[%d]" % (prefix, i)))
        return items
    return {prefix: node}


def changed_paths(base, broken):
    paths = set()
    for obj in sorted(set(base) | set(broken)):
        a, b = flatten(base.get(obj, {})), flatten(broken.get(obj, {}))
        paths |= {"%s:%s" % (obj, p) for p in set(a) | set(b) if a.get(p, object()) != b.get(p, object())}
    return paths


class CatalogueTest(unittest.TestCase):
    def test_there_are_faults(self):
        self.assertGreaterEqual(len(fault_ids()), 4)

    def test_metadata(self):
        for fid in fault_ids():
            with self.subTest(fault=fid):
                fault = load_fault(fid)
                self.assertEqual(REQUIRED - set(fault), set(), "missing fields")
                self.assertEqual(fault["id"], fid)
                self.assertIn(fault["signal"], SIGNALS)
                self.assertIsInstance(fault["service_available"], bool)
                self.assertTrue(fault["changes"])

    def test_signals_are_unique(self):
        signals = [load_fault(f)["signal"] for f in fault_ids()]
        self.assertEqual(len(signals), len(set(signals)))


@unittest.skipUnless(KUBECTL, "kubectl not installed")
class OverlayTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.base = render(os.path.join(ROOT, "k8s", "base"))

    def test_base_selector_matches_pod_labels(self):
        svc = self.base["Service/orders-api"]["spec"]["selector"]
        pod = self.base["Deployment/orders"]["spec"]["template"]["metadata"]["labels"]
        self.assertTrue(svc.items() <= pod.items())

    def test_each_overlay_changes_only_what_its_fault_declares(self):
        for fid in fault_ids():
            with self.subTest(fault=fid):
                broken = render(os.path.join(FAULTS, fid))
                self.assertEqual(changed_paths(self.base, broken), set(load_fault(fid)["changes"]))


if __name__ == "__main__":
    unittest.main()
