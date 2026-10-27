#!/usr/bin/env bash
# Supervise both foreground processes; Kubernetes restarts the pair if either exits.
set -euo pipefail

: "${HERDR_WEB_TOKEN:?HERDR_WEB_TOKEN must be nonempty}"
mkdir -p "${HOME}/.config/herdr" "${HERDR_WEB_STATE_DIR}"
cd /workspace
herdr_pid=
web_pid=
cleanup() {
    trap - EXIT TERM INT
    if [[ -n "${web_pid}" ]]; then kill -TERM "${web_pid}" 2>/dev/null || true; fi
    if [[ -n "${herdr_pid}" ]]; then kill -TERM "${herdr_pid}" 2>/dev/null || true; fi
    # Let Herdr save session state and the web UI release terminal attachments.
    wait || true
}
trap cleanup EXIT
trap 'exit 143' TERM INT

herdr server &
herdr_pid=$!
for ((attempt = 0; attempt < 60; attempt++)); do
    kill -0 "${herdr_pid}"
    if herdr api snapshot >/dev/null 2>&1; then break; fi
    sleep 1
done
herdr api snapshot >/dev/null

cd /opt/herdr/web-ui
# Run directly: Kubernetes owns the lifecycle and upgrades, rather than the app updater.
bun run server/index.ts &
web_pid=$!
wait -n "${herdr_pid}" "${web_pid}"
exit 1
