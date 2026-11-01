#!/usr/bin/env bash
# Keep access links in the private home volume instead of shared container logs.
set -euo pipefail
umask 077
mkdir -p "${ORCA_USER_DATA_PATH}"
exec /usr/local/bin/orca "$@" --json >"${ORCA_USER_DATA_PATH}/serve-ready.jsonl"
