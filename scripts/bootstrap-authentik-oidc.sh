#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname "${0}")/lib/common.sh"

export LOG_LEVEL="${LOG_LEVEL:-info}"
export ROOT_DIR="$(git rev-parse --show-toplevel)"

SECURITY_NS="${SECURITY_NS:-security}"
NETWORK_NS="${NETWORK_NS:-network}"
AUTHENTIK_CLIENT_ID="${AUTHENTIK_CLIENT_ID:-envoy-gateway}"
AUTHENTIK_APP_SLUG="${AUTHENTIK_APP_SLUG:-envoy}"

function wait_for_authentik() {
    log info "Waiting for Authentik deployments to be ready"
    kubectl -n "${SECURITY_NS}" rollout status deploy/authentik-server --timeout=300s >/dev/null
    kubectl -n "${SECURITY_NS}" rollout status deploy/authentik-worker --timeout=300s >/dev/null
}

function ensure_oauth_secret() {
    local client_secret
    client_secret="$(
        kubectl -n "${NETWORK_NS}" get secret oauth-client-secret -o jsonpath='{.data.client-secret}' 2>/dev/null \
            | base64 --decode || true
    )"

    if [[ -z "${client_secret}" ]]; then
        client_secret="$(openssl rand -hex 32)"
        kubectl -n "${NETWORK_NS}" patch secret oauth-client-secret --type merge \
            -p "{\"stringData\":{\"client-secret\":\"${client_secret}\"}}" >/dev/null
        log info "Generated oauth-client-secret.client-secret"
    else
        log info "Using existing oauth-client-secret.client-secret"
    fi

    printf "%s" "${client_secret}"
}

function apply_authentik_provider() {
    local client_secret="${1}"
    local pod
    pod="$(kubectl -n "${SECURITY_NS}" get pods -l app.kubernetes.io/component=server -o jsonpath='{.items[0].metadata.name}')"

    local py_script
    py_script="$(mktemp)"
    cat >"${py_script}" <<'PY'
import os
from authentik.core.models import Application
from authentik.crypto.models import CertificateKeyPair
from authentik.flows.models import Flow
from authentik.providers.oauth2.models import OAuth2Provider, ScopeMapping

client_secret = os.environ["AUTHENTIK_ENVOY_CLIENT_SECRET"]
client_id = os.environ["AUTHENTIK_ENVOY_CLIENT_ID"]
app_slug = os.environ["AUTHENTIK_ENVOY_APP_SLUG"]

auth = Flow.objects.get(slug="default-provider-authorization-implicit-consent")
inv = Flow.objects.get(slug="default-provider-invalidation-flow")
key = CertificateKeyPair.objects.get(name="authentik Self-signed Certificate")
provider, _ = OAuth2Provider.objects.get_or_create(name="envoy-gateway")
provider.client_type = "confidential"
provider.client_id = client_id
provider.client_secret = client_secret
provider.authorization_flow = auth
provider.invalidation_flow = inv
provider.issuer_mode = "per_provider"
provider.signing_key = key
provider._redirect_uris = [
    {"matching_mode": "strict", "url": "https://oauth.juftin.dev/oauth2/callback"},
    {"matching_mode": "strict", "url": "https://oauth-internal.juftin.dev/oauth2/callback"},
]
provider.save()

scopes = ScopeMapping.objects.filter(
    managed__in=[
        "goauthentik.io/providers/oauth2/scope-openid",
        "goauthentik.io/providers/oauth2/scope-email",
        "goauthentik.io/providers/oauth2/scope-profile",
        "goauthentik.io/providers/oauth2/scope-offline_access",
    ]
)
provider.property_mappings.set(scopes)

app, _ = Application.objects.get_or_create(slug=app_slug)
app.name = "Envoy Gateway"
app.provider = provider
app.save()

print(f"upserted provider={provider.name} client_id={provider.client_id} app={app.slug}")
PY

    kubectl -n "${SECURITY_NS}" exec -i "${pod}" -- sh -lc \
        "AUTHENTIK_ENVOY_CLIENT_SECRET='${client_secret}' AUTHENTIK_ENVOY_CLIENT_ID='${AUTHENTIK_CLIENT_ID}' AUTHENTIK_ENVOY_APP_SLUG='${AUTHENTIK_APP_SLUG}' /ak-root/.venv/bin/python -m manage shell" \
        <"${py_script}" >/dev/null
    rm -f "${py_script}"
    log info "Applied Authentik OIDC provider and application"
}

function refresh_envoy_oauth() {
    log info "Restarting oauth gateway deployments"
    kubectl -n "${NETWORK_NS}" rollout restart deploy/envoy-oauth deploy/envoy-oauth-internal >/dev/null
    kubectl -n "${NETWORK_NS}" rollout status deploy/envoy-oauth --timeout=300s >/dev/null
    kubectl -n "${NETWORK_NS}" rollout status deploy/envoy-oauth-internal --timeout=300s >/dev/null
}

function verify_security_policies() {
    local output
    output="$(
        kubectl -n "${NETWORK_NS}" get securitypolicy -o jsonpath='{range .items[*]}{.metadata.name}{"="}{.status.ancestors[0].conditions[0].status}{"\n"}{end}'
    )"
    if echo "${output}" | grep -q '=False'; then
        log error "SecurityPolicy OIDC validation still failing" "policies=${output//$'\n'/,}"
    fi
    log info "SecurityPolicy OIDC validation accepted"
}

function main() {
    check_env KUBECONFIG
    check_cli kubectl openssl
    wait_for_authentik
    local client_secret
    client_secret="$(ensure_oauth_secret)"
    apply_authentik_provider "${client_secret}"
    refresh_envoy_oauth
    verify_security_policies
    log info "Authentik OIDC bootstrap complete"
}

main "$@"
