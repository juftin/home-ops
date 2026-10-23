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
kubectl get envoyextensionpolicy -n network oauth-verified-email
```

Expected:

- DNS label `home-ops.io/cloudflare-dns=true` remains on OAuth gateways.
- Gateway and all policy conditions are accepted/programmed, including the verified-email extension.
- `/denied` and `/logged-out` routes are reachable on each app host and rewritten correctly.
- App-host callbacks succeed; OAuth cookies have no Domain attribute.
- Allowed users succeed; denied users and application errors retain HTTP 403.
- Lunch Money REST/MCP reject missing/wrong keys and accept the configured key; direct raw
  pod port 8000 is blocked from other workloads. Health/readiness remain public.
- Existing sessions obey allowlist removals after policy propagation; check open streams separately.

Complete the [authentication rollout checks](AUTHENTICATION.md) after changes to this boundary.

______________________________________________________________________

## 3. Failure follow-up

If checks fail:

1. use `docs/OIDC-TROUBLESHOOTING.md`
2. revert the problematic commit
3. rerun verification commands
