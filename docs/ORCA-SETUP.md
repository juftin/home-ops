# Orca Setup

[Orca](https://github.com/stablyai/orca) runs an always-on coding-agent workspace at
`https://orca.${SECRET_DOMAIN}` behind admin Google SSO. A private Tailscale Ingress exposes
`https://orca.<tailnet-DNS-suffix>` for native clients. Both require Orca's encrypted device
pairing in addition to network access. Repositories and agents run inside the pod.

## Image and first deployment

The repository builds `ghcr.io/juftin/home-ops-orca:1.4.229` from the official **v1.4.229**
Debian package, checking its release SHA-256 before extraction. The image includes Node/npm,
Git, the Electron runtime libraries, Xvfb, and Tini. Electron headless mode is selected because
the stable Node-only runtime does not serve the browser bundle. No desktop is exposed.

The **Orca Image** workflow builds and smoke-tests changes on pull requests, then publishes
the amd64 image on pushes to `main`. It can also be dispatched on `main`. Before ArgoCD can
pull the image, let the first build finish and set the GHCR package's visibility to **Public**.
The pod may report `ImagePullBackOff` until the image exists and is publicly readable.
The deployment selects amd64 nodes, matching the current homelab. The Dockerfile also supports
local ARM64 builds for development.

```bash
task dev:orca:build
task dev:orca:test
```

Upgrade through Git: change `ORCA_VERSION` and the matching amd64/arm64 release checksums in
`containers/orca/Dockerfile`, and the image tag in Orca's `values.yaml`. The workflow derives
its published tag from `ORCA_VERSION`. Runtime updates remain owned by the image and GitOps.

## First browser connection

No new 1Password item or Google OAuth callback is needed. Orca creates its server identity and
pairing registry in its own persistent home. The startup wrapper writes its access links to
`/home/orca/.config/Orca/serve-ready.jsonl` with owner-only permissions instead of pod logs.
First visit `https://orca.${SECRET_DOMAIN}` and complete Google SSO. Retrieve the browser link
locally after rollout:

```bash
kubectl rollout status -n default deployment/orca --timeout=10m
kubectl exec -n default deployment/orca -c app -- \
  cat /home/orca/.config/Orca/serve-ready.jsonl
```

Open the readiness message's `pairing.webClientUrl` to pair the signed-in browser. Access
links grant control of the workspace; keep them private. A new startup creates a new unused
offer; already-paired clients retain their grants.

## Native desktop and mobile clients

Connect clients to the tailnet first. To create a native-client offer from the headless server,
change the `--pairing-address` argument in `values.yaml` to
`wss://orca.<tailnet-DNS-suffix>:443`, substituting your actual suffix. Roll out through the
branch testing workflow, then retrieve `serve-ready.jsonl` again. Paste `pairing.url` into the
desktop client's **Settings → Remote Orca Servers → Add Server**.

For a phone, also add `--mobile-pairing` to the deployment arguments before rollout and use
that startup's mobile link. Complete pairing before restoring the public pairing address and
removing `--mobile-pairing` through GitOps; existing client grants survive this change. This
avoids relying on desktop-only sharing controls on the headless host. Native clients use the
Tailscale endpoint because the public hostname's OAuth redirects require a browser session.

Keep the server and clients on compatible Orca versions. Tailscale prerequisites are covered
in [Tailscale setup](TAILSCALE-SETUP.md). Upstream describes the server and pairing workflow in
[Remote Orca Servers](https://www.onorca.dev/docs/remote-servers).

## Storage and coding tools

- A 5 GiB `node-local` PVC persists `/home/orca`: Orca configuration, device grants, transcripts,
  provider credentials, and tools. A separate 20 GiB PVC persists `/workspace`. Back up both;
  the storage is tied to its node.
- The shared `agent-tools` init container installs or upgrades Codex, Claude Code, Antigravity,
  and `gh` under `/home/orca/.local`. Authenticate the providers you use, then clone repositories
  into `/workspace` and add them in Orca.
- One replica uses `Recreate`. Running agent processes end when the pod is replaced; saved
  state and repositories remain. Tini forwards shutdown signals and reaps subprocesses.
- Containers run as UID/GID 1000 with capabilities dropped, privilege escalation disabled,
  RuntimeDefault seccomp, and no service account token, host mounts, or container socket.
  Chromium uses `--no-sandbox` to run under those restrictions; pod isolation is the boundary.
  There is no OS keyring in this container, so Orca reports that saved integration credentials
  are unencrypted on the home PVC. Treat the volume and backups as credential storage.
- Cilium permits ingress from the admin Envoy Gateway and this app's Tailscale proxy on TCP
  6768\. Egress permits cluster DNS and public HTTP/HTTPS/SSH. Other agents, cluster APIs, node,
  LAN, tailnet, and metadata addresses are blocked. Outbound SSH cannot reach private hosts.

```bash
kubectl exec -it -n default deployment/orca -c app -- codex login --device-auth
kubectl exec -it -n default deployment/orca -c app -- claude
kubectl exec -it -n default deployment/orca -c app -- agy
kubectl exec -it -n default deployment/orca -c app -- gh auth login
kubectl exec -n default deployment/orca -c app -- orca status --json
```

## Validation

Run `task lint` then `task dev:validate`. `task dev:orca:test` checks the actual image with all
capabilities dropped: the runtime reaches ready, the browser bundle responds, pairing output
is owner-only, and a client connects using E2EE pairing.

After the image is published, use `task dev:start` / `task dev:sync` for cluster testing and
always finish with `task dev:stop`. Check admin SSO, browser pairing, a native Tailscale client,
provider login, a live agent terminal, and persistence after pod recreation. Verify blocked
destinations as described in [agent isolation](ARCHITECTURE.md#agent-isolation). Offline
rendering and Docker smoke tests cannot verify Cilium enforcement, OAuth, or Tailscale routing.
