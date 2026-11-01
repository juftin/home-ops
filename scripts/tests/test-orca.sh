#!/usr/bin/env bash
# Exercise the packaged headless server with the pod's restricted container permissions.
set -euo pipefail

IMAGE="${1:?Usage: test-orca.sh IMAGE}"
CONTAINER="orca-smoke-$$"
trap 'docker rm --force "${CONTAINER}" >/dev/null 2>&1 || true' EXIT
docker run --detach --name "${CONTAINER}" --cap-drop ALL \
    --security-opt no-new-privileges --shm-size 256m \
    "${IMAGE}" >/dev/null

for ((attempt = 0; attempt < 90; attempt++)); do
    if docker exec "${CONTAINER}" curl --fail --silent \
        http://127.0.0.1:6768/web-index.html -o /tmp/orca-index.html &&
        docker exec "${CONTAINER}" grep --quiet '"type":"orca_server_ready"' \
            /home/orca/.config/Orca/serve-ready.jsonl; then
        break
    fi
    if [[ "$(docker inspect --format '{{.State.Running}}' "${CONTAINER}")" != true ]]; then
        docker logs "${CONTAINER}"
        exit 1
    fi
    sleep 2
done
docker exec "${CONTAINER}" curl --fail --silent \
    http://127.0.0.1:6768/web-index.html -o /tmp/orca-index.html
docker exec "${CONTAINER}" orca status --json | \
    docker exec --interactive "${CONTAINER}" node -e '
let input = "";
process.stdin.on("data", chunk => { input += chunk; });
process.stdin.on("end", () => {
    const status = JSON.parse(input);
    if (!status.ok || status.result.runtime.state !== "ready") process.exit(1);
});'
docker exec "${CONTAINER}" node -e '
const fs = require("node:fs");
const path = process.env.HOME + "/.config/Orca/serve-ready.jsonl";
const messages = fs.readFileSync(path, "utf8").split("\n").flatMap(line => {
    try { return [JSON.parse(line)]; } catch { return []; }
});
const ready = messages.find(message => message.type === "orca_server_ready");
if (!ready?.pairing?.available || !ready.pairing.url) process.exit(1);
if ((fs.statSync(path).mode & 0o077) !== 0) process.exit(1);
const { spawnSync } = require("node:child_process");
const paired = spawnSync("/usr/local/bin/orca", [
    "--pairing-code", ready.pairing.url, "status", "--json"
], { encoding: "utf8" });
if (paired.status !== 0) process.exit(1);
const remote = JSON.parse(paired.stdout);
if (!remote.ok || remote.result.runtime.state !== "ready") process.exit(1);
console.log("Orca runtime, browser bundle, E2EE pairing, and private output passed.");'
