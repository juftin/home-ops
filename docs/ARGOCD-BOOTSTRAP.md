# ArgoCD Bootstrap

Use this runbook to bootstrap ArgoCD as a GitOps controller from repository-defined resources.

______________________________________________________________________

## Prerequisites

- `age.key` and `kubeconfig` exist in the current worktree.
- Cluster networking and CRD bootstrap (`task bootstrap:apps`) are healthy.
- `task lint` and `task dev:validate` pass before live bootstrap checks.

______________________________________________________________________

## Bootstrap Commands

```bash
task argocd:bootstrap
task argocd:bootstrap:verify
task dev:argocd:render
task dev:argocd:health
```

`task argocd:bootstrap` seeds the ArgoCD root `Application` (`home-ops-root`) pointing at
`kubernetes/argocd` for the current git branch (`refs/heads/<branch>`) and injects
`ARGOCD_SECRET_DOMAIN` from `flux-system/cluster-secrets` so the chart can create a valid ArgoCD
`HTTPRoute` and URL.

______________________________________________________________________

## Readiness Checks

1. `helm status argocd -n argocd` returns deployed and healthy.
2. `kubectl get deploy -n argocd` shows controller, repo-server, and server ready.
3. `task dev:argocd:render` succeeds with no kustomize errors.
4. `task dev:argocd:verify-cutover` can run without scope validation errors.
5. `argocd.${SECRET_DOMAIN}` is reachable through the oauth-admin gateway route.

Success target: baseline reconciliation readiness within 30 minutes.
