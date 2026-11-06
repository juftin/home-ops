# Implementation Plan: Self-Hosted GitHub Actions Runner

**Branch**: `006-github-actions-runner` | **Date**: 2026-10-16 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/006-github-actions-runner/spec.md`

## Summary

Deploy the official ARC controller and one ephemeral runner scale set for `juftin/home-ops`
through the existing ArgoCD/Kustomize renderer. Use a dedicated Docker-in-Docker daemon per job
for Docker builds, container actions, job containers, and service containers. Use separate
`arc-system` and `arc-runners` namespaces, a repository-scoped fine-grained token from 1Password,
zero idle runners, and at most two active runners. Keep existing PR checks on GitHub-hosted runners.

The privileged Docker daemon is an explicit trust limitation. Network and resource controls
protect against ordinary mistakes; they do not make hostile workflows safe on this shared node.

## Technical Context

**Language/Version**: YAML manifests and Helm values; Bash smoke commands; GitHub Actions workflows.
**Primary Dependencies**: ARC charts `gha-runner-scale-set-controller` and `gha-runner-scale-set`
0.15.0; official `ghcr.io/actions/actions-runner` 2.338.0; pinned Docker DinD image; existing
Kustomize, ArgoCD, Cilium, External Secrets Operator, 1Password, Alloy, and Loki.
**Storage**: Per-pod disk-backed `emptyDir` for workspace, Docker data, Docker socket, and externals;
no persistent runner storage.
**Testing**: Repository lint and render/schema validation; later trusted smoke workflow and
read-only operational checks against the live cluster.
**Target Platform**: Existing Linux amd64 Talos cluster; repository pins Talos v1.13.11 and
Kubernetes v1.36.2. Use the Kubernetes >=1.29 restartable init-sidecar DinD layout.
**Project Type**: GitOps infrastructure feature.
**Performance Goals**: Warm-image jobs start within five minutes; cleanup within five minutes;
at most two concurrent jobs.
**Constraints**: Single shared node, six physical cores and 32GiB RAM; available capacity is not
measured in planning. No host sockets, host paths, cluster credentials in jobs, or fork execution.
**Scale/Scope**: One controller, one listener, one repository, zero to two runners.

## Constitution Check

| Principle                | Design evidence                                                                                                        | Gate                                    |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------- | --------------------------------------- |
| I. GitOps                | App manifests and configuration are reconciled by ArgoCD; no manual applies                                            | Pass                                    |
| II. Reproducibility      | Secret item schema, GitHub token setup, namespace ownership, and ordering documented                                   | Pass                                    |
| III. Template            | Repository URL, runner name, resource budgets, and credentials are explicit values                                     | Pass                                    |
| IV. Modular architecture | Two apps; remove runner set before its controller; no unrelated workflow migration                                     | Pass                                    |
| V. Simplicity            | Official charts, native Docker behavior, existing renderer, no custom operator or image pipeline                       | Pass                                    |
| VI. DRY                  | Renovate tracks chart/image pins; group both ARC charts for compatible updates; shared runner image uses a YAML anchor | Pass                                    |
| VII. Observability       | Controller/listener logs and runner diagnostics go through existing Alloy/Loki; step output remains in GitHub          | Pass, with live retention check         |
| VIII. Least privilege    | Scoped controller RBAC, job SA without token or permissions, external credential reference, Cilium policies            | Documented exception below              |
| IX. Validation           | Lint, placeholder/full rendering, rendered invariant review, and live acceptance gates                                 | Pass, live gates pending implementation |

Pre-research and post-design review reach the same conclusion: the design is ready for task
breakdown with the DinD privilege exception recorded. Live acceptance criteria are implementation
exit gates, not claims that a runner has already been verified.

## Project Structure

### Documentation (this feature)

```text
specs/006-github-actions-runner/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── checklists/requirements.md
└── contracts/
    ├── runner-configuration.md
    └── workflow.md
```

`tasks.md` is produced by the subsequent `/speckit.tasks` phase.

### Source Code (planned changes)

```text
kubernetes/argocd/applicationset.yaml
kubernetes/apps/arc-system/actions-runner-controller/app/
├── kustomization.yaml
├── namespaces.yaml
├── values.yaml
└── ciliumnetworkpolicy.yaml
kubernetes/apps/arc-runners/home-ops-runner/app/
├── kustomization.yaml
├── values.yaml
├── externalsecret.yaml
├── ciliumnetworkpolicy.yaml
└── resourcequota.yaml
.github/workflows/runner-smoke.yaml
.github/runner-smoke/
├── Dockerfile
└── action/
    ├── action.yaml
    └── Dockerfile
.renovaterc.json5
README.md
docs/ARCHITECTURE.md
docs/GITHUB-RUNNER-SETUP.md
```

**Structure Decision**: Each app is self-contained under `app/`. The controller app owns both Namespaces.
This intentionally differs from legacy namespace-level examples: the ApplicationSet discovers
only apps and the renderer copies only `app/`. Parent resource references cannot work in that
isolated copy. Do not duplicate Namespace ownership or add unused namespace-level manifests.

## Phase 0: Research Decisions

See [research.md](research.md) for sources and rejected alternatives. All design questions are
resolved: customized DinD template, fine-grained PAT, separate app-owned namespaces, explicit
controller service account, Cilium DNS/HTTPS policy, and existing centralized diagnostics.

## Phase 1: Design

### GitOps and ordering

- Add `arc-system` wave 3 and `arc-runners` wave 4 to the ApplicationSet's namespace list.
  Keep `CreateNamespace` false for these apps because the controller app owns explicit Namespace resources.
- Both Namespace manifests live in the controller app: single-namespace watch RBAC is created
  in `arc-runners` during controller sync, so that namespace must already exist. The runner app
  does not own a duplicate Namespace. Namespace manifests use resource sync wave -2; runner namespace declares privileged Pod
  Security admission. Apply credential and policy resources before the runner set using resource waves.
- Controller chart includes CRDs and uses stable service account `actions-runner-controller`.
  Set `flags.watchSingleNamespace: arc-runners`; review its rendered RBAC for the watched
  namespace. Cluster CRD installation remains ArgoCD's responsibility.
  Do not add a top-level Kustomize namespace transformer to this app: it could rewrite the
  chart's cross-namespace watch RBAC. Use each Helm entry's namespace and explicit manifest metadata.
- Runner chart explicitly sets `controllerServiceAccount.namespace: arc-system` and
  `controllerServiceAccount.name: actions-runner-controller`; Helm lookup must not be required
  for offline rendering. Use existing OCI Helm chart rendering without changing the renderer.
- Generated Application waves do not establish cross-Application readiness. Initial activation
  must sync controller/CRDs before the runner app; retry after CRDs and ExternalSecret readiness.
  Do not mark a runner app healthy merely because its custom resource was accepted.
- Preserve normal controller reconciliation and cleanup finalizers. For removal, drain work,
  remove the runner set while the controller and credentials remain available, then remove controller.

### Runner and Docker template

Use `runnerScaleSetName: home-ops`, repository URL, and `githubConfigSecret: home-ops-runner-github`.
Leave `containerMode` unset and copy the pinned chart's documented DinD layout into `template.spec`.
The automatic mode injects defaults that cannot supply all required daemon/image/storage controls.

Keep `init-dind-externals`, restartable `dind` init container, `runner`, startup probe, Docker group
123, Unix socket, and shared workspace/externals paths. Add a dedicated `/var/lib/docker` emptyDir.
Runner starts `/home/runner/run.sh` and waits for Docker. Only `dind` is privileged. Preserve chart
JIT registration behavior and its no-permission runner service account; disable token automount.
Runner and externals-copy images share one version pin via YAML anchor. Resolve and pin the
Docker official image patch/digest during implementation; do not use floating `dind` or `latest`.

Proposed limits fit modest smoke builds; scheduling and eviction behavior must be measured before
activation. Nested Docker children must be verified to stay within the intended daemon cgroup.

| Container      | CPU request / limit | Memory request / limit | Ephemeral storage request / limit |
| -------------- | ------------------- | ---------------------- | --------------------------------- |
| Runner         | 250m / 1            | 512Mi / 2Gi            | 1Gi / 6Gi                         |
| DinD           | 500m / 1            | 1Gi / 2Gi              | 2Gi / 12Gi                        |
| Externals copy | 100m / 500m         | 128Mi / 256Mi          | 100Mi / 1Gi                       |
| Controller     | 100m / 500m         | 128Mi / 512Mi          | 100Mi / 1Gi                       |
| Listener       | 100m / 500m         | 128Mi / 512Mi          | 100Mi / 1Gi                       |

Per runner: workspace 4Gi, Docker state 10Gi, externals 1Gi, socket 16Mi emptyDir size limits.
Two runners have combined steady limits of 4 CPU and 8Gi memory; controller/listener add 1 CPU
and 1Gi. Runner namespace quota: requests CPU 2, memory 4Gi, ephemeral storage 8Gi; limits CPU 5,
memory 10Gi, ephemeral storage 40Gi. Include listener and native sidecar accounting in render
review. Avoid a small pod-count quota: finished pods and replacement overlap could block recovery.

Disk budgets use kubelet accounting and eviction, not instantaneous filesystem quotas. Privileged
jobs can also undermine resource controls; the trusted-code restriction remains necessary.

### Credentials and trust

Create a fine-grained PAT with resource owner `juftin`, selected repository `home-ops`, repository
Administration read/write, and implicit Metadata read. Set an expiry and document renewal.
Store it as the `github_token` field on 1Password item `home-ops-runner`; ESO creates the Secret
of the same data shape in `arc-runners`. Follow existing ClusterSecretStore `onepassword` patterns.
No registration credential appears in workflow environments or runner volume mounts.

Initial smoke workflow uses `workflow_dispatch` only, a job-level `github.ref == 'refs/heads/main'`
guard, explicit default-branch checkout, `persist-credentials: false`, `contents: read`, and job
timeouts. It has no arbitrary ref or shell inputs, PR triggers, or `pull_request_target` execution.
Keep required PR checks on `ubuntu-latest`. Repository registration alone cannot enforce which
future workflows select a runner: owners must preserve this trust policy when adding workflows.

### Network and logs

Use CiliumNetworkPolicy with default deny ingress/egress for runner pods; permit CoreDNS DNS and
HTTPS to documented GitHub, action artifact, and public container registry endpoints using FQDN
rules. Deny private/special address ranges, LAN destinations, host, remote-node, and kube-apiserver
entities. Exempt the precise DNS allow path from private-CIDR deny rules because deny takes
precedence. Include every DNS-reachable destination needed by smoke image layers and authentication;
expand deliberately when workflows acquire new dependencies. IPv6 stays denied unless explicitly
configured. The controller and listener get separate DNS, GitHub HTTPS, and Kubernetes API access.
Cilium's in-agent DNS proxy supports FQDN policy without enabling a separate Envoy DaemonSet.

Validate this policy from nested containers as well as the runner, including DNS responses pointing
to private addresses. No inbound route, ingress, Cloudflare entry, or public listener is required.

Set `ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1`; existing Alloy discovers all namespaces and sends
controller, listener, daemon, and runner diagnostic stdout to Loki. Retain GitHub step logs in
GitHub; do not promise that arbitrary step output is mirrored to Loki. The live failed-job check
must find runner/job diagnostic records after pod deletion and separately verify GitHub step logs.
If runner diagnostics are lost before Alloy discovers short-lived pods, fix collection before
acceptance. Query by namespace, pod, and container using existing retention.

## Phase 2: Implementation Sequence and Validation

1. Add controller app, owned namespaces, and ApplicationSet discovery. Verify isolated rendering
   and explicit watched-namespace RBAC.
2. Add runner app, ESO reference, full custom DinD template, policies, quotas, and grouped Renovate
   chart updates. Verify chart/image pins and all rendered resource/security invariants.
3. Add trusted smoke workflow and local synthetic Docker/container action fixtures. Cover shell,
   JavaScript, build/run, container action outputs, host-job service access, and job-container service access.
4. Add setup/architecture/inventory documentation with branch testing, rotation, and ordered removal.
5. Run `task lint`, explicit pre-commit checks for new untracked files, `task dev:validate`, and
   `task dev:validate:ci`. Full decryption requires a securely provisioned age key; never inspect it.
6. During authorized activation, first inspect available capacity and resolve credentials externally.
   Use `task dev:start`/`task dev:sync` with controller-first initial sync; always run `task dev:stop`
   after branch testing, including failures. GitHub manual dispatch requires the workflow on the
   default branch, so complete dispatch acceptance after merge rather than bypassing the branch guard.
7. Prove SC-001–SC-007: three successful runs, queue limit, cancellation cleanup, no state reuse,
   private-network/API denial, retained diagnostics, rotation, and hosted PR continuity. Observe
   job cgroup and ephemeral-storage behavior before accepting resource containment claims.

No new HTTP API is needed. [Configuration contract](contracts/runner-configuration.md) and
[workflow contract](contracts/workflow.md) describe the interfaces operators and jobs actually use.

## Complexity Tracking

| Exception                                   | Why needed                                                              | Alternative considered                                                                                                                              |
| ------------------------------------------- | ----------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| Privileged DinD daemon under principle VIII | Native Docker build/run plus all requested container workflow semantics | Kubernetes mode lacks a normal Docker daemon; rootless DinD still requires privilege in ARC guidance; a separate node/cluster exceeds initial scope |
| Explicit custom DinD PodSpec                | Required image, resource, and ephemeral storage controls                | Automatic mode injects defaults and does not provide all required customization                                                                     |

The privilege exception must be carried into implementation documentation and the PR description.
