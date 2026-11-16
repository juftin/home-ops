#!/usr/bin/env bash
set -Eeuo pipefail

# Migrate Google OAuth credentials and Admins/Users email allowlists from the
# legacy Envoy Gateway SOPS files (working tree or git ref) into Pomerium SOPS files.

ROOT_DIR="$(git rev-parse --show-toplevel)"
GIT_REF="${1:-origin/main}"

ENVOY_POLICY_REL="kubernetes/workloads/network/envoy-gateway/oauth-policy.sops.yaml"
ENVOY_SECRET_REL="kubernetes/workloads/network/envoy-gateway/oauth-client-secret.sops.yaml"
POMERIUM_DIR="${ROOT_DIR}/kubernetes/workloads/network/pomerium"
POMERIUM_IDP_OUT="${POMERIUM_DIR}/google-idp-secret.sops.yaml"
POMERIUM_INGRESSES_OUT="${POMERIUM_DIR}/ingresses.sops.yaml"

for cmd in git sops yq; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        echo "Missing required command: ${cmd}" >&2
        exit 1
    fi
done

if [[ -z "${SOPS_AGE_KEY_FILE:-}" && -f "${ROOT_DIR}/age.key" ]]; then
    export SOPS_AGE_KEY_FILE="${ROOT_DIR}/age.key"
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

read_source_file() {
    local rel_path="$1"
    local out_path="$2"
    if [[ -f "${ROOT_DIR}/${rel_path}" ]]; then
        cp "${ROOT_DIR}/${rel_path}" "${out_path}"
    elif git -C "${ROOT_DIR}" cat-file -e "${GIT_REF}:${rel_path}" 2>/dev/null; then
        git -C "${ROOT_DIR}" show "${GIT_REF}:${rel_path}" > "${out_path}"
    else
        echo "Cannot find ${rel_path} on disk or in git ref ${GIT_REF}" >&2
        exit 1
    fi
}

read_source_file "${ENVOY_POLICY_REL}" "${WORKDIR}/oauth-policy.sops.yaml"
read_source_file "${ENVOY_SECRET_REL}" "${WORKDIR}/oauth-client-secret.sops.yaml"

sops -d --input-type yaml --output-type yaml "${WORKDIR}/oauth-policy.sops.yaml" > "${WORKDIR}/oauth-policy.yaml"
sops -d --input-type yaml --output-type yaml "${WORKDIR}/oauth-client-secret.sops.yaml" > "${WORKDIR}/oauth-client-secret.yaml"

CLIENT_ID="$(yq eval 'select(.metadata.name == "envoy-oauth-admin-policy") | .spec.oidc.clientID' "${WORKDIR}/oauth-policy.yaml")"
CLIENT_SECRET="$(yq eval '.stringData["client-secret"] // ""' "${WORKDIR}/oauth-client-secret.yaml")"
if [[ -z "${CLIENT_SECRET}" || "${CLIENT_SECRET}" == "null" ]]; then
    CLIENT_SECRET_B64="$(yq eval '.data["client-secret"] // ""' "${WORKDIR}/oauth-client-secret.yaml")"
    if [[ -n "${CLIENT_SECRET_B64}" && "${CLIENT_SECRET_B64}" != "null" ]]; then
        CLIENT_SECRET="$(printf '%s' "${CLIENT_SECRET_B64}" | base64 -d)"
    fi
fi

if [[ -z "${CLIENT_ID}" || "${CLIENT_ID}" == "null" || -z "${CLIENT_SECRET}" ]]; then
    echo "Failed to extract client_id or client_secret from legacy OAuth files" >&2
    exit 1
fi

mapfile -t ADMIN_EMAILS < <(yq eval -r 'select(.metadata.name == "envoy-oauth-admin-policy") | .spec.authorization.rules[].principal.jwt.claims[] | select(.name == "email") | .values[]' "${WORKDIR}/oauth-policy.yaml" | tr '[:upper:]' '[:lower:]' | awk '!seen[$0]++')
mapfile -t USER_EMAILS < <(
    {
        printf '%s\n' "${ADMIN_EMAILS[@]}"
        yq eval -r 'select(.metadata.name == "envoy-oauth-users-policy") | .spec.authorization.rules[].principal.jwt.claims[] | select(.name == "email") | .values[]' "${WORKDIR}/oauth-policy.yaml"
    } | tr '[:upper:]' '[:lower:]' | awk 'NF && !seen[$0]++'
)

if (( ${#ADMIN_EMAILS[@]} == 0 || ${#USER_EMAILS[@]} == 0 )); then
    echo "Failed to extract Admins or Users email lists from oauth-policy.yaml" >&2
    exit 1
fi

build_ppl_block() {
    local indent="$1"
    shift
    printf '%sallow:\n' "${indent}"
    printf '%s  or:\n' "${indent}"
    for email in "$@"; do
        printf '%s    - email:\n' "${indent}"
        printf '%s        is: %s\n' "${indent}" "${email}"
    done
}

ADMIN_PPL="$(build_ppl_block "          " "${ADMIN_EMAILS[@]}")"
USERS_PPL="$(build_ppl_block "          " "${USER_EMAILS[@]}")"

cat > "${WORKDIR}/google-idp-secret.sops.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: google-idp
  namespace: pomerium
type: Opaque
stringData:
  client_id: ${CLIENT_ID}
  client_secret: ${CLIENT_SECRET}
EOF

cat > "${WORKDIR}/ingresses.sops.yaml" <<EOF
apiVersion: v1
kind: List
items:
  - apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      name: agentsview
      namespace: agentsview
      annotations:
        ingress.pomerium.io/policy: &admins |
${ADMIN_PPL}
    spec:
      ingressClassName: pomerium
      rules:
        - host: "agentsview.\${SECRET_DOMAIN}"
          http:
            paths:
              - path: /
                pathType: Prefix
                backend:
                  service:
                    name: agentsview-app
                    port:
                      number: 8080
      tls:
        - hosts:
            - "agentsview.\${SECRET_DOMAIN}"
  - apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      name: paseo
      namespace: paseo
      annotations:
        ingress.pomerium.io/allow_websockets: "true"
        ingress.pomerium.io/policy: *admins
    spec:
      ingressClassName: pomerium
      rules:
        - host: "paseo.\${SECRET_DOMAIN}"
          http:
            paths:
              - path: /
                pathType: Prefix
                backend:
                  service:
                    name: paseo
                    port:
                      number: 6767
      tls:
        - hosts:
            - "paseo.\${SECRET_DOMAIN}"
  - apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      name: herdr
      namespace: herdr
      annotations:
        ingress.pomerium.io/allow_websockets: "true"
        ingress.pomerium.io/policy: *admins
    spec:
      ingressClassName: pomerium
      rules:
        - host: "herdr.\${SECRET_DOMAIN}"
          http:
            paths:
              - path: /
                pathType: Prefix
                backend:
                  service:
                    name: herdr
                    port:
                      number: 7317
      tls:
        - hosts:
            - "herdr.\${SECRET_DOMAIN}"
  - apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      name: hermes-agent
      namespace: hermes-agent
      annotations:
        ingress.pomerium.io/allow_websockets: "true"
        ingress.pomerium.io/policy: *admins
    spec:
      ingressClassName: pomerium
      rules:
        - host: "hermes.\${SECRET_DOMAIN}"
          http:
            paths:
              - path: /v1
                pathType: Prefix
                backend:
                  service:
                    name: hermes-agent
                    port:
                      number: 8642
              - path: /
                pathType: Prefix
                backend:
                  service:
                    name: hermes-agent
                    port:
                      number: 9119
      tls:
        - hosts:
            - "hermes.\${SECRET_DOMAIN}"
  - apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      name: openclaw
      namespace: openclaw
      annotations:
        ingress.pomerium.io/allow_websockets: "true"
        ingress.pomerium.io/policy: *admins
    spec:
      ingressClassName: pomerium
      rules:
        - host: "openclaw.\${SECRET_DOMAIN}"
          http:
            paths:
              - path: /
                pathType: Prefix
                backend:
                  service:
                    name: openclaw
                    port:
                      number: 18789
      tls:
        - hosts:
            - "openclaw.\${SECRET_DOMAIN}"
  - apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      name: argocd
      namespace: argocd
      annotations:
        ingress.pomerium.io/allow_websockets: "true"
        ingress.pomerium.io/policy: *admins
    spec:
      ingressClassName: pomerium
      rules:
        - host: "argocd.\${SECRET_DOMAIN}"
          http:
            paths:
              - path: /
                pathType: Prefix
                backend:
                  service:
                    name: argocd-server
                    port:
                      number: 80
      tls:
        - hosts:
            - "argocd.\${SECRET_DOMAIN}"
  - apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      name: grafana
      namespace: observability
      annotations:
        ingress.pomerium.io/allow_websockets: "true"
        ingress.pomerium.io/policy: &users |
${USERS_PPL}
    spec:
      ingressClassName: pomerium
      rules:
        - host: "grafana.\${SECRET_DOMAIN}"
          http:
            paths:
              - path: /
                pathType: Prefix
                backend:
                  service:
                    name: kube-prometheus-stack-grafana
                    port:
                      number: 80
      tls:
        - hosts:
            - "grafana.\${SECRET_DOMAIN}"
EOF

sops --config "${ROOT_DIR}/.sops.yaml" --encrypt "${WORKDIR}/google-idp-secret.sops.yaml" > "${POMERIUM_IDP_OUT}"
sops --config "${ROOT_DIR}/.sops.yaml" --encrypt "${WORKDIR}/ingresses.sops.yaml" > "${POMERIUM_INGRESSES_OUT}"

echo "Migrated ${#ADMIN_EMAILS[@]} admin(s) and ${#USER_EMAILS[@]} user(s) into ${POMERIUM_DIR}"
