# Architecture

`home-ops` is an ArgoCD-first GitOps homelab running on Talos Linux.

______________________________________________________________________

## Control Plane

- **ArgoCD** is the only GitOps reconciler.
- `home-ops-root` (bootstrapped by Helmfile) points to `kubernetes/argocd`.
- `kubernetes/argocd/applicationset.yaml` generates one ArgoCD `Application` per app directory under `kubernetes/apps/<namespace>/<app>/app`.
- Generated apps use server-side apply so Kubernetes-assigned PVC bindings are preserved during sync.
- GitHub push webhooks reach `webhooks.${SECRET_DOMAIN}/argocd/api/webhook` through the public
  `envoy-external` Gateway and refresh existing Applications. Only exact-path POST requests are
  routed to `argocd-server`, with the path rewritten to `/api/webhook`; the UI remains on the
  admin OAuth Gateway. The bootstrap Helm release
  owns this route and an ExternalSecret sourcing `GITHUB_WEBHOOK_SECRET` from the `argocd`
  1Password item. See [webhook setup](ARGOCD-WEBHOOK-SETUP.md). ApplicationSet directory discovery
  continues to poll Git.
- Argo apps are scoped by two AppProjects:
  - `home-ops` for general namespaces with orphan monitoring enabled and targeted ignore rules.
  - `kube-system` for `kube-system` (plus `cilium-secrets`) with orphan warnings disabled to avoid control-plane noise.

______________________________________________________________________

## App Layout

```text
kubernetes/apps/<namespace>/<app>/app/
├── kustomization.yaml   # static resources + helmCharts entries
├── values.yaml          # chart values
└── *.sops.yaml          # encrypted manifests/secrets (optional)
```

`kustomization.yaml` uses `helmCharts`; ArgoCD’s CMP plugin decrypts SOPS files and substitutes
`${SECRET_DOMAIN}` placeholders before apply.

______________________________________________________________________

## Bootstrap

`bootstrap/helmfile.d/01-apps.yaml` installs foundational components in order:

1. `cilium`
2. `coredns`
3. `cert-manager`
4. `argocd`

ArgoCD then continuously reconciles all apps from Git.

______________________________________________________________________

## Validation and CI

- Local gate: `task lint` then `task dev:validate`
- Every PR runs **Repository Quality** (`.github/workflows/quality.yaml`): pre-commit formatting
  and syntax checks, Actionlint for workflows, and ShellCheck warnings/errors for shell scripts.
- PR gate: GitHub Actions **ArgoCD Render Validation** workflow (`.github/workflows/argocd-validate.yaml`)
  runs `task dev:validate:ci` with placeholder secrets and `example.com`, including for fork PRs.
  No cluster credentials or age key are supplied to GitHub Actions.
  Placeholder rendering cannot verify decryption or the contents of encrypted policies.
  ArgoCD continues to decrypt with the real age key.
- Render validation also runs strict Kubeconform checks on built-in Kubernetes resources against
  `talos/talenv.yaml`'s Kubernetes version. Custom resources and CRD definitions are excluded;
  missing schemas for other built-in resources fail validation.

______________________________________________________________________

## Security

- Secrets in Git are SOPS-encrypted with age.
- ArgoCD repo-server mounts `sops-age` and decrypts during render.
- New app secrets should prefer External Secrets Operator + 1Password over new committed SOPS files.

## Coding Agents

| Namespace | App            | Role                                                       |
| --------- | -------------- | ---------------------------------------------------------- |
| `default` | `paseo`        | Coding-agent daemon and bundled web UI                     |
| `default` | `openclaw`     | Personal AI assistant gateway and Control UI               |
| `default` | `hermes-agent` | Self-improving AI agent with Gateway API and Web Dashboard |
| `default` | `herdr`        | Persistent agent terminals and browser/phone web UI        |
| `default` | `agent-tools`  | Shared installer ConfigMap for Paseo, OpenClaw, and Herdr  |

The `agent-tools` app owns one ConfigMap generated from `install-agents.sh`. Paseo, OpenClaw, and Herdr mount
it read-only in their `install-agents` init containers. The script installs or upgrades Codex,
Claude Code, Antigravity, and the GitHub CLI under each app's persistent `$HOME/.local` and reuses
working installed versions if upgrades fail. All three app containers include `$HOME/.local/bin` in
`PATH`. Reloader restarts consumers when the shared ConfigMap changes; the tools and credentials
remain isolated on each app's own PVC.

Paseo is served at `paseo.${SECRET_DOMAIN}` through Cloudflare Tunnel and the admin OAuth Gateway.
The daemon additionally requires a password from the `paseo` 1Password item. It trusts forwarded
headers from the cluster pod network (`10.42.0.0/16`) so HTTPS connections use secure WebSockets.
Relay access is disabled. Node-local PVCs persist `/home/paseo` (state, provider tools, and
credentials) and `/workspace` (repositories and worktrees); a single replica uses `Recreate`
to avoid overlapping agents and volume attachment conflicts. An init container installs or upgrades
Codex, Claude Code, Antigravity, and the GitHub CLI in the persistent home before the daemon starts,
reusing working installed versions if upgrades fail. Authenticate each provider before running tasks; see
[Paseo setup](PASEO-SETUP.md).

Hermes Agent is served at `hermes.${SECRET_DOMAIN}` through Cloudflare Tunnel and the admin OAuth
Gateway (`envoy-oauth-admin`). The deployment exposes the Web Dashboard (port 9119) and
OpenAI-compatible Gateway API (port 8642). A node-local PVC persists `/opt/data` (configuration,
sessions, skills, and memory). A single replica uses `Recreate` to prevent volume attachment
conflicts. See [Hermes setup](HERMES-SETUP.md).

OpenClaw is served at `openclaw.${SECRET_DOMAIN}` through Cloudflare Tunnel and the admin OAuth
Gateway. Its HTTP and WebSocket gateway share port 18789; OpenClaw token authentication and
browser device pairing remain enabled behind SSO. A node-local PVC persists `/home/node`,
including configuration, provider credentials, sessions, and workspaces. One non-root replica
uses `Recreate`. A first-run init container seeds the gateway configuration without overwriting
subsequent onboarding changes. The shared agent installer makes coding CLIs and `gh` available
before the gateway starts. See [OpenClaw setup](OPENCLAW-SETUP.md).

Herdr is served at `herdr.${SECRET_DOMAIN}` through Cloudflare Tunnel and the admin OAuth
Gateway. One container supervises the headless Herdr server and herdr web ui on port 7317,
connected over a Unix socket. Pinned Node and Bun images supply the runtimes; an init container
verifies and installs pinned Herdr and web UI downloads, installs locked UI dependencies, and
builds the frontend on a pod-local volume. Another init container installs the shared coding
tools. Node-local PVCs persist `/home/herdr` (layout, transcripts, tools, credentials, and web UI
device/push state) and `/workspace` (repositories and worktrees). A single non-root replica uses
`Recreate`; either process exiting restarts the pair. The UI additionally requires a token from
the `herdr` 1Password item. Its HTTP health probe checks the Herdr socket as well as the web
server. See [Herdr setup](HERDR-SETUP.md).

### Agent isolation

Each agent has its own pod and PVCs. All app and init containers run as non-root, drop all Linux
capabilities, disable privilege escalation, and use RuntimeDefault seccomp. Container filesystems
remain writable wherever the app user has permission, so agents can install tools and run builds.
Install tools under the persistent home/data volumes (or Paseo workspace) to retain them across
pod recreation; changes in the container image filesystem are ephemeral. System package installation
with root privileges is unavailable; bake system dependencies into an image when needed.
No Kubernetes token,
host directories, container-runtime sockets, or host namespaces are exposed.

App-local CiliumNetworkPolicies default-deny ingress and egress. Ingress permits only the admin
Envoy gateway on each app's service ports; Paseo also permits its specific Tailscale ingress proxy.
Egress permits CoreDNS on TCP/UDP 53 and public HTTP/HTTPS/SSH on TCP 80/443/22. Other cluster
services (including the other agents), Kubernetes API, nodes, LAN, tailnet, and metadata addresses
are blocked, with explicit exceptions for DNS and OpenClaw accessing only the Lunch Money
application on TCP 8000 (`http://lunchmoney-app.default.svc.cluster.local:8000`). Its PostgreSQL,
Valkey, and scheduler pods remain inaccessible to OpenClaw. Paseo, Hermes, and Herdr have no Lunch Money
exception. Existing stateful connections can
receive replies; the ingress exception does not authorize agent-initiated connections to proxies.
See [Cilium policy semantics](https://docs.cilium.io/en/stable/security/policy/layer3/).

These are shared-kernel containers, not a guarantee against kernel exploits. Stronger isolation
requires a separately provisioned sandbox runtime or dedicated VMs/nodes. Public Internet access
still allows external services and publicly exposed homelab URLs, subject to their authentication.
Do not place cluster credentials in agent workspaces; mounted app/provider credentials remain
accessible to that app's tools. Node-local PVCs are mounted by Kubernetes, without exposing their
host parent directories to the containers.

After branch deployment, verify every app starts, provider requests work, OAuth access works, and
Paseo's Tailscale connection works. From each app container, verify DNS and public HTTPS succeed;
connections to `kubernetes.default.svc:443`, another agent's service, a node IP, a LAN IP, and
`169.254.169.254:80` must fail. Test both service and direct pod addresses. Inspect pod security
contexts and Cilium policy verdicts; rendering alone cannot prove runtime enforcement. Always
finish branch testing with `task dev:stop`.

## Private Network Access

| Namespace   | App          | Role                                                                      |
| ----------- | ------------ | ------------------------------------------------------------------------- |
| `tailscale` | `tailscale`  | Kubernetes operator and private HTTPS proxy pods                          |
| `default`   | `lunchmoney` | Lunch Money MCP server, dashboard, PostgreSQL, Valkey, and sync scheduler |

The Tailscale operator exposes Paseo through a private `Ingress` at
`https://paseo.<tailnet-DNS-suffix>`, forwarding directly to the existing `paseo:6767` service.
It also exposes Lunch Money through a private `Ingress` at `https://lunchmoney.<tailnet-DNS-suffix>`,
forwarding to the `lunchmoney:8000` service. Internally on the LAN, Lunch Money is served at
`lunchmoney.${SECRET_DOMAIN}` via the `envoy-internal` Gateway.
Proxies use the shared `tag:k8s`; the documented tailnet policy allows all ports and protocols
between tailnet devices, and the daemon still requires its password.
This route avoids browser OAuth redirects for native clients; the public hostname retains admin
Google SSO. The Ingress uses a userspace proxy without additional pod privileges. Operator OAuth
credentials and the DNS suffix come from the `tailscale` 1Password item through External Secrets.
A Tailscale-owned `ClusterExternalSecret` distributes the DNS suffix as `tailscale-config` to
consumer namespaces; OAuth credentials stay in `tailscale`. Paseo owns only its Ingress and
the environment reference to the shared configuration.
No Funnel or Kubernetes API proxy is enabled. See [Tailscale setup](TAILSCALE-SETUP.md).

## App Access

App-template workloads configure HTTPRoutes and Tailscale Ingresses in their own
`values.yaml`, using the chart's built-in resources. Grafana uses the bundled
Grafana chart's `grafana.route.main` settings, and ArgoCD uses `server.httproute`
in its Helmfile bootstrap values. Public apps use
`envoy-external`; OAuth apps choose the admin or users Gateway and have an explicit
Cloudflare Tunnel rule. Shared OAuth utility pages cover app hosts through a
wildcard while public-policy exceptions stay scoped to denied/logout sections.
See [App access](APP-ACCESS.md).
