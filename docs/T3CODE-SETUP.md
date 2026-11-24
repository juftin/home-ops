# T3 Code Setup

[T3 Code](https://github.com/pingdotgg/t3code) runs its headless server and bundled web UI in
Kubernetes at `https://t3code.${SECRET_DOMAIN}`. Admin Google SSO protects the public hostname,
and T3 Code requires device pairing for browser and client sessions. Agents run inside this pod
and work on repositories in `/workspace`.

For native desktop, iOS, and Android apps (or direct browser access without Google OAuth
redirects), use the private Tailscale endpoint at `https://t3code.<tailnet-DNS-suffix>`. It
requires Tailscale access and a T3 Code pairing link; see [Tailscale setup](TAILSCALE-SETUP.md).

## Access and Pairing

T3 Code uses one-time pairing links rather than a static password Secret, so no new 1Password item
is required for T3 Code itself. The `t3code` namespace reuses the existing `agentsview` item (for
the AgentsView collector sidecar) and the Tailscale `ClusterExternalSecret` (`tailscale-config`).

To sign in from a browser via Pomerium (`https://t3code.${SECRET_DOMAIN}`), first open
`https://t3code.${SECRET_DOMAIN}` and complete Google SSO so a Pomerium session cookie exists
(an OAuth redirect drops `#token=...` URL fragments). Then generate a one-time pairing link
(valid for 5 minutes), replacing `<domain>` with your `SECRET_DOMAIN`:

```bash
kubectl exec -n t3code deployment/t3code -c app -- \
  t3 auth pairing create --label browser --base-url "https://t3code.<domain>"
```

Open the printed URL in the signed-in browser so T3 Code exchanges the pairing token for a
persistent session, or paste the raw token directly on the `/pair` page after Google SSO completes.

To pair a native desktop, iOS, or Android client over Tailscale (bypassing Pomerium OAuth
redirects), pass the Tailscale base URL:

```bash
kubectl exec -n t3code deployment/t3code -c app -- sh -c \
  't3 auth pairing create --label mobile --base-url "https://t3code.${TAILSCALE_DNS_SUFFIX}"'
```

You can also open `https://t3code.${SECRET_DOMAIN}` or `https://t3code.<tailnet-DNS-suffix>` and
paste the raw token directly on the T3 Code sign-in page. Treat pairing URLs and tokens like
passwords.

## Runtime and Storage

- T3 Code is pinned to official release **v0.1.11** from
  [pingdotgg/t3code](https://github.com/pingdotgg/t3code/releases).
- `docker.io/library/node:24.22.1-bookworm` provides Node, npm, Git, Bash, and curl/tar tools.
- The `install-runtime` init container downloads the official `t3-0.1.11-linux-<arch>.tar.gz`
  archive (supporting both x86-64 and ARM64), verifies its pinned SHA-256 checksum, and unpacks
  the self-contained binary and web UI assets onto a pod-local `emptyDir` at `/opt/t3code`. Every
  new pod needs Internet access to install the runtime. Upgrade through Git by updating
  `T3CODE_VERSION` and the matching SHA-256 checksums in `install-runtime.sh`.
- The app container runs `/opt/t3code/t3 serve` via `start.sh` with `workingDir: /workspace`,
  listening on `0.0.0.0:3773` with `T3CODE_HOME=/home/node/.t3` and
  `T3CODE_TELEMETRY_ENABLED=false`. `start.sh` redacts the startup administrative pairing
  token/URL/QR block from stdout so Alloy/Loki never retain live pairing credentials (generate
  one-time pairing links on demand with `t3 auth pairing create`).
- A 10 GiB `node-local` home PVC persists `/home/node` (matching UID 1000's `/etc/passwd` home so
  OpenSSH and Git over SSH persist `.ssh` cleanly): T3 Code's SQLite database, pairing state,
  default managed worktrees (`/home/node/.t3/worktrees`), coding tools (`/home/node/.local`),
  provider credentials, and dotfiles.
- A 20 GiB `node-local` workspace PVC persists `/workspace` for Git repositories. To store T3 Code
  managed Git worktrees on this larger volume instead of `/home/node/.t3/worktrees`, set
  **Worktrees directory** to `/workspace/worktrees` in T3 Code Settings.
- A 2 GiB `node-local` PVC persists the AgentsView collector archive. Back up persistent volumes:
  node-local storage is tied to its node and is not replicated.
- A single non-root replica (UID/GID 1000) uses `Recreate` to avoid SQLite and PVC conflicts, with
  no Kubernetes token, host mounts, or elevated privileges.
- `CiliumNetworkPolicy` (`t3code-isolation`) permits ingress only from `pomerium-proxy` and the
  `t3code-tailscale` ingress proxy on TCP 3773. Egress permits `agentsview-db` on TCP 5432, cluster
  DNS, and public HTTP/HTTPS/SSH; other agents, Kubernetes API, nodes, LAN, tailnet, and metadata
  addresses are blocked.

## Sandboxing Notes

Because the pod runs unprivileged without user namespaces:

- **Codex**: Codex's Supervised and Auto sandboxes require unprivileged user namespaces. Use
  **Full access** (T3 Code's default for new threads), relying on the pod and Cilium network policy
  as the isolation boundary.
- **Built-in browser**: T3 Code's optional built-in browser requires Chromium system libraries and
  user namespaces that are intentionally omitted from the `node:24.22.1-bookworm` base image.

## Coding Tools and Provider Setup

The `install-agents` init container runs the shared
[agent-tools installer](../kubernetes/workloads/apps/agent-tools/install-agents.sh), installing or
upgrading Codex, Claude Code, Antigravity (`agy`), GitHub CLI (`gh`), `uv`, and Spec Kit
(`specify`) under `/home/node/.local` and syncing agent configuration from `juftin/dotfiles`.

Check installation logs and versions:

```bash
kubectl logs -n t3code deployment/t3code -c install-runtime
kubectl logs -n t3code deployment/t3code -c install-agents
kubectl exec -n t3code deployment/t3code -c app -- t3 --version
kubectl exec -n t3code deployment/t3code -c app -- codex --version
kubectl exec -n t3code deployment/t3code -c app -- claude --version
kubectl exec -n t3code deployment/t3code -c app -- agy --version
kubectl exec -n t3code deployment/t3code -c app -- gh --version
kubectl exec -n t3code deployment/t3code -c app -- uv --version
kubectl exec -n t3code deployment/t3code -c app -- specify --version
```

Authenticate the providers you use inside the pod (or via **Settings → Providers** in the UI):

```bash
kubectl exec -it -n t3code deployment/t3code -c app -- codex login --device-auth
kubectl exec -it -n t3code deployment/t3code -c app -- claude
kubectl exec -it -n t3code deployment/t3code -c app -- gh auth login
```

T3 Code isolates its Antigravity provider profile under
`/home/node/.t3/userdata/providers/antigravity` and ignores `GEMINI_HOME`, so authenticate
Antigravity in **Settings → Providers** rather than `kubectl exec ... -- agy` (which signs in only
the standalone CLI under `/home/node/.gemini`). The AgentsView collector reads
`/home/node/.claude/projects`, `/home/node/.codex/sessions`, and standalone
`/home/node/.gemini` sessions; T3 Code's isolated Antigravity sessions are outside that path.

Clone repositories into `/workspace` and open them as projects in T3 Code.

## Validation and Branch Testing

```bash
task lint
task dev:validate
task dev:start
kubectl get externalsecret -n t3code agentsview tailscale-config
kubectl get pvc -n t3code
kubectl rollout status -n t3code deployment/t3code --timeout=10m
kubectl get ingress -n t3code t3code t3code-tailscale
kubectl logs -n t3code deployment/t3code -c agentsview
# Generate a pairing link, verify Pomerium Google SSO + WebSocket streaming,
# test native/Tailscale pairing, and verify persistence across a pod restart.
task dev:stop
```

Always run `task dev:stop` after branch testing, including when a check fails. On a brand-new
install, `t3code` may briefly wait in `CreateContainerConfigError` until `t3code` creates its
namespace, `agent-tools` syncs `ConfigMap/agent-tools`, and `ClusterExternalSecret/tailscale-config`
refreshes (up to 1 minute).

Confirm an unauthenticated request to `https://t3code.${SECRET_DOMAIN}` redirects to Google. To
verify T3 Code's own endpoints directly (bypassing Pomerium's SSO redirect), hit the Tailscale URL
(`https://t3code.<tailnet-DNS-suffix>`) or run inside the pod against `http://127.0.0.1:3773`:
unauthenticated requests to `/api/auth/session` must report `"authenticated":false`, and
`/.well-known/t3/environment` must respond with HTTP 200. Verify DNS and public HTTPS succeed from
the pod while connections to `kubernetes.default.svc:443`, other agents, node/LAN IPs, and
`169.254.169.254` fail, as described in [agent isolation](ARCHITECTURE.md#agent-isolation).
