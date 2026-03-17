# ArgoCD Bootstrap

Use this runbook to bootstrap or refresh ArgoCD control-plane state.

______________________________________________________________________

## Commands

```bash
task argocd:bootstrap
task argocd:bootstrap:verify
task dev:argocd:render
task dev:argocd:health
```

`task argocd:bootstrap` sets:

- `ARGOCD_TARGET_REVISION` to the current branch (`refs/heads/<branch>`)
- `ARGOCD_SECRET_DOMAIN` from decrypted `kubernetes/components/sops/cluster-secrets.sops.yaml`

______________________________________________________________________

## What Bootstrap Configures

- ArgoCD Helm release
- root `Application` (`home-ops-root`)
- CMP plugin for:
  - SOPS decryption
  - `${SECRET_DOMAIN}` placeholder substitution
  - `kustomize build --enable-helm` app rendering

______________________________________________________________________

## Expected State

- `argocd-server`, `argocd-repo-server`, and `argocd-application-controller` are healthy.
- `home-ops-root` is `Synced` and `Healthy`.
- `task dev:validate` and `task dev:argocd:render` both pass.
