#!/usr/bin/env bash
# Verify installs and cached-version fallback without network access or credentials.
set -Eeuo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
INSTALLER="${ROOT_DIR}/kubernetes/workloads/apps/agent-tools/install-agents.sh"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "${TEST_DIR}"' EXIT
export MOCK_BIN="${TEST_DIR}/bin" MOCK_LOG="${TEST_DIR}/commands.log"
mkdir -p "${MOCK_BIN}"

cat > "${MOCK_BIN}/mock" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

write_tool() {
    cat > "$1" <<'TOOL'
#!/usr/bin/env bash
set -euo pipefail
echo "${0##*/} $*" >> "${MOCK_LOG}"
if [[ ("${1:-}" == update || ("${1:-}" == self && "${2:-}" == update)) && "${FAIL_UPGRADES:-0}" == 1 ]]; then
    exit 1
fi
if [[ "${1:-}" == tool && "${2:-}" == install ]]; then
    if [[ "${FAIL_UPGRADES:-0}" == 1 ]]; then
        exit 1
    fi
    tool_bin_dir="${UV_TOOL_BIN_DIR:-${HOME}/.local/bin}"
    mkdir -p "${tool_bin_dir}"
    cat > "${tool_bin_dir}/specify" <<'SPECIFY'
#!/usr/bin/env bash
set -euo pipefail
echo "${0##*/} $*" >> "${MOCK_LOG}"
echo "${0##*/} fixture-version"
SPECIFY
    chmod +x "${tool_bin_dir}/specify"
    exit 0
fi
echo "${0##*/} fixture-version"
TOOL
    chmod +x "$1"
}

command_name="${0##*/}"
echo "${command_name} $*" >> "${MOCK_LOG}"
case "${command_name}" in
    npm)
        [[ "${FAIL_UPGRADES:-0}" != 1 ]] || exit 1
        case "$5" in
            @openai/codex@latest) write_tool "$4/bin/codex" ;;
            @anthropic-ai/claude-code@latest) write_tool "$4/bin/claude" ;;
            *) exit 1 ;;
        esac
        ;;
    curl)
        [[ "${FAIL_UPGRADES:-0}" != 1 ]] || exit 1
        case "$*" in
            *antigravity.google/cli/install.sh*)
                printf '#!/usr/bin/env bash\necho "agy-installer $*" >> "${MOCK_LOG}"\n"${MOCK_BIN}/mock" install-agy "$2"\n' > "${!#}"
                ;;
            *astral.sh/uv/install.sh*)
                printf '#!/usr/bin/env bash\necho "uv-installer $*" >> "${MOCK_LOG}"\n"${MOCK_BIN}/mock" install-uv "${UV_INSTALL_DIR}"\n' > "${!#}"
                ;;
            *releases/latest*) echo 'https://github.com/cli/cli/releases/tag/v1.2.3' ;;
            *)
                [[ "${FAIL_GH_DOWNLOAD:-0}" != 1 ]] || exit 1
                echo 'fixture archive'
                ;;
        esac
        ;;
    tar)
        cat >/dev/null
        write_tool "$3/gh"
        ;;
    uname) echo "${MOCK_ARCH}" ;;
    mock)
        case "$1" in
            install-agy) write_tool "$2/agy" ;;
            install-uv) write_tool "$2/uv" ;;
            *) exit 1 ;;
        esac
        ;;
    git)
        echo "git $*" >> "${MOCK_LOG}"
        [[ "${FAIL_UPGRADES:-0}" != 1 ]] || exit 1
        case "$1" in
            clone)
                target="${!#}"
                mkdir -p "${target}/bootstrap"
                cat > "${target}/bootstrap/bootstrap.sh" <<'BOOTSTRAP'
#!/usr/bin/env bash
set -euo pipefail
echo "bootstrap $*" >> "${MOCK_LOG}"
BOOTSTRAP
                chmod +x "${target}/bootstrap/bootstrap.sh"
                ;;
            -C)
                ;;
            *) exit 1 ;;
        esac
        ;;
    *) exit 1 ;;
esac
EOF
chmod +x "${MOCK_BIN}/mock"
# Shadow host CLIs used by the missing-tool checks.
for command_name in npm curl tar uname codex claude gh git; do
    ln -s mock "${MOCK_BIN}/${command_name}"
done
export PATH="${MOCK_BIN}:/usr/bin:/bin"

for app_home in paseo node; do
    export HOME="${TEST_DIR}/${app_home}"
    export MOCK_ARCH=arm64
    if [[ "${app_home}" == paseo ]]; then
        export MOCK_ARCH=x86_64
    fi
    bash "${INSTALLER}" > "${TEST_DIR}/install.log" 2>&1
    for tool in codex claude agy gh uv specify; do
        test -x "${HOME}/.local/bin/${tool}"
    done
    grep -q -- "--prefix ${HOME}/.local @openai/codex@latest" "${MOCK_LOG}"
    grep -q -- '--allow-scripts=@anthropic-ai/claude-code' "${MOCK_LOG}"
    grep -q -- "--dir ${HOME}/.local/bin" "${MOCK_LOG}"
    grep -q 'uv-installer' "${MOCK_LOG}"
    grep -q 'uv tool install --upgrade git+https://github.com/juftin/spec-kit.git' "${MOCK_LOG}"
    grep -q 'bootstrap --agents' "${MOCK_LOG}"

    # A normal second start upgrades the already-installed Antigravity CLI.
    bash "${INSTALLER}" > "${TEST_DIR}/upgrade.log" 2>&1
    grep -q 'agy update' "${MOCK_LOG}"
    grep -q 'uv self update' "${MOCK_LOG}"

    FAIL_GH_DOWNLOAD=1 bash "${INSTALLER}" > "${TEST_DIR}/download-failure.log" 2>&1
    grep -q 'GitHub CLI upgrade failed' "${TEST_DIR}/download-failure.log"

    # Failed downloads must preserve all working executables, including gh.
    FAIL_UPGRADES=1 bash "${INSTALLER}" > "${TEST_DIR}/fallback.log" 2>&1
    grep -q 'Codex upgrade failed' "${TEST_DIR}/fallback.log"
    grep -q 'Claude Code upgrade failed' "${TEST_DIR}/fallback.log"
    grep -q 'Antigravity upgrade failed' "${TEST_DIR}/fallback.log"
    grep -q 'GitHub CLI upgrade failed' "${TEST_DIR}/fallback.log"
    grep -q 'uv upgrade failed' "${TEST_DIR}/fallback.log"
    grep -q 'specify upgrade failed' "${TEST_DIR}/fallback.log"
done
grep -q 'gh_1.2.3_linux_amd64.tar.gz' "${MOCK_LOG}"
grep -q 'gh_1.2.3_linux_arm64.tar.gz' "${MOCK_LOG}"

export HOME="${TEST_DIR}/fresh-failure"
if FAIL_UPGRADES=1 bash "${INSTALLER}" > "${TEST_DIR}/failure.log" 2>&1; then
    echo 'Installer accepted a failed first installation' >&2
    exit 1
fi

export HOME="${TEST_DIR}/node"
rm "${HOME}/.local/bin/gh"
if FAIL_UPGRADES=1 bash "${INSTALLER}" > "${TEST_DIR}/missing-gh.log" 2>&1; then
    echo 'Installer accepted a missing GitHub CLI after a failed download' >&2
    exit 1
fi

rm "${HOME}/.local/bin/uv"
if FAIL_UPGRADES=1 bash "${INSTALLER}" > "${TEST_DIR}/missing-uv.log" 2>&1; then
    echo 'Installer accepted a missing uv after a failed download' >&2
    exit 1
fi

rm "${HOME}/.local/bin/specify"
if FAIL_UPGRADES=1 bash "${INSTALLER}" > "${TEST_DIR}/missing-specify.log" 2>&1; then
    echo 'Installer accepted a missing specify after a failed download' >&2
    exit 1
fi

echo 'Shared agent installer regression checks passed'
