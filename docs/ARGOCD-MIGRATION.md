# ArgoCD Migration Notes

Migration is complete: this repository now uses ArgoCD as the sole GitOps reconciler.

______________________________________________________________________

## Current Ownership Model

- ArgoCD owns reconciliation for all app resources.
- App charts are rendered from `helmCharts` entries in app-local `kustomization.yaml`.
- Legacy control-plane bridge resources are removed.

______________________________________________________________________

## Validation After Migration

```bash
task lint
task dev:validate
task dev:argocd:health
task dev:argocd:verify-health
```
