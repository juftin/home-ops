#!/usr/bin/env sh
set -eu

APP_DIR="${1:-.}"
SOPS_BIN="$(command -v "${SOPS_BIN:-sops}")"
HELM_BIN="$(command -v "${HELM_BIN:-helm}")"
KUSTOMIZE_BIN="$(command -v "${KUSTOMIZE_BIN:-kustomize}")"

APP_ABS="$(cd "${APP_DIR}" && pwd)"
SECRET_DOMAIN="${SECRET_DOMAIN:-example.com}"
SECRET_DOMAIN_DASHED="$(printf '%s' "${SECRET_DOMAIN}" | tr '.' '-')"

WORKDIR="$(mktemp -d)"
cleanup() {
    rm -rf "${WORKDIR}"
}
trap cleanup EXIT

cp -R "${APP_ABS}/." "${WORKDIR}/src"

find "${WORKDIR}/src" -type f \( -name '*.sops.yaml' -o -name '*.sops.yml' \) | while IFS= read -r file; do
    "${SOPS_BIN}" -d --input-type yaml --output-type yaml "${file}" >"${file}.dec"
    mv "${file}.dec" "${file}"
done

mkdir -p "${WORKDIR}/bin"
cat >"${WORKDIR}/bin/helm" <<EOF
#!/usr/bin/env sh
set -eu
if [ "\${1:-}" = "version" ]; then
  echo "v3.17.3"
  exit 0
fi
exec "${HELM_BIN}" "\$@"
EOF
chmod +x "${WORKDIR}/bin/helm"

RAW_MANIFESTS="${WORKDIR}/raw.yaml"
PATH="${WORKDIR}/bin:${PATH}" "${KUSTOMIZE_BIN}" build --enable-helm "${WORKDIR}/src" >"${RAW_MANIFESTS}"

sed -e 's#\${SECRET_DOMAIN/./-}#'"${SECRET_DOMAIN_DASHED}"'#g' \
    -e 's#\${SECRET_DOMAIN}#'"${SECRET_DOMAIN}"'#g' \
    "${RAW_MANIFESTS}"
