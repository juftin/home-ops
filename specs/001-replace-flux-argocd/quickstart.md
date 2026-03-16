# Quickstart: Flux to ArgoCD Rollout

## Purpose

This guide describes the planned rollout sequence for replacing Flux with ArgoCD, including
bootstrap, migration waves, verification, and rollback checkpoints.

## Prerequisites

- [x] Feature branch `001-replace-flux-argocd` is checked out
- [x] `age.key` and `kubeconfig` are present in the worktree
- [x] Existing Flux-managed cluster is healthy before migration
- [x] Required operator access exists for bootstrap and verification commands
- [x] `task lint` and baseline validation command(s) pass before rollout starts

## Rollout Sequence

### 1) Prepare ArgoCD bootstrap resources

1. Add ArgoCD bootstrap release and values in `bootstrap/helmfile.d/`.
2. Define ArgoCD root resources under `kubernetes/argocd/`:
   - project scope
   - application generation pattern
   - role-based access policy
3. Ensure SOPS decryption parity is configured for ArgoCD reconciliation.

### 2) Bootstrap ArgoCD controller

1. Execute bootstrap procedure from repository-defined workflow.
2. Confirm ArgoCD control plane is healthy.
3. Confirm repository reconciliation can render target manifests.

Success checkpoint: baseline ArgoCD reconciliation established within 30 minutes (SC-001).

### 3) Execute migration waves

1. Migrate dependency-first workload group.
2. Verify health/sync/drift outcomes.
3. Retire Flux ownership for completed wave.
4. Repeat for remaining waves until all in-scope workloads are ArgoCD-managed.

Constraint: each wave must stay within a 10-minute planned disruption window (SC-005).

Representative workload groups:

- `platform`: `kube-system`
- `core`: `cert-manager`, `external-secrets`
- `network`: `network`
- `observability`: `observability`
- `apps`: `default`

First-pass success-rate evidence capture (SC-003):

| Wave          | Attempt | Result  | Duration (min) | Evidence ref                                                                                  |
| ------------- | ------- | ------- | -------------- | --------------------------------------------------------------------------------------------- |
| platform      | 1       | success | \<1            | `task dev:argocd:verify-wave WAVE=platform NAMESPACE=kube-system`                             |
| core          | 1       | success | \<1            | `task dev:argocd:verify-wave WAVE=core NAMESPACE=cert-manager` + `NAMESPACE=external-secrets` |
| network       | 1       | success | \<1            | `task dev:argocd:verify-wave WAVE=network NAMESPACE=network`                                  |
| observability | 1       | success | \<1            | `task dev:argocd:verify-wave WAVE=observability NAMESPACE=observability`                      |
| apps          | 1       | success | \<1            | `task dev:argocd:verify-wave WAVE=apps NAMESPACE=default`                                     |

### 4) Run post-cutover verification

1. Validate full ownership transfer (no in-scope workload reconciled by Flux).
2. Validate ArgoCD health and sync for all migrated groups.
3. Record verification evidence and operator sign-off.

Success checkpoint: 100% workload ownership cutover with no unresolved critical drift (SC-002).

### 5) Rollback drill and readiness

1. Execute documented ArgoCD-only rollback procedure in a controlled scenario.
2. Validate restoration to known-good state.
3. Capture completion evidence for incident response readiness.

Success checkpoint: restoration completed within 15 minutes (SC-004).

## Verification Checklist

- [x] ArgoCD bootstrap health confirmed
- [x] Each migration wave verification record captured
- [x] Flux ownership retired for all in-scope workloads
- [x] Role-based access policy validated (admin write, maintainer read-only)
- [x] ArgoCD-only rollback procedure validated

## Rollout Verification Commands (Evidence Capture)

```bash
task dev:argocd:render
task dev:argocd:verify-health
task dev:argocd:verify-cutover
task dev:argocd:validate-rbac
```

Capture and store command output references for each wave and full cutover in change records.

## Validation Evidence

| Command                                                                                                                      | Result | Evidence                                                                                                   |
| ---------------------------------------------------------------------------------------------------------------------------- | ------ | ---------------------------------------------------------------------------------------------------------- |
| `task lint`                                                                                                                  | PASS   | `pre-commit` hooks passed on 2026-03-16 (two consecutive runs)                                             |
| `task dev:validate`                                                                                                          | PASS   | `flux-local` passed (41/41) after worktree git-common-dir mount                                            |
| `task dev:argocd:render`                                                                                                     | PASS   | `kustomize build kubernetes/argocd` exited successfully                                                    |
| `task dev:argocd:verify-health`                                                                                              | PASS   | Full-cutover health/sync/drift verification passed after creating `argocd/sops-age`                        |
| `task dev:argocd:validate-rbac`                                                                                              | PASS   | `argocd-rbac-cm` present and contains admin/read-only bindings and explicit deny rules                     |
| `./scripts/rollback-argocd-wave.sh --wave apps --reason "rollback drill validation execution" --namespace default --execute` | PASS   | Rollback drill executed in 1s; post-drill `task dev:argocd:verify-wave WAVE=apps NAMESPACE=default` passed |

Rollout verification command evidence notes:

- Initial verify-health run failed with `secret-unavailable` as designed, then passed after
  creating the `sops-age` secret in `argocd`.
- Full cutover verification (`task dev:argocd:verify-cutover`) and RBAC object validation
  (`task dev:argocd:validate-rbac`) were completed in-cluster.
- User-level RBAC simulation was executed via `argocd admin settings rbac can` in
  `argocd-server`:
  - `argocd-admins` can `create applications` (`PASS`)
  - `argocd-maintainers` can `get applications` (`PASS`)
  - `argocd-maintainers` cannot `create/sync applications` (`PASS`, denied as expected)
- Rollback drill executed with `--execute` and validated via post-drill wave verification.

## Notes

- Do not run direct production `kubectl apply` for desired state changes.
- Keep secrets encrypted in Git; do not introduce plaintext secret files.
- Perform rollout in controlled windows with explicit operator communication per wave.
