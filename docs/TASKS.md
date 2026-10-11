# Tasks

This repository uses [Task](https://taskfile.dev/) as its task runner.

Run `task` to list all available tasks.

______________________________________________________________________

## Essential Tasks (Complete Reference: `task --list`)

### Core Tasks

| Task                           | Description                                                            |
| ------------------------------ | ---------------------------------------------------------------------- |
| `task lint`                    | Run all pre-commit hooks and auto-fix formatting                       |
| `task dev:validate`            | Render all ArgoCD app manifests locally (SOPS + kustomize + helm)      |
| `task dev:validate:ci`         | Render with placeholder secrets, without an age key (same as PR CI)    |
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

`task dev:validate` requires the real age key. For a fresh checkout or a fork PR without secrets,
use `task dev:validate:ci`. This uses `example.com` and replaces encrypted values in temporary
app copies; it validates rendering but does not check secret contents or SOPS decryption.

GitHub Actions always uses placeholder rendering, so no age key or cluster credentials are needed
in GitHub secrets. Keep full decryption checks local with `task dev:validate`; ArgoCD also decrypts
with its existing age key when syncing the cluster.

______________________________________________________________________

## ArgoCD Health Checks

```bash
task dev:argocd:render
task dev:argocd:health
task dev:argocd:verify-health
task dev:argocd:validate-rbac
```
