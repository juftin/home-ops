# Tasks

This repository uses [Task](https://taskfile.dev/) as its task runner.

Run `task` to list all available tasks.

______________________________________________________________________

## Essential Tasks (Complete Reference: `task --list`)

### Core Tasks

| Task                           | Description                                                            |
| ------------------------------ | ---------------------------------------------------------------------- |
| `task lint`                    | Run pre-commit formatting, Actionlint, and ShellCheck                  |
| `task dev:agents:test`         | Test shared agent installs and upgrade fallback without network access |
| `task dev:validate`            | Render apps with decryption and validate built-in resource schemas     |
| `task dev:validate:ci`         | Render and validate schemas with placeholder secrets (same as PR CI)   |
| `task dev:validate:bootstrap`  | Render the ArgoCD bootstrap chart and validate built-in schemas        |
| `task dev:validate:test`       | Test rendering, decryption, and schema failure handling with fixtures  |
| `task argocd:bootstrap`        | Bootstrap/update ArgoCD Helm release and root app                      |
| `task argocd:bootstrap:verify` | Verify ArgoCD control-plane workloads                                  |
| `task bootstrap:apps`          | Bootstrap core platform charts (Cilium, CoreDNS, cert-manager, ArgoCD) |

______________________________________________________________________

## Branch Testing Workflow

### Test one app

Use the single-app tasks to keep `home-ops-root`, directory discovery, and all other apps on
`main`. Run them from a feature worktree after committing and pushing its changes:

```bash
git push origin HEAD
task dev:app:start APP=echo
task dev:app:sync APP=echo   # push committed changes and refresh only echo
task dev:app:stop APP=echo   # always run after testing, including failures
```

`BRANCH` defaults to the current branch. Start fetches the pushed branch without pushing or
checking it out, so an existing PR can be tested directly from the tooling worktree:

```bash
# PR #232 uses the older directory layout and the default namespace.
task dev:app:start APP=orca BRANCH=feeble-emu APP_PATH=kubernetes/apps/default/orca/app
kubectl get application orca -n argocd
task dev:app:stop APP=orca
```

`APP_PATH` is the directory containing the app's `kustomization.yaml`. It defaults to the
unique `kubernetes/workloads/<folder>/<APP>` directory on the remote branch. Namespace changes
for an existing app are rejected; rebase or migrate the app before testing them. Sync must run
from the selected branch's own worktree; start and stop can run from another tooling worktree.

For an existing app, start temporarily disables root automatic sync and adds a named
ApplicationSet exception for the app's source path and revision. Root and all other app source
refs stay on `main`, and other workload Applications keep reconciling normally. Stop restores the
saved source before removing
the exception. Other exceptions are preserved, and concurrent ApplicationSet updates fail
instead of being overwritten. The [ApplicationSet documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Controlling-Resource-Modification/)
describes these revision exceptions. Root automatic sync returns to its saved setting when the
last existing-app test stops. Root configuration changes are deferred during these tests. A
manual sync of `home-ops-root` can reset the temporary exception; avoid syncing the root during
a single-app test.

For a branch-only app, start creates a temporary Application from the current ApplicationSet
template. Stop disables its automatic sync and deletes only the Application, retaining workloads
and PVCs. The remaining resources are no longer reconciled; remove them deliberately or let the
app's eventual merge bring them under GitOps. No root or generator revisions are changed, so
`dev:app:stop` is the cleanup command for these tests. Use the whole-cluster `dev:stop` only for
the whole-cluster workflow below. Do not mix the two workflows.

Only the selected app is deployed. Shared changes on its branch, such as Cloudflare Tunnel rules,
agent-tools ConfigMaps, or image publishing workflows, are not deployed. PR #232 specifically
needs its GHCR image published and readable, an `agent-tools` ConfigMap in `default`, and a
Cloudflare Tunnel rule for admin SSO. Its branch predates the app namespace migration; a single-app
deployment alone cannot verify its full browser or native-client setup.

These tasks require `kubeconfig`, Git, kubectl, and jq. Run `task dev:app:test` for regression checks
using a local Git remote and a simulated Kubernetes API, without cluster access.

### Test the whole branch

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

If a branch changes `kubernetes/argocd/`, sync `home-ops-root` in ArgoCD after
`task dev:start`; the root Application does not sync automatically. Then run
`task dev:sync` again because applying the ApplicationSet restores its branch references
to `main`. After testing, run `task dev:stop` and sync `home-ops-root` again to restore
the root manifests from `main`.

`task dev:validate` requires the real age key. For a fresh checkout or a fork PR without secrets,
use `task dev:validate:ci`. This uses `example.com` and replaces encrypted values in temporary
app copies; it validates rendering but does not check secret contents or SOPS decryption.

Both render tasks run strict Kubeconform validation for built-in Kubernetes API groups, using
the Kubernetes version in `talos/talenv.yaml`. Custom resources and CRD definitions are excluded.
Missing schemas for other built-in resources fail validation. These checks require no cluster access.

Both tasks also render ArgoCD's Helmfile bootstrap release with placeholder settings and check its
built-in resource schemas. Bootstrap changes trigger the same PR validation workflow.

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
