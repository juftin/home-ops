# Quickstart: Flux to ArgoCD Rollout

## Purpose

This guide describes the planned rollout sequence for replacing Flux with ArgoCD, including
bootstrap, migration waves, verification, and rollback checkpoints.

## Prerequisites

- [ ] Feature branch `001-replace-flux-argocd` is checked out
- [ ] `age.key` and `kubeconfig` are present in the worktree
- [ ] Existing Flux-managed cluster is healthy before migration
- [ ] Required operator access exists for bootstrap and verification commands
- [ ] `task lint` and baseline validation command(s) pass before rollout starts

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

- [ ] ArgoCD bootstrap health confirmed
- [ ] Each migration wave verification record captured
- [ ] Flux ownership retired for all in-scope workloads
- [ ] Role-based access policy validated (admin write, maintainer read-only)
- [ ] ArgoCD-only rollback procedure validated

## Notes

- Do not run direct production `kubectl apply` for desired state changes.
- Keep secrets encrypted in Git; do not introduce plaintext secret files.
- Perform rollout in controlled windows with explicit operator communication per wave.
