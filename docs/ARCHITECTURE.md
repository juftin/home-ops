# Architecture

`home-ops` is an ArgoCD-first GitOps homelab running on Talos Linux.

______________________________________________________________________

## Control Plane

- **ArgoCD** is the only GitOps reconciler.
- `home-ops-root` (bootstrapped by Helmfile) points to `kubernetes/argocd`.
- `kubernetes/argocd/applicationset.yaml` generates one ArgoCD `Application` per app directory under `kubernetes/apps/<namespace>/<app>/app`.

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
