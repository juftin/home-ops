# Architecture

This document describes how the `home-ops` repository is structured and how its components work
together to manage a GitOps-driven Kubernetes homelab.

______________________________________________________________________

## Overview

The cluster is a single-node Kubernetes cluster running on bare metal using
[Talos Linux](https://talos.dev/) as the OS. All cluster state is declared in this Git repository
and continuously reconciled by [Flux](https://fluxcd.io/). Secrets are encrypted at rest using
[SOPS](https://github.com/getsops/sops) with an [age](https://github.com/FiloSottile/age) key.
Dependency updates are automated with [Renovate](https://renovatebot.com/).

```
┌─────────────────────────────────────────────────────────────────┐
│  GitHub Repository (home-ops)                                   │
│                                                                 │
│  ┌──────────┐  ┌─────────────┐  ┌──────────┐  ┌────────────┐  │
│  │  talos/  │  │ kubernetes/ │  │bootstrap/│  │  .github/  │  │
│  │  (OS)    │  │  (GitOps)   │  │ (init)   │  │  (CI/CD)   │  │
│  └──────────┘  └─────────────┘  └──────────┘  └────────────┘  │
└─────────────────────────────────────────────────────────────────┘
         │               │
         ▼               ▼
  ┌─────────────┐  ┌───────────────────────────────┐
  │ Talos Linux │  │  Flux (in-cluster GitOps)     │
  │  bare metal │  │  continuously reconciles       │
  │  node       │  │  kubernetes/ from Git          │
  └─────────────┘  └───────────────────────────────┘
```

______________________________________________________________________

## Repository Layout

```
home-ops/
├── talos/               # Talos OS node configuration
├── kubernetes/          # All Kubernetes manifests (owned by Flux)
│   ├── flux/            # Flux entrypoint Kustomization
│   ├── apps/            # Namespaced application definitions
│   └── components/      # Shared reusable Kustomize components
├── bootstrap/           # One-time cluster bootstrap (Helmfile)
├── docs/                # Project documentation
├── scripts/             # Helper scripts
├── templates/           # makejinja templates for config generation
├── .github/             # GitHub Actions workflows, Renovate config, Copilot instructions
├── .taskfiles/          # Task runner task definitions
├── AGENTS.md            # Agent instructions (Copilot, Codex, Cursor, etc.)
├── CLAUDE.md            # Claude Code entry point (references AGENTS.md)
├── cluster.yaml         # Cluster-level configuration values
├── nodes.yaml           # Node-level configuration values
├── Taskfile.yaml        # Task runner entrypoint
└── .mise.toml           # Tool version pinning (mise)
```

______________________________________________________________________

## Layers

### 1. OS Layer – Talos

[Talos Linux](https://talos.dev/) is the immutable, API-driven OS running on the bare-metal
node. Configuration is managed by [talhelper](https://github.com/budimanjojo/talhelper) using
`talos/talconfig.yaml` which is rendered into per-node machine configs.

Key files:

| File                        | Purpose                                                 |
| --------------------------- | ------------------------------------------------------- |
| `talos/talconfig.yaml`      | Node definitions, IP config, Talos/Kubernetes versions  |
| `talos/talenv.yaml`         | Version variables (`talosVersion`, `kubernetesVersion`) |
| `talos/talsecret.sops.yaml` | Encrypted cluster PKI / join tokens                     |
| `talos/patches/`            | Global and controller-specific Talos config patches     |
| `talos/clusterconfig/`      | Generated output of `talhelper genconfig`               |

The VIP (`192.168.1.145`) floats across control-plane nodes and is the stable API server address.

Networking: pod CIDR `10.42.0.0/16`, service CIDR `10.43.0.0/16`. The built-in CNI is disabled
in favor of Cilium.

______________________________________________________________________

### 2. Bootstrap Layer – Helmfile

The `bootstrap/helmfile.d/` directory installs the minimum set of components required to get Flux
running inside the cluster. This is a **one-time** operation (run via `task bootstrap:apps`).

Bootstrap install order (each release `needs` the previous):

1. **cilium** – CNI (networking)
2. **coredns** – cluster DNS
3. **cert-manager** – TLS certificate management
4. **flux-operator** – installs the Flux operator
5. **flux-instance** – creates a Flux `FluxInstance` pointing at this repo

`bootstrap/helmfile.d/00-crds.yaml` is a separate helmfile used only to extract CRDs from charts
that need them installed before the main bootstrap run.

After bootstrap, Flux takes over and manages all further state from Git.

______________________________________________________________________

### 3. GitOps Layer – Flux

Once bootstrapped, Flux continuously reconciles `kubernetes/` from the Git repository.

#### Entrypoint

`kubernetes/flux/cluster/ks.yaml` is the root `Kustomization` resource. It points Flux at
`kubernetes/apps/` and applies global patches to every child `Kustomization` and `HelmRelease`
(e.g. SOPS decryption, CRD install/upgrade strategy, rollback behavior).

#### App structure

Each application under `kubernetes/apps/` follows this pattern:

```
kubernetes/apps/<namespace>/
├── kustomization.yaml      # namespace-level Kustomization pointing to child ks.yaml files
├── namespace.yaml          # Namespace manifest
└── <app-name>/
    ├── ks.yaml             # Flux Kustomization for this app
    └── app/
        ├── kustomization.yaml
        ├── helmrelease.yaml     # HelmRelease (Helm chart + values)
        ├── ocirepository.yaml   # OCI source reference
        └── *.sops.yaml          # Encrypted secrets (if any)
```

#### Namespaces

| Namespace          | Contents                                                                       |
| ------------------ | ------------------------------------------------------------------------------ |
| `kube-system`      | cilium, coredns, metrics-server, reloader                                      |
| `cert-manager`     | cert-manager (TLS)                                                             |
| `network`          | envoy-gateway, cloudflared tunnel, external-dns (k8s-gateway + cloudflare-dns) |
| `external-secrets` | external-secrets operator, 1Password Connect                                   |
| `flux-system`      | Flux itself                                                                    |
| `default`          | General applications (e.g. `echo` test server)                                 |

#### Shared components

`kubernetes/components/sops/` is a reusable Kustomize component that injects the SOPS
`cluster-secrets` `Secret` and decryption config into any `Kustomization` that references it.

______________________________________________________________________

### 4. Secrets – SOPS + age

All secrets committed to Git are encrypted with SOPS using an age key. The `.sops.yaml` file
defines encryption rules:

- Files matching `talos/*.sops.yaml` → encrypt entire file
- Files matching `(bootstrap|kubernetes)/*.sops.yaml` → encrypt only `data`/`stringData` fields

The age public key is stored in `.sops.yaml`; the private key lives in `age.key` (gitignored) and
is referenced by the `SOPS_AGE_KEY_FILE` environment variable.

Flux decrypts secrets in-cluster using a `Secret` containing the age private key, configured via
the SOPS decryption provider on each `Kustomization`.

______________________________________________________________________

### 5. Networking

| Component                         | Role                                                               |
| --------------------------------- | ------------------------------------------------------------------ |
| **Cilium**                        | eBPF CNI, kube-proxy replacement, network policy                   |
| **CoreDNS**                       | In-cluster DNS                                                     |
| **Envoy Gateway**                 | Kubernetes Gateway API implementation (ingress/traffic routing)    |
| **cloudflared**                   | Cloudflare Tunnel – exposes services externally without open ports |
| **external-dns (k8s-gateway)**    | Internal DNS resolution for cluster services                       |
| **external-dns (cloudflare-dns)** | Syncs DNS records to Cloudflare for external access                |

______________________________________________________________________

### 6. Certificate Management

**cert-manager** issues TLS certificates for in-cluster services. It is bootstrapped via
Helmfile and subsequently managed by Flux.

______________________________________________________________________

### 7. Dependency Updates – Renovate

Renovate runs on a weekend schedule (`.renovaterc.json5`) and opens PRs to update:

- Helm chart versions in `HelmRelease` manifests
- Container image digests
- OCI chart references
- GitHub Actions versions
- Tool versions in `.mise.toml`

Annotated inline comments (`# renovate: datasource=...`) drive version tracking for values that
Renovate cannot auto-detect. GitHub Actions minor/patch updates are auto-merged after 3 days.

______________________________________________________________________

### 8. CI – GitHub Actions

| Workflow          | Trigger                                | Purpose                                                                                                            |
| ----------------- | -------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `flux-local.yaml` | PR to `main` (kubernetes/\*\* changes) | Validates Flux manifests with `flux-local test`; posts a diff of HelmRelease/Kustomization changes as a PR comment |
| `renovate.yaml`   | Schedule + dispatch                    | Runs Renovate dependency updates                                                                                   |
| `label-sync.yaml` | Push to `main`                         | Syncs GitHub labels from `labels.yaml`                                                                             |
| `labeler.yaml`    | PR                                     | Auto-labels PRs based on changed paths                                                                             |
| `release.yaml`    | Push to `main`                         | Creates GitHub releases                                                                                            |

______________________________________________________________________

### 9. Developer Tooling

Tools are pinned in `.mise.toml` and managed by [mise](https://mise.jdx.dev/). Linting is handled
by [pre-commit](https://pre-commit.com/) with hooks for YAML formatting (`yamlfmt`), Markdown
formatting (`mdformat`), and whitespace. Common tasks are wrapped with
[Task](https://taskfile.dev/) (`Taskfile.yaml` + `.taskfiles/`).

Key tasks:

| Task                         | Description                                                                 |
| ---------------------------- | --------------------------------------------------------------------------- |
| `task bootstrap:talos`       | Apply Talos machine configs to nodes                                        |
| `task bootstrap:apps`        | Run the Helmfile bootstrap (installs Flux)                                  |
| `task talos:generate-config` | Render `talconfig.yaml` → node configs via talhelper                        |
| `task reconcile`             | Force Flux to pull changes from Git immediately                             |
| `task configure`             | Re-render cluster config from `cluster.yaml` / `nodes.yaml` templates       |
| `task lint`                  | Run all pre-commit hooks (yamlfmt, mdformat, YAML checks) against all files |
| `task dev:validate`          | Validate all Flux manifests offline via `flux-local` (no cluster needed)    |
| `task dev:start`             | Redirect Flux to the current branch for live cluster testing                |
| `task dev:stop`              | Restore Flux to `main` after branch testing                                 |

Configuration values in `cluster.yaml` and `nodes.yaml` are rendered through
[makejinja](https://github.com/mirkolenz/makejinja) (`makejinja.toml`) to generate the actual YAML
manifests and Talos configs from the `templates/` directory.
