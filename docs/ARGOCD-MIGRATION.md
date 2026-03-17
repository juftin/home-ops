# ArgoCD Migration Waves

Use this runbook to execute phased ownership transfer from Flux to ArgoCD.

______________________________________________________________________

## Wave Sequencing

1. Wave `platform`: shared cluster dependencies.
2. Wave `core`: certificate and secret controllers.
3. Wave `network`: ingress, DNS, and gateway components.
4. Wave `observability`: logging and monitoring.
5. Wave `apps`: tenant-facing workloads.

Each wave must complete health/sync/drift verification before advancing.

______________________________________________________________________

## Communication Steps

1. Announce wave scope and disruption window (\<=10 minutes) before execution.
2. Confirm rollback owner and verification owner for the wave.
3. Run migration + verification commands and post outcomes with evidence links.
4. After verified success, label Flux Kustomizations for that namespace group with
   `home-ops.io/gitops-controller=argocd`.
5. Post a completion update with any follow-ups before starting the next wave.

______________________________________________________________________

## Command Sequence

```bash
task dev:argocd:migrate-wave WAVE=<wave> NAMESPACE=<namespace>
task dev:argocd:verify-wave WAVE=<wave> NAMESPACE=<namespace>
task dev:argocd:verify-cutover
```

If verification still reports stale sync status after a successful fix, force a hard refresh and
sync from controller context:

```bash
kubectl annotate application -n argocd <app-name> argocd.argoproj.io/refresh=hard --overwrite
kubectl exec -n argocd statefulset/argocd-application-controller -- argocd app sync <app-name> --core --timeout 180
```
