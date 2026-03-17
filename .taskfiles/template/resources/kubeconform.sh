#!/usr/bin/env bash

set -euo pipefail

KUBERNETES_DIR=$1

[[ -z "${KUBERNETES_DIR}" ]] && echo "Kubernetes location not specified" && exit 1

kustomize_args=("--load-restrictor=LoadRestrictionsNone" "--enable-helm")
kustomize_config="kustomization.yaml"
kubeconform_args=(
    "-strict"
    "-ignore-missing-schemas"
    "-skip"
    "Gateway,HTTPRoute,Secret"
    "-schema-location"
    "default"
    "-schema-location"
    "https://kubernetes-schemas.pages.dev/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
    "-verbose"
)

echo "=== Validating kustomizations in ${KUBERNETES_DIR}/apps ==="
HELM_BIN="$(command -v helm)"
HELM_SHIM_DIR="$(mktemp -d)"
trap 'rm -rf "${HELM_SHIM_DIR}"' EXIT
cat >"${HELM_SHIM_DIR}/helm" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "version" ]]; then
  echo "v3.17.3"
  exit 0
fi
exec "${HELM_BIN}" "\$@"
EOF
chmod +x "${HELM_SHIM_DIR}/helm"

find "${KUBERNETES_DIR}/apps" -type f -name $kustomize_config -print0 | while IFS= read -r -d $'\0' file;
do
    echo "=== Validating kustomizations in ${file/%$kustomize_config} ==="
    PATH="${HELM_SHIM_DIR}:${PATH}" kustomize build "${file/%$kustomize_config}" "${kustomize_args[@]}" | kubeconform "${kubeconform_args[@]}"
    if [[ ${PIPESTATUS[0]} != 0 ]]; then
        exit 1
    fi
done
