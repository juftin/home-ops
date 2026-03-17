# ArgoCD Rollout Runbook

Use this runbook for day-2 ArgoCD operations.

______________________________________________________________________

## Command Index

```bash
task dev:validate
task dev:argocd:render
task dev:argocd:health
task dev:argocd:verify-health
task dev:argocd:validate-rbac
```

______________________________________________________________________

## Branch Validation Cycle

```bash
task dev:start
task dev:sync
task dev:stop
```

Always run `task dev:stop` when testing is complete to restore reconciliation refs to `main`.
