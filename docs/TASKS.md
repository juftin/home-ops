# Tasks

This repository uses [Task](https://taskfile.dev/) as its task runner.

Run `task` to list all available tasks.

______________________________________________________________________

## Essential Tasks (Complete Reference: `task --list`)

### Core Tasks

| Task                           | Description                                                            |
| ------------------------------ | ---------------------------------------------------------------------- |
| `task lint`                    | Run pre-commit formatting, Actionlint, and ShellCheck                  |
| `task dev:validate`            | Render apps with decryption and validate built-in resource schemas     |
| `task dev:validate:ci`         | Render and validate schemas with placeholder secrets (same as PR CI)   |
| `task dev:validate:test`       | Test rendering, decryption, and schema failure handling with fixtures  |
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

Both render tasks run strict Kubeconform validation for built-in Kubernetes API groups, using
the Kubernetes version in `talos/talenv.yaml`. Custom resources and CRD definitions are excluded.
Missing schemas for other built-in resources fail validation. These checks require no cluster access.

`mise install` installs pre-commit, Actionlint, ShellCheck, and Kubeconform. The Repository Quality
workflow runs `task lint` on every PR and skips only the local `no-commit-to-branch` hook.

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
