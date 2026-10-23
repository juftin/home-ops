#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "${TEST_DIR}"' EXIT

mkdir -p "${TEST_DIR}/repo/scripts" "${TEST_DIR}/repo/kubernetes/argocd" \
    "${TEST_DIR}/repo/kubernetes/components/sops" "${TEST_DIR}/repo/kubernetes/apps/default/test/app" \
    "${TEST_DIR}/repo/talos" "${TEST_DIR}/scratch"
cp "${ROOT_DIR}/scripts/validate-argocd-render.sh" "${TEST_DIR}/repo/scripts/"
cp "${ROOT_DIR}/scripts/validate-kubernetes-schema.sh" "${TEST_DIR}/repo/scripts/"
cp "${ROOT_DIR}/scripts/validate-auth.py" "${TEST_DIR}/repo/scripts/"
cp "${ROOT_DIR}/scripts/render-argocd-app.sh" "${TEST_DIR}/repo/scripts/render-real.sh"
cp "${ROOT_DIR}/talos/talenv.yaml" "${TEST_DIR}/repo/talos/"
git -C "${TEST_DIR}/repo" init --quiet
cd "${TEST_DIR}/repo"

age-keygen -o "${TEST_DIR}/age.key" 2>/dev/null
RECIPIENT="$(age-keygen -y "${TEST_DIR}/age.key")"
export SOPS_AGE_KEY_FILE="${TEST_DIR}/missing-age.key"
unset SOPS_AGE_KEY SOPS_BIN

# All secrets here are generated test data, unrelated to the cluster.
cat <<'EOF' | sops --encrypt --age "${RECIPIENT}" --encrypted-regex '^(stringData)$' \
    --input-type yaml --output-type yaml /dev/stdin > kubernetes/components/sops/cluster-secrets.sops.yaml
apiVersion: v1
kind: Secret
metadata:
  name: cluster-secrets
stringData:
  SECRET_DOMAIN: fixture.test
EOF
cat <<'EOF' | sops --encrypt --age "${RECIPIENT}" --encrypted-regex '^(stringData|spec)$' \
    --input-type yaml --output-type yaml /dev/stdin > kubernetes/apps/default/test/app/secret.sops.yaml
apiVersion: v1
kind: Secret
metadata:
  name: fixture-secret
stringData:
  token: fixture-token
---
apiVersion: example.com/v1
kind: TestPolicy
metadata:
  name: fixture-policy
spec:
  enabled: true
  count: 3
  ratio: 2.5
  subjects:
    - fixture-user
EOF
cat > kubernetes/argocd/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources: []
EOF
cat > kubernetes/apps/default/test/app/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - secret.sops.yaml
  - domain.yaml
EOF
cat > kubernetes/apps/default/test/app/domain.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: fixture-domain
data:
  domain: ${SECRET_DOMAIN}
  dashed: ${SECRET_DOMAIN/./-}
EOF
cp kubernetes/apps/default/test/app/secret.sops.yaml "${TEST_DIR}/original.yaml"

# Capture the renderer's output while still using real Kustomize, SOPS, and yq.
export TEST_RENDERED="${TEST_DIR}/rendered.yaml"
cat > scripts/render-argocd-app.sh <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
"$(dirname "$0")/render-real.sh" "$@" | tee -a "${TEST_RENDERED}"
EOF
chmod +x scripts/render-argocd-app.sh
export TMPDIR="${TEST_DIR}/scratch"

assert_yaml() {
    if ! yq --exit-status "$1" "${TEST_RENDERED}" >/dev/null; then
        echo "Rendered fixture failed assertion: $1" >&2
        cat "${TEST_RENDERED}" >&2
        exit 1
    fi
}

scripts/validate-argocd-render.sh --offline
assert_yaml 'select(.kind == "Secret") | .stringData.token == "Y2ktcGxhY2Vob2xkZXI="'
assert_yaml 'select(.kind == "TestPolicy") | (.spec.enabled == false) and (.spec.count == 1) and (.spec.ratio == 1) and (.spec.subjects[0] == "Y2ktcGxhY2Vob2xkZXI=") and (has("sops") == false)'
assert_yaml 'select(.kind == "ConfigMap") | (.data.domain == "example.com") and (.data.dashed == "example-com")'
cmp kubernetes/apps/default/test/app/secret.sops.yaml "${TEST_DIR}/original.yaml"
test -z "$(find "${TMPDIR}" -mindepth 1 -print -quit)"

# An inline key works even when mise/Task points SOPS_AGE_KEY_FILE at a missing file.
export SOPS_AGE_KEY="$(cat "${TEST_DIR}/age.key")"
rm "${TEST_RENDERED}"
scripts/validate-argocd-render.sh
assert_yaml 'select(.kind == "Secret") | .stringData.token == "fixture-token"'
assert_yaml 'select(.kind == "ConfigMap") | .data.domain == "fixture.test"'
cmp kubernetes/apps/default/test/app/secret.sops.yaml "${TEST_DIR}/original.yaml"

unset SOPS_AGE_KEY
if scripts/validate-argocd-render.sh >"${TEST_DIR}/missing-key.log" 2>&1; then
    echo "Full validation unexpectedly succeeded without a key" >&2
    exit 1
fi

# Valid YAML that Kustomize renders must still fail Kubernetes type validation.
yq --inplace '.data.domain = 42' kubernetes/apps/default/test/app/domain.yaml
if scripts/validate-argocd-render.sh --offline >"${TEST_DIR}/invalid-schema.log" 2>&1; then
    echo "Offline validation unexpectedly accepted an invalid ConfigMap" >&2
    exit 1
fi
grep -q 'Invalid: 1' "${TEST_DIR}/invalid-schema.log"
yq --inplace '.data.domain = "${SECRET_DOMAIN}"' kubernetes/apps/default/test/app/domain.yaml

# Strict validation rejects unknown fields, even when known fields are well typed.
yq --inplace '.unexpectedField = true' kubernetes/apps/default/test/app/domain.yaml
if scripts/validate-argocd-render.sh --offline >"${TEST_DIR}/unknown-field.log" 2>&1; then
    echo "Offline validation unexpectedly accepted an unknown ConfigMap field" >&2
    exit 1
fi
grep -q 'Invalid: 1' "${TEST_DIR}/unknown-field.log"
yq --inplace 'del(.unexpectedField)' kubernetes/apps/default/test/app/domain.yaml

# Unknown built-in kinds must fail, rather than being treated as custom resources.
yq --inplace '.kind = "ConfigMapTypo"' kubernetes/apps/default/test/app/domain.yaml
if scripts/validate-argocd-render.sh --offline >"${TEST_DIR}/missing-schema.log" 2>&1; then
    echo "Offline validation unexpectedly accepted a missing built-in schema" >&2
    exit 1
fi
grep -q 'could not find schema' "${TEST_DIR}/missing-schema.log"
yq --inplace '.kind = "ConfigMap"' kubernetes/apps/default/test/app/domain.yaml

printf '\n  - missing.yaml\n' >> kubernetes/apps/default/test/app/kustomization.yaml
if scripts/validate-argocd-render.sh --offline >"${TEST_DIR}/invalid-app.log" 2>&1; then
    echo "Offline validation unexpectedly accepted an invalid app" >&2
    exit 1
fi
test -z "$(find "${TMPDIR}" -mindepth 1 -print -quit)"

echo "ArgoCD render regression checks passed"
