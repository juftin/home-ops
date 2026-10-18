#!/usr/bin/env bash
# Install pinned runtime artifacts on the pod-local volume, separate from user state.
set -euo pipefail

HERDR_VERSION=0.9.5
WEB_UI_VERSION=0.4.11
WEB_UI_SHA256=9d15e826ab852d179f970b930dca919b73ce9f91f81acd76e35fbca9f897313c

case "$(uname -m)" in
    x86_64)
        ARCH=x86_64
        HERDR_SHA256=14d9e8bc8b4a9e0118d77c32266f76d461f09b40342eb23752960bd89f59929d
        ;;
    aarch64|arm64)
        ARCH=aarch64
        HERDR_SHA256=17d7536f2da50859523680ef279dffcac8e4a235f4e46fe8da6c2ec44141897c
        ;;
    *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

mkdir -p /opt/herdr/bin /opt/herdr/web-ui
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT
curl --fail --silent --show-error --location --retry 3 \
    "https://github.com/herdrdev/herdr/releases/download/v${HERDR_VERSION}/herdr-linux-${ARCH}" \
    -o "${TMP_DIR}/herdr"
printf '%s  %s\n' "${HERDR_SHA256}" "${TMP_DIR}/herdr" | sha256sum --check
install -m 0755 "${TMP_DIR}/herdr" /opt/herdr/bin/herdr
curl --fail --silent --show-error --location --retry 3 \
    "https://codeload.github.com/devswha/herdr-web-ui/tar.gz/refs/tags/v${WEB_UI_VERSION}" \
    -o "${TMP_DIR}/web-ui.tar.gz"
printf '%s  %s\n' "${WEB_UI_SHA256}" "${TMP_DIR}/web-ui.tar.gz" | sha256sum --check
tar -xzf "${TMP_DIR}/web-ui.tar.gz" --strip-components=1 -C /opt/herdr/web-ui
cd /opt/herdr/web-ui
bun install --frozen-lockfile
bun run build
herdr --version
