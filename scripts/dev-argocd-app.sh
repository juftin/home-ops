#!/usr/bin/env bash
set -Eeuo pipefail

ACTION="${1:-}"
APP="${DEV_APP:-}"
BRANCH="${DEV_BRANCH:-$(git branch --show-current)}"
APP_PATH="${DEV_APP_PATH:-}"
STATE_KEY=home-ops.io/dev-source
ROOT_KEY=home-ops.io/dev-apps

fail() {
    echo "Error: $*" >&2
    exit 1
}

patch_app() {
    local version patch
    version="$(jq -r .metadata.resourceVersion <<< "${APPLICATION}")"
    patch="$(jq --arg version "${version}" '.metadata.resourceVersion = $version' <<< "$1")"
    APPLICATION="$(kubectl patch application "${APP}" -n argocd --type=merge --patch "${patch}" -o json)"
}

patch_set() {
    local patch
    patch="$(jq --argjson rules "$1" '{metadata: {resourceVersion: .metadata.resourceVersion}, spec: {ignoreApplicationDifferences: $rules}}' <<< "${APP_SET}")"
    kubectl patch applicationset home-ops -n argocd --type=merge --patch "${patch}" >/dev/null
}

hold_root() {
    local state patch
    jq -e '.operation == null and (.status.operationState.phase != "Running") and (.status.operationState.phase != "Terminating")' <<< "${ROOT_APP}" >/dev/null || fail 'Wait for the current root sync to finish before testing an existing app'
    state="$(jq -c --arg key "${ROOT_KEY}" --arg app "${APP}" '
        ((.metadata.annotations[$key] | fromjson?) // {apps:[],automated:.spec.syncPolicy.automated}) |
        .apps = ((.apps + [$app]) | unique)
    ' <<< "${ROOT_APP}")"
    patch="$(jq -nc --arg version "$(jq -r .metadata.resourceVersion <<< "${ROOT_APP}")" --arg key "${ROOT_KEY}" --arg state "${state}" '
        {metadata:{resourceVersion:$version,annotations:{($key):$state}},spec:{syncPolicy:{automated:{enabled:false}}}}
    ')"
    kubectl patch application home-ops-root -n argocd --type=merge --patch "${patch}" >/dev/null
}

release_root() {
    local state patch
    ROOT_APP="$(kubectl get application home-ops-root -n argocd -o json)"
    state="$(jq -c --arg key "${ROOT_KEY}" --arg app "${APP}" '
        .metadata.annotations[$key] | fromjson? | .apps -= [$app]
    ' <<< "${ROOT_APP}")"
    [[ -n "${state}" ]] || return 0
    patch="$(jq -nc --argjson root "${ROOT_APP}" --argjson state "${state}" --arg key "${ROOT_KEY}" '
        {metadata:{resourceVersion:$root.metadata.resourceVersion,annotations:{($key):($state | tojson)}}} |
        if ($state.apps | length) == 0 then
            .metadata.annotations[$key] = null |
            .spec.syncPolicy.automated = (if $state.automated == null then null else $state.automated + {enabled:$state.automated.enabled} end)
        else . end
    ')"
    kubectl patch application home-ops-root -n argocd --type=merge --patch "${patch}" >/dev/null
}

[[ "${ACTION}" == start || "${ACTION}" == sync || "${ACTION}" == stop ]] || fail 'Expected start, sync or stop'
[[ "${APP}" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ && ${#APP} -le 63 && "${APP}" != home-ops-root ]] || fail 'APP must name one workload Application'
RULE="$(jq -nc --arg app "${APP}" '{name:$app,jsonPointers:["/spec/source/path","/spec/source/targetRevision"]}')"
APPLICATION="$(kubectl get application "${APP}" -n argocd -o json --ignore-not-found)"
STATE="$(jq -r --arg key "${STATE_KEY}" '.metadata.annotations[$key] // empty' <<< "${APPLICATION:-null}")"

if [[ "${ACTION}" == stop ]]; then
    if [[ -z "${STATE}" ]]; then
        echo "${APP} has no single-app branch test to stop"
        exit 0
    fi
    if jq -e '.created' <<< "${STATE}" >/dev/null; then
        jq -e '(.metadata.ownerReferences // []) | length == 0' <<< "${APPLICATION}" >/dev/null || fail 'Application was adopted by a controller; refusing to delete it'
        patch_app '{"spec":{"syncPolicy":{"automated":{"enabled":false}}}}'
        patch_app '{"metadata":{"finalizers":null}}'
        DELETE_OPTIONS="$(jq '{apiVersion:"v1",kind:"DeleteOptions",propagationPolicy:"Orphan",preconditions:{uid:.metadata.uid,resourceVersion:.metadata.resourceVersion}}' <<< "${APPLICATION}")"
        kubectl delete --raw "/apis/argoproj.io/v1alpha1/namespaces/argocd/applications/${APP}" -f - <<< "${DELETE_OPTIONS}" >/dev/null
        echo "Removed temporary ${APP} Application; deployed resources and PVCs are retained"
    else
        patch_app "$(jq '{spec:{source:{path:.path,targetRevision:.revision}}}' <<< "${STATE}")"
        if jq -e '.ignoreAdded' <<< "${STATE}" >/dev/null; then
            APP_SET="$(kubectl get applicationset home-ops -n argocd -o json)"
            patch_set "$(jq --argjson rule "${RULE}" '[.spec.ignoreApplicationDifferences[]? | select(. != $rule)]' <<< "${APP_SET}")"
        fi
        release_root
        patch_app "$(jq -nc --arg key "${STATE_KEY}" '{metadata:{annotations:{($key):null}}}')"
        kubectl annotate application "${APP}" -n argocd argocd.argoproj.io/refresh=hard --overwrite
        echo "Restored ${APP} to its original source on main"
    fi
    exit 0
fi

[[ -n "${BRANCH}" && "${BRANCH}" != main ]] || fail 'Select a non-main BRANCH'
git check-ref-format --branch "${BRANCH}" >/dev/null
APP_SET="$(kubectl get applicationset home-ops -n argocd -o json)"
ROOT_APP="$(kubectl get application home-ops-root -n argocd -o json)"
jq -e '.spec.source.targetRevision | . == "main" or . == "refs/heads/main"' <<< "${ROOT_APP}" >/dev/null || fail 'Stop whole-cluster branch testing first'
jq -e '(.spec.template.spec.source.targetRevision == "refs/heads/main") and (.spec.generators[0].matrix.generators[1].git.revision == "refs/heads/main")' <<< "${APP_SET}" >/dev/null || fail 'ApplicationSet must track main'

if [[ "${ACTION}" == sync ]]; then
    [[ "$(git branch --show-current)" == "${BRANCH}" ]] || fail 'Sync must run from the selected branch worktree'
    git push origin "HEAD:refs/heads/${BRANCH}"
fi
git fetch --quiet origin "refs/heads/${BRANCH}"
REVISION="$(git rev-parse FETCH_HEAD)"
if [[ -z "${APP_PATH}" ]]; then
    APP_PATH="$(git ls-tree -r --name-only "${REVISION}" -- kubernetes/workloads | awk -F/ -v app="${APP}" 'NF == 5 && $4 == app && $5 == "kustomization.yaml" {sub(/\/kustomization.yaml$/, ""); print}')"
fi
case "${APP_PATH}" in
    kubernetes/workloads/*/"${APP}") FOLDER="${APP_PATH#kubernetes/workloads/}"; FOLDER="${FOLDER%%/*}" ;;
    kubernetes/apps/*/"${APP}"/app) FOLDER="${APP_PATH#kubernetes/apps/}"; FOLDER="${FOLDER%%/*}" ;;
    *) fail 'No unique app directory found; specify APP_PATH pointing to its kustomization.yaml directory' ;;
esac
[[ "${APP_PATH}" != *$'\n'* && "${APP_PATH}" != *..* ]] || fail 'APP_PATH must name one app directory'
git cat-file -e "${REVISION}:${APP_PATH}/kustomization.yaml" || fail 'App kustomization does not exist on the remote branch'
NAMESPACE="${FOLDER}"
[[ "${FOLDER}" != apps ]] || NAMESPACE="${APP}"

if [[ -n "${APPLICATION}" ]]; then
    jq -e --arg namespace "${NAMESPACE}" '.spec.destination.namespace == $namespace' <<< "${APPLICATION}" >/dev/null || fail 'Branch changes the app namespace; rebase/migrate it before testing'
    if [[ -z "${STATE}" ]]; then
        jq -e 'any(.metadata.ownerReferences[]?; .kind == "ApplicationSet" and .name == "home-ops") and (.spec.source.targetRevision | . == "main" or . == "refs/heads/main")' <<< "${APPLICATION}" >/dev/null || fail 'Existing app must be managed by home-ops and track main'
        IGNORE_ADDED="$(jq --argjson rule "${RULE}" '(.spec.ignoreApplicationDifferences // [] | index($rule)) == null' <<< "${APP_SET}")"
        STATE="$(jq -c --argjson added "${IGNORE_ADDED}" '{created:false,path:.spec.source.path,revision:.spec.source.targetRevision,ignoreAdded:$added}' <<< "${APPLICATION}")"
        patch_app "$(jq -nc --arg key "${STATE_KEY}" --arg state "${STATE}" '{metadata:{annotations:{($key):$state}}}')"
    fi
    if ! jq -e '.created' <<< "${STATE}" >/dev/null; then
        hold_root
        patch_set "$(jq --argjson rule "${RULE}" '(.spec.ignoreApplicationDifferences // []) | if index($rule) == null then . + [$rule] else . end' <<< "${APP_SET}")"
    fi
    patch_app "$(jq -nc --arg path "${APP_PATH}" --arg revision "refs/heads/${BRANCH}" '{spec:{source:{path:$path,targetRevision:$revision}}}')"
else
    WAVE="$(jq -r --arg folder "${FOLDER}" '[.spec.generators[0].matrix.generators[0].list.elements[] | select(.folder == $folder) | .wave][0] // "3"' <<< "${APP_SET}")"
    MANIFEST="$(jq --arg app "${APP}" --arg namespace "${NAMESPACE}" --arg path "${APP_PATH}" --arg revision "refs/heads/${BRANCH}" --arg key "${STATE_KEY}" --arg wave "${WAVE}" '
        {apiVersion:"argoproj.io/v1alpha1",kind:"Application",
         metadata:{name:$app,namespace:"argocd",labels:{"home-ops.io/namespace":$namespace},annotations:{($key):"{\"created\":true}","argocd.argoproj.io/sync-wave":$wave}},
         spec:.spec.template.spec} |
        .spec.project = (if $namespace == "kube-system" then "kube-system" else "home-ops" end) |
        .spec.source.path = $path | .spec.source.targetRevision = $revision | .spec.destination.namespace = $namespace
    ' <<< "${APP_SET}")"
    [[ -z "$(jq -r '.. | strings | select(contains("{{"))' <<< "${MANIFEST}")" ]] || fail 'ApplicationSet has unsupported template fields'
    kubectl create -f - <<< "${MANIFEST}"
fi
kubectl annotate application "${APP}" -n argocd argocd.argoproj.io/refresh=hard --overwrite
echo "${APP} now tracks refs/heads/${BRANCH} at ${APP_PATH}; finish with task dev:app:stop APP=${APP}"
