#!/usr/bin/env bash
# Supervise both foreground processes; Kubernetes restarts the pair if either exits.
set -euo pipefail

: "${OVIS_TOKEN:?OVIS_TOKEN must be nonempty}"
mkdir -p "${XDG_CONFIG_HOME}/herdr"
cd /workspace
herdr_pid=
ovis_pid=
cleanup() {
    trap - EXIT TERM INT
    if [[ -n "${ovis_pid}" ]]; then kill -TERM "${ovis_pid}" 2>/dev/null || true; fi
    if [[ -n "${herdr_pid}" ]]; then kill -TERM "${herdr_pid}" 2>/dev/null || true; fi
    # Let Herdr save session state and Ovis release terminal attachments.
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

cd /opt/herdr/ovis
# Kubernetes owns the lifecycle and upgrades.
bun run server/index.ts &
ovis_pid=$!
wait -n "${herdr_pid}" "${ovis_pid}"
exit 1
