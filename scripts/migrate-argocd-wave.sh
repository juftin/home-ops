#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname "${0}")/lib/common.sh"

readonly DEFAULT_CUTOVER_WINDOW_MINUTES="${ARGOCD_MAX_CUTOVER_WINDOW_MINUTES}"
readonly ROOT_DIR="$(git rev-parse --show-toplevel)"
readonly FLUX_CLUSTER_KS="${ROOT_DIR}/kubernetes/flux/cluster/ks.yaml"
readonly ARGOCD_ROOT_KS="${ROOT_DIR}/kubernetes/argocd/kustomization.yaml"

function usage() {
    cat <<'EOF'
Usage:
  scripts/migrate-argocd-wave.sh --wave <name> --namespace <ns> [--namespace <ns>]... [--window <minutes>]

Start a migration wave that transfers workload ownership from Flux to ArgoCD.

Options:
  --wave        Wave ID (must match configured wave order)
  --namespace   Target namespace; repeat for multi-namespace wave scope
  --window      Disruption budget in minutes (default: 10, allowed: 1-10)
  --help, -h    Show this help text
EOF
}

function parse_args() {
    WAVE_ID=""
    CUTOVER_WINDOW_MINUTES="${DEFAULT_CUTOVER_WINDOW_MINUTES}"
    NAMESPACES=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
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
    require_file "${FLUX_CLUSTER_KS}"
    require_file "${ARGOCD_ROOT_KS}"
    check_cli kubectl kustomize yq
}

function render_argocd_manifests() {
    if ! kustomize build "${ROOT_DIR}/kubernetes/argocd" >/dev/null; then
        log error "Failed to render ArgoCD manifests" "path=${ROOT_DIR}/kubernetes/argocd"
    fi
    log info "ArgoCD manifests render succeeded"
}

function emit_wave_plan() {
    local namespaces_json=
    local ns
    for ns in "${NAMESPACES[@]}"; do
        if [[ -n "${namespaces_json}" ]]; then
            namespaces_json+=", "
        fi
        namespaces_json+="\"${ns}\""
    done
    cat <<EOF
{
  "waveId": "${WAVE_ID}",
  "cutoverWindowMinutes": ${CUTOVER_WINDOW_MINUTES},
  "status": "in_progress",
  "namespaces": [${namespaces_json}]
}
EOF
}

function print_retirement_hint() {
    local ns
    for ns in "${NAMESPACES[@]}"; do
        log info "Flux retirement hint" \
            "namespace=${ns}" \
            "instruction=Label matching Flux Kustomizations with home-ops.io/gitops-controller=argocd after successful wave verification"
    done
}

function run_wave_cutover() {
    local wave_position
    wave_position="$(wave_index "${WAVE_ID}")"
    validate_cutover_window "${CUTOVER_WINDOW_MINUTES}"

    log info "Starting ArgoCD migration wave" \
        "wave=${WAVE_ID}" \
        "position=${wave_position}" \
        "windowMinutes=${CUTOVER_WINDOW_MINUTES}" \
        "namespaces=${NAMESPACES[*]}"

    log info "Wave ordering" "order=$(print_wave_order)"
    render_argocd_manifests
    emit_wave_plan
    print_retirement_hint
    log info "Wave cutover plan prepared"
}

function main() {
    parse_args "$@"
    require_non_empty "wave" "${WAVE_ID}"
    if [[ ${#NAMESPACES[@]} -eq 0 ]]; then
        log error "At least one namespace is required" "argument=--namespace"
    fi
    preflight_checks
    run_wave_cutover
}

main "$@"
