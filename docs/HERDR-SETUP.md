# Herdr Setup

[Herdr](https://github.com/herdrdev/herdr) runs its headless server alongside
[herdr web ui](https://github.com/devswha/herdr-web-ui) at `https://herdr.${SECRET_DOMAIN}`.
Admin Google SSO protects the hostname; the web UI also requires its own token. Agents run
inside this pod, with repositories in `/workspace`. Existing laptop and Paseo sessions remain
separate.

## Token

Before syncing, create a **Login** item named `herdr` in the 1Password **homelab** vault.
Set its website to the Herdr hostname and generate a strong password with at least 32 random
bytes. External Secrets copies the item's `password` field into `herdr-secret` as
`HERDR_WEB_TOKEN`. The app cannot start until that Secret exists, and its startup script rejects
an empty token. Reloader restarts the pod when the Secret changes.

Open the hostname, complete Google SSO, and enter the token from 1Password when the UI asks.
Device pairing remains available. Do not enable `HERDR_WEB_TAILSCALE_SERVE_ONLY`: this
deployment uses a public HTTPS proxy and does not run `tailscale serve`.
Envoy forwards the original host, HTTPS scheme, and WebSocket upgrades to port 7317.
No new Google OAuth callback registration is required.

## Runtime and Storage

- Herdr is pinned to **v0.9.5**; herdr web ui is pinned to **v0.4.11**.
- `node:24.22.0-bookworm` provides Node, npm, Git, Bash, and download/build tools.
  `oven/bun:1.4.2-debian` supplies Bun through a copy-only init container.
- The runtime installer downloads Herdr and the web UI release archive, verifies their SHA-256
  checksums, runs `bun install --frozen-lockfile`, and builds the frontend. Both x86-64 and ARM64
  Herdr downloads are supported. Runtime files and the frontend live on a pod-local `emptyDir`,
  so every new pod needs Internet access to install them. Init logs show installation failures.
- Kubernetes supervises the foreground Herdr server and web UI together. If either exits,
  the container restarts. Shutdown signals both processes and allows up to 60 seconds for saving
  state and releasing terminals. Herdr can restore saved layouts and resume supported agents;
  running processes do not survive pod replacement.
- A 5 GiB `node-local` home PVC persists `/home/herdr`: Herdr configuration, session state,
  coding tools, provider credentials, transcripts, and web UI device/push state.
  A separate 20 GiB PVC persists `/workspace`. Back up both: storage is tied to its node.
- The app runs as UID/GID 1000 with no Kubernetes token, host mounts, or elevated privileges.
  Cilium permits ingress only from the admin Envoy Gateway on TCP 7317. Egress permits cluster
  DNS and public HTTP/HTTPS/SSH; other agents, cluster APIs, LAN, tailnet, and metadata addresses
  are blocked. Remote-PC access over SSH is limited to public addresses by this policy.
- The web UI runs directly through `server/index.ts`, with automatic updates and anonymous
  telemetry disabled. Upgrade through Git: update versions and matching checksums in
  `install-runtime.sh`, or image tags in `values.yaml`, then validate and branch-test.
  The app's source updater cannot update this release archive installation.

## Coding Tools and Provider Setup

The `install-agents` init container runs the shared `agent-tools` installer, installing or
upgrading Codex, Claude Code, Antigravity, and `gh` under `/home/herdr/.local`. Each pod start
attempts upgrades; failed upgrades reuse working installed versions, while failed first
installs prevent startup. Herdr has its own credentials, separate from the other apps.

```bash
kubectl logs -n default deployment/herdr -c install-runtime
kubectl logs -n default deployment/herdr -c install-agents
kubectl exec -n default deployment/herdr -c app -- herdr --version
kubectl exec -n default deployment/herdr -c app -- codex --version
kubectl exec -it -n default deployment/herdr -c app -- codex login --device-auth
kubectl exec -it -n default deployment/herdr -c app -- claude
kubectl exec -it -n default deployment/herdr -c app -- agy
kubectl exec -it -n default deployment/herdr -c app -- gh auth login
```

Authenticate the providers you use, clone repositories into `/workspace`, and create a workspace
in the browser. The same terminal can be reached through the TUI:

```bash
kubectl exec -it -n default deployment/herdr -c app -- herdr
```

## Validation and Branch Testing

```bash
task lint
task dev:validate
task dev:start
kubectl get externalsecret -n default herdr
kubectl rollout status -n default deployment/herdr --timeout=10m
kubectl get httproute -n default herdr
# Check Google SSO, web UI token authentication, and a live agent terminal in the browser.
# Verify /denied and /logged-out, and check that saved workspaces survive a pod restart.
task dev:stop
```

Always run `task dev:stop` after branch testing, including when a check fails. Check that a
signed-out request to the public hostname redirects to Google. A direct unauthenticated request
to `/api/session` must return HTTP 401; `/api/health` is intentionally public and verifies both
the web server and Herdr socket. Confirm DNS/public HTTPS work from the pod and connections to
the Kubernetes API, another agent, node/LAN addresses, and `169.254.169.254` fail, as described in
[agent isolation](ARCHITECTURE.md#agent-isolation).
