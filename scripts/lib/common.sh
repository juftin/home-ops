#!/usr/bin/env bash
set -Eeuo pipefail

# Log messages with different levels
function log() {
    local level="${1:-info}"
    shift

    # Define log levels with their priorities
    local -A level_priority=(
        [debug]=1
        [info]=2
        [warn]=3
        [error]=4
    )

    # Get the current log level's priority
    local current_priority=${level_priority[$level]:-2} # Default to "info" priority

    # Get the configured log level from the environment, default to "info"
    local configured_level=${LOG_LEVEL:-info}
    local configured_priority=${level_priority[$configured_level]:-2}

    # Skip log messages below the configured log level
    if ((current_priority < configured_priority)); then
        return
    fi

    # Define log colors
    local -A colors=(
        [debug]="\033[1m\033[38;5;63m"  # Blue
        [info]="\033[1m\033[38;5;87m"   # Cyan
        [warn]="\033[1m\033[38;5;192m"  # Yellow
        [error]="\033[1m\033[38;5;198m" # Red
    )

    # Fallback to "info" if the color for the given level is not defined
    local color="${colors[$level]:-${colors[info]}}"
    local msg="$1"
    shift

    # Prepare additional data
    local data=
    if [[ $# -gt 0 ]]; then
        for item in "$@"; do
            if [[ "${item}" == *=* ]]; then
                data+="\033[1m\033[38;5;236m${item%%=*}=\033[0m\"${item#*=}\" "
            else
                data+="${item} "
            fi
        done
    fi

    # Determine output stream based on log level
    local output_stream="/dev/stdout"
    if [[ "$level" == "error" ]]; then
        output_stream="/dev/stderr"
    fi

    # Print the log message
    printf "%s %b%s%b %s %b\n" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        "${color}" "${level^^}" "\033[0m" "${msg}" "${data}" >"${output_stream}"

    # Exit if the log level is error
    if [[ "$level" == "error" ]]; then
        exit 1
    fi
}

# Check if required environment variables are set
function check_env() {
    local envs=("${@}")
    local missing=()
    local values=()

    for env in "${envs[@]}"; do
        if [[ -z "${!env-}" ]]; then
            missing+=("${env}")
        else
            values+=("${env}=${!env}")
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        log error "Missing required env variables" "envs=${missing[*]}"
    fi

    log debug "Env variables are set" "envs=${values[*]}"
}

# Check if required CLI tools are installed
function check_cli() {
    local deps=("${@}")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "${dep}" &>/dev/null; then
            missing+=("${dep}")
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        log error "Missing required deps" "deps=${missing[*]}"
    fi

    log debug "Deps are installed" "deps=${deps[*]}"
}

declare -ar ARGOCD_WAVE_ORDER=("platform" "core" "network" "observability" "apps")
readonly ARGOCD_MIN_CUTOVER_WINDOW_MINUTES=1
readonly ARGOCD_MAX_CUTOVER_WINDOW_MINUTES=10

function require_file() {
    local file="$1"
    if [[ ! -f "${file}" ]]; then
        log error "Required file does not exist" "file=${file}"
    fi
}

function require_non_empty() {
    local key="$1"
    local value="$2"
    if [[ -z "${value}" ]]; then
        log error "Required argument is empty" "argument=${key}"
    fi
}

function wave_index() {
    local wave="$1"
    local i
    for i in "${!ARGOCD_WAVE_ORDER[@]}"; do
        if [[ "${ARGOCD_WAVE_ORDER[$i]}" == "${wave}" ]]; then
            echo "${i}"
            return 0
        fi
    done
    log error "Unknown migration wave" "wave=${wave}" "valid=${ARGOCD_WAVE_ORDER[*]}"
}

function validate_cutover_window() {
    local minutes="$1"
    if [[ ! "${minutes}" =~ ^[0-9]+$ ]]; then
        log error "Cutover window must be a positive integer" "minutes=${minutes}"
    fi
    if ((minutes < ARGOCD_MIN_CUTOVER_WINDOW_MINUTES || minutes > ARGOCD_MAX_CUTOVER_WINDOW_MINUTES)); then
        log error "Cutover window outside allowed range" \
            "minutes=${minutes}" \
            "min=${ARGOCD_MIN_CUTOVER_WINDOW_MINUTES}" \
            "max=${ARGOCD_MAX_CUTOVER_WINDOW_MINUTES}"
    fi
}

function print_wave_order() {
    local joined
    joined=$(printf ",%s" "${ARGOCD_WAVE_ORDER[@]}")
    echo "${joined:1}"
}
