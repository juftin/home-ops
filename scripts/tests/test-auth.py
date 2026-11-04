#!/usr/bin/env python3
"""Exercise auth boundaries with synthetic identities and an actual nginx proxy."""

import copy
import importlib.util
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from lupa import LuaRuntime

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("auth_validation", ROOT / "scripts/validate-auth.py")
auth = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(auth)


def load(path):
    """Read repository YAML with the same parser used by validation."""
    return auth.yaml_documents((ROOT / path).read_text())[0]


VALUES = load("kubernetes/apps/default/lunchmoney/app/values.yaml")
PROXY = VALUES["configMaps"]["auth-proxy"]["data"]["nginx.conf"]
EXTENSION = load("kubernetes/apps/network/envoy-gateway/app/oauth-verified-email.yaml")


class VerifiedEmailTests(unittest.TestCase):
    """Run the actual filter against boolean claims and attacker-controlled headers."""

    def check_request(self, claims, path="/", expected=403, cookies=None):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(EXTENSION["spec"]["lua"][0]["inline"])
        lua.execute('''
          function run(claims, path, cookies)
            local headers = {[":path"] = path, ["cookie"] = cookies}
            local status = 200
            local header_api = {
              get = function(_, name) return headers[name] end,
              remove = function(_, name) headers[name] = nil end,
              add = function(_, name, value) headers[name] = value end
            }
            local metadata_api = {get = function() return {google = claims} end}
            local stream_api = {dynamicMetadata = function() return metadata_api end}
            local handle = {
              headers = function() return header_api end,
              streamInfo = function() return stream_api end,
              respond = function(_, response) status = tonumber(response[":status"]) end
            }
            envoy_on_request(handle)
            return status, headers["cookie"]
          end
        ''')
        converted = lua.table_from(claims, recursive=True) if claims is not None else None
        status, forwarded_cookies = lua.globals().run(converted, path, cookies)
        self.assertEqual(status, expected)
        return forwarded_cookies

    def test_google_boolean_true_is_allowed(self):
        self.check_request({"email_verified": True}, expected=200)

    def test_false_missing_and_string_claims_fail_closed(self):
        for claims in (None, {}, {"email_verified": False}, {"email_verified": "true"}, {"email_verified": 1}):
            with self.subTest(claims=claims):
                self.check_request(claims)

    def test_oauth_cookies_are_removed_but_app_sessions_are_preserved(self):
        oauth = ["HomeOpsAccessToken", "HomeOpsIdToken", "OauthHMAC-123", "OauthExpires-123",
                 "RefreshToken-123", "OauthNonce-123", "CodeVerifier-123"]
        cookies = "; ".join(name + "=fixture" for name in oauth)
        self.assertIsNone(self.check_request({"email_verified": True}, expected=200, cookies=cookies))
        remaining = self.check_request({"email_verified": True}, expected=200,
                                       cookies=cookies + "; app_session=keep; preference=dark")
        self.assertEqual(remaining.strip(), "app_session=keep; preference=dark")

    def test_public_pages_are_exact_exceptions(self):
        for path in ("/denied", "/logged-out", "/denied?next=/secret"):
            self.check_request(None, path, expected=200)
        for path in ("/oauth2/callback", "/logout", "/denied/secret", "/logged-out.html", "/"):
            self.check_request(None, path)


class InvariantTests(unittest.TestCase):
    """Render public patches against synthetic client IDs and encrypted-list stand-ins."""

    @classmethod
    def setUpClass(cls):
        app = ROOT / "kubernetes/apps/network/envoy-gateway/app"
        kustomization = load(str(app.relative_to(ROOT) / "kustomization.yaml"))
        for field in ("helmCharts", "patchesStrategicMerge"):
            kustomization.pop(field)
        kustomization["resources"] = ["policies.yaml", "oauth-verified-email.yaml"]
        policies = []
        for group in ("admin", "users", "internal"):
            policies.append({
                "apiVersion": "gateway.envoyproxy.io/v1alpha1", "kind": "SecurityPolicy",
                "metadata": {"name": f"envoy-oauth-{group}-policy", "namespace": "network"},
                "spec": {
                    "targetRefs": [], "oidc": {"clientID": f"{group}-client", "cookieDomain": "example.com"},
                    "authorization": {"rules": [{"principal": {"jwt": {
                        "claims": [{"values": [f"{group}@example.com"]}]
                    }}}]},
                },
            })
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            (target / "kustomization.yaml").write_text(json.dumps(kustomization))
            (target / "policies.yaml").write_text("\n---\n".join(json.dumps(p) for p in policies))
            for name in ("oauth-hardening.yaml", "oauth-verified-email.yaml"):
                shutil.copy(app / name, target / name)
            rendered = subprocess.run(["kustomize", "build", str(target)], check=True, capture_output=True, text=True)
        cls.resources = auth.yaml_documents(rendered.stdout)
        utility_values = load("kubernetes/apps/default/oauth-pages/app/values.yaml")
        cls.resources.extend([
            {"apiVersion": "gateway.networking.k8s.io/v1", "kind": "Gateway", "metadata": {
                "name": f"envoy-oauth-{group}", "labels": {"home-ops.io/oauth-gateway": "true"}
            }} for group in ("admin", "users", "internal")
        ])
        containers = []
        for name, container in VALUES["controllers"]["app"]["containers"].items():
            rendered_container = {"name": name, **copy.deepcopy(container)}
            rendered_container["env"] = [{"name": key, **value} for key, value in container["env"].items()
                                         if isinstance(value, dict)]
            containers.append(rendered_container)
        cls.resources += [
            {"kind": "HTTPRoute", "metadata": {"name": "paseo"}, "spec": {
                "hostnames": ["paseo.${SECRET_DOMAIN}"], "parentRefs": [{"name": "envoy-oauth-admin"}]
            }},
            {"kind": "HTTPRoute", "metadata": {"name": "oauth-pages"}, "spec": utility_values["route"]["app"]},
            load("kubernetes/apps/default/oauth-pages/app/securitypolicy.yaml"),
            {"kind": "ConfigMap", "metadata": {"name": "tunnel"}, "data": {"config.yaml": json.dumps({"ingress": [
                {"hostname": "paseo.${SECRET_DOMAIN}", "service": "https://envoy-oauth-admin.network.svc.cluster.local:443",
                 "originRequest": {"originServerName": "oauth.${SECRET_DOMAIN}"}},
                {"hostname": "*.${SECRET_DOMAIN}", "service": "public"}
            ]})}},
            {"kind": "Service", "metadata": {"name": "lunchmoney-app"}, "spec": {"ports": [{"port": 8000, "targetPort": 8080}]}},
            {"kind": "Deployment", "metadata": {"name": "lunchmoney"}, "spec": {"template": {"spec": {
                "containers": containers
            }}}},
            load("kubernetes/apps/default/lunchmoney/app/networkpolicy.yaml"),
        ]

    def setUp(self):
        self.docs = copy.deepcopy(self.resources)
        self.policy = next(r for r in self.docs if r.get("kind") == "SecurityPolicy" and r["metadata"]["name"] == "envoy-oauth-admin-policy")

    def test_hardened_render_preserves_distinct_clients_and_allowlists(self):
        auth.validate_auth(self.docs)
        for group in ("admin", "users", "internal"):
            policy = next(r for r in self.docs if r.get("kind") == "SecurityPolicy" and r["metadata"]["name"] == f"envoy-oauth-{group}-policy")
            self.assertEqual(policy["spec"]["jwt"]["providers"][0]["audiences"], [f"{group}-client"])
            self.assertEqual(policy["spec"]["authorization"]["rules"][0]["principal"]["jwt"]["claims"][0]["values"], [f"{group}@example.com"])

    def test_wrong_audience_is_rejected(self):
        self.policy["spec"]["jwt"]["providers"][0]["audiences"] = ["another-client"]
        with self.assertRaisesRegex(auth.AuthValidationError, "audience"):
            auth.validate_auth(self.docs)

    def test_root_cookies_are_rejected(self):
        self.policy["spec"]["oidc"]["cookieDomain"] = "example.com"
        with self.assertRaisesRegex(auth.AuthValidationError, "host-scoped"):
            auth.validate_auth(self.docs)

    def test_query_tokens_are_rejected(self):
        self.policy["spec"]["jwt"]["providers"][0]["extractFrom"]["params"] = ["access_token"]
        with self.assertRaisesRegex(auth.AuthValidationError, "OIDC cookie"):
            auth.validate_auth(self.docs)

    def test_callback_public_exception_is_rejected(self):
        policy = next(r for r in self.docs if r.get("metadata", {}).get("name") == "oauth-pages-public")
        policy["spec"]["targetRefs"][0]["sectionName"] = "callback"
        with self.assertRaisesRegex(auth.AuthValidationError, "Public exceptions"):
            auth.validate_auth(self.docs)

    def test_public_gateway_bypass_is_rejected(self):
        self.docs.append({"kind": "HTTPRoute", "metadata": {"name": "bypass"}, "spec": {
            "hostnames": ["paseo.${SECRET_DOMAIN}"], "parentRefs": [{"name": "envoy-external"}]
        }})
        with self.assertRaisesRegex(auth.AuthValidationError, "unauthenticated Gateway"):
            auth.validate_auth(self.docs)

    def test_missing_verified_email_filter_is_rejected(self):
        self.docs = [r for r in self.docs if r.get("kind") != "EnvoyExtensionPolicy"]
        with self.assertRaisesRegex(auth.AuthValidationError, "verified-email"):
            auth.validate_auth(self.docs)

    def test_raw_lunchmoney_port_is_rejected(self):
        service = next(r for r in self.docs if r.get("kind") == "Service")
        service["spec"]["ports"][0]["targetPort"] = 8000
        with self.assertRaisesRegex(auth.AuthValidationError, "authentication proxy"):
            auth.validate_auth(self.docs)

    def test_missing_key_reference_is_rejected(self):
        deployment = next(r for r in self.docs if r.get("kind") == "Deployment")
        deployment["spec"]["template"]["spec"]["containers"][0]["env"] = []
        with self.assertRaisesRegex(auth.AuthValidationError, "required Secret"):
            auth.validate_auth(self.docs)

    def test_strict_crd_schema_rejects_unknown_fields(self):
        crd = {"kind": "CustomResourceDefinition", "spec": {
            "group": "gateway.envoyproxy.io", "names": {"kind": "TestPolicy"}, "versions": [{
                "name": "v1alpha1", "schema": {"openAPIV3Schema": {"type": "object", "properties": {
                    "apiVersion": {"type": "string"}, "kind": {"type": "string"},
                    "metadata": {"type": "object"}, "spec": {"type": "object", "properties": {"enabled": {"type": "boolean"}}}
                }}}
            }]
        }}
        policy = {"apiVersion": "gateway.envoyproxy.io/v1alpha1", "kind": "TestPolicy", "metadata": {"name": "test"}, "spec": {"enabled": True}}
        auth.validate_gateway_schemas([crd, policy])
        policy["spec"]["typo"] = True
        with self.assertRaisesRegex(auth.AuthValidationError, "schema validation failed"):
            auth.validate_gateway_schemas([crd, policy])


class Backend(BaseHTTPRequestHandler):
    """Model the pinned app: key-protected /api, deliberately unprotected /mcp."""

    verify_status = None

    def do_GET(self):
        status = 200
        if self.path == "/api":
            status = self.verify_status or (200 if self.headers.get("X-API-Key") == "fixture-key" else 401)
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        payload = json.dumps({"path": self.path, "body": body.decode()}).encode()
        self.send_response(status)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    do_POST = do_GET

    def log_message(self, *_args):
        pass


class ProxyTests(unittest.TestCase):
    """Send REST/MCP requests through nginx with the repository's actual config."""

    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        cls.backend = ThreadingHTTPServer(("127.0.0.1", 0), Backend)
        cls.thread = threading.Thread(target=cls.backend.serve_forever, daemon=True)
        cls.thread.start()
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            cls.port = sock.getsockname()[1]
        config = PROXY.replace("listen 8080;", f"listen 127.0.0.1:{cls.port};")
        config = config.replace("127.0.0.1:8000", f"127.0.0.1:{cls.backend.server_port}")
        config = config.replace("/tmp/", cls.directory.name + "/")
        path = Path(cls.directory.name) / "nginx.conf"
        path.write_text(config)
        cls.logs = (Path(cls.directory.name) / "nginx.log").open("w")
        cls.process = subprocess.Popen(["nginx", "-p", cls.directory.name + "/", "-c", str(path), "-g", "daemon off;"],
                                       stdout=cls.logs, stderr=cls.logs)
        for _ in range(100):
            if cls.process.poll() is not None:
                raise RuntimeError((Path(cls.directory.name) / "nginx.log").read_text())
            try:
                with socket.create_connection(("127.0.0.1", cls.port), timeout=0.1):
                    break
            except OSError:
                time.sleep(0.02)
        else:
            raise RuntimeError("nginx proxy did not become ready")

    @classmethod
    def tearDownClass(cls):
        cls.process.terminate()
        cls.process.wait(timeout=5)
        cls.backend.shutdown()
        cls.backend.server_close()
        cls.logs.close()
        cls.directory.cleanup()

    def setUp(self):
        Backend.verify_status = None

    def request(self, path, key=None, data=None):
        headers = {"X-API-Key": key} if key else {}
        request = Request(f"http://127.0.0.1:{self.port}{path}", headers=headers, data=data)
        try:
            with urlopen(request, timeout=3) as response:
                return response.status, response.read()
        except HTTPError as error:
            return error.code, error.read()

    def test_rest_and_mcp_reject_missing_and_wrong_keys(self):
        for path in ("/api/user", "/mcp", "/mcp/", "/?api_key=fixture-key"):
            for key in (None, "wrong"):
                with self.subTest(path=path, key=key):
                    self.assertEqual(self.request(path, key)[0], 401)

    def test_authenticated_mcp_preserves_request_body(self):
        status, body = self.request("/mcp", "fixture-key", b'{"jsonrpc":"2.0","method":"initialize"}')
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["body"], '{"jsonrpc":"2.0","method":"initialize"}')

    def test_health_is_public_and_auth_subrequest_is_internal(self):
        for path in ("/health", "/ready"):
            self.assertEqual(self.request(path)[0], 200)
        self.assertEqual(self.request("/verify-key", "fixture-key")[0], 404)

    def test_auth_backend_failure_is_closed(self):
        Backend.verify_status = 503
        self.assertEqual(self.request("/mcp", "fixture-key")[0], 500)

    def test_empty_secret_prevents_proxy_start(self):
        container = VALUES["controllers"]["app"]["containers"]["auth-proxy"]
        result = subprocess.run(container["command"] + container["args"],
                                env={**os.environ, "LUNCHMONEY_APP_API_KEY": ""}, capture_output=True)
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
