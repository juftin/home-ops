#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
RENDER_SCRIPT="${ROOT_DIR}/scripts/render-argocd-app.sh"
CLUSTER_SECRETS_FILE="${ROOT_DIR}/kubernetes/components/sops/cluster-secrets.sops.yaml"

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
        WORKDIR="$(mktemp -d)"
        trap 'rm -rf "${WORKDIR}"' EXIT
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
    SECRET_DOMAIN="${SECRET_DOMAIN}" "${RENDER_SCRIPT}" "${app_dir}" | bash "${ROOT_DIR}/scripts/validate-kubernetes-schema.sh"
done < <(find "${ROOT_DIR}/kubernetes/apps" -mindepth 3 -maxdepth 3 -type d -name app | sort)

echo "ArgoCD render validation passed"
