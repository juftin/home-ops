"""Check the public route boundary against ntfy's read and write endpoint forms."""

import json
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
VALUES = json.loads(
    subprocess.check_output(
        ["yq", "-o=json", ".", str(ROOT / "kubernetes/workloads/apps/ntfy/values.yaml")],
        text=True,
    )
)


def routed(method, path):
    """Evaluate the method/path matches used by this app's HTTPRoute."""
    for rule in VALUES["route"]["app"]["rules"]:
        for match in rule.get("matches", [{}]):
            if match.get("method", method) != method:
                continue
            spec = match.get("path", {"type": "PathPrefix", "value": "/"})
            if spec["type"] == "RegularExpression":
                if re.fullmatch(spec["value"], path):
                    return True
            elif spec["type"] == "Exact":
                if path == spec["value"]:
                    return True
            elif path.startswith(spec["value"]):
                return True
    return False


class PublicRouteTest(unittest.TestCase):
    def test_reads(self):
        paths = [
            "/", "/homelab", "/config.js", "/app.html", "/sw.js",
            "/static/css/main.css", "/v1/health", "/v1/config", "/v1/account",
            "/file/abc123.txt",
        ]
        paths += [f"/{topic}/{suffix}" for topic in ["homelab", "a,b"]
                  for suffix in ["json", "sse", "raw", "ws", "auth"]]
        for path in paths:
            with self.subTest(path=path):
                self.assertTrue(routed("GET", path))
        self.assertTrue(routed("HEAD", "/file/abc123.txt"))

    def test_write_methods(self):
        for method in ["POST", "PUT", "PATCH", "DELETE"]:
            for path in ["/", "/homelab", "/homelab/messageID", "/_matrix/push/v1/notify",
                         "/v1/account", "/v1/webpush", "/file/abc123.txt"]:
                with self.subTest(method=method, path=path):
                    self.assertFalse(routed(method, path))

    def test_get_writes(self):
        for topic in ["homelab", "a", "test-123"]:
            paths = [f"/{topic}/{alias}" for alias in ["publish", "send", "trigger"]]
            paths += [f"/{topic}/messageID/{action}" for action in ["read", "clear", "delete"]]
            for path in paths:
                with self.subTest(path=path):
                    self.assertFalse(routed("GET", path))

    def test_public_hostname(self) -> None:
        """Keep canonical URLs and the route on the dedicated Camply hostname."""
        self.assertEqual(list(VALUES["route"]), ["app"])
        self.assertEqual(VALUES["route"]["app"]["hostnames"], ["ntfy.camply.rocks"])
        self.assertEqual(VALUES["route"]["app"]["parentRefs"][0]["sectionName"], "ntfy-https")
        self.assertEqual(
            VALUES["controllers"]["ntfy"]["containers"]["app"]["env"]["NTFY_BASE_URL"],
            "https://ntfy.camply.rocks",
        )
        self.assertFalse(routed("GET", "/ntfy/homelab/json"))

    def test_no_auth_and_private_ingress(self):
        app = VALUES["controllers"]["ntfy"]["containers"]["app"]
        self.assertNotIn("envFrom", app)
        self.assertNotIn("NTFY_AUTH_FILE", app["env"])
        self.assertEqual(app["env"]["NTFY_AUTH_DEFAULT_ACCESS"], "read-write")
        self.assertEqual(VALUES["ingress"]["tailscale"]["className"], "tailscale")
        self.assertEqual(VALUES["ingress"]["tailscale"]["defaultBackend"]["service"]["name"], "ntfy")


if __name__ == "__main__":
    unittest.main()
