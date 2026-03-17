# Tasks

This repository uses [Task](https://taskfile.dev/) as its task runner.

Run `task` to list all available tasks.

______________________________________________________________________

## Core Tasks

| Task                           | Description                                                            |
| ------------------------------ | ---------------------------------------------------------------------- |
| `task lint`                    | Run all pre-commit hooks and auto-fix formatting                       |
| `task dev:validate`            | Render all ArgoCD app manifests locally (SOPS + kustomize + helm)      |
| `task argocd:bootstrap`        | Bootstrap/update ArgoCD Helm release and root app                      |
| `task argocd:bootstrap:verify` | Verify ArgoCD control-plane workloads                                  |
| `task bootstrap:apps`          | Bootstrap core platform charts (Cilium, CoreDNS, cert-manager, ArgoCD) |

______________________________________________________________________

## Branch Testing Workflow

```bash
task dev:worktree:create NAME=home-ops-my-change
cd worktrees/home-ops-my-change

task lint
task dev:validate
task dev:start   # patch ArgoCD refs to current branch
task dev:sync    # push + refresh while iterating
task dev:stop    # restore refs to main (always run)

cd ../..
task dev:worktree:remove NAME=home-ops-my-change
```

`task dev:start` / `task dev:sync` / `task dev:stop` require cluster access (`kubeconfig`).

______________________________________________________________________

## ArgoCD Health Checks

```bash
task dev:argocd:render
task dev:argocd:health
task dev:argocd:verify-health
task dev:argocd:validate-rbac
```
