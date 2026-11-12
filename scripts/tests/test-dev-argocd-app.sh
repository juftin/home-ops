#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "${TEST_DIR}"' EXIT
export TEST_STATE="${TEST_DIR}/state"
mkdir -p "${TEST_STATE}" "${TEST_DIR}/bin" "${TEST_DIR}/repo"
yq -o=json '.metadata.resourceVersion = "1"' "${ROOT_DIR}/kubernetes/argocd/applicationset.yaml" > "${TEST_DIR}/base.json"
cat > "${TEST_DIR}/bin/kubectl" <<'STUB'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >> "${TEST_STATE}/calls"
resource="$2"
name="$3"
case "$1" in
    get)
        case "${resource}/${name}" in
            application/home-ops-root) jq --arg revision "${TEST_ROOT_REVISION:-refs/heads/main}" '.spec.source.targetRevision = $revision' "${TEST_STATE}/home-ops-root.json" ;;
            applicationset/home-ops) cat "${TEST_STATE}/set.json" ;;
            application/*) test ! -f "${TEST_STATE}/${name}.json" || cat "${TEST_STATE}/${name}.json" ;;
            *) exit 1 ;;
        esac
        ;;
    patch)
        while [[ "$1" != --patch ]]; do shift; done
        patch="$2"
        if [[ "${TEST_CONFLICT:-}" == true && "${resource}" == applicationset ]]; then exit 1; fi
        if [[ "${TEST_FAIL_SOURCE:-}" == true ]] && jq -e '.spec.source.targetRevision == "refs/heads/feature"' <<< "${patch}" >/dev/null; then exit 1; fi
        file="${TEST_STATE}/${name}.json"
        [[ "${resource}" != applicationset ]] || file="${TEST_STATE}/set.json"
        if [[ "${TEST_ADOPT_ON_PATCH:-}" == true && "${name}" == orca ]]; then
            jq '.metadata.ownerReferences = [{kind:"ApplicationSet",name:"home-ops"}] | .metadata.resourceVersion = "999"' "${file}" > "${file}.tmp"
            mv "${file}.tmp" "${file}"
        fi
        jq -e --argjson patch "${patch}" '.metadata.resourceVersion == $patch.metadata.resourceVersion' "${file}" >/dev/null || exit 1
        jq --argjson patch "${patch}" '. * $patch | .metadata.resourceVersion = ((.metadata.resourceVersion | tonumber) + 1 | tostring)' "${file}" > "${file}.tmp"
        mv "${file}.tmp" "${file}"
        cat "${file}"
        ;;
    create)
        jq '.metadata.resourceVersion = "1" | .metadata.uid = "new-app-uid"' > "${TEST_STATE}/created.json"
        name="$(jq -r .metadata.name "${TEST_STATE}/created.json")"
        cp "${TEST_STATE}/created.json" "${TEST_STATE}/${name}.json"
        ;;
    delete)
        [[ "$2" == --raw ]] || exit 1
        name="${3##*/}"
        options="$(cat)"
        if [[ "${TEST_ADOPT_ON_DELETE:-}" == true ]]; then
            jq '.metadata.ownerReferences = [{kind:"ApplicationSet",name:"home-ops"}] | .metadata.resourceVersion = "999"' "${TEST_STATE}/${name}.json" > "${TEST_STATE}/adopted.json"
            mv "${TEST_STATE}/adopted.json" "${TEST_STATE}/${name}.json"
        fi
        jq -e --argjson options "${options}" '.metadata.uid == $options.preconditions.uid and .metadata.resourceVersion == $options.preconditions.resourceVersion' "${TEST_STATE}/${name}.json" >/dev/null || exit 1
        rm "${TEST_STATE}/${name}.json"
        ;;
    annotate) ;;
    *) exit 1 ;;
esac
STUB
chmod +x "${TEST_DIR}/bin/kubectl"
export PATH="${TEST_DIR}/bin:${PATH}"
git init --quiet --bare "${TEST_DIR}/remote.git"
git -C "${TEST_DIR}/repo" init --quiet -b feature
git -C "${TEST_DIR}/repo" config user.name 'Test User'
git -C "${TEST_DIR}/repo" config user.email test@example.com
mkdir -p "${TEST_DIR}/repo/kubernetes/workloads/apps/echo" "${TEST_DIR}/repo/kubernetes/workloads/apps/other" "${TEST_DIR}/repo/kubernetes/apps/default/orca/app"
printf 'resources: []\n' > "${TEST_DIR}/repo/kubernetes/workloads/apps/echo/kustomization.yaml"
printf 'resources: []\n' > "${TEST_DIR}/repo/kubernetes/apps/default/orca/app/kustomization.yaml"
printf 'resources: []\n' > "${TEST_DIR}/repo/kubernetes/workloads/apps/other/kustomization.yaml"
git -C "${TEST_DIR}/repo" add .
git -C "${TEST_DIR}/repo" commit --quiet -m 'Test fixtures'
git -C "${TEST_DIR}/repo" remote add origin "${TEST_DIR}/remote.git"
git -C "${TEST_DIR}/repo" push --quiet origin feature
cd "${TEST_DIR}/repo"
export DEV_BRANCH=feature DEV_APP=echo DEV_APP_PATH=''

reset_state() {
    printf '%s' '{"metadata":{"resourceVersion":"1"},"spec":{"source":{"targetRevision":"refs/heads/main"},"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}' > "${TEST_STATE}/home-ops-root.json"
    cp "${TEST_DIR}/base.json" "${TEST_STATE}/set.json"
    rm -f "${TEST_STATE}/echo.json" "${TEST_STATE}/orca.json" "${TEST_STATE}/other.json"
    : > "${TEST_STATE}/calls"
    jq '{apiVersion: "argoproj.io/v1alpha1", kind: "Application", metadata: {name: "echo", namespace: "argocd", resourceVersion: "2", ownerReferences: [{kind: "ApplicationSet", name: "home-ops"}]}, spec: .spec.template.spec} | .spec.source.path = "kubernetes/workloads/apps/echo" | .spec.destination.namespace = "echo" | .spec.project = "home-ops"' "${TEST_DIR}/base.json" > "${TEST_STATE}/echo.json"
}

run_app() {
    bash "${ROOT_DIR}/scripts/dev-argocd-app.sh" "$@"
}

assert_json() {
    jq --exit-status "$2" "${TEST_STATE}/$1.json" > /dev/null
}

expect_failure() {
    if run_app "$@" > "${TEST_DIR}/failure.log" 2>&1; then
        echo "Unexpected success: $*" >&2
        exit 1
    fi
}

# Removing the source override or changing the whole-set revision breaks isolation.
reset_state
run_app start
assert_json echo '.spec.source.targetRevision == "refs/heads/feature"'
assert_json home-ops-root '.spec.source.targetRevision == "refs/heads/main" and .spec.syncPolicy.automated.enabled == false'
assert_json set '.spec.template.spec.source.targetRevision == "refs/heads/main" and .spec.generators[0].matrix.generators[1].git.revision == "refs/heads/main"'
assert_json set '.spec.ignoreApplicationDifferences == [{name:"echo",jsonPointers:["/spec/source/path","/spec/source/targetRevision"]}]'
run_app start
assert_json set '.spec.ignoreApplicationDifferences | length == 1'
run_app sync
run_app stop
assert_json home-ops-root '(.spec.syncPolicy.automated.enabled == null) and .spec.syncPolicy.automated.selfHeal and .spec.syncPolicy.automated.prune'
assert_json echo '.spec.source.targetRevision == "refs/heads/main" and .spec.source.path == "kubernetes/workloads/apps/echo"'
assert_json set '(.spec.ignoreApplicationDifferences // []) | length == 0'
run_app stop

# Root resumes only after the last existing-app test stops.
reset_state
jq '.metadata.name = "other" | .spec.source.path = "kubernetes/workloads/apps/other" | .spec.destination.namespace = "other"' "${TEST_STATE}/echo.json" > "${TEST_STATE}/other.json"
run_app start
DEV_APP=other run_app start
run_app stop
assert_json home-ops-root '.spec.syncPolicy.automated.enabled == false'
DEV_APP=other run_app stop
assert_json home-ops-root '.spec.syncPolicy.automated.enabled == null'
for enabled in true false; do
    reset_state
    jq --argjson enabled "${enabled}" '.spec.syncPolicy.automated.enabled = $enabled' "${TEST_STATE}/home-ops-root.json" > "${TEST_DIR}/root.json"
    mv "${TEST_DIR}/root.json" "${TEST_STATE}/home-ops-root.json"
    run_app start
    run_app stop
    assert_json home-ops-root ".spec.syncPolicy.automated.enabled == ${enabled}"
done

# A branch-only app in the current layout needs no APP_PATH override.
reset_state
rm "${TEST_STATE}/echo.json"
run_app start
assert_json echo '.spec.destination.namespace == "echo" and .spec.source.path == "kubernetes/workloads/apps/echo"'
run_app stop

# Preserve unrelated ignore rules and a pre-existing identical scoped rule.
reset_state
jq '.spec.ignoreApplicationDifferences = [{name:"other",jsonPointers:["/spec/source/targetRevision"]},{name:"echo",jsonPointers:["/spec/source/path","/spec/source/targetRevision"]}]' "${TEST_STATE}/set.json" > "${TEST_DIR}/rules.json"
cp "${TEST_DIR}/rules.json" "${TEST_STATE}/set.json"
run_app start
run_app stop
jq '.spec.ignoreApplicationDifferences' "${TEST_DIR}/rules.json" > "${TEST_DIR}/expected.json"
jq '.spec.ignoreApplicationDifferences' "${TEST_STATE}/set.json" > "${TEST_DIR}/actual.json"
cmp "${TEST_DIR}/expected.json" "${TEST_DIR}/actual.json"

# A new app can use PR #232's legacy path without deploying other branch changes.
reset_state
export DEV_APP=orca DEV_APP_PATH=kubernetes/apps/default/orca/app
run_app start
assert_json orca '.spec.source.path == "kubernetes/apps/default/orca/app" and .spec.source.targetRevision == "refs/heads/feature" and .spec.destination.namespace == "default" and .spec.project == "home-ops"'
assert_json orca '(.metadata.ownerReferences // [] | length == 0) and (.metadata.finalizers // [] | length == 0)'
cmp "${TEST_DIR}/base.json" "${TEST_STATE}/set.json"
run_app start
run_app stop
test ! -f "${TEST_STATE}/orca.json"
if grep -Eq 'delete (namespace|deployment|pvc|persistentvolumeclaim)' "${TEST_STATE}/calls"; then exit 1; fi

# Invalid paths and refs, whole-cluster testing and stale updates cannot mutate refs.
export DEV_APP=echo DEV_APP_PATH=''
reset_state
DEV_BRANCH=main expect_failure start
DEV_APP=home-ops-root expect_failure start
DEV_APP_PATH=kubernetes/workloads/apps/missing expect_failure start
DEV_APP_PATH=kubernetes/apps/default/orca/app expect_failure start
TEST_ROOT_REVISION=refs/heads/other expect_failure start
TEST_CONFLICT=true expect_failure start
assert_json echo '.spec.source.targetRevision == "refs/heads/main"'
run_app stop
reset_state
TEST_FAIL_SOURCE=true expect_failure start
run_app stop
assert_json echo '.spec.source.targetRevision == "refs/heads/main"'
assert_json set '(.spec.ignoreApplicationDifferences // []) | length == 0'

# Root syncs already in progress must finish before adding an exception.
reset_state
jq '.operation = {sync:{}} | .status.operationState.phase = "Running"' "${TEST_STATE}/home-ops-root.json" > "${TEST_DIR}/running.json"
mv "${TEST_DIR}/running.json" "${TEST_STATE}/home-ops-root.json"
expect_failure start
assert_json set '(.spec.ignoreApplicationDifferences // []) | length == 0'
run_app stop

# Adoption during cleanup must reject stale patches and conditional deletion.
reset_state
export DEV_APP=orca DEV_APP_PATH=kubernetes/apps/default/orca/app
run_app start
TEST_ADOPT_ON_PATCH=true expect_failure stop
assert_json orca '.metadata.ownerReferences[0].name == "home-ops"'
reset_state
run_app start
TEST_ADOPT_ON_DELETE=true expect_failure stop
assert_json orca '.metadata.ownerReferences[0].name == "home-ops"'

echo 'Single-app ArgoCD branch regression checks passed'
