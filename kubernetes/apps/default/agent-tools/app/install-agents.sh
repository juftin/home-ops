#!/usr/bin/env bash
# Install shared coding tools in the persistent home before an agent app starts.
set -euo pipefail

export PATH="${HOME}/.local/bin:${PATH}"
mkdir -p "${HOME}/.local/bin"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

if ! npm install --global --prefix "${HOME}/.local" @openai/codex@latest; then
    codex --version
    echo "Codex upgrade failed; using the installed version." >&2
fi
if ! npm install --global --prefix "${HOME}/.local" @anthropic-ai/claude-code@latest --allow-scripts=@anthropic-ai/claude-code; then
    claude --version
    echo "Claude Code upgrade failed; using the installed version." >&2
fi
if command -v agy >/dev/null 2>&1; then
    if ! agy update; then
        echo "Antigravity upgrade failed; using the installed version." >&2
    fi
else
    curl -fsSL https://antigravity.google/cli/install.sh -o "${TMP_DIR}/install-agy.sh"
    bash "${TMP_DIR}/install-agy.sh" --dir "${HOME}/.local/bin"
fi

case "$(uname -m)" in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

if GH_URL=$(curl -fsSL -o /dev/null -w "%{url_effective}" https://github.com/cli/cli/releases/latest) &&
    GH_TAG=$(basename "${GH_URL}") &&
    GH_VER="${GH_TAG#v}" &&
    curl -fsSL "https://github.com/cli/cli/releases/download/${GH_TAG}/gh_${GH_VER}_linux_${ARCH}.tar.gz" | \
        tar --strip-components=2 -C "${TMP_DIR}" -xzf - --wildcards "*/bin/gh" &&
    chmod +x "${TMP_DIR}/gh" &&
    mv -f "${TMP_DIR}/gh" "${HOME}/.local/bin/gh"; then
    :
else
    gh --version
    echo "GitHub CLI upgrade failed; using the installed version." >&2
fi

codex --version
claude --version
agy --version
gh --version
