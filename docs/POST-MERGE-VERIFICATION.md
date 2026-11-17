# Post-merge Verification

Use this checklist after ArgoCD, Pomerium, or Gateway changes merge to `main`.

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

## 2. Pomerium / Gateway sanity

```bash
kubectl get pomerium -n pomerium global
kubectl get pods,svc,pvc -n pomerium
kubectl get ingress -A --field-selector spec.ingressClassName=pomerium
kubectl get gateway -n network envoy-external envoy-internal --show-labels
```

Expected:

- `Pomerium/global` and `Deployment/pomerium` are healthy and bound to `pomerium-data` PVC.
- Protected app `Ingress` objects (`agentsview`, `paseo`, `herdr`, `hermes-agent`, `openclaw`, `argocd`, `grafana`) are reconciled by Pomerium.
- `envoy-external` retains `home-ops.io/cloudflare-dns=true`.

______________________________________________________________________

## 3. Failure follow-up

If checks fail:

1. use `docs/OIDC-TROUBLESHOOTING.md`
2. revert the problematic commit
3. rerun verification commands
