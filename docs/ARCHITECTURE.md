# Architecture

`home-ops` is an ArgoCD-first GitOps homelab running on Talos Linux.

______________________________________________________________________

## Control Plane

- **ArgoCD** is the only GitOps reconciler.
- `home-ops-root` (bootstrapped by Helmfile) points to `kubernetes/argocd`.
- `kubernetes/argocd/applicationset.yaml` generates one ArgoCD `Application` per app directory under `kubernetes/apps/<namespace>/<app>/app`.
- Generated apps use server-side apply so Kubernetes-assigned PVC bindings are preserved during sync.
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
- PR gate: GitHub Actions **ArgoCD Render Validation** workflow (`.github/workflows/argocd-validate.yaml`)
- Template/e2e checks also run `task dev:validate`

______________________________________________________________________

## Security

- Secrets in Git are SOPS-encrypted with age.
- ArgoCD repo-server mounts `sops-age` and decrypts during render.
- New app secrets should prefer External Secrets Operator + 1Password over new committed SOPS files.

## Coding Agents

| Namespace | App     | Role                                   |
| --------- | ------- | -------------------------------------- |
| `default` | `paseo` | Coding-agent daemon and bundled web UI |

Paseo is served at `paseo.${SECRET_DOMAIN}` through Cloudflare Tunnel and the admin OAuth Gateway.
The daemon additionally requires a password from the `paseo` 1Password item. It trusts forwarded
headers from the cluster pod network (`10.42.0.0/16`) so HTTPS connections use secure WebSockets.
Relay access is disabled. Node-local PVCs persist `/home/paseo` (state, provider tools, and
credentials) and `/workspace` (repositories and worktrees); a single replica uses `Recreate`
to avoid overlapping agents and volume attachment conflicts. An init container installs or upgrades
Codex and Antigravity in the persistent home before the daemon starts, reusing working installed
versions if upgrades fail. Authenticate each provider before running tasks; see
[Paseo setup](PASEO-SETUP.md).

## Private Network Access

| Namespace   | App         | Role                                             |
| ----------- | ----------- | ------------------------------------------------ |
| `tailscale` | `tailscale` | Kubernetes operator and private HTTPS proxy pods |

The Tailscale operator exposes Paseo through a private `Ingress` at
`https://paseo.<tailnet-DNS-suffix>`, forwarding directly to the existing `paseo:6767` service.
Tailnet policy grants access to `tag:paseo` on TCP 443, and the daemon still requires its password.
This route avoids browser OAuth redirects for native clients; the public hostname retains admin
Google SSO. The Ingress uses a userspace proxy without additional pod privileges. Operator OAuth
credentials and the DNS suffix come from the `tailscale` 1Password item through External Secrets.
A Tailscale-owned `ClusterExternalSecret` distributes the DNS suffix as `tailscale-config` to
consumer namespaces; OAuth credentials stay in `tailscale`. Paseo owns only its Ingress and
the environment reference to the shared configuration.
No Funnel or Kubernetes API proxy is enabled. See [Tailscale setup](TAILSCALE-SETUP.md).
