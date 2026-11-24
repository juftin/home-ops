#!/usr/bin/env bash
# Install pinned official T3 Code release on the pod-local volume, separate from user state.
set -euo pipefail

T3CODE_VERSION=0.1.11

case "$(uname -m)" in
    x86_64)
        ARCH=x64
        T3CODE_SHA256=2b691c07f5bcb5adea4a863d5324aae7db21bd6d82280cec7787836dcaa013e1
        ;;
    aarch64|arm64)
        ARCH=arm64
        T3CODE_SHA256=7d90a5af032fe0988a616403e0f51a6cb68eff7ed7a84bc40999cc3997dffd71
        ;;
    *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

ARCHIVE="t3-${T3CODE_VERSION}-linux-${ARCH}.tar.gz"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

curl --fail --silent --show-error --location --retry 3 \
    "https://github.com/pingdotgg/t3code/releases/download/v${T3CODE_VERSION}/${ARCHIVE}" \
    -o "${TMP_DIR}/${ARCHIVE}"
printf '%s  %s\n' "${T3CODE_SHA256}" "${TMP_DIR}/${ARCHIVE}" | sha256sum --check

mkdir -p /opt/t3code
find /opt/t3code -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
tar -xzf "${TMP_DIR}/${ARCHIVE}" --strip-components=1 -C /opt/t3code
/opt/t3code/t3 --version
