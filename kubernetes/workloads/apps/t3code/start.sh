#!/usr/bin/env bash
# Run T3 Code and redact its startup administrative pairing token/QR block from stdout
# so log collectors (Alloy/Loki) never ingest a live pairing credential.
set -euo pipefail

cd /workspace
fifo_dir=$(mktemp -d)
fifo="${fifo_dir}/stdout"
mkfifo "${fifo}"

t3_pid=
filter_pid=

cleanup() {
    trap - EXIT TERM INT
    if [[ -n "${t3_pid}" ]]; then
        kill -TERM "${t3_pid}" 2>/dev/null || true
        wait "${t3_pid}" 2>/dev/null || true
    fi
    if [[ -n "${filter_pid}" ]]; then
        wait "${filter_pid}" 2>/dev/null || true
    fi
    rm -rf "${fifo_dir}"
}
trap cleanup EXIT
trap 'exit 143' TERM INT

awk '
    /^(Token|Pairing URL|App link):/ {
        sub(/:.*/, ": [redacted]")
        print
        fflush()
        next
    }
    /█|▀|▄/ {
        next
    }
    {
        gsub(/#token=[^[:space:]"]+/, "#token=[redacted]")
        print
        fflush()
    }
' <"${fifo}" &
filter_pid=$!

/opt/t3code/t3 serve >"${fifo}" &
t3_pid=$!

rc=0
wait "${t3_pid}" || rc=$?
t3_pid=
wait "${filter_pid}" 2>/dev/null || true
filter_pid=
exit "${rc}"
