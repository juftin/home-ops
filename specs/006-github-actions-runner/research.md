# Research: Self-Hosted GitHub Actions Runner

**Date**: 2026-10-16
**Status**: Design decisions resolved; live verification deferred to implementation.

## 1. ARC distribution and container execution

**Decision**: Use the official controller and runner scale-set charts at 0.15.0, with an explicit
custom DinD template based on that release. Use official runner 2.338.0 and a pinned Docker daemon
image. Resolve immutable image digests when implementing.

**Rationale**: Modern scale sets provide ephemeral jobs and bounded scaling. The upstream chart
instructs users to leave `containerMode` empty when customizing injected DinD configuration.
A restartable init-container daemon supports the existing Kubernetes version. Add explicit
`/var/lib/docker` storage and resource budgets instead of relying on generated defaults.

**Alternatives considered**: Legacy RunnerDeployment resources add unnecessary legacy behavior.
Kubernetes container hooks need pod-management RBAC and do not supply ordinary Docker build/run.
Host Docker sockets violate the spec and are not the Talos host runtime interface. Rootless DinD
still requires privilege according to upstream guidance, so it does not remove the key exception.

**Evidence**:

- [ARC release 0.15.0](https://github.com/actions/actions-runner-controller/releases/tag/gha-runner-scale-set-0.15.0)
- [Pinned chart values and documented template](https://github.com/actions/actions-runner-controller/blob/gha-runner-scale-set-0.15.0/charts/gha-runner-scale-set/values.yaml)
- [Runner release 2.338.0](https://github.com/actions/runner/releases/tag/v2.338.0)

## 2. Authentication

**Decision**: Repository-selected fine-grained PAT, Administration read/write, stored in 1Password
item `home-ops-runner`, property `github_token`. ESO materializes `home-ops-runner-github` in
`arc-runners`; the chart receives its name as a string.

**Rationale**: GitHub documents this permission for repository runners. It fits the personal
repository without an organization dependency. Tokens expire and require explicit renewal.

**Alternatives considered**: GitHub App authentication is attractive for future expansion, but
current ARC setup instructions assume an organization-owned app. A classic PAT has broader scope.
Never pass token values through Helm values, CLI arguments, or workflow environments.

**Evidence**: [ARC authentication permissions](https://docs.github.com/en/actions/how-tos/manage-runners/use-actions-runner-controller/authenticate-to-the-api).
Local precedent: `kubernetes/apps/default/paseo/app/externalsecret.yaml`.

## 3. Namespace ownership and offline Helm rendering

**Decision**: Two independently discovered apps; the controller app owns both Namespace manifests
inside its `app/` directory. Explicitly name the controller service account in both charts. Watch only
`arc-runners`. Stage first activation controller-before-runner.

**Rationale**: Local `applicationset.yaml` uses an explicit namespace list. Namespace-level
kustomizations are not discovered; `render-argocd-app.sh` copies only `app/` into a temporary
directory. The scale-set chart otherwise uses live lookup to locate a controller. Application
sync-wave annotations alone do not wait for another Application's readiness. Single-namespace
controller watch RBAC is created in `arc-runners`, so that namespace must exist before the
controller chart syncs; it cannot be created only by the later runner app.

**Alternatives considered**: Parent directory references break isolated rendering. Namespace
auto-creation alone cannot express app-owned PSA metadata cleanly. Installing with standalone Helm
would create another lifecycle outside GitOps.

**Evidence**:

- `kubernetes/argocd/applicationset.yaml`
- `scripts/render-argocd-app.sh`
- [Controller service account chart setting](https://github.com/actions/actions-runner-controller/blob/gha-runner-scale-set-0.15.0/charts/gha-runner-scale-set/values.yaml)

## 4. Privileges, network policy, and budgets

**Decision**: Give only DinD privilege; no host mounts or host networking, no job API token.
Use Cilium DNS/FQDN HTTPS allow rules with explicit private/LAN denial. Use finite CPU/memory
limits, per-pod emptyDir storage, namespace quota, and maximum two runners.

**Rationale**: Native Docker behavior satisfies every requested container capability without
job pod-management RBAC. Talos supports privileged pods with intentional admission settings;
this repository removes its default admission configuration, so actual enforcement must be
observed rather than assumed. Cilium DNS policy does not require a separate Envoy DaemonSet.
Deny rules take precedence: do not accidentally deny the allowed CoreDNS path.

**Alternatives considered**: Broad unrestricted network access fails the isolation requirement.
A broad public-HTTPS policy is simpler but allows more destinations than smoke jobs require.
A separate node or cluster provides a stronger trust boundary but is outside initial scope.
Persistent caches complicate cleanup and are unnecessary for smoke workloads.

**Limits**: Privileged Docker is not hostile-code isolation. EmptyDir sizes are enforced by
accounting/eviction, not hard filesystem quotas. Nested Docker cgroup placement and actual node
headroom must be checked before activation; desired resource declarations alone do not prove them.

**Evidence**:

- [Talos pod security](https://docs.siderolabs.com/kubernetes-guides/security/pod-security)
- [Cilium DNS policy](https://docs.cilium.io/en/stable/security/dns/)
- [Cilium Envoy deployment](https://docs.cilium.io/en/stable/security/network/proxy/envoy/)
- [Kubernetes resource accounting](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- Local `talos/patches/controller/cluster.yaml` and Cilium values.

## 5. Observability and smoke workflow

**Decision**: Preserve runner diagnostic stdout and existing Alloy discovery. Keep full step
output in GitHub. Use a manual-only workflow guarded to `main`, with explicit default-branch
checkout and no arbitrary ref input. Exercise trusted synthetic workloads after merge.

**Rationale**: The official runner image enables diagnostic stdout. Alloy already discovers all
pod namespaces, so no new logging stack is required. Diagnostic logs and complete step output
are different streams; acceptance must check each where it is retained. Manual dispatch requires
an existing default-branch workflow, which makes post-merge smoke execution the straightforward path.

**Alternatives considered**: PR-triggered self-hosted tests increase exposure to untrusted code.
Custom image builds and a new logging sidecar introduce maintenance without demonstrated need.
Do not add them unless the retention acceptance check exposes missing diagnostics.

**Evidence**:

- [Official runner image](https://github.com/actions/runner/blob/main/images/Dockerfile)
- [Manual workflow execution](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)
- Local `.github/workflows/quality.yaml` and Alloy `values.yaml`.
