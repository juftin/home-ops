#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT_DIR="$(git rev-parse --show-toplevel)"
RENDER_SCRIPT="${ROOT_DIR}/scripts/render-argocd-app.sh"
CLUSTER_SECRETS_FILE="${ROOT_DIR}/kubernetes/components/sops/cluster-secrets.sops.yaml"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT
AUTH_ARGS=()

if (( $# > 1 )); then
    echo "Usage: $0 [--offline]" >&2
    exit 1
fi

if [[ ! -x "${RENDER_SCRIPT}" ]]; then
    echo "Render script not executable: ${RENDER_SCRIPT}" >&2
    exit 1
fi

if [[ ! -f "${CLUSTER_SECRETS_FILE}" ]]; then
    echo "Missing cluster secret manifest: ${CLUSTER_SECRETS_FILE}" >&2
    exit 1
fi

case "${1:-}" in
    "")
        SECRET_DOMAIN="$(sops -d --input-type yaml --output-type yaml "${CLUSTER_SECRETS_FILE}" | yq eval -r '.stringData.SECRET_DOMAIN' -)"
        ;;
    --offline)
        # PRs (including forks) render with placeholders, without access to cluster secrets.
        # Only this validator uses the shim; ArgoCD still requires real SOPS decryption.
        cat >"${WORKDIR}/sops" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
yq eval '
    del(.sops) |
    (.. | select(tag == "!!str") | select(test("^ENC\\[.*type:bool\\]$"))) = false |
    (.. | select(tag == "!!str") | select(test("^ENC\\[.*type:int\\]$"))) = 1 |
    (.. | select(tag == "!!str") | select(test("^ENC\\[.*type:float\\]$"))) = 1.0 |
    (.. | select(tag == "!!str") | select(test("^ENC\\["))) = "Y2ktcGxhY2Vob2xkZXI="
' "${!#}"
EOF
        chmod +x "${WORKDIR}/sops"
        export SOPS_BIN="${WORKDIR}/sops"
        SECRET_DOMAIN="example.com"
        AUTH_ARGS+=(--offline)
        echo "Offline validation: encrypted values use placeholders; decryption and secret semantics are not checked"
        ;;
    *)
        echo "Usage: $0 [--offline]" >&2
        exit 1
        ;;
esac

if [[ -z "${SECRET_DOMAIN}" || "${SECRET_DOMAIN}" == "null" ]]; then
    echo "Unable to resolve SECRET_DOMAIN from ${CLUSTER_SECRETS_FILE}" >&2
    exit 1
fi

kustomize build "${ROOT_DIR}/kubernetes/argocd" | bash "${ROOT_DIR}/scripts/validate-kubernetes-schema.sh"

while IFS= read -r app_dir; do
    echo "Validating ${app_dir#"${ROOT_DIR}/"}"
    SECRET_DOMAIN="${SECRET_DOMAIN}" "${RENDER_SCRIPT}" "${app_dir}" >"${WORKDIR}/app.yaml"
    bash "${ROOT_DIR}/scripts/validate-kubernetes-schema.sh" <"${WORKDIR}/app.yaml"
    cat "${WORKDIR}/app.yaml" >>"${WORKDIR}/all.yaml"
    printf '\n---\n' >>"${WORKDIR}/all.yaml"
done < <(find "${ROOT_DIR}/kubernetes/apps" -mindepth 3 -maxdepth 3 -type d -name app | sort)

if [[ -f "${ROOT_DIR}/bootstrap/helmfile.d/01-apps.yaml" ]]; then
    # Include the bootstrap-owned ArgoCD routes in cross-app authentication checks.
    ARGOCD_SECRET_DOMAIN="${SECRET_DOMAIN}" ARGOCD_OIDC_CLIENT_ID=ci-placeholder \
        ARGOCD_RBAC_ADMINS='' ARGOCD_TARGET_REVISION=refs/heads/main \
        helmfile --file "${ROOT_DIR}/bootstrap/helmfile.d/01-apps.yaml" \
        --selector name=argocd template --skip-deps >"${WORKDIR}/bootstrap.yaml"
    bash "${ROOT_DIR}/scripts/validate-kubernetes-schema.sh" <"${WORKDIR}/bootstrap.yaml"
    cat "${WORKDIR}/bootstrap.yaml" >>"${WORKDIR}/all.yaml"
fi

python3 "${ROOT_DIR}/scripts/validate-auth.py" "${WORKDIR}/all.yaml" "${AUTH_ARGS[@]}"
echo "ArgoCD render validation passed"
