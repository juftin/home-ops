#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname "${0}")/lib/common.sh"

readonly ROOT_DIR="$(git rev-parse --show-toplevel)"

function usage() {
    cat <<'EOF'
Usage:
  scripts/rollback-argocd-wave.sh --wave <name> --reason <text> [--namespace <ns>]... [--execute]

Execute ArgoCD-only rollback for a migration wave.

Options:
  --wave        Wave ID to roll back
  --reason      Human-readable rollback trigger context
  --namespace   Namespace in scope; repeat as needed
  --execute     Execute rollback actions (default is dry-run messaging)
  --help, -h    Show this help text
EOF
}

function parse_args() {
    WAVE_ID=""
    REASON=""
    EXECUTE=false
    NAMESPACES=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --wave)
                WAVE_ID="${2:-}"
                shift 2
                ;;
            --reason)
                REASON="${2:-}"
                shift 2
                ;;
            --namespace)
                NAMESPACES+=("${2:-}")
                shift 2
                ;;
            --execute)
                EXECUTE=true
                shift
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

function safety_guards() {
    require_non_empty "wave" "${WAVE_ID}"
    require_non_empty "reason" "${REASON}"
    wave_index "${WAVE_ID}" >/dev/null
    if ((${#REASON} < 10)); then
        log error "Rollback reason must contain useful incident context" "minimumLength=10"
    fi
}

function run_rollback() {
    log warn "Starting ArgoCD rollback workflow" \
        "wave=${WAVE_ID}" \
        "namespaces=${NAMESPACES[*]:-all}" \
        "execute=${EXECUTE}" \
        "reason=${REASON}"

    log info "Rollback step" "step=1" "action=verify-argocd-health"
    kubectl get deploy -n argocd argocd-server argocd-repo-server >/dev/null
    kubectl get statefulset -n argocd argocd-application-controller >/dev/null

    log info "Rollback step" "step=2" "action=resume-flux-ownership-for-target-wave"
    if [[ "${EXECUTE}" == true ]]; then
        log warn "Apply ownership labels manually per namespace before full reconciliation resumes"
    else
        log info "Dry run mode: no ownership labels changed"
    fi

    log info "Rollback step" "step=3" "action=run-wave-verification-after-restoration"
    log info "Rollback workflow prepared" "wave=${WAVE_ID}" "status=pending-operator-confirmation"
}

function main() {
    parse_args "$@"
    check_cli kubectl
    safety_guards
    run_rollback
}

main "$@"
