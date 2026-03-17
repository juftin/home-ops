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

The bootstrap values also install the `kustomize-substitute-secret-domain` CMP plugin in
`argocd-repo-server`. That plugin decrypts `*.sops.yaml` manifests with the mounted age key and
substitutes both `${SECRET_DOMAIN}` and `${SECRET_DOMAIN/./-}` placeholders before ArgoCD applies
resources.

______________________________________________________________________

## Readiness Checks

1. `helm status argocd -n argocd` returns deployed and healthy.
2. `kubectl get deploy -n argocd argocd-server argocd-repo-server` and
   `kubectl get statefulset -n argocd argocd-application-controller` are ready.
3. `kubectl get application -n argocd home-ops-root` reports `Synced` / `Healthy`.
4. `task dev:argocd:render` succeeds with no kustomize errors.
5. `task dev:argocd:verify-cutover` can run without scope validation errors.
6. `argocd.${SECRET_DOMAIN}` is reachable through the oauth-admin gateway route.

## Troubleshooting stale app status

If an app still shows outdated `OutOfSync` state after bootstrap fixes:

```bash
kubectl annotate application -n argocd <app-name> argocd.argoproj.io/refresh=hard --overwrite
kubectl exec -n argocd statefulset/argocd-application-controller -- argocd app sync <app-name> --core --timeout 180
```

When running `task dev:start` branch testing, `flux-system-flux-instance` may appear
`OutOfSync`/`Suspended`; this is expected while Flux is intentionally suspended.

Success target: baseline reconciliation readiness within 30 minutes.
