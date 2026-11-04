#!/usr/bin/env python3
"""Validate rendered authentication boundaries without printing secret values."""

import argparse
import json
from pathlib import Path
import subprocess
import tempfile


class AuthValidationError(ValueError):
    """An authentication invariant failed."""


def require(condition, message):
    """Fail with a non-sensitive description of a violated invariant."""
    if not condition:
        raise AuthValidationError(message)


def yaml_documents(source):
    """Use the repository's pinned yq instead of another YAML dependency."""
    result = subprocess.run(
        ["yq", "eval-all", "-o=json", "-I=0", ".", "-"],
        input=source, text=True, capture_output=True, check=True,
    )
    return [doc for line in result.stdout.splitlines() if (doc := json.loads(line))]


def validate_auth(resources, offline=False):
    """Check policies, alternate routes, tunnel mappings, and private API access."""
    policies = {r["metadata"]["name"]: r for r in resources if r.get("kind") == "SecurityPolicy"}
    gateways = {r["metadata"]["name"]: r for r in resources if r.get("kind") == "Gateway"}
    routes = [r for r in resources if r.get("kind") == "HTTPRoute"]
    oauth_gateways = {
        name for name, gateway in gateways.items()
        if gateway["metadata"].get("labels", {}).get("home-ops.io/oauth-gateway") == "true"
    }
    protected_hosts = {}
    for route in routes:
        if route["metadata"]["name"] == "oauth-pages":
            continue
        for parent in route["spec"].get("parentRefs", []):
            name = parent["name"]
            if name.startswith("envoy-oauth-"):
                require(name in oauth_gateways, "OAuth route references an unprotected Gateway")
                for host in route["spec"].get("hostnames", []):
                    require("*" not in host, "Protected app hostnames must be explicit")
                    require(host not in protected_hosts or protected_hosts[host] == name,
                            "A hostname belongs to multiple OAuth groups")
                    protected_hosts[host] = name

    if oauth_gateways:
        require(oauth_gateways == {"envoy-oauth-admin", "envoy-oauth-users", "envoy-oauth-internal"},
                "Unexpected OAuth Gateway set; update the authentication checks")
        for gateway in sorted(oauth_gateways):
            name = gateway + "-policy"
            require(name in policies, f"Missing SecurityPolicy: {name}")
            spec = policies[name]["spec"]
            require(spec["targetRefs"] == [{"group": "gateway.networking.k8s.io", "kind": "Gateway", "name": gateway}],
                    f"{name}: incorrect Gateway target")
            oidc = spec["oidc"]
            require(not oidc.get("cookieDomain"), f"{name}: cookies must be host-scoped")
            require(oidc.get("redirectURL") == "https://%REQ(:authority)%/oauth2/callback",
                    f"{name}: callback must return to the app host over HTTPS")
            require(oidc.get("cookieConfig", {}).get("sameSite") == "Lax", f"{name}: SameSite must be Lax")
            require(oidc.get("disableTokenEncryption") is True, f"{name}: pinned Gateway JWT extraction requires signed cookies")
            require(oidc.get("passThroughAuthHeader") is False, f"{name}: OIDC bypass is forbidden")
            require(oidc.get("forwardAccessToken") is False, f"{name}: do not forward access tokens")
            require("forwardIDToken" not in oidc and oidc.get("cookieNames") == {
                "accessToken": "HomeOpsAccessToken", "idToken": "HomeOpsIdToken"
            }, f"{name}: use cookie extraction supported by the pinned controller")
            providers = spec["jwt"]["providers"]
            require(len(providers) == 1, f"{name}: exactly one JWT provider required")
            jwt = providers[0]
            require(not spec["jwt"].get("optional"), f"{name}: JWT verification must be mandatory")
            require(jwt.get("name") == "google" and jwt.get("issuer") == "https://accounts.google.com",
                    f"{name}: unexpected JWT issuer/provider")
            require(jwt.get("audiences") == [oidc["clientID"]] and bool(oidc["clientID"]),
                    f"{name}: audience must equal the OIDC client ID")
            require(jwt.get("extractFrom") == {"cookies": ["HomeOpsIdToken"]},
                    f"{name}: tokens must come from the OIDC cookie only")
            authorization = spec["authorization"]
            require(authorization.get("defaultAction") == "Deny", f"{name}: default deny required")
            rules = authorization.get("rules", [])
            require(len(rules) == 1 and rules[0].get("action") == "Allow", f"{name}: one email allow rule required")
            principal = rules[0]["principal"]["jwt"]
            require(principal.get("provider") == "google", f"{name}: incorrect authorization provider")
            claims = principal.get("claims", [])
            require(len(claims) == 1 and claims[0].get("name") == "email" and claims[0].get("values"),
                    f"{name}: nonempty email allowlist required")
            if not offline:
                require(all(isinstance(v, str) and "@" in v and v == v.lower() for v in claims[0]["values"]),
                        f"{name}: allowlist must contain lowercase emails")

        extensions = [r for r in resources if r.get("kind") == "EnvoyExtensionPolicy"
                      and r["metadata"]["name"] == "oauth-verified-email"]
        require(len(extensions) == 1, "Missing verified-email extension")
        require(extensions[0]["spec"]["targetSelectors"] == [{
            "group": "gateway.networking.k8s.io", "kind": "Gateway",
            "matchLabels": {"home-ops.io/oauth-gateway": "true"},
        }], "Verified-email extension must cover every OAuth Gateway")
        utility_routes = [r for r in routes if r["metadata"]["name"] == "oauth-pages"]
        require(len(utility_routes) == 1, "Missing OAuth utility route")
        utility = utility_routes[0]["spec"]
        require(set(protected_hosts) <= set(utility["hostnames"]),
                "OAuth utility routes need explicit app hostnames to outrank app catch-all routes")
        require(oauth_gateways <= {p["name"] for p in utility["parentRefs"]}, "Missing utility Gateway attachment")
        require("oauth-pages-public" in policies, "Missing utility-page policy")
        public = policies["oauth-pages-public"]["spec"]
        require(public.get("authorization") == {"defaultAction": "Allow"}, "Incorrect utility-page authorization")
        require(public.get("targetRefs") == [
            {"group": "gateway.networking.k8s.io", "kind": "HTTPRoute", "name": "oauth-pages", "sectionName": section}
            for section in ("denied", "logged-out")
        ], "Public exceptions must cover only denied/logged-out rules")
        for route in routes:
            if route["metadata"]["name"] != "oauth-pages":
                for parent in route["spec"].get("parentRefs", []):
                    if parent["name"] in {"envoy-external", "envoy-internal"}:
                        require(not set(route["spec"].get("hostnames", [])) & set(protected_hosts),
                                "An OAuth hostname is also exposed through an unauthenticated Gateway")
        # A new route-level policy replaces Gateway authentication unless carefully merged.
        require(set(policies) == {g + "-policy" for g in oauth_gateways} | {"oauth-pages-public"},
                "Unexpected SecurityPolicy; review Gateway override semantics before allowing it")
        tunnel_entries = []
        for resource in resources:
            if resource.get("kind") == "ConfigMap" and "config.yaml" in resource.get("data", {}):
                tunnel_entries.extend(yaml_documents(resource["data"]["config.yaml"])[0].get("ingress", []))
        for host, gateway in protected_hosts.items():
            if gateway == "envoy-oauth-internal":
                continue
            matches = [e for e in tunnel_entries if e.get("hostname") == host]
            require(len(matches) == 1 and matches[0].get("service") == f"https://{gateway}.network.svc.cluster.local:443",
                    "OAuth hostname missing or assigned to the wrong Cloudflare origin")
            entry = matches[0]
            expected_origin = ("oauth" if gateway == "envoy-oauth-admin" else "oauth-users") + "." + host.split(".", 1)[1]
            require(entry.get("originRequest", {}).get("originServerName") == expected_origin,
                    "OAuth tunnel origin TLS hostname does not match its group")
            require(tunnel_entries.index(entry) < next((i for i, e in enumerate(tunnel_entries)
                    if e.get("hostname", "").startswith("*.")), len(tunnel_entries)),
                    "OAuth tunnel entry must precede the public wildcard")
        for resource in resources:
            if resource.get("kind") == "BackendTrafficPolicy":
                for override in resource.get("spec", {}).get("responseOverride", []):
                    require(not any(c.get("value") == 403 for c in override.get("match", {}).get("statusCodes", [])),
                            "Do not turn application 403 responses into OAuth redirects")

    services = [r for r in resources if r.get("kind") == "Service" and r["metadata"]["name"] == "lunchmoney-app"]
    if services:
        require(len(services) == 1 and all(p.get("targetPort") == 8080 for p in services[0]["spec"]["ports"]),
                "Lunch Money Service must expose only its authentication proxy")
        deployments = [r for r in resources if r.get("kind") == "Deployment" and r["metadata"]["name"] == "lunchmoney"]
        # Chart versions can name the Deployment lunchmoney-app.
        if not deployments:
            deployments = [r for r in resources if r.get("kind") == "Deployment" and r["metadata"]["name"] == "lunchmoney-app"]
        require(len(deployments) == 1, "Missing Lunch Money app Deployment")
        containers = {c["name"]: c for c in deployments[0]["spec"]["template"]["spec"]["containers"]}
        for name in ("app", "auth-proxy"):
            require(name in containers, "Missing Lunch Money authentication proxy")
            key = next((e for e in containers[name].get("env", []) if e["name"] == "LUNCHMONEY_APP_API_KEY"), {})
            ref = key.get("valueFrom", {}).get("secretKeyRef", {})
            require(ref.get("name") == "lunchmoney-secret" and ref.get("key") == "LUNCHMONEY_APP_API_KEY"
                    and not ref.get("optional"), "Lunch Money API key must be a required Secret reference")
        networks = [r for r in resources if r.get("kind") == "NetworkPolicy" and r["metadata"]["name"] == "lunchmoney-ingress"]
        require(len(networks) == 1 and networks[0]["spec"]["podSelector"] == {"matchLabels": {"app.kubernetes.io/instance": "lunchmoney"}},
                "Lunch Money requires ingress isolation")
        allowed_ports = {p.get("port") for rule in networks[0]["spec"].get("ingress", []) for p in rule.get("ports", [])}
        require(all(rule.get("ports") and rule.get("from") for rule in networks[0]["spec"].get("ingress", [])),
                "Lunch Money ingress rules must restrict both sources and ports")
        require(8000 not in allowed_ports and allowed_ports == {8080, 5432, 6379}, "Raw Lunch Money application port must remain blocked")


def strict_schema(schema):
    """Make structural CRD schemas reject unknown fields, respecting free-form maps."""
    if isinstance(schema, dict):
        if schema.get("type") == "object" and "properties" in schema and not schema.get("x-kubernetes-preserve-unknown-fields"):
            schema.setdefault("additionalProperties", False)
        for value in schema.values():
            strict_schema(value)
    elif isinstance(schema, list):
        for value in schema:
            strict_schema(value)


def validate_gateway_schemas(resources):
    """Validate Gateway/Envoy CRs using CRDs from the exact rendered Helm chart."""
    groups = {"gateway.envoyproxy.io", "gateway.networking.k8s.io"}
    schemas = {}
    for resource in resources:
        if resource.get("kind") == "CustomResourceDefinition" and resource["spec"]["group"] in groups:
            for version in resource["spec"]["versions"]:
                schema = version.get("schema", {}).get("openAPIV3Schema")
                if schema:
                    strict_schema(schema)
                    schemas[(resource["spec"]["group"] + "/" + version["name"], resource["spec"]["names"]["kind"])] = schema
    batches = {}
    for resource in resources:
        if resource.get("apiVersion", "").split("/")[0] in groups:
            key = (resource["apiVersion"], resource["kind"])
            require(key in schemas, f"Missing rendered CRD schema for {key[1]}")
            batches.setdefault(key, []).append(resource)
    with tempfile.TemporaryDirectory(prefix="home-ops-auth-schemas-") as directory:
        schema_file = Path(directory) / "schema.json"
        for key, batch in sorted(batches.items()):
            schema_file.write_text(json.dumps(schemas[key]))
            result = subprocess.run(
                ["kubeconform", "-strict", "-summary", "-schema-location", str(schema_file)],
                input="\n---\n".join(json.dumps(r) for r in batch), text=True, capture_output=True,
            )
            require(result.returncode == 0, f"{key[1]} CRD schema validation failed:\n{result.stdout}{result.stderr}")
    print("Gateway and Envoy CRD schemas passed (CEL admission rules require a live API server)")


def main():
    """Run schema and authentication validation against a complete rendered cluster."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifests", type=Path)
    parser.add_argument("--offline", action="store_true")
    args = parser.parse_args()
    resources = yaml_documents(args.manifests.read_text())
    try:
        validate_gateway_schemas(resources)
        validate_auth(resources, args.offline)
    except (AuthValidationError, KeyError, TypeError, IndexError) as error:
        raise SystemExit(f"Authentication validation failed: {error}") from None
    print("Authentication invariants passed" + (" (encrypted email values require full validation)" if args.offline else ""))


if __name__ == "__main__":
    main()
