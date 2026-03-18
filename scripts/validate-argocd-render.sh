#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
RENDER_SCRIPT="${ROOT_DIR}/scripts/render-argocd-app.sh"
CLUSTER_SECRETS_FILE="${ROOT_DIR}/kubernetes/components/sops/cluster-secrets.sops.yaml"

if [[ ! -x "${RENDER_SCRIPT}" ]]; then
    echo "Render script not executable: ${RENDER_SCRIPT}" >&2
    exit 1
fi

if [[ ! -f "${CLUSTER_SECRETS_FILE}" ]]; then
    echo "Missing cluster secret manifest: ${CLUSTER_SECRETS_FILE}" >&2
    exit 1
fi

SECRET_DOMAIN="example.com"
if [[ -n "${SOPS_AGE_KEY_FILE:-}" && -f "${SOPS_AGE_KEY_FILE}" ]] || [[ -f "${HOME}/.config/sops/age/keys.txt" ]]; then
    RESOLVED_SECRET_DOMAIN="$(sops -d --input-type yaml --output-type yaml "${CLUSTER_SECRETS_FILE}" | yq eval -r '.stringData.SECRET_DOMAIN' -)"
    if [[ -z "${RESOLVED_SECRET_DOMAIN}" || "${RESOLVED_SECRET_DOMAIN}" == "null" ]]; then
        echo "Unable to resolve SECRET_DOMAIN from ${CLUSTER_SECRETS_FILE}" >&2
        exit 1
    fi
    SECRET_DOMAIN="${RESOLVED_SECRET_DOMAIN}"
else
    echo "warning: no age key available, using SECRET_DOMAIN=${SECRET_DOMAIN} for render validation" >&2
fi

kustomize build "${ROOT_DIR}/kubernetes/argocd" >/dev/null

while IFS= read -r app_dir; do
    SECRET_DOMAIN="${SECRET_DOMAIN}" "${RENDER_SCRIPT}" "${app_dir}" >/dev/null
done < <(find "${ROOT_DIR}/kubernetes/apps" -mindepth 3 -maxdepth 3 -type d -name app | sort)

echo "ArgoCD render validation passed"
