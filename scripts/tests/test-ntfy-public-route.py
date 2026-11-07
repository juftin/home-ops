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


def matching_rule(method, path, route="app"):
    """Evaluate the method/path matches used by this app's HTTPRoute."""
    for rule in VALUES["route"][route]["rules"]:
        for match in rule.get("matches", [{}]):
            if match.get("method", method) != method:
                continue
            spec = match.get("path", {"type": "PathPrefix", "value": "/"})
            if spec["type"] == "RegularExpression":
                if re.fullmatch(spec["value"], path):
                    return rule
            elif spec["type"] == "Exact":
                if path == spec["value"]:
                    return rule
            elif path == spec["value"] or path.startswith(spec["value"].rstrip("/") + "/"):
                return rule
    return None


def routed(method, path, route="app"):
    """Return whether the request is forwarded to the ntfy backend."""
    rule = matching_rule(method, path, route)
    return bool(rule and rule.get("backendRefs"))


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

    def test_camply_reads_and_rewrite(self):
        paths = ["/v1/health", "/v1/config", "/v1/account", "/file/abc123.txt"]
        paths += [f"/{topic}/{suffix}" for topic in ["homelab", "a,b"]
                  for suffix in ["json", "sse", "raw", "ws", "auth"]]
        filters = json.loads(subprocess.check_output(
            ["yq", "-o=json", "-I=0", ".", str(ROOT / "kubernetes/workloads/apps/ntfy/httproutefilter.yaml")],
            text=True,
        ).splitlines()[0])
        rewrite = filters["spec"]["urlRewrite"]["path"]["replaceRegexMatch"]
        for path in paths:
            with self.subTest(path=path):
                external = "/ntfy" + path
                self.assertTrue(routed("GET", external, "camply"))
                rule = matching_rule("GET", external, "camply")
                self.assertEqual(rule["filters"][0]["extensionRef"]["name"], filters["metadata"]["name"])
                self.assertEqual(re.sub(rewrite["pattern"], rewrite["substitution"], external), path)
        self.assertTrue(routed("HEAD", "/ntfy/file/abc123.txt", "camply"))

    def test_camply_rejects_writes_and_web_ui(self):
        for method in ["POST", "PUT", "PATCH", "DELETE", "OPTIONS"]:
            for path in ["/ntfy", "/ntfy/", "/ntfy/homelab", "/ntfy/homelab/json",
                         "/ntfy/v1/account", "/ntfy/file/abc123.txt"]:
                with self.subTest(method=method, path=path):
                    self.assertFalse(routed(method, path, "camply"))
                    rule = matching_rule(method, path, "camply")
                    self.assertEqual(rule["filters"][0]["extensionRef"]["name"], "ntfy-not-found")
        for path in ["/ntfy", "/ntfy/", "/ntfy/homelab", "/ntfy/static/main.js",
                     "/ntfy/app.html", "/ntfy/config.js", "/ntfy/homelab/publish",
                     "/ntfy/homelab/send", "/ntfy/homelab/trigger",
                     "/ntfy/homelab/messageID/clear", "/ntfy/homelab/messageID/delete"]:
            with self.subTest(path=path):
                self.assertFalse(routed("GET", path, "camply"))
                self.assertIsNotNone(matching_rule("GET", path, "camply"))
        for path in ["/", "/api/health", "/ntfylike", "/v1/health"]:
            self.assertIsNone(matching_rule("GET", path, "camply"))
        self.assertEqual(VALUES["route"]["camply"]["hostnames"], ["camply.rocks"])
        self.assertEqual(VALUES["route"]["camply"]["parentRefs"][0]["sectionName"], "camply-https")

    def test_no_auth_and_private_ingress(self):
        app = VALUES["controllers"]["ntfy"]["containers"]["app"]
        self.assertNotIn("envFrom", app)
        self.assertNotIn("NTFY_AUTH_FILE", app["env"])
        self.assertEqual(app["env"]["NTFY_AUTH_DEFAULT_ACCESS"], "read-write")
        self.assertEqual(VALUES["ingress"]["tailscale"]["className"], "tailscale")
        self.assertEqual(VALUES["ingress"]["tailscale"]["defaultBackend"]["service"]["name"], "ntfy")


if __name__ == "__main__":
    unittest.main()
