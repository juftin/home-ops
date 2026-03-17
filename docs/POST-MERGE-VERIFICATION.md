# Post-merge Verification

Use this checklist after ArgoCD, OAuth, or Gateway changes merge to `main`.

______________________________________________________________________

## 1. ArgoCD health and sync

```bash
task dev:argocd:health
task dev:argocd:verify-health
kubectl get applications -n argocd
```

Expected:

- ArgoCD control-plane workloads are healthy.
- Applications are `Synced` and `Healthy`.

______________________________________________________________________

## 2. OAuth/Gateway sanity

```bash
kubectl get gateway -n network envoy-oauth-admin envoy-oauth-users envoy-oauth-internal --show-labels
kubectl get securitypolicy -n network envoy-oauth-admin-policy envoy-oauth-users-policy envoy-oauth-internal-policy
kubectl get httproute -n default oauth-pages
```

Expected:

- DNS label `home-ops.io/cloudflare-dns=true` remains on OAuth gateways.
- `/denied` and `/logged-out` routes are reachable and rewritten correctly.

______________________________________________________________________

## 3. Failure follow-up

If checks fail:

1. use `docs/OIDC-TROUBLESHOOTING.md`
2. revert the problematic commit
3. rerun verification commands
