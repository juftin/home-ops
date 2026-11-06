# Quickstart: Self-Hosted GitHub Actions Runner

This is the planned operator procedure. The app manifests and workflow are created in the
implementation phase; the commands below are not evidence of an installed runner.

## 1. Prepare external authentication

Create a fine-grained GitHub token owned by `juftin`, selected repository `home-ops`, repository
Administration read/write (Metadata read is implicit). Set an expiry and renewal reminder.
Store the token directly in 1Password item `home-ops-runner`, property `github_token`.
Never paste it into Git, a shell command, or workflow secrets. Existing ESO/1Password access must
be healthy. Registration uses this credential; jobs use their own GitHub-issued temporary token.

## 2. Review capacity and trust

Before activation, inspect node allocatable resources, existing requests, and available ephemeral
storage through read-only cluster tooling. Reserve headroom for the existing homelab workloads.
Compare with [plan budgets](plan.md); reduce maximum runners to one if two cannot fit.

Only maintainer-controlled default-branch code is eligible. Docker's privileged daemon means
these jobs share the node's trust boundary. No fork or ordinary PR jobs move to the homelab.

## 3. Validate the implementation

From the existing feature worktree:

```bash
task lint
task dev:validate
task dev:validate:ci
```

The full render needs a securely provisioned age key; placeholder validation does not validate
secret contents. Do not print or decrypt secrets into agent context. Review rendered charts for
explicit service accounts, scoped RBAC, image/resource pins, namespace ownership, and policies.
New untracked files also need explicit pre-commit checks because `--all-files` lists tracked files.

## 4. Activate through GitOps

Provision credentials before activating the runner. Controller app owns both namespaces so its
watch RBAC can be created before the scale set. Sync controller/CRDs first; verify its health;
then sync runner resources and wait for ESO Ready and listener startup. Application waves alone
are not a controller-readiness barrier.

For authorized branch testing, commit the implementation and use the repository workflow:

```bash
task dev:start
# Verify controller, CRDs, ESO status, and listener; use dev:sync for further commits.
task dev:stop
```

Always run `task dev:stop` after branch testing, including failures. It restores reconciliation
to `main`; branch-only runner resources may be pruned. The stable deployment comes from merged Git.
Do not manually apply resources.

Read-only status examples, after implementation:

```bash
kubectl get deployments,pods -n arc-system
kubectl get externalsecret -n arc-runners home-ops-runner
kubectl get autoscalingrunnersets,ephemeralrunnersets,ephemeralrunners -n arc-runners
kubectl get pods -n arc-runners
```

With zero idle runners, a listener without a waiting runner pod is normal.

## 5. Dispatch smoke jobs after merge

After `.github/workflows/runner-smoke.yaml` exists on `main`, dispatch it on `main` using GitHub's
Actions UI. It selects `home-ops`. Dispatching another branch must skip runner jobs.
Follow [the workflow contract](contracts/workflow.md) to verify all requested Docker capabilities,
three successful runs, concurrency, cancellation cleanup, state isolation, and denied private access.

In Grafana Explore, search Loki with `{namespace="arc-runners"}` and narrow by pod/container.
Verify controller logs with `{namespace="arc-system"}`. Find failed-job diagnostic records after
runner deletion; full job step output is retained separately by GitHub. Existing Loki retention
is seven days. Measure actual discovery/retention before declaring acceptance complete.

## 6. Rotate and recover

Replace the token directly in 1Password. Wait for the one-hour ESO refresh or use the documented
ESO force-refresh annotation through the normal operator workflow; inspect readiness without
reading Secret values. After jobs drain, restart affected control components if cached
credentials prevent registration. Verify a fresh job succeeds before revoking a still-valid old
credential when rotation allows overlap. For an already expired credential, expect temporary queuing.

For queued jobs, check selector and branch guard, listener/controller logs, ESO status, image
pulls, Cilium policy denials, namespace quota, and scheduling events. Expand only missing declared
network dependencies. Node loss may fail jobs; rerun after recovery rather than assuming replay.

## 7. Remove in order

Disable dispatch and drain active jobs. Keep registration credentials and controller alive.
Remove the runner scale-set app through Git, reconcile, and wait for ARC-generated runner/listener
resources and finalizers to disappear. Then remove controller app and its owned namespaces and
ApplicationSet entries. Review the retained ESO target Secret lifecycle and revoke the PAT last.
Keep existing hosted PR checks available throughout. Never force-delete finalizers as routine cleanup.
