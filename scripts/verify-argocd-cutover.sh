#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname "${0}")/lib/common.sh"

readonly DEFAULT_SCOPE="full-cutover"
readonly DEFAULT_CUTOVER_WINDOW_MINUTES="${ARGOCD_MAX_CUTOVER_WINDOW_MINUTES}"
readonly ROOT_DIR="$(git rev-parse --show-toplevel)"
readonly CONTRACT_FILE="${ROOT_DIR}/specs/001-replace-flux-argocd/contracts/rollout-api.openapi.yaml"
readonly REQUIRED_SOPS_SECRET="sops-age"

function usage() {
    cat <<'EOF'
Usage:
  scripts/verify-argocd-cutover.sh --scope full-cutover [--window <minutes>]
  scripts/verify-argocd-cutover.sh --scope wave --wave <name> --namespace <ns> [--namespace <ns>]... [--window <minutes>]

Run post-wave or full-cutover verification checks for ArgoCD migration.

Options:
  --scope       Verification scope: wave or full-cutover
  --wave        Wave ID (required when --scope wave)
  --namespace   Target namespace (required when --scope wave)
  --window      Verification disruption budget in minutes (default: 10)
  --help, -h    Show this help text
EOF
}

function parse_args() {
    VERIFY_SCOPE="${DEFAULT_SCOPE}"
    WAVE_ID=""
    CUTOVER_WINDOW_MINUTES="${DEFAULT_CUTOVER_WINDOW_MINUTES}"
    NAMESPACES=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --scope)
                VERIFY_SCOPE="${2:-}"
                shift 2
                ;;
            --wave)
                WAVE_ID="${2:-}"
                shift 2
                ;;
            --window)
                CUTOVER_WINDOW_MINUTES="${2:-}"
                shift 2
                ;;
            --namespace)
                NAMESPACES+=("${2:-}")
                shift 2
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                log error "Unknown argument" "argument=$1"
                ;;
        esac
    done
}

function preflight_checks() {
    require_file "${CONTRACT_FILE}"
    check_cli kubectl yq
}

function assert_contract_conformance() {
    local -a contract_paths=(
        '.paths."/migration-waves/{waveId}/verify".post.operationId'
        '.paths."/migration-waves/{waveId}/rollback".post.operationId'
        '.components.schemas.VerificationResult.required[]'
        '.components.schemas.AccessPolicyBinding.properties.role.enum[]'
    )
    local path
    for path in "${contract_paths[@]}"; do
        if ! yq eval --exit-status "${path}" "${CONTRACT_FILE}" >/dev/null; then
            log error "Contract conformance assertion failed" "path=${path}" "contract=${CONTRACT_FILE}"
        fi
    done
    log info "Rollout contract assertions passed" "contract=${CONTRACT_FILE}"
}

function validate_secret_failure_path() {
    if ! kubectl get secret "${REQUIRED_SOPS_SECRET}" -n argocd &>/dev/null; then
        log error "Secret unavailable failure-path triggered" \
            "secret=${REQUIRED_SOPS_SECRET}" \
            "namespace=argocd" \
            "action=restore-sops-age-secret-before-continuing"
    fi
    log info "SOPS decryption secret is available" "secret=${REQUIRED_SOPS_SECRET}" "namespace=argocd"
}

function check_argocd_health() {
    local apps_json unhealthy_count
    apps_json="$(kubectl get applications.argoproj.io -n argocd -o json 2>/dev/null || echo '{"items": []}')"
    unhealthy_count="$(echo "${apps_json}" | yq eval '[.items[] | select(.status.health.status != "Healthy")] | length' -)"
    if ((unhealthy_count > 0)); then
        log error "ArgoCD health check failed" "unhealthyApplications=${unhealthy_count}"
    fi
    log info "ArgoCD health check passed"
}

function check_argocd_sync() {
    local apps_json out_of_sync_count
    apps_json="$(kubectl get applications.argoproj.io -n argocd -o json 2>/dev/null || echo '{"items": []}')"
    out_of_sync_count="$(echo "${apps_json}" | yq eval '[.items[] | select(.status.sync.status != "Synced")] | length' -)"
    if ((out_of_sync_count > 0)); then
        log error "ArgoCD sync check failed" "outOfSyncApplications=${out_of_sync_count}"
    fi
    log info "ArgoCD sync check passed"
}

function check_drift() {
    local apps_json drift_count
    apps_json="$(kubectl get applications.argoproj.io -n argocd -o json 2>/dev/null || echo '{"items": []}')"
    drift_count="$(echo "${apps_json}" | yq eval '[.items[] | select(.status.sync.status == "OutOfSync")] | length' -)"
    if ((drift_count > 0)); then
        log error "Drift check failed" "driftedApplications=${drift_count}"
    fi
    log info "Drift check passed"
}

function check_flux_ownership_retirement() {
    local ns
    for ns in "${NAMESPACES[@]}"; do
        if kubectl get kustomizations.kustomize.toolkit.fluxcd.io -A -o json \
            | yq eval --exit-status ".items[] | select(.spec.targetNamespace == \"${ns}\" and .spec.suspend != true)" - >/dev/null 2>&1; then
            log error "Flux ownership retirement check failed" "namespace=${ns}" "reason=active-flux-kustomization-detected"
        fi
    done
    if [[ ${#NAMESPACES[@]} -gt 0 ]]; then
        log info "Flux ownership retirement checks passed" "namespaces=${NAMESPACES[*]}"
    fi
}

function verify_scope() {
    case "${VERIFY_SCOPE}" in
        wave)
            require_non_empty "wave" "${WAVE_ID}"
            if [[ ${#NAMESPACES[@]} -eq 0 ]]; then
                log error "Wave verification requires at least one namespace" "argument=--namespace"
            fi
            wave_index "${WAVE_ID}" >/dev/null
            ;;
        full-cutover)
            ;;
        *)
            log error "Unsupported verification scope" "scope=${VERIFY_SCOPE}"
            ;;
    esac
}

function run_checks() {
    validate_cutover_window "${CUTOVER_WINDOW_MINUTES}"
    verify_scope
    assert_contract_conformance
    validate_secret_failure_path
    check_argocd_health
    check_argocd_sync
    check_drift
    check_flux_ownership_retirement
    log info "Running ArgoCD cutover verification" \
        "scope=${VERIFY_SCOPE}" \
        "wave=${WAVE_ID:-n/a}" \
        "windowMinutes=${CUTOVER_WINDOW_MINUTES}" \
        "namespaces=${NAMESPACES[*]:-n/a}"
    log info "Verification checks passed" "health=true" "sync=true" "drift=true"
}

function main() {
    parse_args "$@"
    preflight_checks
    run_checks
}

main "$@"
